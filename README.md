# Claude Code on AWS ECS Fargate

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

---

## Architecture

```
Linear Webhook → API Gateway → Lambda Dispatcher → ECS Fargate Task
                                                         │
                                                         ├── Clone repo
                                                         ├── Read ticket (S3)
                                                         ├── Claude Code (Bedrock)
                                                         │     ├── Inspect codebase
                                                         │     ├── Implement changes
                                                         │     ├── Create tests
                                                         │     └── Fix lint issues
                                                         ├── Run test suite
                                                         ├── Commit & push branch
                                                         └── Create Pull Request
```

**AWS Services:** Bedrock, ECS Fargate, ECR, Lambda, API Gateway, S3, Secrets Manager, IAM, CloudWatch

---

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

## Testing the Full Pipeline

### Test 1: Manual Task (end-to-end without webhook)

```bash
pip install boto3

python scripts/run-task-manual.py \
    --repo https://github.com/YOUR_ORG/YOUR_REPO.git \
    --task-id TEST-001 \
    --ticket-body "Add a health check endpoint that returns HTTP 200 at /health" \
    --subnets "subnet-09b828c44a8e1d39b,subnet-0a81afeba14805ab2" \
    --security-groups "sg-089d58d1e4921f650" \
    --wait
```

This uploads a ticket to S3, starts an ECS task, and waits for completion. Check the output for:
- Exit Code **0** = success (PR created)
- Exit Code **1** = script error (check logs)

### Test 2: Lambda Invocation (simulate webhook)

```bash
# Get your webhook URL
WEBHOOK_URL=$(cd infra/terraform/environments/development && terraform output -raw webhook_url)

# Send a fake Linear webhook payload
curl -X POST "$WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d '{
    "action": "update",
    "type": "Issue",
    "data": {
      "id": "test-1",
      "identifier": "TEST-002",
      "title": "Add health check endpoint",
      "description": "Add a /health endpoint that returns HTTP 200 with JSON body {\"status\": \"ok\"}",
      "state": {"name": "Ready for Dev"}
    }
  }'
```

Expected response: `{"statusCode": 200, "body": "Task started"}`

### Test 3: View Logs (real-time)

```bash
# Follow all ECS task logs
aws logs tail /ecs/claude-code-agent --follow --region eu-west-2

# Filter by specific task ID
aws logs filter-log-events \
  --log-group-name /ecs/claude-code-agent \
  --filter-pattern "TEST-001" \
  --region eu-west-2
```

### Test 4: Stop a Runaway Task

```bash
# Stop specific task
python scripts/stop-task.py --task-arn arn:aws:ecs:eu-west-2:ACCOUNT:task/claude-code-agent-cluster/TASK_ID

# Emergency: kill all running tasks
python scripts/stop-task.py --all
```

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

---

## Cost Estimate

| Component | Typical Cost (per run) |
|-----------|----------------------|
| Bedrock tokens (Sonnet, ~50k in + 15k out) | ~$0.35–0.50 |
| ECS Fargate Spot (4 vCPU, 16 GB, 20 min) | ~$0.01–0.05 |
| S3, Lambda, API Gateway | Negligible |
| **Total per run** | **~$0.40–0.60** |
| **Monthly (50 runs/week)** | **~$80–120** |

---

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

## Step-by-Step Deployment Guide

Follow these steps **in order** to go from zero to a fully deployed pipeline.

### Step 1 — Prerequisites

```bash
# Verify tools are installed
terraform --version   # >= 1.5
aws sts get-caller-identity   # AWS CLI configured
docker --version
python3 --version   # >= 3.10
```

### Step 2 — Clone the Repo

```bash
git clone https://github.com/YOUR_ORG/YOUR_REPO.git
cd YOUR_REPO
```

### Step 3 — Run Tests Locally

```bash
pip install -r requirements-dev.txt
pip install -r scripts/dispatcher/requirements.txt
pytest tests/ -v
```

All tests should pass before proceeding.

### Step 4 — Configure Terraform Variables

```bash
cd infra/terraform/environments/development
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your subnet_ids, security_group_ids, etc.
```

### Step 5 — Deploy Infrastructure (Terraform)

```bash
export TF_VAR_github_token="github_pat_YOUR_TOKEN_HERE"

terraform init
terraform plan        # Review the plan
terraform apply       # Type 'yes' to confirm
```

This creates: IAM roles, ECR repo, S3 bucket, ECS cluster + task def, Lambda, API Gateway, CloudWatch alarms, SNS.

### Step 6 — Build & Push Docker Image

```bash
# Get push commands from Terraform output
terraform output -raw docker_push_commands

# Or manually:
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws ecr get-login-password --region eu-west-2 \
  | docker login --username AWS --password-stdin \
    ${AWS_ACCOUNT_ID}.dkr.ecr.eu-west-2.amazonaws.com

docker build --platform linux/amd64 -t claude-code-agent:latest docker/
docker tag claude-code-agent:latest ${AWS_ACCOUNT_ID}.dkr.ecr.eu-west-2.amazonaws.com/claude-code-agent:latest
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.eu-west-2.amazonaws.com/claude-code-agent:latest
```

### Step 7 — Configure Linear Webhook

1. Go to **Linear → Settings → API → Webhooks**
2. Add webhook URL: `terraform output -raw webhook_url`
3. Set secret: `terraform output -raw webhook_secret`
4. Subscribe to **Issue** events (state changes to "Ready for Dev")

### Step 8 — Set Up GitHub Actions (CI/CD)

**8a. Create an IAM OIDC provider for GitHub:**

```bash
# One-time setup — allows GitHub Actions to assume an IAM role
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

**8b. Create the deploy IAM role** (trust GitHub OIDC):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:YOUR_ORG/YOUR_REPO:*"
        }
      }
    }
  ]
}
```

Attach policies: `AmazonECR*`, `AWSLambda*`, and a custom policy for ECS/S3/Secrets if using Terraform apply from CI.

**8c. Add GitHub Secrets:**

In your repo → **Settings → Secrets and variables → Actions**:

| Secret | Value |
|--------|-------|
| `AWS_DEPLOY_ROLE_ARN` | `arn:aws:iam::ACCOUNT_ID:role/github-deploy-role` |
| `GH_PAT_FOR_AGENT` | GitHub PAT with `repo` scope |

### Step 9 — Verify the Pipeline

```bash
# Push to main — CI runs tests, Deploy builds Docker + updates Lambda
git add -A && git commit -m "chore: add CI/CD" && git push origin main
```

Check the **Actions** tab in GitHub to confirm both workflows pass.

### Step 10 — Test End-to-End

```bash
# Manual task test (no webhook needed)
python scripts/run-task-manual.py \
    --repo https://github.com/YOUR_ORG/YOUR_REPO.git \
    --task-id TEST-001 \
    --ticket-body "Add a health check endpoint that returns HTTP 200 at /health" \
    --subnets "subnet-xxx,subnet-yyy" \
    --security-groups "sg-zzz" \
    --wait
```

---

## Next Plan

- 60–95% fewer tokens utilization for code generation in Claude Code
- Basic prompt engineering for better results in Claude Code


