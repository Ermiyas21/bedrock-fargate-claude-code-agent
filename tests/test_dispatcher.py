"""
Unit tests for the Lambda dispatcher handler.

Run with: pytest tests/ -v
"""

import json
from unittest.mock import patch

import pytest


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture(autouse=True)
def _set_env(monkeypatch):
    """Set required environment variables before importing the handler."""
    monkeypatch.setenv("ECS_CLUSTER", "test-cluster")
    monkeypatch.setenv("ECS_TASK_DEFINITION", "test-task-def")
    monkeypatch.setenv("SUBNETS", "subnet-aaa,subnet-bbb")
    monkeypatch.setenv("SECURITY_GROUPS", "sg-111")
    monkeypatch.setenv("CONTAINER_NAME", "claude-code-agent")
    monkeypatch.setenv("TICKET_BUCKET", "test-bucket")
    monkeypatch.setenv("WEBHOOK_SECRET", "")


@pytest.fixture
def _reload_handler():
    """Force-reload the handler module so env vars are picked up."""
    import importlib
    import scripts.dispatcher.handler as mod

    importlib.reload(mod)
    return mod


def _apigw_event(body: dict) -> dict:
    """Build a minimal API Gateway v2 proxy event."""
    return {
        "body": json.dumps(body),
        "headers": {},
        "requestContext": {},
    }


def _linear_payload(
    identifier="TEAM-42",
    title="Add /health endpoint",
    description="Return 200 OK at /health",
    state_name="Ready for Dev",
    action="update",
    issue_type="Issue",
) -> dict:
    return {
        "action": action,
        "type": issue_type,
        "data": {
            "id": "issue-abc",
            "identifier": identifier,
            "title": title,
            "description": description,
            "state": {"name": state_name},
        },
    }


# ---------------------------------------------------------------------------
# _parse_body
# ---------------------------------------------------------------------------


class TestParseBody:
    def test_parses_json_string(self, _reload_handler):
        handler_mod = _reload_handler
        event = {"body": '{"key": "value"}'}
        assert handler_mod._parse_body(event) == {"key": "value"}

    def test_returns_dict_body_as_is(self, _reload_handler):
        handler_mod = _reload_handler
        event = {"body": {"key": "value"}}
        assert handler_mod._parse_body(event) == {"key": "value"}

    def test_empty_body_returns_empty_dict(self, _reload_handler):
        handler_mod = _reload_handler
        event = {}
        assert handler_mod._parse_body(event) == {}


# ---------------------------------------------------------------------------
# _should_process
# ---------------------------------------------------------------------------


class TestShouldProcess:
    def test_qualifies_ready_for_dev(self, _reload_handler):
        body = _linear_payload(state_name="Ready for Dev")
        assert _reload_handler._should_process(body) is True

    def test_qualifies_ai_ready(self, _reload_handler):
        body = _linear_payload(state_name="AI Ready")
        assert _reload_handler._should_process(body) is True

    def test_qualifies_case_insensitive(self, _reload_handler):
        body = _linear_payload(state_name="READY FOR DEV")
        assert _reload_handler._should_process(body) is True

    def test_skips_wrong_state(self, _reload_handler):
        body = _linear_payload(state_name="In Progress")
        assert _reload_handler._should_process(body) is False

    def test_skips_wrong_action(self, _reload_handler):
        body = _linear_payload(action="create")
        assert _reload_handler._should_process(body) is False

    def test_skips_wrong_type(self, _reload_handler):
        body = _linear_payload(issue_type="Comment")
        assert _reload_handler._should_process(body) is False


# ---------------------------------------------------------------------------
# _extract_ticket
# ---------------------------------------------------------------------------


class TestExtractTicket:
    def test_extracts_fields(self, _reload_handler):
        body = _linear_payload(
            identifier="PROJ-99",
            title="My Title",
            description="Do the thing",
        )
        ticket = _reload_handler._extract_ticket(body)
        assert ticket["identifier"] == "PROJ-99"
        assert ticket["title"] == "My Title"
        assert ticket["description"] == "Do the thing"
        assert "created_at" in ticket

    def test_handles_missing_optional_fields(self, _reload_handler):
        body = {
            "data": {
                "identifier": "X-1",
            }
        }
        ticket = _reload_handler._extract_ticket(body)
        assert ticket["identifier"] == "X-1"
        assert ticket["title"] == ""
        assert ticket["labels"] == []


