# infra/

AWS infrastructure definitions.

## Structure

```
infra/
├── task-definition.json          # Reference ECS task definition (for manual use)
└── terraform/
    ├── modules/                  # Reusable Terraform modules
    │   ├── ecr/                  # ECR repository + lifecycle policy
    │   ├── ecs/                  # S3 bucket, CloudWatch logs, ECS cluster + task def
    │   ├── iam/                  # IAM roles (ECS execution, task, Lambda)
    │   ├── lambda/               # Lambda function + API Gateway HTTP API
    │   ├── monitoring/           # CloudWatch alarms + SNS alerts
    │   └── secrets/              # Secrets Manager (GitHub token, webhook secret)
    └── environments/
        └── development/          # Dev environment wiring all modules together
```

## How it works

Each module is self-contained with `main.tf`, `variables.tf`, and `outputs.tf`. The environment directory composes all modules and passes values between them.

## Deploy

```bash
cd infra/terraform/environments/development
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars
export TF_VAR_github_token="ghp_..."
terraform init && terraform apply
```
