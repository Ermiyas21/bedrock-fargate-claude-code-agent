"""
Lambda Dispatcher for Claude Code ECS Tasks.

Receives webhook events from Linear (or any ticketing system) via API Gateway,
validates the payload, and starts an ECS Fargate task to run Claude Code headless.
"""

import json
import os
import logging
from datetime import datetime

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Environment variables
ECS_CLUSTER = os.environ["ECS_CLUSTER"]
ECS_TASK_DEFINITION = os.environ["ECS_TASK_DEFINITION"]
SUBNETS = os.environ["SUBNETS"].split(",")
SECURITY_GROUPS = os.environ["SECURITY_GROUPS"].split(",")
CONTAINER_NAME = os.environ.get("CONTAINER_NAME", "claude-code-agent")
TICKET_BUCKET = os.environ["TICKET_BUCKET"]
WEBHOOK_SECRET = os.environ.get("WEBHOOK_SECRET", "")

# AWS clients
ecs_client = boto3.client("ecs")
s3_client = boto3.client("s3")


def handler(event, context):
    """
    Lambda handler for API Gateway webhook events.

    Expected payload from Linear webhook:
    {
        "action": "update",
        "type": "Issue",
        "data": {
            "id": "issue-id",
            "identifier": "TEAM-123",
            "title": "Issue title",
            "description": "Issue description",
            "state": { "name": "Ready for Dev" }
        }
    }
    """
    logger.info("Received event: %s", json.dumps(event))

    try:
        # Parse body from API Gateway
        body = _parse_body(event)

        # Validate webhook (optional signature verification)
        if WEBHOOK_SECRET:
            if not _validate_webhook(event, WEBHOOK_SECRET):
                return _response(401, {"error": "Invalid webhook signature"})

        # Check if this is a ticket transition to "Ready for Dev"
        if not _should_process(body):
            logger.info("Skipping event - not a qualifying state transition")
            return _response(200, {"message": "Skipped - not a qualifying event"})

        # Extract ticket data
        ticket_data = _extract_ticket(body)
        task_id = ticket_data["identifier"]

        # Upload ticket to S3
        ticket_key = f"tickets/{task_id}.json"
        s3_client.put_object(
            Bucket=TICKET_BUCKET,
            Key=ticket_key,
            Body=json.dumps(ticket_data),
            ContentType="application/json",
        )
        ticket_location = f"s3://{TICKET_BUCKET}/{ticket_key}"

        # Start ECS task
        task_arn = _start_ecs_task(task_id, ticket_location, ticket_data)

        logger.info("Started ECS task %s for ticket %s", task_arn, task_id)

        return _response(
            200,
            {
                "message": "Task started",
                "task_id": task_id,
                "task_arn": task_arn,
                "ticket_location": ticket_location,
            },
        )

    except KeyError as e:
        logger.error("Missing required field: %s", e)
        return _response(400, {"error": f"Missing required field: {e}"})
    except ClientError as e:
        logger.error("AWS error: %s", e)
        return _response(500, {"error": f"AWS error: {e.response['Error']['Message']}"})
    except Exception as e:
        logger.error("Unexpected error: %s", e, exc_info=True)
        return _response(500, {"error": "Internal server error"})


def _parse_body(event):
    """Parse the request body from API Gateway event."""
    body = event.get("body", "{}")
    if isinstance(body, str):
        return json.loads(body)
    return body


def _validate_webhook(event, secret):
    """Validate webhook signature (Linear uses HMAC-SHA256)."""
    import hmac
    import hashlib

    signature = event.get("headers", {}).get("x-linear-signature", "")
    body = event.get("body", "")
    if isinstance(body, dict):
        body = json.dumps(body)

    expected = hmac.new(
        secret.encode("utf-8"),
        body.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()

    return hmac.compare_digest(signature, expected)


def _should_process(body):
    """Check if the webhook event qualifies for processing."""
    action = body.get("action", "")
    issue_type = body.get("type", "")

    if action != "update" or issue_type != "Issue":
        return False

    # Check if state transitioned to "Ready for Dev"
    data = body.get("data", {})
    state = data.get("state", {})
    state_name = state.get("name", "")

    return state_name.lower() in ("ready for dev", "ready for development", "ai ready")


def _extract_ticket(body):
    """Extract ticket information from the webhook payload."""
    data = body["data"]
    return {
        "identifier": data["identifier"],
        "title": data.get("title", ""),
        "description": data.get("description", ""),
        "labels": [label.get("name", "") for label in data.get("labels", [])],
        "priority": data.get("priority", 0),
        "url": data.get("url", ""),
        "created_at": datetime.utcnow().isoformat(),
    }


def _start_ecs_task(task_id, ticket_location, ticket_data):
    """Start an ECS Fargate task for the given ticket."""
    response = ecs_client.run_task(
        cluster=ECS_CLUSTER,
        taskDefinition=ECS_TASK_DEFINITION,
        launchType="FARGATE",
        count=1,
        platformVersion="LATEST",
        networkConfiguration={
            "awsvpcConfiguration": {
                "subnets": SUBNETS,
                "securityGroups": SECURITY_GROUPS,
                "assignPublicIp": "DISABLED",
            }
        },
        overrides={
            "containerOverrides": [
                {
                    "name": CONTAINER_NAME,
                    "environment": [
                        {"name": "TASK_ID", "value": task_id},
                        {"name": "TICKET_LOCATION", "value": ticket_location},
                        {"name": "PR_TITLE", "value": f"feat: {ticket_data['title']}"},
                    ],
                }
            ]
        },
        tags=[
            {"key": "TaskId", "value": task_id},
            {"key": "LaunchedBy", "value": "claude-code-dispatcher"},
        ],
        capacityProviderStrategy=[
            {
                "capacityProvider": "FARGATE_SPOT",
                "weight": 1,
                "base": 0,
            }
        ],
    )

    tasks = response.get("tasks", [])
    if not tasks:
        failures = response.get("failures", [])
        raise RuntimeError(f"Failed to start ECS task: {failures}")

    return tasks[0]["taskArn"]


def _response(status_code, body):
    """Build API Gateway response."""
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
        },
        "body": json.dumps(body),
    }
