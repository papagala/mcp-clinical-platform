# MCP Clinical Platform

> **MCP_HACK//26 Submission** — Federated MCP servers on Kubernetes: a medical data AI agent platform combining kagent, agentgateway, and m3, deployed via ArgoCD GitOps.

<div align="center">

[![kagent](https://img.shields.io/badge/kagent-v0.8.3-blue?style=for-the-badge)](https://kagent.dev/)
[![agentgateway](https://img.shields.io/badge/agentgateway-v1.0-green?style=for-the-badge)](https://agentgateway.dev/)
[![MCP](https://img.shields.io/badge/MCP-Streamable_HTTP-purple?style=for-the-badge)](https://modelcontextprotocol.io/)
[![ArgoCD](https://img.shields.io/badge/ArgoCD-GitOps-EF7B4D?style=for-the-badge&logo=argo&logoColor=white)](https://argoproj.github.io/argo-cd/)
[![Kind](https://img.shields.io/badge/Kind-K8s-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white)](https://kind.sigs.k8s.io/)

</div>

---

## What It Does

```
 "What is the race distribution in ICU admissions?"

 ┌─────────────┐     ┌──────────────────┐     ┌────────────────────┐
 │  VS Code    │────▶│  agentgateway    │────▶│  kagent (/mcp)     │
 │  Cursor     │     │  :4000           │     │  list_agents       │
 │  Claude     │     │  MCP federation  │     │  invoke_agent      │
 └─────────────┘     │                  │     └────────────────────┘
                     │                  │
                     │                  │     ┌────────────────────┐
                     │                  │────▶│  m3 MCP server     │
                     └──────────────────┘     │  :3000             │
                                              │  6 clinical tools  │
                                              │  MIMIC-IV + DuckDB │
                                              └────────────────────┘

 → "WHITE: 41,266 (54.8%), BLACK/AFRICAN AMERICAN: 13,197 (17.5%)..."
```

**One MCP endpoint. Two servers. Six medical data tools. All from your IDE.**

agentgateway federates kagent (AI agent orchestration) and m3 (MIMIC-IV clinical data) into a single MCP endpoint. VS Code, Cursor, or any MCP client connects once and gets access to everything.

---

## Quick Start

```bash
# Prerequisites: kind, kubectl, helm
brew install kind kubectl helm

# 1. Clone and configure
git clone https://github.com/YOUR_USERNAME/mcp-clinical-platform.git
cd mcp-clinical-platform
export OPENAI_API_KEY=sk-your-key

# 2. Deploy everything (Kind + ArgoCD + kagent + m3)
make create

# 3. Start port-forwards
make ports

# 4. Start agentgateway (new terminal)
make gateway

# 5. Run the demo
make demo
```

That's it. Five commands from zero to a working federated MCP platform.

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
| **agentgateway federation** | One endpoint for all MCP servers = simpler client config |
| **kagent as MCP server** | v0.8+ exposes agents via `/mcp` — any IDE can invoke them |
| **m3 with `appProtocol: mcp`** | K8s-native MCP discovery — kagent auto-connects |
| **Go runtime** for agent | 2s startup vs 15s Python — great for demo responsiveness |
| **Kind cluster** | Works on any machine, no cloud account needed |

---

## Hackathon Categories

### 🤖 Building Cool Agents (Primary)
- `medical-data-agent`: kagent Agent CRD querying MIMIC-IV clinical data via MCP
- Uses Go runtime for fast cold starts
- Demonstrates kagent's K8s Service discovery for MCP servers (`appProtocol: mcp`)
- Real clinical data — not a toy example

### 🚀 MCP & AI Agents Starter Track
- Complete from-zero tutorial: 5 commands to a working platform
- Each Makefile target is idempotent and documented
- VS Code integration shows practical developer workflow
- Interactive demo script for step-by-step learning

### 🛡️ Secure & Govern MCP
- All agent-tool traffic flows through agentgateway (single auditable proxy)
- CORS policy, MCP session management, and routing built in
- Ready for JWT auth and RBAC policy extension (documented below)

---

## File Structure

```
mcp-clinical-platform/
├── Makefile                              # Main orchestration
├── README.md                             # ← you are here
├── .env.template                         # Environment template
├── .vscode/
│   └── mcp.json                          # VS Code MCP client config
├── deploy/
│   ├── demo.sh                           # Interactive demo script
│   ├── kind/
│   │   └── cluster-config.yaml           # Kind cluster config
│   ├── argocd/
│   │   ├── kagent-app.yaml               # kagent ArgoCD Application (v0.8.3)
│   │   └── m3-app.yaml                   # m3 ArgoCD Application
│   ├── kagent-resources/
│   │   ├── modelconfig.yaml              # OpenAI LLM provider config
│   │   └── medical-data-agent.yaml       # Agent CRD with m3 MCP tools
│   └── agentgateway/
│       └── config.yaml                   # MCP federation config
└── helm-charts/
    └── m3/                               # m3 Helm chart (deployed by ArgoCD)
        ├── Chart.yaml
        ├── values.yaml
        └── templates/
            ├── deployment.yaml
            ├── service.yaml              # appProtocol: mcp
            ├── configmap.yaml
            ├── namespace.yaml
            ├── pvc.yaml
            └── _helpers.tpl
```

---

## Extending

### Add another MCP server
1. Deploy to cluster (Helm chart + ArgoCD Application)
2. Add as target in `deploy/agentgateway/config.yaml`
3. Restart agentgateway — new tools appear automatically

### Add RBAC to agentgateway
```yaml
# deploy/agentgateway/config.yaml — add to route policies
policies:
  auth:
    - type: jwt
      jwt:
        issuer: https://your-idp.com
        audience: agentgateway
```

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
| [agentgateway](https://agentgateway.dev) | v1.0+ | MCP federation proxy | Linux Foundation |
| [m3](https://github.com/rafiattrach/m3) | v0.0.3 | MIMIC-IV clinical data MCP server | — |
| [ArgoCD](https://argoproj.github.io/argo-cd/) | stable | GitOps continuous delivery | CNCF |
| [Kind](https://kind.sigs.k8s.io/) | latest | Local Kubernetes cluster | — |
| [MCP](https://modelcontextprotocol.io/) | Streamable HTTP | Model Context Protocol | Anthropic |

## Troubleshooting

```bash
make status          # Check everything
make logs            # Stream kagent + m3 logs
make destroy         # Start fresh
```

---

<div align="center">

**Built for [MCP_HACK//26](https://aihackathon.dev/)**

kagent (CNCF) · agentgateway (Linux Foundation) · m3 · ArgoCD · MCP

</div>

## License

Apache 2.0
