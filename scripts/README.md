# scripts/

Utility scripts for operating the Claude Code agent.

## Files

| File | Purpose |
|------|---------|
| `run-task-manual.py` | Start an ECS task from CLI (bypass webhook) |
| `stop-task.py` | Kill a running task or all tasks (emergency stop) |

## dispatcher/

Lambda function code deployed to AWS. Receives Linear webhook events via API Gateway, validates the signature, uploads the ticket to S3, and starts an ECS Fargate task.

| File | Purpose |
|------|---------|
| `handler.py` | Lambda entry point (`handler` function) |
| `requirements.txt` | Lambda Python dependencies (boto3) |
| `__init__.py` | Package marker |

## Usage

```bash
# Manual task (no webhook needed)
python scripts/run-task-manual.py \
    --repo https://github.com/org/repo.git \
    --task-id TICKET-123 \
    --ticket-body "Implement feature X" \
    --subnets "subnet-aaa" \
    --security-groups "sg-bbb" \
    --wait

# Emergency stop all tasks
python scripts/stop-task.py --all
```
