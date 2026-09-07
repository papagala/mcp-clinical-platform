# MCP Clinical Platform

Federated MCP servers on Kubernetes: kagent (agent orchestration), m3 (MIMIC-IV clinical data), and agentregistry, behind a single agentgateway `/mcp` endpoint, deployed via ArgoCD GitOps on Kind.

Backs the talk *From Ideas to Agents: A Practical Journey into Agentic AI*, structured in three layers: **MCP** (protocol) → **kagent** (infrastructure) → **Agent Substrate** (runtime).

## Working here

```bash
make create    # Kind + ArgoCD + kagent + m3 + agentgateway + agentregistry
make ports     # port-forwards (run before anything else)
make registry-seed  # publish this platform into the agentregistry catalog
make status    # pods + ArgoCD app health
make destroy   # tear down
```

`make create` must stay self-contained and idempotent — it's the repo's headline claim. Never make it depend on optional components.

**The demo is not a make target.** `make` builds and health-checks the platform; the demo itself runs in Claude Code over MCP, guided by `index.html`. Don't add a `demo` or `hitl` target back — driving the demo from a shell script contradicts the argument the demo exists to make.

## Demo output: keep it short

During the demo the audience is reading the screen, not your prose. Report what a tool
returned in one or two lines. No preambles ("I'll invoke the gated agent..."), no
restating the task, no numbered walkthroughs of your own tool calls, no unsolicited
alternatives or caveats. When a gate fires, three lines is enough: which tool was
blocked, the state, and where to approve.

## Ports

| Service | URL |
|---|---|
| agentgateway MCP | http://localhost:4000/mcp |
| kagent UI | http://localhost:8090 |
| agentregistry UI | http://localhost:12121 |
| ArgoCD | https://localhost:8080 |

## Transport: stateless, but not the 2026-07-28 core

Two different things get called "stateless". Don't conflate them on a slide.

| | Status |
|---|---|
| **Deployment-stateless** — no `Mcp-Session-Id`, any replica answers | ✅ **yes, today** |
| **`2026-07-28` stateless core** — no handshake, `server/discover`, per-request `_meta` | ❌ no upstream implements it |

