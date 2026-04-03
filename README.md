# MCP Clinical Platform

> **MCP_HACK//26 Submission** — Federated MCP servers on Kubernetes: a medical data AI agent platform combining kagent, kgateway (agentgateway), m3, and agentregistry — fully deployed via ArgoCD GitOps.

<div align="center">

[![kagent](https://img.shields.io/badge/kagent-v0.8.3-blue?style=for-the-badge)](https://kagent.dev/)
[![kgateway](https://img.shields.io/badge/kgateway-v1.0.1-green?style=for-the-badge)](https://agentgateway.dev/)
[![agentregistry](https://img.shields.io/badge/agentregistry-v0.3.3-orange?style=for-the-badge)](https://agentregistry.dev/)
[![MCP](https://img.shields.io/badge/MCP-Streamable_HTTP-purple?style=for-the-badge)](https://modelcontextprotocol.io/)
[![ArgoCD](https://img.shields.io/badge/ArgoCD-GitOps-EF7B4D?style=for-the-badge&logo=argo&logoColor=white)](https://argoproj.github.io/argo-cd/)
[![Kind](https://img.shields.io/badge/Kind-K8s-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white)](https://kind.sigs.k8s.io/)

</div>

---

## What It Does

```
 "What is the race distribution in ICU admissions?"

 ┌─────────────┐     ┌──────────────────────────┐     ┌────────────────────┐
 │  VS Code    │────▶│  kgateway (agentgateway)  │────▶│  kagent (/mcp)     │
 │  Cursor     │     │  K8s Gateway API          │     │  list_agents       │
 │  Claude     │     │  /mcp endpoint            │     │  invoke_agent      │
 └─────────────┘     │                          │     └────────────────────┘
                     │                          │
                     │                          │     ┌────────────────────┐
                     │                          │────▶│  m3 MCP server     │
                     │                          │     │  6 clinical tools  │
                     │                          │     │  MIMIC-IV + DuckDB │
                     │                          │     └────────────────────┘
                     │                          │
                     │                          │     ┌────────────────────┐
                     │                          │────▶│  agentregistry     │
                     └──────────────────────────┘     │  12 registry tools │
                                                      │  K8s discovery     │
                                                      └────────────────────┘

 → "WHITE: 41,266 (54.8%), BLACK/AFRICAN AMERICAN: 13,197 (17.5%)..."
```

**One MCP endpoint. Three servers. 22 federated tools. All from your IDE.**

kgateway (agentgateway on Kubernetes) federates kagent (AI agent orchestration), m3 (MIMIC-IV clinical data), and agentregistry (service discovery) into a single `/mcp` endpoint. Everything runs in-cluster — no local binaries needed.

---

## Quick Start

```bash
# Prerequisites: kind, kubectl, helm
brew install kind kubectl helm

# 1. Clone and configure
git clone https://github.com/papagala/mcp-clinical-platform.git
cd mcp-clinical-platform
export OPENAI_API_KEY=sk-your-key

# 2. Deploy everything (Kind + ArgoCD + kagent + m3 + kgateway + agentregistry)
make create

# 3. Start port-forwards (including kgateway proxy → localhost:4000)
make ports

# 4. Run the demo
make demo
```

That's it. Three commands from zero to a working federated MCP platform.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    MCP Clients (any)                         │
│  VS Code + Copilot  │  Cursor  │  Claude Code  │  curl     │
└──────────┬──────────┴──────────┴───────────────┴───────────┘
           │ MCP Streamable HTTP
           ▼
┌──────────────────────┐
│   agentgateway       │  Federation proxy (Rust, Linux Foundation)
│   localhost:4000     │  ├─ Virtual MCP multiplexing
│   UI: :15000         │  ├─ CORS / session management
│                      │  └─ Observability + routing
└───┬──────────┬───────┘
    │          │          ← port-forwarded from Kind cluster
    ▼          ▼
┌────────┐ ┌────────────┐
│ kagent │ │ m3         │    ← Both deployed via ArgoCD GitOps
│ :8083  │ │ :3000      │    ← Both speak MCP Streamable HTTP
│ /mcp   │ │ /mcp       │    ← Both discoverable as K8s Services
└───┬────┘ └────────────┘
    │
    ▼
┌──────────────────────┐
│ medical-data-agent   │  kagent Agent CRD (Go runtime, 2s startup)
│ Wired to m3 via      │  ├─ get_database_schema
│ K8s Service discovery │  ├─ execute_mimic_query
│ (appProtocol: mcp)   │  ├─ get_race_distribution
│                      │  ├─ get_icu_stays
│                      │  ├─ get_lab_results
│                      │  └─ get_table_info
└──────────────────────┘
```

### What Gets Deployed

| Component | Method | Purpose |
|-----------|--------|---------|
| **Kind cluster** | `kind create cluster` | Local K8s environment |
| **ArgoCD** | `kubectl apply` | GitOps engine — auto-syncs all deployments |
| **kagent v0.8.3** | ArgoCD → Helm OCI | AI agent framework + MCP server at `/mcp` |
| **m3 v0.0.3** | ArgoCD → Helm (this repo) | MIMIC-IV MCP server with 6 clinical data tools |
| **medical-data-agent** | `kubectl apply` Agent CRD | kagent agent wired to m3 MCP tools |
| **agentgateway** | Binary on host | Federates kagent + m3 → single MCP endpoint |

---

## Demo Walkthrough

### 1. List all federated tools

```bash
curl -s http://localhost:4000/ \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"tools/list","id":1}' | python3 -m json.tool
```

Tools from both servers, prefixed: `kagent_list_agents`, `kagent_invoke_agent`, `m3_get_database_schema`, `m3_execute_mimic_query`, `m3_get_race_distribution`, etc.

### 2. Query clinical data through agentgateway

```bash
curl -s http://localhost:4000/ \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"m3_get_race_distribution","arguments":{}},"id":2}' \
  | python3 -m json.tool
```

### 3. List kagent agents

```bash
curl -s http://localhost:4000/ \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"kagent_list_agents","arguments":{}},"id":3}' \
  | python3 -m json.tool
```

### 4. VS Code Integration

The repo includes `.vscode/mcp.json` — open this project in VS Code with Copilot and ask:

> "What is the race distribution in ICU admissions?"

Copilot discovers `m3_get_race_distribution` through agentgateway and calls it automatically.

### 5. Explore the UIs

| UI | URL | What You See |
|----|-----|-------------|
| **agentgateway** | http://localhost:15000/ui | Federated MCP targets, playground, traffic |
| **kagent** | http://localhost:8090 | Agent management, chat with medical-data-agent |
| **ArgoCD** | https://localhost:8080 | GitOps sync status for kagent + m3 |

### 6. Interactive demo (for judges)

```bash
make demo-script
```

Walks through each step with explanations and pauses.

---

## Why This Architecture

| Decision | Why |
|----------|-----|
| **ArgoCD** over `kubectl apply` | GitOps = self-healing, audit trail, drift detection |
| **kgateway on K8s** over local binary | Fully in-cluster, no host dependencies, Gateway API native |
| **agentgateway federation** | One `/mcp` endpoint for all MCP servers = simpler client config |
| **agentregistry** | Service discovery catalog — tracks all deployed MCP servers, agents, and skills |
| **kagent as MCP server** | v0.8+ exposes agents via `/mcp` — any IDE can invoke them |
| **m3 with `appProtocol: mcp`** | K8s-native MCP discovery — kagent auto-connects |
| **Go runtime** for agent | 2s startup vs 15s Python — great for demo responsiveness |
| **Custom VS Code agent** | `.agent.md` gives clinicians a dedicated chat persona for data queries |
| **Kind cluster** | Works on any machine, no cloud account needed |

---

## Hackathon Categories

### 🤖 Building Cool Agents (Primary)
- `medical-data-agent`: kagent Agent CRD querying MIMIC-IV clinical data via MCP
- **Clinical Analyst** custom VS Code agent (`.github/agents/clinical-analyst.agent.md`) for IDE-native clinical queries
- Uses Go runtime for fast cold starts
- Demonstrates kagent's K8s Service discovery for MCP servers (`appProtocol: mcp`)
- Real clinical data from [m3](https://github.com/rafiattrach/m3) — not a toy example
- Demo notebook with agent-driven cohort analysis and publication-quality visualizations

### 🚀 MCP & AI Agents Starter Track
- Complete from-zero tutorial: 3 commands to a working platform
- Each Makefile target is idempotent and documented
- VS Code integration with custom agent shows practical developer workflow
- Demo notebook for step-by-step learning

### 🛡️ Secure & Govern MCP
- All agent-tool traffic flows through kgateway (single auditable K8s-native proxy)
- Gateway API resources (Gateway, AgentgatewayBackend, HTTPRoute) for declarative routing
- agentregistry provides service/agent/skill catalog with K8s discovery
- Ready for JWT auth and RBAC policy extension

---

## File Structure

```
mcp-clinical-platform/
├── Makefile                              # Main orchestration (create/destroy/ports/demo)
├── README.md                             # ← you are here
├── pyproject.toml                        # Python deps (pandas, matplotlib, requests)
├── .vscode/
│   └── mcp.json                          # VS Code MCP client → localhost:4000/mcp
├── .github/
│   └── agents/
│       └── clinical-analyst.agent.md     # Custom VS Code agent for clinical queries
├── demo/
│   └── lactate_cohort_analysis.ipynb     # Live demo notebook (agent → data → plots)
├── deploy/
│   ├── kind/
│   │   └── cluster-config.yaml           # Kind cluster config
│   ├── argocd/
│   │   ├── kagent-app.yaml               # kagent v0.8.3 (multi-source: CRDs + chart)
│   │   ├── m3-app.yaml                   # m3 v0.0.3
│   │   ├── agentgateway-crds-app.yaml    # kgateway CRDs v1.0.1 (ServerSideApply)
│   │   ├── agentgateway-app.yaml         # kgateway control plane v1.0.1
│   │   └── agentregistry-app.yaml        # agentregistry v0.3.3
│   ├── agentgateway/
│   │   └── k8s-resources.yaml            # Gateway + AgentgatewayBackend + HTTPRoute
│   └── kagent-resources/
│       ├── modelconfig.yaml              # OpenAI LLM provider config
│       └── medical-data-agent.yaml       # Agent CRD with m3 MCP tools
└── helm-charts/
    └── m3/                               # m3 Helm chart (deployed by ArgoCD)
        ├── Chart.yaml
        ├── values.yaml
        └── templates/
            ├── deployment.yaml
            ├── service.yaml              # appProtocol: agentgateway.dev/mcp
            ├── configmap.yaml
            ├── namespace.yaml
            ├── pvc.yaml
            └── _helpers.tpl
```

---

## Extending

### Add another MCP server
1. Deploy to cluster (Helm chart + ArgoCD Application)
2. Add as a static target in `deploy/agentgateway/k8s-resources.yaml` (AgentgatewayBackend)
3. The new tools appear automatically through the federated `/mcp` endpoint

### Create a new kagent agent
```yaml
kubectl apply -f - <<EOF
apiVersion: kagent.dev/v1alpha2
kind: Agent
metadata:
  name: my-agent
  namespace: kagent
spec:
  type: Declarative
  declarative:
    modelConfig: default-model-config
    systemMessage: "You are a helpful agent."
    tools:
      - type: McpServer
        mcpServer:
          name: m3
          kind: Service
          toolNames:
            - get_database_schema
EOF
```

It's immediately available via kagent's `/mcp` endpoint and through agentgateway.

---

## Technologies

| Tech | Version | Role | Project |
|------|---------|------|---------|
| [kagent](https://kagent.dev) | v0.8.3 | K8s-native AI agent framework | CNCF |
| [kgateway / agentgateway](https://agentgateway.dev) | v1.0.1 | MCP federation proxy on K8s (Gateway API) | Linux Foundation |
| [m3](https://github.com/rafiattrach/m3) | v0.0.3 | MIMIC-IV clinical data MCP server | — |
| [agentregistry](https://agentregistry.dev) | v0.3.3 | MCP server/agent/skill registry | — |
| [ArgoCD](https://argoproj.github.io/argo-cd/) | stable | GitOps continuous delivery | CNCF |
| [Gateway API](https://gateway-api.sigs.k8s.io/) | v1.5.0 | K8s-native routing for kgateway | K8s SIG |
| [Kind](https://kind.sigs.k8s.io/) | latest | Local Kubernetes cluster | — |
| [MCP](https://modelcontextprotocol.io/) | Streamable HTTP | Model Context Protocol | Anthropic |

## References

- Al Attrach, R., Moreira, P., Fani, R., Umeton, R., & Celi, L. A. (2025). *Conversational LLMs Simplify Secure Clinical Data Access, Understanding, and Analysis.* [arXiv:2507.01053](https://doi.org/10.48550/arXiv.2507.01053)

## Known Issues & Contributions

### kagent A2A Client Timeout (hardcoded 30s)

**Problem:** kagent's MCP handler uses a hardcoded 30-second timeout for A2A client calls (`invoke_agent`). When an agent performs multi-step work — schema exploration, multiple tool calls, LLM reasoning — the total round-trip easily exceeds 30s. The agent completes successfully (visible in pod logs), but the caller receives a timeout error:

```
Failed to send A2A message: context deadline exceeded (Client.Timeout exceeded while awaiting headers)
```

**Our fix:** We opened [kagent PR #1617](https://github.com/kagent-dev/kagent/pull/1617) to make the timeout configurable, reusing the existing `STREAMING_TIMEOUT` config (default 600s) that the A2A registrar and CLI already use.

**Notebook workaround:** Until the fix is merged, the demo notebook ([`demo/lactate_cohort_analysis.ipynb`](demo/lactate_cohort_analysis.ipynb)) includes an automatic retry loop (up to 3 attempts with 5s pause) that handles the timeout gracefully — on retry, the agent typically responds faster since it's already warmed up.

---

## Troubleshooting

```bash
make status          # Check everything
make logs            # Stream kagent + m3 logs
make destroy         # Start fresh
```

---

<div align="center">

**Built for [MCP_HACK//26](https://aihackathon.dev/)**

kagent (CNCF) · kgateway / agentgateway (Linux Foundation) · m3 · agentregistry · ArgoCD · MCP

</div>

## License

Apache 2.0
