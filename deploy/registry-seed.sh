#!/usr/bin/env bash
# Publish this platform's own MCP servers and agents into the agentregistry
# catalog, so the registry lists what is actually deployed.
#
# The chart ships with disableBuiltinSeed=true (no generic sample data), so
# without this the catalog is empty. Run after: make create && make ports
#
# Registry constraints worth knowing (all discovered the hard way):
#   - $schema must be the 2025-10-17 revision
#   - name is reverse-DNS and must contain exactly one "/"
#   - description is capped at 100 characters
#   - remote AND websiteUrl hosts must match the publisher domain, so neither
#     in-cluster Service URLs nor upstream project links can be attached under
#     a dev.* namespace — the address goes in the description instead
#   - agent names are stricter than server names: the DB enforces
#     ^[a-zA-Z0-9][a-zA-Z0-9.-]*[a-zA-Z0-9]$ — no slash, no underscore — so
#     agents are registered under their plain kubectl names
set -euo pipefail

REGISTRY="${REGISTRY_URL:-http://localhost:12121}"
SCHEMA="https://static.modelcontextprotocol.io/schemas/2025-10-17/server.schema.json"
NS="dev.mcp-clinical-platform"

GREEN='\033[0;32m'; RED='\033[0;31m'; DIM='\033[2m'; NC='\033[0m'

if ! curl -sf -m 5 "$REGISTRY/v0/health" >/dev/null 2>&1; then
    echo -e "${RED}✘ agentregistry unreachable at $REGISTRY${NC} — run: make ports"
    exit 1
fi

TOKEN=$(curl -s -X POST "$REGISTRY/v0/auth/none" \
    -H 'Content-Type: application/json' -d '{}' | jq -r '.token // .registry_token // empty')
if [ -z "$TOKEN" ]; then
    echo -e "${RED}✘ could not get an anonymous registry token${NC}"
    echo "  (needs config.enableAnonymousAuth=true on the agentregistry chart)"
    exit 1
fi

publish() {  # $1 = endpoint (servers|agents), $2 = label, $3 = json
    local out code body
    out=$(curl -s -w '\n%{http_code}' -X POST "$REGISTRY/v0/$1" \
        -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d "$3")
    code=$(echo "$out" | tail -1)
    body=$(echo "$out" | sed '$d')
    if [ "$code" = "200" ] || [ "$code" = "201" ]; then
        echo -e "  ${GREEN}✓${NC} $2"
    elif echo "$body" | grep -q "duplicate version"; then
        # Already published at this version — the registry rejects re-publishing
        # the same version, which is what keeps this script safe to re-run.
        echo -e "  ${DIM}·${NC} $2 ${DIM}(already registered)${NC}"
    else
        echo -e "  ${RED}✘${NC} $2 ${DIM}(HTTP $code)${NC}"
        echo "$body" | jq -r '.errors[]?.message // .detail // .' 2>/dev/null | sed 's/^/      /'
    fi
}

echo ""
echo "📚 Seeding agentregistry catalog → $REGISTRY"
echo ""
echo "MCP servers:"

publish servers "m3 — MIMIC-IV clinical data" "$(cat <<EOF
{
  "\$schema": "$SCHEMA",
  "name": "$NS/m3",
  "title": "m3 — MIMIC-IV Clinical Data",
  "description": "MIMIC-IV clinical data over MCP. In-cluster at m3.kagent.svc:3000/mcp",
  "version": "0.0.3"
}
EOF
)"

publish servers "kagent — agent orchestration" "$(cat <<EOF
{
  "\$schema": "$SCHEMA",
  "name": "$NS/kagent",
  "title": "kagent — Agent Orchestration",
  "description": "Kubernetes-native agent runtime. Tools: list_agents, invoke_agent.",
  "version": "0.10.0-rc3"
}
EOF
)"

publish servers "agentregistry — catalog" "$(cat <<EOF
{
  "\$schema": "$SCHEMA",
  "name": "$NS/agentregistry",
  "title": "agentregistry — Catalog",
  "description": "Catalog of MCP servers, agents and skills deployed on this platform.",
  "version": "0.3.3"
}
EOF
)"

echo ""
echo "Agents:"

publish agents "medical-data-agent (ungated)" "$(cat <<EOF
{
  "name": "medical-data-agent",
  "description": "Read-only clinical analysis over MIMIC-IV via m3. No approval gates.",
  "version": "0.10.0-rc3",
  "image": "ghcr.io/kagent-dev/kagent/golang-adk:0.10.0-rc3",
  "language": "go",
  "framework": "kagent",
  "modelProvider": "OpenAI",
  "modelName": "gpt-4.1-mini",
  "status": "active"
}
EOF
)"

publish agents "clinical-ops-agent (approval-gated)" "$(cat <<EOF
{
  "name": "clinical-ops-agent",
  "description": "Platform SRE for the clinical data plane. 4 tools require human approval.",
  "version": "0.10.0-rc3",
  "image": "ghcr.io/kagent-dev/kagent/golang-adk:0.10.0-rc3",
  "language": "go",
  "framework": "kagent",
  "modelProvider": "OpenAI",
  "modelName": "gpt-4.1-mini",
  "status": "active"
}
EOF
)"

echo ""
echo "Catalog now contains:"
curl -s "$REGISTRY/v0/servers" | jq -r '.servers[]?.server | "   📦 \(.name) v\(.version)"' 2>/dev/null || true
curl -s "$REGISTRY/v0/agents"  | jq -r '.agents[]?.agent   | "   🤖 \(.name) v\(.version)"' 2>/dev/null || true
echo ""
echo "   Browse: $REGISTRY"
echo ""
