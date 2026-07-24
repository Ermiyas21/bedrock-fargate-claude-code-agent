# Headless Claude Code — Where Should the Agent Container Run?

---

---

## 1. The Problem

Claude Code already handles the **code → build → test → fix** loop natively. We don't need to build an agent framework — we just need somewhere to run it.

The question this document answers: **should that "somewhere" be our own AWS infrastructure, or Anthropic's hosted agent platform?**

---

## 2. The Flow

Regardless of where the container runs, the workflow is the same:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         TICKET-TO-PR AGENT FLOW                              │
│                                                                              │
│  ┌─────────────┐     ┌─────────────┐     ┌──────────────┐     ┌──────────┐ │
│  │ 1. TRIGGER   │     │ 2. SPIN UP  │     │ 3. AGENT     │     │ 4. PR    │ │
│  │              │     │             │     │    LOOP       │     │          │ │
│  │ Ticket moves │────▶│ Container   │────▶│ Claude Code   │────▶│ Create   │ │
│  │ to "Ready    │     │ starts      │     │ runs headless │     │ PR for   │ │
│  │ for Dev" in  │     │ (ECS task   │     │              │     │ engineer │ │
│  │ Linear       │     │  or Managed │     │ clone repo   │     │ to review│ │
│  │              │     │  Agent      │     │ read ticket  │     │ & merge  │ │
│  │ Webhook fires│     │  session)   │     │ write code   │     │          │ │
│  │              │     │             │     │ run tests    │     │          │ │
│  └─────────────┘     └─────────────┘     │ fix failures │     └──────────┘ │
│                                           │ loop until   │                  │
│                                           │ green        │                  │
│                                           └──────────────┘                  │
│                                                                              │
│  The only variable: WHERE does step 2 run?                                  │
│                                                                              │
│  Option A: Our AWS account (ECS Fargate + Claude Code headless container)   │
│  Option B: Anthropic's infra (Claude Managed Agents)                        │
└──────────────────────────────────────────────────────────────────────────────┘
```

**Trigger detail** — Linear (or any ticketing system) fires a webhook when a ticket moves to "Ready for Dev". This hits an API Gateway + Lambda dispatcher that either starts an ECS task (Option A) or creates a Managed Agent session (Option B). The agent clones the repo, reads the ticket description, works the code, loops `claude -p` until tests pass, and opens a PR.

---

## 3. Option A — Self-Hosted on AWS (ECS Fargate)

We build and run our own headless Claude Code container on ECS Fargate, using Amazon Bedrock for inference. A reference implementation exists at [akadesilva/claude-code-headless](https://github.com/akadesilva/claude-code-headless).

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    OPTION A — SELF-HOSTED (ECS FARGATE)                       │
│                                                                              │
│  ┌───────────┐     ┌──────────────┐     ┌────────────────────────────────┐  │
│  │ Linear     │     │ API Gateway  │     │ ECS Fargate Task               │  │
│  │ Webhook    │────▶│ + Lambda     │────▶│                                │  │
│  │            │     │ (dispatcher) │     │  ┌──────────────────────────┐  │  │
│  └───────────┘     └──────────────┘     │  │ Claude Code Headless     │  │  │
│                                          │  │ Container                │  │  │
│                                          │  │                          │  │  │
│                                          │  │ • Clone repo             │  │  │
│                                          │  │ • Read ticket from S3    │  │  │
│                                          │  │ • claude -p "implement   │  │  │
│                                          │  │   the ticket, run tests, │  │  │
│                                          │  │   fix until green"       │  │  │
│                                          │  │ • Commit + push branch   │  │  │
│                                          │  │ • gh pr create           │  │  │
│                                          │  └──────────────────────────┘  │  │
│                                          │                                │  │
│                                          │  Env vars (from Secrets Mgr): │  │
│                                          │  CLAUDE_CODE_USE_BEDROCK=1     │  │
│                                          │  CLAUDE_MODEL_ID=us.anthropic. │  │
│                                          │    claude-sonnet-4-6           │  │
│                                          │  GIT_CREDENTIALS_SECRET_ID=... │  │
│                                          │  AWS_REGION=eu-west-2          │  │
│                                          │                                │  │
│                                          │  4 vCPU, 16 GB RAM, Spot      │  │
│                                          │  Timeout: 30 min              │  │
│                                          └────────────────────────────────┘  │
│                                                     │                        │
│                                          ┌──────────▼──────────┐            │
│                                          │  Amazon Bedrock      │            │
│                                          │  (eu-west-2 region)  │            │
│                                          │  Claude inference     │            │
│                                          └─────────────────────┘            │
│                                                                              │
│  YOU BUILD: Container image, ECS task def, Lambda dispatcher, IAM roles,    │
│             Secrets Manager entries, VPC/subnets, CloudWatch alarms          │
│  YOU MAINTAIN: Container updates, Claude Code CLI version, infra lifecycle  │
└──────────────────────────────────────────────────────────────────────────────┘
```






