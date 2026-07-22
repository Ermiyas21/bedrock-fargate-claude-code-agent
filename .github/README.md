# .github/workflows/

CI/CD pipelines for the Claude Code agent.

## Workflows

| Workflow | Trigger | What it does |
|----------|---------|--------------|
| `ci.yml` | Push to `main`/`develop`, PRs | Run tests, ruff lint/format, Terraform validate |
| `deploy.yml` | Push to `main`, manual dispatch | Build Docker → ECR, deploy Lambda, Terraform apply |

## CI (`ci.yml`)

3 parallel jobs:
1. **test** — Install deps, run pytest
2. **lint** — ruff check + format check
3. **terraform-validate** — fmt, init, validate

## Deploy (`deploy.yml`)

4 jobs (all gated by tests):
1. **test** — Gate job
2. **docker** — Build & push image to ECR (on push to main)
3. **lambda** — Package & deploy Lambda code (on push to main)
4. **terraform** — Plan & apply (manual trigger only)

## Required secrets

| Secret | Purpose |
|--------|---------|
| `AWS_DEPLOY_ROLE_ARN` | IAM role for GitHub OIDC |
| `GH_PAT_FOR_AGENT` | GitHub PAT for Terraform |
| `TF_VARS_DEVELOPMENT` | terraform.tfvars content for dev |
