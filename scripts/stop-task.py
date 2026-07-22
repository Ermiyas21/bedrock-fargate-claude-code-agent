"""
Kill switch — stop a running Claude Code ECS task.

Usage:
    python stop-task.py --task-arn arn:aws:ecs:eu-west-2:123:task/cluster/task-id
    python stop-task.py --all  # Stop all running tasks in the cluster
"""

import argparse
import sys

import boto3


def main():
    parser = argparse.ArgumentParser(description="Stop Claude Code ECS tasks")
    parser.add_argument("--task-arn", help="Specific task ARN to stop")
    parser.add_argument("--all", action="store_true", help="Stop all running tasks")
    parser.add_argument("--cluster", default="claude-code-agent-cluster", help="ECS cluster")
    parser.add_argument("--region", default="eu-west-2", help="AWS region")
    parser.add_argument("--reason", default="Manual kill switch activated", help="Stop reason")

    args = parser.parse_args()

    if not args.task_arn and not args.all:
        print("ERROR: Provide --task-arn or --all")
        sys.exit(1)

    ecs = boto3.client("ecs", region_name=args.region)

    if args.all:
        # List all running tasks
        response = ecs.list_tasks(
            cluster=args.cluster,
            desiredStatus="RUNNING",
        )
        task_arns = response.get("taskArns", [])

        if not task_arns:
            print("No running tasks found.")
            return

        print(f"Stopping {len(task_arns)} task(s)...")
        for arn in task_arns:
            ecs.stop_task(cluster=args.cluster, task=arn, reason=args.reason)
            print(f"  ✓ Stopped: {arn}")
    else:
        ecs.stop_task(cluster=args.cluster, task=args.task_arn, reason=args.reason)
        print(f"✓ Stopped: {args.task_arn}")


if __name__ == "__main__":
    main()
