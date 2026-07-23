#!/bin/bash
set -euo pipefail

echo "============================================"
echo " Claude Code AI Developer - Task Starting"
echo " Task ID: ${TASK_ID:-unknown}"
echo " Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "============================================"

# ------------------------------------------------------------------
# 1. Fetch secrets from AWS Secrets Manager
# ------------------------------------------------------------------
echo "[1/8] Fetching secrets..."

# GITHUB_TOKEN can come from:
#   1. Direct env var (set by ECS secrets injection — value is already the token)
#   2. GIT_CREDENTIALS_SECRET_ID containing a Secrets Manager secret name
if [ -z "${GITHUB_TOKEN:-}" ]; then
    if [ -n "${GIT_CREDENTIALS_SECRET_ID:-}" ]; then
        # Check if the value looks like a Secrets Manager secret name (not a raw token)
        if echo "$GIT_CREDENTIALS_SECRET_ID" | grep -qE "^(github_pat_|ghp_|gho_|ghu_)"; then
            # Value is already a raw token (injected by ECS secrets block)
            export GITHUB_TOKEN="$GIT_CREDENTIALS_SECRET_ID"
        else
            export GITHUB_TOKEN=$(aws secretsmanager get-secret-value \
                --secret-id "$GIT_CREDENTIALS_SECRET_ID" \
                --query SecretString --output text \
                --region "${AWS_DEFAULT_REGION:-eu-central-1}")
        fi
    fi
fi

if [ -z "${JIRA_TOKEN:-}" ] && [ -n "${JIRA_TOKEN_SECRET_ID:-}" ]; then
    export JIRA_TOKEN=$(aws secretsmanager get-secret-value \
        --secret-id "$JIRA_TOKEN_SECRET_ID" \
        --query SecretString --output text \
        --region "${AWS_DEFAULT_REGION:-eu-central-1}") || true
fi

# Linear API token (for updating issue status)
if [ -z "${LINEAR_TOKEN:-}" ] && [ -n "${LINEAR_TOKEN_SECRET_ID:-}" ]; then
    export LINEAR_TOKEN=$(aws secretsmanager get-secret-value \
        --secret-id "$LINEAR_TOKEN_SECRET_ID" \
        --query SecretString --output text \
        --region "${AWS_DEFAULT_REGION:-eu-central-1}") || true
fi

# Anthropic API key (long-term Claude Code token — fallback when not using Bedrock)
# When ANTHROPIC_API_KEY is set, Claude Code can use it directly.
# If CLAUDE_CODE_USE_BEDROCK=1, Bedrock is used instead and this key is optional.
if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
    echo "  Anthropic API key configured (Claude Code direct access available)"
fi

# Configure git credentials
echo "[2/8] Configuring git..."
git config --global credential.helper store
echo "https://x-access-token:${GITHUB_TOKEN}@github.com" > ~/.git-credentials
git config --global user.email "claude-code-bot@company.com"
git config --global user.name "Claude Code Bot"

# Authenticate GitHub CLI
# When GITHUB_TOKEN env var is set, gh uses it automatically.
# Only call gh auth login if it's not already authenticated.
echo "${GITHUB_TOKEN}" | gh auth login --with-token 2>&1 || echo "Note: gh auth via env var GITHUB_TOKEN"
gh auth status 2>&1 || true

# ------------------------------------------------------------------
# 2. Clone the repository
# ------------------------------------------------------------------
echo "[3/8] Cloning repository: ${REPO_URL}"
git clone "https://x-access-token:${GITHUB_TOKEN}@${REPO_URL#https://}" /workspace/repo
cd /workspace/repo

# Checkout base branch
BASE_BRANCH="${BASE_BRANCH:-main}"
git checkout "$BASE_BRANCH"
git pull origin "$BASE_BRANCH"

# ------------------------------------------------------------------
# 3. Download ticket/task description
# ------------------------------------------------------------------
echo "[4/8] Downloading ticket..."

if [ -n "${TICKET_LOCATION:-}" ]; then
    aws s3 cp "$TICKET_LOCATION" /workspace/ticket.json --region "${AWS_DEFAULT_REGION:-eu-central-1}"
    TICKET_CONTENT=$(cat /workspace/ticket.json)
elif [ -n "${TICKET_BODY:-}" ]; then
    TICKET_CONTENT="$TICKET_BODY"
else
    echo "ERROR: No ticket source specified (TICKET_LOCATION or TICKET_BODY)"
    exit 1
