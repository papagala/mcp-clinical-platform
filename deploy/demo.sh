#!/usr/bin/env bash
# =============================================================================
# MCP Clinical Platform — Interactive Demo Script
# Run after: make create && make ports && make gateway
# =============================================================================
set -euo pipefail

GATEWAY_URL="http://localhost:4000"
KAGENT_URL="http://localhost:8083/mcp"
M3_URL="http://localhost:3000/mcp"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

header() {
    echo ""
    echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${BLUE}  $1${NC}"
    echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo ""
}

step() { echo -e "${YELLOW}▸ $1${NC}"; }
ok()   { echo -e "${GREEN}✓ $1${NC}"; }
pause() { echo ""; echo -e "${CYAN}  Press Enter to continue...${NC}"; read -r; }

# =============================================================================
header "MCP Clinical Platform — Live Demo"
echo "  Architecture:"
echo "  VS Code → agentgateway(:4000) → kagent MCP + m3 MCP"
echo ""
echo "  Two MCP servers, one federated endpoint, six medical data tools."
echo ""

# =============================================================================
header "Step 1: Service Health Check"

step "Checking m3 MCP server (localhost:3000)..."
if curl -sf "$M3_URL" -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"demo","version":"1.0"}},"id":0}' > /dev/null 2>&1; then
    ok "m3 MCP server is running"
else
    echo "  ⚠ m3 not responding — run: make ports"
fi

step "Checking kagent MCP server (localhost:8083)..."
if curl -sf "$KAGENT_URL" -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"demo","version":"1.0"}},"id":0}' > /dev/null 2>&1; then
    ok "kagent MCP server is running"
else
    echo "  ⚠ kagent not responding — run: make ports"
fi

step "Checking agentgateway (localhost:4000)..."
if curl -sf "$GATEWAY_URL" -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"demo","version":"1.0"}},"id":0}' > /dev/null 2>&1; then
    ok "agentgateway is running"
else
    echo "  ⚠ agentgateway not responding — run: make gateway"
fi

pause

# =============================================================================
header "Step 2: Federated MCP — List All Tools"
echo "  agentgateway multiplexes kagent + m3 into one endpoint."
echo "  Tools are prefixed: kagent_* and m3_*"
echo ""
step "Calling tools/list on agentgateway..."
echo ""

curl -s "$GATEWAY_URL" \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"tools/list","id":1}' | python3 -m json.tool 2>/dev/null || \
  echo "  (tools/list requires initialized session — try the agentgateway playground)"

pause

# =============================================================================
header "Step 3: Query Clinical Data — Race Distribution"
echo "  Flow: curl → agentgateway → m3 MCP → DuckDB → MIMIC-IV"
echo ""
step "Calling m3_get_race_distribution..."
echo ""

curl -s "$GATEWAY_URL" \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"m3_get_race_distribution","arguments":{}},"id":2}' | python3 -m json.tool 2>/dev/null || \
  echo "  (Try via agentgateway playground: http://localhost:15000/ui)"

pause

# =============================================================================
header "Step 4: Direct m3 — Database Schema"
step "Calling get_database_schema on m3 directly..."
echo ""

curl -s "$M3_URL" \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"get_database_schema","arguments":{}},"id":1}' | python3 -m json.tool 2>/dev/null || \
  echo "  (May require MCP session initialization)"

pause

# =============================================================================
header "Step 5: kagent Agents in Cluster"
step "kubectl get agents -n kagent"
echo ""
kubectl get agents -n kagent 2>/dev/null || echo "  (kubectl not configured)"

pause

# =============================================================================
header "Step 6: VS Code / IDE Integration"
echo "  Add to your project's .vscode/mcp.json:"
echo ""
echo '  {'
echo '    "servers": {'
echo '      "mcp-clinical-platform": {'
echo '        "type": "http",'
echo '        "url": "http://localhost:4000/"'
echo '      }'
echo '    }'
echo '  }'
echo ""
echo "  Then ask Copilot: \"What is the race distribution in ICU admissions?\""

pause

# =============================================================================
header "Step 7: Explore the UIs"
echo "  agentgateway UI:  http://localhost:15000/ui"
echo "  kagent Dashboard: http://localhost:8090"
argocd_pw=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null || echo "unknown")
echo "  ArgoCD:           https://localhost:8080  (admin/${argocd_pw})"
echo ""

# =============================================================================
header "Demo Complete!"
echo "  ✓ Two MCP servers federated by agentgateway"
echo "  ✓ Medical data queried via MCP tools"
echo "  ✓ Everything deployed via ArgoCD GitOps"
echo "  ✓ VS Code / Cursor / any MCP client can connect"
echo ""
echo "  Built with: kagent (CNCF) + agentgateway (LF) + m3 + ArgoCD"
echo ""
