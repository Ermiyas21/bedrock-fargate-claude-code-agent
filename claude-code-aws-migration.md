# Headless Claude Code — Where Should the Agent Container Run?

---

## Table of Contents

1. [The Problem](#1-the-problem)
2. [The Flow](#2-the-flow)
3. [Option A — Self-Hosted on AWS (ECS Fargate)](#3-option-a--self-hosted-on-aws-ecs-fargate)
4. [Option B — Anthropic Claude Managed Agents](#4-option-b--anthropic-claude-managed-agents)
5. [Head-to-Head Comparison](#5-head-to-head-comparison)
6. [Cost — How Do We Control and Predict Spend?](#6-cost--how-do-we-control-and-predict-spend)
7. [Security — Where Does Our Code Go?](#7-security--where-does-our-code-go)
8. [Control — Monitoring, Kill Switches, and Audit](#8-control--monitoring-kill-switches-and-audit)
9. [Simplicity — What Do We Actually Build and Maintain?](#9-simplicity--what-do-we-actually-build-and-maintain)
10. [Recommendation](#10-recommendation)
11. [References](#11-references)

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

**Reference implementation:** The [claude-code-headless](https://github.com/akadesilva/claude-code-headless) repo provides a ready-made Dockerfile and setup scripts (`step1` through `step5`) that handle secrets, IAM roles, ECR, ECS task definitions, and Fargate task execution. It clones a repo, downloads instructions from S3, runs Claude Code in `-p` mode, and pushes results back.

---

## 4. Option B — Anthropic Claude Managed Agents

Anthropic runs the agent loop for us. We call their API to create a session, and Claude executes tools (bash, file ops, web fetch) inside a managed sandbox. Currently in **public beta** (`managed-agents-2026-04-01`).

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                OPTION B — ANTHROPIC MANAGED AGENTS                            │
│                                                                              │
│  ┌───────────┐     ┌──────────────┐     ┌────────────────────────────────┐  │
│  │ Linear     │     │ Lambda       │     │ Anthropic Control Plane        │  │
│  │ Webhook    │────▶│ (dispatcher) │────▶│                                │  │
│  │            │     │              │     │  POST /v1/agents → create agent│  │
│  └───────────┘     └──────────────┘     │  POST /v1/environments → cloud │  │
│                                          │    or self-hosted sandbox      │  │
│                                          │  POST /v1/sessions → start    │  │
│                                          │  POST /v1/sessions/:id/events │  │
│                                          │    → send task prompt          │  │
│                                          │                                │  │
│                                          │  Claude autonomously:          │  │
│                                          │  • Runs bash, reads/writes     │  │
│                                          │    files, executes code        │  │
│                                          │  • Streams results via SSE     │  │
│                                          │  • Can be steered or           │  │
│                                          │    interrupted mid-run         │  │
│                                          └────────────────────────────────┘  │
│                                                                              │
│  TWO SANDBOX MODES:                                                         │
│                                                                              │
│  Cloud sandbox:        Tool execution on Anthropic infra.                   │
│                        Code goes to Anthropic's cloud.                      │
│                                                                              │
│  Self-hosted sandbox:  Orchestration on Anthropic, but tool execution       │
│                        runs on YOUR infra (ECS, EC2, etc.).                 │
│                        Filesystem + processes stay in your network.         │
│                        Tool inputs/outputs still flow to Anthropic's        │
│                        control plane so the model can see results.          │
│                                                                              │
│  YOU BUILD: Lambda dispatcher, agent config (API call). Optionally a        │
│             self-hosted worker if using self-hosted sandbox mode.            │
│  YOU MAINTAIN: API key rotation, session monitoring, webhook integration.   │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## 5. Head-to-Head Comparison

| Dimension | Option A — Self-Hosted (ECS Fargate) | Option B — Managed Agents (Anthropic) |
|---|---|---|
| **What you run** | Full container with Claude Code CLI headless | API calls to Anthropic; they run the agent loop |
| **Inference provider** | Amazon Bedrock (your AWS account) | Anthropic API (their infra) |
| **Code execution** | Your ECS task, your VPC | Cloud sandbox (Anthropic) or self-hosted sandbox (your infra) |
| **Data residency** | Everything stays in your AWS region (e.g. `eu-west-2`) | Cloud sandbox: data goes to Anthropic (US only today). Self-hosted: tool execution stays on your infra, but prompts/results flow through Anthropic control plane |
| **Billing** | AWS bill (Bedrock tokens + Fargate compute) | Anthropic bill (tokens + session runtime) |
| **Setup effort** | ~2–3 weeks (container, IAM, networking, monitoring) | ~2–3 days (API integration, webhook) |
| **Ongoing maintenance** | Container image updates, infra lifecycle, scaling | Minimal — Anthropic manages the runtime |
| **Maturity** | Production-ready (ECS/Fargate is GA, Claude Code `-p` is GA) | Public beta (`managed-agents-2026-04-01`) |

---

## 6. Cost — How Do We Control and Predict Spend?

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

```
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

┌──────────────────────────────────────────────────────────────────────────────┐
│                           DATA FLOW — OPTION B                               │
│                   (Managed Agents, cloud sandbox)                             │
│                                                                              │
│  Your code ──▶ Anthropic cloud sandbox (US) ──▶ Claude inference (US)       │
│                                                                              │
│  ⚠ Code is sent to Anthropic's infrastructure                               │
│  ⚠ Workspace geo: only "us" available today — no eu-west-2 option           │
│  ⚠ Not eligible for Zero Data Retention or HIPAA BAA                        │
│  ⚠ Sessions are stateful — conversation history stored server-side          │
│  ✓ You can delete sessions and uploaded files via API                        │
└──────────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────────┐
│                           DATA FLOW — OPTION B                               │
│                   (Managed Agents, self-hosted sandbox)                       │
│                                                                              │
│  Tool execution ──▶ your infra (ECS worker)                                 │
│  Prompts + tool results ──▶ Anthropic control plane (US)                    │
│                                                                              │
│  ✓ Filesystem and processes stay on your infra                              │
│  ⚠ Tool inputs/outputs still flow to Anthropic so the model can see them   │
│  ⚠ Prompt content (including code snippets) goes to Anthropic               │
│  ⚠ Workspace geo still US-only                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

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

## 8. Control — Monitoring, Kill Switches, and Audit

### 8.1 What Is the Agent Doing Right Now?

| Capability | Option A (Self-Hosted) | Option B (Managed Agents) |
|---|---|---|
| **Live output** | CloudWatch Logs — stream container stdout in real time | SSE stream from session — real-time tool calls + results |
| **Status check** | ECS `DescribeTask` — running/stopped/pending | `GET /v1/sessions/:id` — running/idle/terminated |
| **Token usage** | Bedrock invocation logs in CloudWatch | Anthropic Usage API |

### 8.2 How Do We Kill a Runaway Session?

| Action | Option A | Option B |
|---|---|---|
| **Stop immediately** | `aws ecs stop-task --task <id>` — instant kill | `POST /v1/sessions/:id/events` with interrupt, or stop the session |
| **Timeout** | ECS task timeout (30 min default). Step Functions `TimeoutSeconds`. | Set in your dispatcher. Send interrupt after timeout. |
| **Budget kill** | CloudWatch alarm → SNS → Lambda that calls `stop-task` | Must build: poll Usage API → trigger session stop |

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

### 9.2 Option B — What You Build

| Component | Effort | Notes |
|---|---|---|
| **Lambda dispatcher** | Custom (~50 lines) | Receives Linear webhook, calls Anthropic API to create session |
| **API Gateway** | Standard webhook endpoint | Same as Option A |
| **Agent configuration** | API call | Define model, system prompt, tools — stored at Anthropic |
| **Environment setup** | API call (cloud) or worker (self-hosted) | Cloud: nothing to run. Self-hosted: run an environment worker. |
| **Result handler** | Custom (~50 lines) | Poll session status, trigger PR creation when done |
| **API key management** | Anthropic Console | Rotate periodically |

**Total setup effort:** ~2–3 days.
**Ongoing maintenance:** ~1 hour/week (monitor session outcomes, update agent prompts).

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

---

## 10. Recommendation

### Decision Matrix

| Factor | Weight | Option A (Self-Hosted) | Option B (Managed Agents) |
|---|---|---|---|
| **Data stays in eu-west-2** | Critical | ✅ Full control | ❌ US only (cloud), partial (self-hosted) |
| **Cost predictability** | High | ✅ AWS Budgets, Bedrock quotas, Spot pricing | ⚠️ Must build budget controls yourself |
| **Simplicity** | High | ⚠️ 2–3 weeks setup, ongoing maintenance | ✅ Days to set up, minimal maintenance |
| **Audit / compliance** | High | ✅ CloudTrail, CloudWatch, full ownership | ⚠️ Anthropic session logs, less granular |
| **Kill a runaway agent** | Medium | ✅ `stop-task` — instant | ✅ Interrupt event — instant |
| **Maturity** | Medium | ✅ GA (ECS + Claude Code -p) | ⚠️ Public beta |
| **Time to first agent run** | Medium | ⚠️ Weeks | ✅ Days |

### If Data Residency Is a Hard Requirement

**Go with Option A.** Managed Agents only supports US workspace geo today. Even with self-hosted sandboxes, prompt content (which includes your code) flows through Anthropic's US-based control plane. If you need everything in `eu-west-2`, self-hosted on ECS + Bedrock is the only path.

### If Speed-to-Market Is the Priority

**Start with Option B (cloud sandbox)** to validate the ticket-to-PR workflow in days, not weeks. Accept that code goes to Anthropic during the beta phase. Migrate to Option A (or Option B self-hosted) once the workflow is proven and data residency controls mature.

### Hybrid Path

1. **Week 1–2:** Ship the flow with Managed Agents (cloud sandbox) on a non-sensitive test repo. Validate trigger → agent → PR loop.
2. **Week 3–4:** If it works, evaluate self-hosted sandbox mode — keep orchestration at Anthropic but run tool execution on your ECS infra.
3. **Month 2:** If eu-west-2 residency is required, migrate to full Option A using the [claude-code-headless](https://github.com/akadesilva/claude-code-headless) reference. You already know the workflow works.

---

## 11. References

- [claude-code-headless — Reference container implementation (GitHub)](https://github.com/akadesilva/claude-code-headless)
- [Claude Code headless / `-p` flag documentation](https://code.claude.com/docs/en/headless)
- [Claude Managed Agents — Overview (Anthropic Docs)](https://platform.claude.com/docs/en/managed-agents/overview)
- [Claude Managed Agents — Self-Hosted Sandboxes](https://platform.claude.com/docs/en/managed-agents/self-hosted-sandboxes)
- [Claude Managed Agents — Pricing (tokens + session runtime)](https://platform.claude.com/docs/en/about-claude/pricing)
- [Anthropic Data Residency](https://platform.claude.com/docs/en/manage-claude/data-residency)
- [Amazon Bedrock Pricing](https://aws.amazon.com/bedrock/pricing/)
- [LinkedIn post — Headless Claude Code workflow](https://www.linkedin.com/feed/update/urn:li:share:7345727008741445632/)