fi

echo "Ticket loaded successfully."

# ------------------------------------------------------------------
# 4. Create feature branch
# ------------------------------------------------------------------
BRANCH_NAME="ai/${TASK_ID:-$(date +%s)}"
echo "[5/8] Creating branch: ${BRANCH_NAME}"
git checkout -b "$BRANCH_NAME"

# ------------------------------------------------------------------
# 5. Run Claude Code in headless mode
# ------------------------------------------------------------------
echo "[6/8] Running Claude Code..."

CLAUDE_PROMPT="You are an AI developer implementing a task. Here is the task description:

${TICKET_CONTENT}

Requirements:
- Follow the existing coding standards and patterns in this repository
- Read and understand the codebase structure before making changes
- Implement the feature/fix described in the task
- Add appropriate tests for your changes
- Fix any lint issues introduced by your changes
- Run the test suite and fix any failures
- Ensure all tests pass before finishing

Steps:
1. Read the ticket carefully
2. Inspect the codebase structure and relevant files
3. Search for related code patterns
4. Implement the changes
5. Create or update tests
6. Run tests and fix any issues
7. Fix lint/formatting issues

Do NOT commit or push - just make the code changes."

# Set Bedrock environment for Claude Code
export CLAUDE_CODE_USE_BEDROCK="${CLAUDE_CODE_USE_BEDROCK:-1}"
export ANTHROPIC_MODEL="${CLAUDE_MODEL_ID:-us.anthropic.claude-sonnet-4-6}"

claude -p "$CLAUDE_PROMPT" \
    --max-turns "${MAX_TURNS:-50}" \
    --output-format text \
    2>&1 | tee /workspace/claude-output.log

CLAUDE_EXIT_CODE=${PIPESTATUS[0]}

if [ $CLAUDE_EXIT_CODE -ne 0 ]; then
    echo "WARNING: Claude Code exited with code $CLAUDE_EXIT_CODE"
fi

# ------------------------------------------------------------------
# 6. Run test suite
# ------------------------------------------------------------------
echo "[7/8] Running tests..."

TEST_COMMAND="${TEST_COMMAND:-npm test}"
if $TEST_COMMAND 2>&1 | tee /workspace/test-output.log; then
    echo "Tests passed!"
else
    echo "Tests failed. Attempting fix with Claude Code..."
    TEST_OUTPUT=$(cat /workspace/test-output.log)

    claude -p "The tests are failing. Here is the test output:

${TEST_OUTPUT}

Please fix the failing tests. Make sure all tests pass.
Do NOT commit or push." \
        --max-turns 20 \
        --output-format text

    # Retry tests
    if $TEST_COMMAND; then
        echo "Tests passed after fix!"
    else
        echo "WARNING: Tests still failing after retry. Proceeding with PR anyway."
    fi
fi

# ------------------------------------------------------------------
# 7. Commit and push
# ------------------------------------------------------------------
echo "[8/8] Committing and pushing..."

# Check if there are changes to commit
if git diff --quiet && git diff --staged --quiet; then
    echo "No changes were made. Exiting."
    exit 1
fi

git add -A
git commit -m "feat: AI implementation for ${TASK_ID}

Implemented by Claude Code (headless).
Task: ${TASK_ID}
Model: ${CLAUDE_MODEL_ID:-us.anthropic.claude-sonnet-4-6}"

git push origin "$BRANCH_NAME"

# ------------------------------------------------------------------
# 8. Create Pull Request
# ------------------------------------------------------------------
PR_TITLE="${PR_TITLE:-feat: AI implementation ${TASK_ID}}"
PR_BODY="## AI-Generated Implementation

**Task ID:** ${TASK_ID}
**Model:** ${CLAUDE_MODEL_ID:-us.anthropic.claude-sonnet-4-6}
**Branch:** ${BRANCH_NAME}

### Summary
This PR was generated by Claude Code running in headless mode on ECS Fargate.

### Changes
$(git log ${BASE_BRANCH}..HEAD --oneline)

### Test Results
Tests were executed as part of the CI pipeline within the container.

---
*⚠️ This PR requires human review before merging.*"

gh pr create \
    --title "$PR_TITLE" \
    --body "$PR_BODY" \
    --base "$BASE_BRANCH" \
    --head "$BRANCH_NAME"

echo "============================================"
echo " Task completed successfully!"
echo " Branch: ${BRANCH_NAME}"
echo " PR created."
echo "============================================"
