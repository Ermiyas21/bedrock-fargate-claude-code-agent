"""
Bedrock Budget Kill Switch Lambda.

Auto-terminates ECS tasks and revokes Bedrock API permissions
when cost/token limits are exceeded.
"""

import json
import os
import logging
from datetime import datetime, timedelta

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ECS_CLUSTER = os.environ["ECS_CLUSTER"]
ECS_TASK_ROLE_NAME = os.environ["ECS_TASK_ROLE_NAME"]
DAILY_TOKEN_LIMIT = int(os.environ.get("DAILY_TOKEN_LIMIT", "5000000"))
DAILY_COST_LIMIT = float(os.environ.get("DAILY_COST_LIMIT", "50"))
BEDROCK_REGION = os.environ.get("BEDROCK_REGION", "eu-central-1")
SNS_TOPIC_ARN = os.environ.get("SNS_TOPIC_ARN", "")

ecs_client = boto3.client("ecs")
iam_client = boto3.client("iam")
cloudwatch_client = boto3.client("cloudwatch", region_name=BEDROCK_REGION)
sns_client = boto3.client("sns")


def handler(event, context):
    """Check Bedrock usage and kill tasks if budget exceeded."""
    logger.info("Budget check triggered: %s", json.dumps(event, default=str))

    try:
        token_usage = _get_daily_token_usage()
        logger.info("Daily token usage: %d (limit: %d)", token_usage, DAILY_TOKEN_LIMIT)

        if token_usage > DAILY_TOKEN_LIMIT:
            logger.warning("TOKEN BUDGET EXCEEDED: %d > %d", token_usage, DAILY_TOKEN_LIMIT)
            _kill_all_tasks()
            _revoke_bedrock_access()
            _notify(f"Bedrock token budget exceeded: {token_usage:,} tokens (limit: {DAILY_TOKEN_LIMIT:,})")
            return {"action": "killed", "reason": "token_limit", "usage": token_usage}

        logger.info("Budget OK — usage within limits")
        return {"action": "ok", "token_usage": token_usage}

    except Exception as e:
        logger.error("Kill switch error: %s", e, exc_info=True)
        _notify(f"Kill switch error: {e}")
        raise


def _get_daily_token_usage():
    """Get today's total Bedrock token usage from CloudWatch metrics."""
    now = datetime.utcnow()
    start = now.replace(hour=0, minute=0, second=0, microsecond=0)

    response = cloudwatch_client.get_metric_statistics(
        Namespace="AWS/Bedrock",
        MetricName="InputTokenCount",
        StartTime=start,
        EndTime=now,
        Period=86400,
        Statistics=["Sum"],
    )

    datapoints = response.get("Datapoints", [])
    if not datapoints:
        return 0

    return int(sum(dp["Sum"] for dp in datapoints))


def _kill_all_tasks():
    """Stop all running ECS tasks in the cluster."""
    logger.info("Stopping all tasks in cluster: %s", ECS_CLUSTER)

    paginator = ecs_client.get_paginator("list_tasks")
    for page in paginator.paginate(cluster=ECS_CLUSTER, desiredStatus="RUNNING"):
        for task_arn in page.get("taskArns", []):
            logger.info("Stopping task: %s", task_arn)
            ecs_client.stop_task(
                cluster=ECS_CLUSTER,
                task=task_arn,
                reason="Budget kill switch — Bedrock usage limit exceeded",
            )


def _revoke_bedrock_access():
    """Attach a deny policy to the ECS task role to block Bedrock calls."""
    logger.info("Revoking Bedrock access for role: %s", ECS_TASK_ROLE_NAME)

    deny_policy = json.dumps({
        "Version": "2012-10-17",
        "Statement": [
            {
                "Sid": "BudgetKillSwitchDeny",
                "Effect": "Deny",
                "Action": [
                    "bedrock:InvokeModel",
                    "bedrock:InvokeModelWithResponseStream",
                ],
                "Resource": "*",
            }
        ],
    })

    iam_client.put_role_policy(
        RoleName=ECS_TASK_ROLE_NAME,
        PolicyName="bedrock-budget-kill-switch-deny",
        PolicyDocument=deny_policy,
    )

    logger.info("Bedrock access revoked via deny policy")


def _notify(message):
    """Send alert notification via SNS."""
    if not SNS_TOPIC_ARN:
        logger.warning("No SNS_TOPIC_ARN configured — skipping notification")
        return

    sns_client.publish(
        TopicArn=SNS_TOPIC_ARN,
        Subject="Bedrock Budget Kill Switch Activated",
        Message=message,
    )
