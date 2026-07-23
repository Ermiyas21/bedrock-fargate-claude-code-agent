# Claude Code on AWS ECS Fargate

![Amazon Bedrock](https://img.shields.io/badge/Amazon%20Bedrock-232F3E?style=for-the-badge&logo=amazonaws&logoColor=white)
![AWS](https://img.shields.io/badge/AWS-%23FF9900.svg?style=for-the-badge&logo=amazon-web-services&logoColor=white)
![Claude Code](https://img.shields.io/badge/Claude%20Code-191919?style=for-the-badge&logo=anthropic&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-2496ED?style=for-the-badge&logo=docker&logoColor=white)
![AI Agent](https://img.shields.io/badge/AI%20Agent-6B4FBB?style=for-the-badge&logo=robot-framework&logoColor=white)

Headless Claude Code running on ECS Fargate with Amazon Bedrock for inference.  
Receives tickets from Linear or Jira via webhook, implements code changes, and creates PRs automatically.

---

## How It Works

Claude Code CLI runs inside a Docker container on ECS Fargate (Spot) in **headless mode** (`-p` flag).

```
1. Linear/Jira webhook fires → API Gateway → Lambda dispatcher
2. Lambda uploads ticket to S3 and starts an ECS Fargate Spot task
3. Container starts:
   ├── Clones your GitHub repo
   ├── Downloads ticket from S3
   ├── Runs: claude -p "implement this ticket..."
   │     ├── Inspects & reviews codebase
   │     ├── Implements changes
   │     ├── Writes tests & verifies own work
   │     └── Auto-fixes lint & test errors until green
   ├── Runs test suite & autonomous code review
   ├── Commits & pushes branch
   └── Creates Pull Request
```

**Bedrock API:** Uses `bedrock:InvokeModel` / `InvokeModelWithResponseStream` via the ECS task's IAM role. No API key needed — `CLAUDE_CODE_USE_BEDROCK=1` routes inference through Amazon Bedrock in `eu-central-1`.

**Budget Kill Switch:** CloudWatch monitors token usage and cost. When limits are exceeded, a kill switch Lambda auto-terminates running tasks and revokes Bedrock API permissions.

**Observability:** CloudWatch dashboard tracks Lambda errors, Bedrock invocation errors/throttles/latency, token usage, and ECS task status. Metric filters on Lambda and ECS log groups surface errors automatically.



## Project Structure

```
.
├── .github/
│   └── workflows/
│       ├── ci.yml              # CI: test, lint, terraform validate
│       └── deploy.yml          # CD: build Docker, deploy Lambda, terraform apply
├── .gitignore
├── claude-code-aws-migration.md # Migration planning notes
├── docker/
│   ├── .dockerignore           # Docker build exclusions
│   ├── Dockerfile              # Claude Code container image
│   ├── entrypoint.sh           # Main task orchestration script
│   ├── requirements.txt        # Python deps for container
│   └── scripts/
│       └── healthcheck.sh      # Container healthcheck
├── infra/
│   ├── task-definition.json    # ECS task definition (reference)
│   └── terraform/
│       ├── modules/            # Reusable Terraform modules
│       │   ├── ecr/            # ECR repository
│       │   ├── ecs/            # S3, ECS cluster, task definition
│       │   ├── iam/            # IAM roles & policies
│       │   ├── lambda/         # Lambda + API Gateway
│       │   ├── monitoring/     # CloudWatch alarms, CloudTrail, SNS
│       │   ├── budget-kill-switch/ # Budget enforcement Lambda
│       │   └── secrets/        # Secrets Manager
│       └── environments/
│           └── development/    # Dev environment configuration
│               ├── main.tf     # Module composition
│               ├── providers.tf
│               ├── variables.tf
│               ├── outputs.tf
│               └── terraform.tfvars.example
├── scripts/
│   ├── dispatcher/
│   │   ├── __init__.py         # Package init
│   │   ├── handler.py          # Lambda: webhook → ECS task (Linear + Jira)
│   │   └── requirements.txt
│   ├── kill-switch/
│   │   ├── kill_switch.py      # Budget kill switch Lambda
│   │   └── requirements.txt
│   ├── run-task-manual.py      # Manual task runner (CLI)
│   └── stop-task.py            # Kill switch
├── tests/
│   ├── __init__.py             # Package init
│   └── test_dispatcher.py      # Unit tests for Lambda handler
├── requirements-dev.txt        # Dev/test dependencies
├── pytest.ini                  # Pytest configuration
└── README.md
```

---

## Quick Start (Terraform)

### Prerequisites

- **Terraform** >= 1.5
- **AWS CLI** configured with credentials (`aws sts get-caller-identity` works)
- **Docker** installed (for building the container image)
- **Python 3.10+** with `boto3` (for manual test scripts)
- **Bedrock access** enabled in `eu-central-1` for Claude models

### 1. Deploy Infrastructure

```bash
cd infra/terraform/environments/development

# Copy example vars and fill in your values
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your subnet_ids, security_group_ids, etc.

# Pass GitHub token securely via environment variable
export TF_VAR_github_token="github_pat_YOUR_TOKEN_HERE"

# Initialize and deploy
terraform init
terraform plan
terraform apply
```

Terraform creates: IAM roles, Secrets Manager secrets, ECR repo, S3 bucket, ECS cluster + task definition (Fargate Spot), Lambda dispatcher, API Gateway, CloudTrail (Bedrock audit), CloudWatch alarms + dashboard, SNS topic, and budget kill switch Lambda.

### 2. Build & Push Docker Image

After `terraform apply`, get the push commands:

```bash
terraform output -raw docker_push_commands
```

Or manually:

```bash
# Authenticate Docker to ECR
aws ecr get-login-password --region eu-central-1 \
  | docker login --username AWS --password-stdin \
    YOUR_ACCOUNT_ID.dkr.ecr.eu-central-1.amazonaws.com

# Build for linux/amd64 (required for Fargate)
docker build --platform linux/amd64 -t claude-code-agent:latest docker/

# Tag and push
docker tag claude-code-agent:latest YOUR_ACCOUNT_ID.dkr.ecr.eu-central-1.amazonaws.com/claude-code-agent:latest
docker push YOUR_ACCOUNT_ID.dkr.ecr.eu-central-1.amazonaws.com/claude-code-agent:latest
```

### 3. Configure Webhooks

#### Linear
1. Go to **Linear → Settings → API → Webhooks**
2. Add webhook URL (from `terraform output webhook_url`)
3. Set the webhook secret: `terraform output -raw webhook_secret`
4. Subscribe to **Issue** events (state changes to "Ready for Dev")

#### Jira
1. Go to **Jira → Settings → System → Webhooks**
2. Add webhook URL (same as Linear — `terraform output webhook_url`)
3. Configure webhook secret in Jira settings
4. Subscribe to **Issue updated** events
5. Filter by status transition to "Ready for Dev" or "Selected for Development"

---



## Environment Variables (ECS Task)

| Variable | Description | Default |
|----------|-------------|---------|
| `CLAUDE_CODE_USE_BEDROCK` | Enable Bedrock inference | `1` |
| `CLAUDE_MODEL_ID` | Bedrock model ID | `us.anthropic.claude-sonnet-4-6` |
| `AWS_REGION` | Bedrock inference region | `eu-central-1` |
| `AWS_DEFAULT_REGION` | Primary AWS region | `eu-central-1` |
| `REPO_URL` | Repository to clone | Set per task |
| `TASK_ID` | Ticket identifier | Set per task |
| `TICKET_LOCATION` | S3 path to ticket JSON | Set per task |
| `BASE_BRANCH` | Branch to base work on | `main` |
| `TEST_COMMAND` | Command to run tests | `npm test` |
| `MAX_TURNS` | Max Claude iterations | `50` |
| `GIT_CREDENTIALS_SECRET_ID` | GitHub PAT | Injected from Secrets Manager |

---

## Terraform Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `github_token` | Yes | GitHub PAT with `repo` scope |
| `subnet_ids` | Yes | VPC subnet IDs for ECS tasks |
| `security_group_ids` | Yes | Security group IDs |
| `aws_region` | No | Primary AWS region (default: `eu-central-1`) |
| `bedrock_region` | No | Bedrock inference region (default: `eu-central-1`) |
| `claude_model_id` | No | Bedrock model (default: `us.anthropic.claude-sonnet-4-6`) |
| `ecs_cpu` | No | Task CPU units (default: `4096`) |
| `ecs_memory` | No | Task memory MiB (default: `16384`) |
| `alarm_email` | No | Email for alarm notifications |
| `daily_token_limit` | No | Max daily tokens before kill switch (default: `5000000`) |
| `daily_cost_limit` | No | Max daily cost USD before kill switch (default: `50`) |

See `infra/terraform/environments/development/terraform.tfvars.example` for all options.

---

## Observability & Governance

### Monitoring

| Component | Purpose |
|-----------|---------|
| **CloudTrail** | Audit all Bedrock API invocation logs |
| **CloudWatch Metrics** | Bedrock invocation counts, token usage, latency |
| **CloudWatch Log Groups** | Dedicated logs for Lambda dispatcher, kill switch, and ECS agent |
| **CloudWatch Metric Filters** | Auto-detect `ERROR` patterns in Lambda and ECS logs |
| **CloudWatch Dashboard** | Single-pane view of Lambda, Bedrock, and ECS health |
| **CloudWatch Alarms** | Task failures, long-running tasks, Bedrock errors/throttles, Lambda errors |
| **SNS Notifications** | Alerts on high usage, errors, budget breaches |

### CloudWatch Dashboard

Access the dashboard after deploy:
```bash
terraform output cloudwatch_dashboard
# Open: https://eu-central-1.console.aws.amazon.com/cloudwatch/home?region=eu-central-1#dashboards/claude-code-agent-observability
```

Dashboard panels:
- **Lambda Dispatcher** — invocations, errors, throttles, duration
- **Bedrock** — invocations, client/server errors, throttles, latency, token usage
- **ECS** — running task count, task failures
- **Recent Errors** — log insights queries for Lambda and ECS error logs

### Alarms

| Alarm | Trigger |
|-------|---------|
| Task failures | >3 failures in 5 minutes |
| Long-running tasks | Task runs >30 minutes |
| Bedrock invocations | >500 calls/day |
| Bedrock client errors | Any `InvocationClientErrors` |
| Bedrock throttles | >5 `InvocationThrottles` in 5 minutes |
| Lambda errors | Any Lambda invocation `Errors` |
| Lambda high duration | Duration >25s (approaching 30s timeout) |
| ECS agent errors | >3 `ERROR` log entries in 5 minutes |
| Token budget | Exceeds daily token limit → triggers kill switch |
| Kill switch errors | Kill switch Lambda itself is failing |

### Debugging Errors

**Lambda dispatcher errors:**
```bash
aws logs tail /aws/lambda/claude-code-agent-dispatcher --follow --filter-pattern "ERROR"
```

**Bedrock invocation errors:**
```bash
aws logs tail /ecs/claude-code-agent --follow --filter-pattern "bedrock"
```

**ECS agent errors:**
```bash
aws logs tail /ecs/claude-code-agent --follow --filter-pattern "ERROR"
```

### Budget Kill Switch

When token usage exceeds the configured limit:
1. CloudWatch alarm fires → SNS → Kill Switch Lambda
2. Lambda stops all running ECS tasks in the cluster
3. Lambda attaches an IAM deny policy to the ECS task role, blocking all `bedrock:InvokeModel` calls
4. SNS notification sent to alert subscribers

The kill switch also runs on a 5-minute schedule via EventBridge for proactive monitoring.

Alarms notify via SNS topic `claude-code-agent-alerts`.


## Security

- **Code stays in AWS** — never leaves your VPC/account
- **Bedrock inference** — in `eu-central-1`, no external API calls
- **No secrets in images** — all injected from Secrets Manager at runtime
- **Branch-only access** — agent creates branches, never merges to main
- **Human review required** — all PRs need approval before merge
- **IAM least privilege** — each role has only the permissions it needs
- **CloudTrail audit** — all Bedrock API calls logged for compliance
- **Budget enforcement** — automatic kill switch prevents runaway costs

---

## Destroy All Resources

```bash
cd infra/terraform/environments/development
terraform destroy
```

This removes everything: ECS cluster, Lambda functions, API Gateway, ECR (images), S3 buckets, secrets, IAM roles, CloudWatch alarms, CloudTrail, and SNS topic.

---

## CI/CD — GitHub Actions

Two workflows automate testing and deployment:

| Workflow | File | Trigger | What it does |
|----------|------|---------|--------------|
| **CI** | `.github/workflows/ci.yml` | Push to `main`/`develop`, PRs | Run tests, lint (ruff), validate Terraform |
| **Deploy** | `.github/workflows/deploy.yml` | Push to `main`, manual dispatch | Build Docker → ECR, deploy Lambda, Terraform apply |

### Required GitHub Secrets

| Secret | Description |
|--------|-------------|
| `AWS_DEPLOY_ROLE_ARN` | ARN of the IAM role for GitHub OIDC (see setup below) |
| `GH_PAT_FOR_AGENT` | GitHub PAT with `repo` scope (used by Terraform / ECS tasks) |

---


## How to provide the tokens (at deploy time) 

# Pass ALL tokens as env vars — never hardcode in files
export TF_VAR_github_token="github_pat_YOUR_TOKEN"
export TF_VAR_jira_token="your_jira_api_token"
export TF_VAR_linear_token="lin_api_YOUR_TOKEN"
export TF_VAR_anthropic_api_key="sk-ant-YOUR_KEY"

cd infra/terraform/environments/development
terraform apply 


## Building docker images and push 

NOTE: Make sure Docker Desktop is running before you start. The build takes a few minutes (installs Node, AWS CLI, GitHub CLI, and Claude Code CLI).

 
1. Step 1 — Authenticate Docker to ECR: 

aws ecr get-login-password --region eu-central-1 | docker login --username AWS --password-stdin 260073348880.dkr.ecr.eu-central-1.amazonaws.com/claude-code-agent

2. Step 2 - Build the image (linux/amd64 for rargate)

docker build --platform linux/amd64 -t claude-code-agent:latest docker/

3. Step 3 — Tag and push:

docker tag claude-code-agent:latest 260073348880.dkr.ecr.eu-central-1.amazonaws.com/claude-code-agent:latest

docker push 260073348880.dkr.ecr.eu-central-1.amazonaws.com/claude-code-agent:latest 




## upload the jira ticket into S3 bucket 
- /Volumes/data/project/bedrock-fargate-claude-code-agent/data  
- aws s3 cp data/RECO-101.json s3://claude-code-agent-tickets-260073348880/tickets/RECO-101.json --region eu-central-1 

- Then trigger the agent manually with it : 
 
 python scripts/run-task-manual.py \
  --repo https://github.com/Ermiyas2146/claude-code-repo.git \
  --task-id RECO-101 \
  --ticket-file data/RECO-101.json \
  --subnets "subnet-0417c686623f80fa6" \
  --security-groups "sg-0d7c10ef18b64cadb" \
  --wait 


## Next Plan

- 60–95% fewer tokens utilization for code generation in Claude Code
- Basic prompt engineering for better results in Claude Code