### 6.1 Cost Breakdown per Agent Run

| Cost Component | Option A (Self-Hosted) | Option B (Managed Agents) |
|---|---|---|
| **Inference tokens** | Bedrock pricing: Sonnet ~$3/$15 per MTok in/out | Anthropic API pricing: same model rates |
| **Compute** | ECS Fargate Spot: ~$0.01–0.05 per run (4 vCPU, 16 GB, 20 min avg) | Session runtime fee (billed per millisecond while `running`) |
| **Infrastructure** | Lambda, API Gateway, Secrets Manager, S3 — negligible | None |
| **Typical run (20 min, Sonnet, ~50k input + 15k output tokens)** | **~$0.40–0.60** total | **~$0.40–0.80** total (tokens + runtime) |
| **Monthly estimate (50 agent runs/week)** | **$80–$120/month** | **$80–$160/month** |

### 6.2 Cost Control Levers

| Lever | Option A | Option B |
|---|---|---|
| **Model choice** | Set `CLAUDE_MODEL_ID` env var. Use Sonnet for most tasks, Haiku for simple ones. Restrict via IAM policy. | Set model in agent config. Same choice: Sonnet vs Haiku vs Opus. |
| **Token limits** | Set `--max-tokens` flag on `claude -p`. Cap context window. | Managed via session configuration. |
| **Timeouts** | ECS task timeout (e.g. 30 min). Step Functions can enforce max iterations. | Send interrupt event to stop a session. Set timeouts in your dispatcher. |
| **Iteration cap** | Control in your orchestration logic (Step Functions choice state). | Send steering events or interrupt after N tool calls. |
| **Budget alarms** | CloudWatch on Bedrock spend + Fargate spend. AWS Budgets for hard caps. | Anthropic Usage API. No native budget caps — must build your own. |
| **Prompt caching** | `ENABLE_PROMPT_CACHING_1H=1` — up to 90% input cost reduction for repeated context. | Prompt caching applies identically to Managed Agent sessions. |
| **Spot pricing** | ECS Fargate Spot saves ~70% on compute. | Not applicable — no compute to manage. |

**Bottom line on cost:** Token costs are comparable. Option A has cheaper compute (Fargate Spot) but more infra to manage. Option B charges session runtime but you skip Fargate costs. At low-to-moderate volume (<200 runs/month), the difference is marginal. At high volume, Option A gives more cost levers.

---

## 7. Security — Where Does Our Code Go?

This is the most important section for most teams.

### 7.1 Data Flow Comparison

┌──────────────────────────────────────────────────────────────────────────────┐
│                           DATA FLOW — OPTION A                               │
│                     (Self-Hosted on AWS, Bedrock inference)                   │
│                                                                              │
│  Your code ──▶ ECS container (your VPC) ──▶ Bedrock (your AWS region)       │
│                                                                              │
│  ✓ Code never leaves your AWS account                                       │
│  ✓ Inference in eu-west-2 if Bedrock is available there                     │
│  ✓ Git credentials in Secrets Manager, scoped to specific repos             │
│  ✓ Private subnets, no inbound internet, VPC endpoints optional             │
│  ✓ Covered by your existing AWS BAA / SOC2 / DPA                           │
│  ✓ CloudTrail logs every Bedrock API call                                   │
└──────────────────────────────────────────────────────────────────────────────┘





### 7.2 Data Residency Summary

| Requirement | Option A | Option B (Cloud) | Option B (Self-Hosted) |
|---|---|---|---|
| **Keep everything in eu-west-2?** | **Yes** — if Bedrock Claude is available in eu-west-2 | **No** — US only | **Partial** — execution on your infra, but prompts go to US |
| **Code never leaves our network?** | **Yes** | **No** | Filesystem yes, prompt content no |
| **ZDR / HIPAA eligible?** | Via AWS BAA | **No** (Managed Agents excluded) | **No** |
| **Audit trail** | CloudTrail + CloudWatch | Anthropic session logs (API) | Mixed — your infra logs + Anthropic logs |

