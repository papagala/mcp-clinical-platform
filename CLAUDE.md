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

## Model providers

OpenAI is the default (`OPENAI_API_KEY`, wired through the kagent chart's `providers` block). An optional Anthropic ModelConfig ships in `deploy/kagent-resources/optional/` for the provider-swap demo — apply with `make claude-model`.

Claude Code connects as an **MCP client** via `.mcp.json`, not as the in-cluster reasoning model.

## Agent Substrate

Opt-in only, via `make substrate`. Requires gVisor (runsc) on the Kind node, which may not work on Docker Desktop/macOS. Core demo must never depend on it.