What each surface negotiates (probe it, don't guess — `serverInfo` tells you):

| Surface | Revision | Session |
|---|---|---|
| agentgateway `/mcp` (what Claude Code talks to) | `2025-06-18` | none |
| m3 | `2025-06-18` | none |
| kagent `:8083` | `2025-11-25` | issues one |
| agentregistry `:31313` | `2025-06-18` | issues one |

Two settings produce this, and **they must move together**:

- `deploy/agentgateway/k8s-resources.yaml` → `spec.mcp.sessionRouting: Stateless`
- `helm-charts/m3/values.yaml` → `env.statelessHttp: "true"` (→ `FASTMCP_STATELESS_HTTP`)

A stateless gateway in front of a **stateful** m3 returns `HTTP 200` with an **empty body** on most calls — it looks like a hung tool, not a config error. If m3 tool calls go quiet, check that both are set.

m3 needs no source change and no image rebuild for this: FastMCP reads `stateless_http` as a global setting. Note the deployed image ships fastmcp **2.13.0.2** / mcp **1.21.0**, not the `2.10.2` in the upstream `uv.lock` — m3's Dockerfile never applies the lockfile, so never quote a fastmcp version from it.

Because m3 is stateless, `kubectl scale deploy m3 -n kagent --replicas=2` is now safe — verified, both replicas serve a cold `tools/call` with no `initialize`. That makes the clinical-ops skill at `clinical-ops-agent.yaml:169` demoable rather than a landmine.

## Datasets: `m3` vs `m3-full` — never both in one answer

Two MCP servers can serve MIMIC-IV, and their numbers differ by three orders of magnitude.

| | `mcp-clinical-platform` (in-cluster `m3`) | `m3-full` (local stdio) |
|---|---|---|
| Data | SQLite demo subset — 275 admissions, ~100 patients | DuckDB+Parquet, full MIMIC-IV v2.2 — 431,231 admissions |
| Gated | **yes**, `execute_mimic_query` needs approval | **no**, runs ungated |
| Needs cluster | yes | no |

**Default to the cluster server.** The demo, `/demo`, and the entire governance story run on it. Only reach for `m3-full` when the user explicitly names it, or when the question genuinely cannot be answered by 100 patients.

Rules:

- **Never mix sources in one answer.** Pick a server, then say which one the numbers came from. A figure without its dataset is worse than no figure.
- **Governance beats must use the cluster path.** `m3-full` is ungated — routing a gated demo through it means the gate silently never fires, which reads as a broken gate.
- **`clinical-analyst` and `clinical-ops` are already pinned** to `mcp__mcp-clinical-platform__*` in their frontmatter and cannot reach `m3-full`. The ambiguity exists only in the top-level conversation.
- To force one server: `/mcp` toggle (no restart), or `enabledMcpjsonServers` in `.claude/settings.local.json` (allowlist, needs restart).

`m3-full` is opt-in and never part of `make create` — full MIMIC-IV is credentialed under the PhysioNet DUA. Never bake it into the published image, and never commit any of it.

Two failure modes that look like bugs but aren't:

- m3's query validator is a naive substring scan rejecting `ADMIN`, `KEY`, `AUTH`, `USER`. `LIKE '%Administered%'` is **blocked** — that is not the governance gate.
- The full-dataset `.duckdb` holds views with **absolute** Parquet paths baked in. Move the Parquet tree and every query fails while `get_database_schema` still lists all 31 views.

## Agents

Both are `kagent.dev/v1alpha2` `Agent` CRDs in the `kagent` namespace, in `deploy/kagent-resources/`.

- **`medical-data-agent`** — read-only clinical analysis over m3's tools. Ungated.
- **`clinical-ops-agent`** — platform SRE for the clinical data plane. **Approval-gated** via `requireApproval`: destructive K8s tools (`k8s_delete_resource`, `k8s_apply_manifest`, `k8s_patch_resource`) and `execute_mimic_query` (LLM-authored SQL over patient records) block until a human approves in the kagent UI.

The contrast between them is the governance story — keep `medical-data-agent` ungated.

### Always give the user a clickable approval URL

When `kagent_invoke_agent` returns `confirmation_requested` / `TASK_STATE_INPUT_REQUIRED`, the call is parked awaiting a human. There is no global approvals inbox — it lives in the chat session that created it. The `context_id` **is** the session id, and it goes in the URL **path**:

```
http://localhost:8090/agents/kagent/<agent-name>/chat/<context_id>
```

Note: a `?session=` query parameter does **not** work — it renders an empty "Start a conversation" pane. It must be a path segment.

Always print the full link. `make approve` also resolves and opens the most recent pending one.

If you edit `requireApproval`, the Agent CRD enforces a CEL rule: **every entry must also appear in `toolNames`**, or the resource is rejected.

## Layout

```
deploy/
  argocd/            ArgoCD Applications (kagent, m3, agentgateway, agentregistry)
    optional/        Agent Substrate — opt-in, not applied by make create
  kagent-resources/  Agent + ModelConfig CRDs, applied non-recursively
    optional/        Claude ModelConfig, SandboxAgent, AgentHarness
  agentgateway/      Gateway API resources (Gateway, AgentgatewayBackend, HTTPRoute)
  kind/              cluster config
helm-charts/m3/      m3 chart (Service uses appProtocol for MCP discovery)
demo/                lactate_cohort_analysis.ipynb
```

`deploy/kagent-resources/optional/` is a subdirectory specifically because `make _agents` applies the parent dir **non-recursively** — that's what keeps optional manifests inert. Don't flatten it.

## Versions

kagent **0.10.0-rc3**, deliberately ahead of stable. 0.9.12 is the latest stable release but its UI has **no working Approve/Reject control** — the HITL rework (PR #2396, merged 2026-08-07) landed after it. On 0.9.12 the runtime blocks correctly but the approval can never be granted, which kills the demo's payoff. Verified: rc3 blocks *and* approves, and a clean `make create` succeeds from zero.

agentgateway v1.0.1 and agentregistry 0.3.3 are pinned deliberately — newer releases exist, but the federation depends on the `AgentgatewayBackend`/`HTTPRoute` shape in `deploy/agentgateway/k8s-resources.yaml`. Working federation beats a version badge; verify federation end to end before bumping either.

Bumping agentgateway was tried and reverted — it buys nothing here. `spec.mcp.sessionRouting` already exists in v1.0.1, and `2026-07-28` is unreachable end to end regardless: kagent's go-sdk caps at `2025-11-25`, and agentregistry at `2025-06-18` with no stateless knob at all.

If an ArgoCD app ever sits `Unknown/Healthy` on an old revision after a pin change, read `.status.conditions` — a failed `helm pull` leaves the deployed state correct and silently ignores the new pin, so the cluster looks fine while GitOps has actually stopped.

## Model providers

OpenAI is the default (`OPENAI_API_KEY`, wired through the kagent chart's `providers` block). An optional Anthropic ModelConfig ships in `deploy/kagent-resources/optional/` for the provider-swap demo — apply with `make claude-model`.

Claude Code connects as an **MCP client** via `.mcp.json`, not as the in-cluster reasoning model.

## Agent Substrate

Opt-in only, via `make substrate`. Requires gVisor (runsc) on the Kind node, which may not work on Docker Desktop/macOS. Core demo must never depend on it.