### 7.3 Security Posture for Option A

| Concern | Mitigation |
|---|---|
| **Code access** | Agents run in isolated ECS tasks; git credentials scoped to specific repos via Secrets Manager |
| **Bedrock access** | ECS Task IAM Role with least-privilege Bedrock policy |
| **Secrets** | No secrets in container images — all from Secrets Manager at runtime |
| **Network** | Private subnets, NAT gateway for outbound, no inbound internet |
| **Blast radius** | Agents can only create branches + PRs, never merge to main |
| **Audit** | CloudTrail (every API call) + CloudWatch Logs (container stdout) |
| **Human in the loop** | All code changes require human PR approval before merge |

---





### 8.3 How Do We Audit Agent Actions?

| What | Option A | Option B |
|---|---|---|
| **Every Bedrock/API call** | CloudTrail — automatic, per-request, with IAM principal | Anthropic session history — fetch full event log via API |
| **Git operations** | Container logs (stdout) in CloudWatch | Session tool call log (bash commands visible in SSE stream) |
| **Cost per run** | Bedrock cost allocation tags + Fargate cost | Anthropic Usage API (tokens + runtime per session) |
| **Retention** | You control — S3/CloudWatch retention policies | Anthropic stores session history server-side; you can delete via API |

---

## 9. Simplicity — What Do We Actually Build and Maintain?

### 9.1 Option A — What You Build

Using the [claude-code-headless](https://github.com/akadesilva/claude-code-headless) reference as a starting point:

| Component | Effort | Notes |
|---|---|---|
| **Dockerfile** | Provided by reference repo | Debian base + Claude Code CLI + Git + build tools |
| **ECR repository** | `step3-setup-ecr.sh` | One-time setup |
| **Secrets Manager** | `step1-setup-secrets.sh` | Git PAT, API credentials |
| **IAM roles** | `step2-setup-iam-roles.sh` | Execution role + task role, least privilege |
| **ECS task definition** | `step4-setup-ecs.sh` | 4 vCPU, 16 GB RAM, Spot |
| **Lambda dispatcher** | Custom (~100 lines) | Receives Linear webhook, starts ECS task |
| **API Gateway** | Standard webhook endpoint | Receives Linear POST |
| **VPC / subnets** | Use existing or create | Private subnets, NAT gateway |
| **CloudWatch alarms** | Standard setup | Spend, duration, failure rate |
| **Container maintenance** | Ongoing | Rebuild weekly or on Claude Code CLI updates |

**Total setup effort:** ~2–3 weeks for a platform engineer.
**Ongoing maintenance:** ~2–4 hours/week (container updates, monitoring, debugging failures).


### 9.3 Complexity Comparison

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                      WHAT YOU OWN — SIDE BY SIDE                             │
│                                                                              │
│  OPTION A (Self-Hosted)              OPTION B (Managed Agents)              │
│  ─────────────────────               ────────────────────────               │
│  ✗ Dockerfile                        ✓ Not needed                          │
│  ✗ ECR repository                    ✓ Not needed                          │
│  ✗ ECS cluster + task def            ✓ Not needed (or worker for self-host)│
│  ✗ IAM roles (execution + task)      ✓ Just API key                        │
│  ✗ VPC / subnets / NAT               ✓ Not needed                          │
│  ✗ Secrets Manager entries           ~ API key only                         │
│  ✗ Container image lifecycle         ✓ Not needed                          │
│  = Lambda dispatcher                 = Lambda dispatcher                    │
│  = API Gateway                       = API Gateway                          │
│  = CloudWatch alarms                 ~ Must build equivalent monitoring     │
│                                                                              │
│  Infrastructure lines of code:       Infrastructure lines of code:          │
│  ~400 Terraform + Dockerfile         ~50 Terraform + API calls              │
│                                                                              │
│  Trade-off: MORE control             Trade-off: LESS to maintain            │
│             MORE to maintain                     LESS control               │
│             Full data residency                  Data goes to Anthropic     │
└──────────────────────────────────────────────────────────────────────────────┘
```


### If Data Residency Is a Hard Requirement

**Go with Option A.** Managed Agents only supports US workspace geo today. Even with self-hosted sandboxes, prompt content (which includes your code) flows through Anthropic's US-based control plane. If you need everything in `eu-west-2`, self-hosted on ECS + Bedrock is the only path.




