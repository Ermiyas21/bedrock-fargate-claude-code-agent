# docker/

Claude Code agent container image for ECS Fargate.

## What it does

1. Installs Node.js, Python, AWS CLI, GitHub CLI, and Claude Code CLI
2. On startup (`entrypoint.sh`) orchestrates the full workflow:
   - Fetches GitHub token from Secrets Manager
   - Clones the target repository
   - Downloads the ticket from S3
   - Runs `claude -p` in headless mode to implement the ticket
   - Runs the test suite
   - Commits, pushes a branch, and creates a Pull Request

## Build

```bash
docker build --platform linux/amd64 -t claude-code-agent:latest docker/
```

## Files

| File | Purpose |
|------|---------|
| `Dockerfile` | Multi-stage image build (Node 22 base) |
| `entrypoint.sh` | Main orchestration script (8 steps) |
| `requirements.txt` | Python deps for helper scripts |
| `scripts/healthcheck.sh` | Container health check |
| `.dockerignore` | Build context exclusions |
