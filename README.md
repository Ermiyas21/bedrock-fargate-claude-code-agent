# Claude Code on AWS ECS Fargate

![Amazon Bedrock](https://img.shields.io/badge/Amazon%20Bedrock-232F3E?style=for-the-badge&logo=amazonaws&logoColor=white)
![AWS](https://img.shields.io/badge/AWS-%23FF9900.svg?style=for-the-badge&logo=amazon-web-services&logoColor=white)
![Claude Code](https://img.shields.io/badge/Claude%20Code-191919?style=for-the-badge&logo=anthropic&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-2496ED?style=for-the-badge&logo=docker&logoColor=white)
![AI Agent](https://img.shields.io/badge/AI%20Agent-6B4FBB?style=for-the-badge&logo=robot-framework&logoColor=white)

Headless Claude Code running on ECS Fargate with Amazon Bedrock for inference.  
Receives tickets from Linear via webhook, implements code changes, and creates PRs automatically.

---

## How It Works

Claude Code CLI runs inside a Docker container on ECS Fargate in **headless mode** (`-p` flag).

```
1. Linear webhook fires → API Gateway → Lambda dispatcher
2. Lambda uploads ticket to S3 and starts an ECS Fargate task
3. Container starts:
   ├── Clones your GitHub repo
   ├── Downloads ticket from S3
   ├── Runs: claude -p "implement this ticket..."
   │     ├── Inspects codebase
   │     ├── Implements changes
   │     ├── Creates tests
   │     └── Fixes lint issues
   ├── Runs test suite
   ├── Commits & pushes branch
   └── Creates Pull Request
```

**Bedrock API:** Uses `bedrock:InvokeModel` / `InvokeModelWithResponseStream` via the ECS task's IAM role. No API key needed — the env var `CLAUDE_CODE_USE_BEDROCK=1` routes all inference through Amazon Bedrock in `eu-west-2`.



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
│       │   ├── monitoring/     # CloudWatch alarms + SNS
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
│   │   ├── handler.py          # Lambda: webhook → ECS task
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
- **Bedrock access** enabled in `eu-west-2` for Claude models

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

Terraform creates: IAM roles, Secrets Manager secrets, ECR repo, S3 bucket, ECS cluster + task definition, Lambda function, API Gateway, CloudWatch alarms, and SNS topic.

### 2. Build & Push Docker Image

After `terraform apply`, get the push commands:

```bash
terraform output -raw docker_push_commands
```

Or manually:

```bash
# Authenticate Docker to ECR
aws ecr get-login-password --region eu-west-2 \
  | docker login --username AWS --password-stdin \
    YOUR_ACCOUNT_ID.dkr.ecr.eu-west-2.amazonaws.com

# Build for linux/amd64 (required for Fargate)
docker build --platform linux/amd64 -t claude-code-agent:latest docker/

# Tag and push
docker tag claude-code-agent:latest YOUR_ACCOUNT_ID.dkr.ecr.eu-west-2.amazonaws.com/claude-code-agent:latest
docker push YOUR_ACCOUNT_ID.dkr.ecr.eu-west-2.amazonaws.com/claude-code-agent:latest
```

### 3. Configure Linear Webhook

1. Go to **Linear → Settings → API → Webhooks**
2. Add webhook URL (from `terraform output webhook_url`)
3. Set the webhook secret: `terraform output -raw webhook_secret`
4. Subscribe to **Issue** events (state changes to "Ready for Dev")

---



## Environment Variables (ECS Task)

| Variable | Description | Default |
|----------|-------------|---------|
| `CLAUDE_CODE_USE_BEDROCK` | Enable Bedrock inference | `1` |
| `CLAUDE_MODEL_ID` | Bedrock model ID | `eu.anthropic.claude-sonnet-4-6` |
| `AWS_REGION` | AWS region | `eu-west-2` |
| `REPO_URL` | Repository to clone | Set per task |
| `TASK_ID` | Ticket identifier | Set per task |
| `TICKET_LOCATION` | S3 path to ticket JSON | Set per task |
| `BASE_BRANCH` | Branch to base work on | `main` |
| `TEST_COMMAND` | Command to run tests | `npm test` |
| `MAX_TURNS` | Max Claude iterations | `50` |
| `GITHUB_TOKEN_SECRET_ID` | GitHub PAT | Injected from Secrets Manager |

---

## Terraform Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `github_token` | Yes | GitHub PAT with `repo` scope |
| `subnet_ids` | Yes | VPC subnet IDs for ECS tasks |
| `security_group_ids` | Yes | Security group IDs |
| `aws_region` | No | AWS region (default: `eu-west-2`) |
| `claude_model_id` | No | Bedrock model (default: `eu.anthropic.claude-sonnet-4-6`) |
| `ecs_cpu` | No | Task CPU units (default: `4096`) |
| `ecs_memory` | No | Task memory MiB (default: `16384`) |
| `alarm_email` | No | Email for alarm notifications |

See `infra/terraform/environments/development/terraform.tfvars.example` for all options.

---

## Monitoring

| Alarm | Trigger |
|-------|---------|
| Task failures | >3 failures in 5 minutes |
| Long-running tasks | Task runs >30 minutes |
| Bedrock invocations | >500 calls/day |

Alarms notify via SNS topic `claude-code-agent-alerts`.


## Security

- **Code stays in AWS** — never leaves your VPC/account
- **Bedrock inference** — stays in `eu-west-2`, no external API calls
- **No secrets in images** — all injected from Secrets Manager at runtime
- **Branch-only access** — agent creates branches, never merges to main
- **Human review required** — all PRs need approval before merge
- **IAM least privilege** — each role has only the permissions it needs

---

## Destroy All Resources

```bash
cd infra/terraform/environments/development
terraform destroy
```

This removes everything: ECS cluster, Lambda, API Gateway, ECR (images), S3 bucket, secrets, IAM roles, CloudWatch alarms, and SNS topic.

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




## Next Plan

- 60–95% fewer tokens utilization for code generation in Claude Code
- Basic prompt engineering for better results in Claude Code