# ---------------------------------------------------------------------------
# _response
# ---------------------------------------------------------------------------


class TestResponse:
    def test_builds_api_gateway_response(self, _reload_handler):
        resp = _reload_handler._response(200, {"msg": "ok"})
        assert resp["statusCode"] == 200
        assert json.loads(resp["body"]) == {"msg": "ok"}
        assert resp["headers"]["Content-Type"] == "application/json"


# ---------------------------------------------------------------------------
# _validate_webhook
# ---------------------------------------------------------------------------


class TestValidateWebhook:
    def test_valid_signature(self, _reload_handler):
        import hmac
        import hashlib

        secret = "test-secret"
        body = '{"action":"update"}'
        sig = hmac.new(secret.encode(), body.encode(), hashlib.sha256).hexdigest()

        event = {"headers": {"x-linear-signature": sig}, "body": body}
        assert _reload_handler._validate_webhook(event, secret) is True

    def test_invalid_signature(self, _reload_handler):
        event = {"headers": {"x-linear-signature": "bad"}, "body": "{}"}
        assert _reload_handler._validate_webhook(event, "secret") is False


# ---------------------------------------------------------------------------
# handler (integration-level, AWS calls mocked)
# ---------------------------------------------------------------------------


class TestHandler:
    @patch("scripts.dispatcher.handler.ecs_client")
    @patch("scripts.dispatcher.handler.s3_client")
    def test_successful_task_start(self, mock_s3, mock_ecs, _reload_handler):
        mock_ecs.run_task.return_value = {
            "tasks": [{"taskArn": "arn:aws:ecs:eu-west-2:123:task/cluster/abc"}],
            "failures": [],
        }

        event = _apigw_event(_linear_payload())
        resp = _reload_handler.handler(event, None)

        assert resp["statusCode"] == 200
        body = json.loads(resp["body"])
        assert body["message"] == "Task started"
        assert "task_arn" in body
        mock_s3.put_object.assert_called_once()
        mock_ecs.run_task.assert_called_once()

    @patch("scripts.dispatcher.handler.ecs_client")
    @patch("scripts.dispatcher.handler.s3_client")
    def test_skipped_event(self, mock_s3, mock_ecs, _reload_handler):
        event = _apigw_event(_linear_payload(state_name="In Progress"))
        resp = _reload_handler.handler(event, None)

        assert resp["statusCode"] == 200
        body = json.loads(resp["body"])
        assert "Skipped" in body["message"]
        mock_ecs.run_task.assert_not_called()

    @patch("scripts.dispatcher.handler.ecs_client")
    @patch("scripts.dispatcher.handler.s3_client")
    def test_ecs_failure_returns_500(self, mock_s3, mock_ecs, _reload_handler):
        from botocore.exceptions import ClientError

        mock_ecs.run_task.side_effect = ClientError(
            {"Error": {"Message": "Access denied", "Code": "403"}},
            "RunTask",
        )

        event = _apigw_event(_linear_payload())
        resp = _reload_handler.handler(event, None)
        assert resp["statusCode"] == 500

    @patch("scripts.dispatcher.handler.ecs_client")
    @patch("scripts.dispatcher.handler.s3_client")
    def test_invalid_webhook_returns_401(
        self, mock_s3, mock_ecs, _reload_handler, monkeypatch
    ):
        monkeypatch.setattr(_reload_handler, "WEBHOOK_SECRET", "my-secret")
        event = _apigw_event(_linear_payload())
        event["headers"] = {"x-linear-signature": "wrong"}
        resp = _reload_handler.handler(event, None)
        assert resp["statusCode"] == 401

    @patch("scripts.dispatcher.handler.ecs_client")
    @patch("scripts.dispatcher.handler.s3_client")
    def test_missing_field_returns_400(self, mock_s3, mock_ecs, _reload_handler):
        bad_payload = {
            "action": "update",
            "type": "Issue",
            "data": {
                "id": "x",
                "state": {"name": "Ready for Dev"},
                # missing "identifier"
            },
        }
        event = _apigw_event(bad_payload)
        resp = _reload_handler.handler(event, None)
        assert resp["statusCode"] == 400
