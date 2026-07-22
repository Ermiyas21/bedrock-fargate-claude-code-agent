"""
Manual task runner — start a Claude Code ECS task from the command line.

Usage:
    python run-task-manual.py \
        --repo https://github.com/org/repo.git \
        --task-id TICKET-123 \
        --ticket-body "Implement feature X..."

    python run-task-manual.py \
        --repo https://github.com/org/repo.git \
        --task-id TICKET-123 \
        --ticket-file ./ticket.json
"""

import argparse
import json
import sys
import time

import boto3


def main():
    parser = argparse.ArgumentParser(description="Start a Claude Code ECS task manually")
    parser.add_argument("--repo", required=True, help="Repository URL (https)")
    parser.add_argument("--task-id", required=True, help="Task/ticket identifier")
    parser.add_argument("--ticket-body", help="Ticket description as text")
    parser.add_argument("--ticket-file", help="Path to ticket JSON file")
    parser.add_argument("--base-branch", default="main", help="Base branch (default: main)")
    parser.add_argument("--model", default="eu.anthropic.claude-sonnet-4-6", help="Claude model ID")
    parser.add_argument("--test-command", default="npm test", help="Test command")
    parser.add_argument("--region", default="eu-west-2", help="AWS region")
    parser.add_argument("--cluster", default="claude-code-agent-cluster", help="ECS cluster name")
    parser.add_argument("--task-def", default="claude-code-agent-task", help="Task definition family")
    parser.add_argument("--subnets", required=True, help="Comma-separated subnet IDs")
    parser.add_argument("--security-groups", required=True, help="Comma-separated security group IDs")
    parser.add_argument("--wait", action="store_true", help="Wait for task to complete")

    args = parser.parse_args()

    # Validate inputs
    if not args.ticket_body and not args.ticket_file:
        print("ERROR: Provide either --ticket-body or --ticket-file")
        sys.exit(1)

    # Load ticket content
    if args.ticket_file:
        with open(args.ticket_file, "r") as f:
            ticket_data = json.load(f)
    else:
        ticket_data = {
            "identifier": args.task_id,
            "title": args.task_id,
            "description": args.ticket_body,
        }

    # Upload ticket to S3
    s3 = boto3.client("s3", region_name=args.region)
    ecs = boto3.client("ecs", region_name=args.region)

    account_id = boto3.client("sts").get_caller_identity()["Account"]
    bucket = f"claude-code-agent-tickets-{account_id}"
    ticket_key = f"tickets/{args.task_id}.json"

    print(f"Uploading ticket to s3://{bucket}/{ticket_key}...")
    s3.put_object(
        Bucket=bucket,
        Key=ticket_key,
        Body=json.dumps(ticket_data),
        ContentType="application/json",
    )

    # Start ECS task
    print(f"Starting ECS task for {args.task_id}...")
    response = ecs.run_task(
        cluster=args.cluster,
        taskDefinition=args.task_def,
        count=1,
        platformVersion="LATEST",
        networkConfiguration={
            "awsvpcConfiguration": {
                "subnets": args.subnets.split(","),
                "securityGroups": args.security_groups.split(","),
                "assignPublicIp": "ENABLED",
            }
        },
        overrides={
            "containerOverrides": [
                {
                    "name": "claude-code-agent",
                    "environment": [
                        {"name": "TASK_ID", "value": args.task_id},
                        {"name": "REPO_URL", "value": args.repo},
                        {"name": "BASE_BRANCH", "value": args.base_branch},
                        {"name": "CLAUDE_MODEL_ID", "value": args.model},
                        {"name": "TEST_COMMAND", "value": args.test_command},
                        {"name": "TICKET_LOCATION", "value": f"s3://{bucket}/{ticket_key}"},
                    ],
                }
            ]
        },
        capacityProviderStrategy=[
            {"capacityProvider": "FARGATE", "weight": 1, "base": 0}
        ],
        tags=[
            {"key": "TaskId", "value": args.task_id},
            {"key": "LaunchedBy", "value": "manual-runner"},
        ],
    )

    tasks = response.get("tasks", [])
    if not tasks:
        failures = response.get("failures", [])
        print(f"ERROR: Failed to start task: {failures}")
        sys.exit(1)

    task_arn = tasks[0]["taskArn"]
    task_id = task_arn.split("/")[-1]
    print(f"✓ Task started: {task_arn}")

    # Optionally wait for completion
    if args.wait:
        print("Waiting for task to complete...")
        waiter = ecs.get_waiter("tasks_stopped")
        waiter.wait(
            cluster=args.cluster,
            tasks=[task_arn],
            WaiterConfig={"Delay": 30, "MaxAttempts": 60},
        )

        # Get final status
        result = ecs.describe_tasks(cluster=args.cluster, tasks=[task_arn])
        task = result["tasks"][0]
        exit_code = task["containers"][0].get("exitCode", -1)
        status = task["lastStatus"]
        reason = task.get("stoppedReason", "")

        print(f"\nTask completed:")
        print(f"  Status: {status}")
        print(f"  Exit Code: {exit_code}")
        if reason:
            print(f"  Reason: {reason}")

        # Print log stream info
        print(f"\n  View logs:")
        print(f"  aws logs tail /ecs/claude-code-agent --follow --filter-pattern '{task_id}'")

        sys.exit(0 if exit_code == 0 else 1)
    else:
        print(f"\nTask running in background.")
        print(f"  Monitor: aws ecs describe-tasks --cluster {args.cluster} --tasks {task_arn}")
        print(f"  Logs:    aws logs tail /ecs/claude-code-agent --follow")
        print(f"  Stop:    aws ecs stop-task --cluster {args.cluster} --task {task_arn}")


if __name__ == "__main__":
    main()
