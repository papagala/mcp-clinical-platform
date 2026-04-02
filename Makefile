# MCP Clinical Platform — Federated MCP + GitOps + AI Agents
# =============================================================================
# QUICK START:
#   export OPENAI_API_KEY=sk-your-key
#   make create     → Kind cluster + ArgoCD + kagent + m3 + agentregistry (full GitOps deploy)
#   make ports      → Start all port-forwards
#   make gateway    → Start agentgateway (federates kagent + m3 + agentregistry MCP servers)
#   make demo       → Show demo curl commands
#   make stop       → Stop port-forwards + gateway
#   make destroy    → Tear down cluster
# =============================================================================

.PHONY: create destroy demo demo-script ports stop status help gateway logs \
        create-cluster install-argocd deploy-kagent deploy-m3 deploy-agentregistry \
        apply-agent-resources \
        _check-prereqs _create-secrets _wait-kagent _wait-m3 _wait-agentregistry

CLUSTER_NAME   := mcp-clinical
NAMESPACE      := kagent
KAGENT_VERSION := 0.8.3

# Load .env if present
-include .env
export

# =============================================================================
# 🚀 MAIN COMMANDS
# =============================================================================

## Full setup: cluster + ArgoCD + kagent + m3 + agentregistry + agent resources
create: _check-prereqs create-cluster install-argocd _create-secrets deploy-kagent deploy-m3 deploy-agentregistry _wait-kagent _wait-m3 _wait-agentregistry apply-agent-resources
	@echo ""
	@echo "============================================"
	@echo "✅ MCP Clinical Platform is ready!"
	@echo "============================================"
	@echo ""
	@echo "Next steps:"
	@echo "  make ports     → Start port-forwards"
	@echo "  make gateway   → Start agentgateway (in separate terminal)"
	@echo "  make demo      → Show demo commands"
	@echo ""

## Tear down the cluster completely
destroy: stop
	@echo "💥 Destroying cluster..."
	@kind delete cluster --name $(CLUSTER_NAME) 2>/dev/null || true
	@echo "✅ Cluster destroyed"

## Show demo commands
demo:
	@echo ""
	@echo "🎯 MCP Clinical Platform Demo"
	@echo "=============================="
	@echo ""
	@echo "Prerequisites: make ports && make gateway (in separate terminal)"
	@echo ""
	@echo "1️⃣  Test m3 MCP server directly (medical data tools):"
	@echo '   curl -s http://localhost:3000/mcp -H "Content-Type: application/json" \'
	@echo '     -d '"'"'{"jsonrpc":"2.0","method":"tools/list","id":1}'"'"' | python3 -m json.tool'
	@echo ""
	@echo "2️⃣  Test kagent MCP server (agent orchestration tools):"
	@echo '   curl -s http://localhost:8083/mcp -H "Content-Type: application/json" \'
	@echo '     -d '"'"'{"jsonrpc":"2.0","method":"tools/list","id":1}'"'"' | python3 -m json.tool'
	@echo ""
	@echo "3️⃣  Test agentgateway (federated MCP — both servers unified):"
	@echo '   curl -s http://localhost:4000/ -H "Content-Type: application/json" \'
	@echo '     -d '"'"'{"jsonrpc":"2.0","method":"tools/list","id":1}'"'"' | python3 -m json.tool'
	@echo ""
	@echo "4️⃣  Call m3 tool via agentgateway (race distribution):"
	@echo '   curl -s http://localhost:4000/ -H "Content-Type: application/json" \'
	@echo '     -d '"'"'{"jsonrpc":"2.0","method":"tools/call","params":{"name":"m3_get_race_distribution","arguments":{}},"id":2}'"'"' | python3 -m json.tool'
	@echo ""
	@echo "5️⃣  List kagent agents via agentgateway:"
	@echo '   curl -s http://localhost:4000/ -H "Content-Type: application/json" \'
	@echo '     -d '"'"'{"jsonrpc":"2.0","method":"tools/call","params":{"name":"kagent_list_agents","arguments":{}},"id":3}'"'"' | python3 -m json.tool'
	@echo ""
	@echo "6️⃣  UIs:"
	@echo "   open http://localhost:15000/ui   # agentgateway playground"
	@echo "   open http://localhost:8090       # kagent dashboard"
	@echo "   open http://localhost:12121      # agentregistry catalog"
	@echo "   open https://localhost:8080      # ArgoCD"
	@echo ""
	@echo "7️⃣  VS Code: copy .vscode/mcp.json to your project"
	@echo ""

## Run interactive demo script (for hackathon judges)
demo-script:
	@./deploy/demo.sh

# =============================================================================
# 🔌 PORT FORWARDING
# =============================================================================

## Start all port-forwards
ports:
	@echo "🔌 Starting port-forwards..."
	@pkill -f "kubectl port-forward" 2>/dev/null || true
	@sleep 1
	@echo "   🤖 kagent MCP   → localhost:8083"
	@kubectl port-forward svc/kagent-controller -n $(NAMESPACE) 8083:8083 >/dev/null 2>&1 &
	@echo "   🖥️  kagent UI    → localhost:8090"
	@kubectl port-forward svc/kagent-ui -n $(NAMESPACE) 8090:8080 >/dev/null 2>&1 &
	@echo "   🏥 m3 MCP       → localhost:3000"
	@kubectl port-forward svc/m3 -n $(NAMESPACE) 3000:3000 >/dev/null 2>&1 &
	@echo "   📦 ArgoCD UI    → localhost:8080"
	@kubectl port-forward svc/argocd-server -n argocd 8080:443 >/dev/null 2>&1 &
	@echo "   📚 agentregistry UI → localhost:12121"
	@kubectl port-forward svc/agentregistry -n $(NAMESPACE) 12121:12121 >/dev/null 2>&1 &
	@echo "   📚 agentregistry MCP → localhost:31313"
	@kubectl port-forward svc/agentregistry -n $(NAMESPACE) 31313:31313 >/dev/null 2>&1 &
	@sleep 2
	@echo ""
	@echo "✅ Port-forwards running!"
	@echo "   http://localhost:8083  → kagent MCP (Streamable HTTP)"
	@echo "   http://localhost:8090  → kagent Dashboard"
	@echo "   http://localhost:3000  → m3 MCP Server"
	@echo "   http://localhost:12121 → agentregistry UI"
	@echo "   http://localhost:31313 → agentregistry MCP"
	@ARGOCD_PW=$$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d); \
	echo "   https://localhost:8080 → ArgoCD (admin/$$ARGOCD_PW)"
	@echo ""
	@echo "Run 'make gateway' to start agentgateway (separate terminal)"

## Stop all port-forwards and agentgateway
stop:
	@echo "🛑 Stopping everything..."
	@pkill -f "kubectl port-forward" 2>/dev/null || true
	@pkill -f "agentgateway" 2>/dev/null || true
	@echo "✅ All stopped"

# =============================================================================
# 🌐 AGENTGATEWAY
# =============================================================================

## Start agentgateway (federates kagent + m3 + agentregistry MCP servers into :4000)
gateway:
	@echo "🌐 Starting agentgateway..."
	@if ! command -v agentgateway >/dev/null 2>&1; then \
		echo "   Installing agentgateway..."; \
		curl -sL https://agentgateway.dev/install | bash; \
	fi
	@pkill -f "agentgateway" 2>/dev/null || true
	@sleep 1
	@echo "   Federating MCP servers:"
	@echo "     kagent        → http://localhost:8083/mcp"
	@echo "     m3            → http://localhost:3000/mcp"
	@echo "     agentregistry → http://localhost:31313/mcp"
	@echo ""
	@echo "   agentgateway MCP endpoint: http://localhost:4000/"
	@echo "   agentgateway UI:           http://localhost:15000/ui"
	@echo ""
	agentgateway -f deploy/agentgateway/config.yaml

# =============================================================================
# 📊 STATUS & LOGS
# =============================================================================

## Show cluster and service status
status:
	@echo "📊 MCP Clinical Platform Status"
	@echo "================================"
	@echo ""
	@echo "Cluster:"
	@kubectl cluster-info --context kind-$(CLUSTER_NAME) 2>/dev/null && echo "  ✅ Running" || echo "  ❌ Not running"
	@echo ""
	@echo "Pods ($(NAMESPACE)):"
	@kubectl get pods -n $(NAMESPACE) 2>/dev/null || echo "  Not available"
	@echo ""
	@echo "ArgoCD Apps:"
	@kubectl get applications -n argocd 2>/dev/null || echo "  Not available"
	@echo ""
	@echo "kagent Agents:"
	@kubectl get agents -n $(NAMESPACE) 2>/dev/null || echo "  None"
	@echo ""
	@echo "Port-forwards:"
	@pgrep -f "kubectl port-forward" >/dev/null 2>&1 && echo "  ✅ Running" || echo "  ❌ Not running (make ports)"
	@echo ""
	@echo "agentgateway:"
	@pgrep -f "agentgateway" >/dev/null 2>&1 && echo "  ✅ Running" || echo "  ❌ Not running (make gateway)"

## Stream logs from kagent and m3
logs:
	@echo "📜 Streaming logs (Ctrl+C to stop)..."
	kubectl logs -f -n $(NAMESPACE) -l 'app.kubernetes.io/name in (kagent-controller,m3)' --all-containers --max-log-requests=5

# =============================================================================
# 🔧 INDIVIDUAL STEPS
# =============================================================================

## Create Kind cluster
create-cluster:
	@echo "🏗️  Creating Kind cluster '$(CLUSTER_NAME)'..."
	@kind delete cluster --name $(CLUSTER_NAME) 2>/dev/null || true
	@kind create cluster --config deploy/kind/cluster-config.yaml --wait 120s
	@kubectl cluster-info --context kind-$(CLUSTER_NAME)
	@echo "✅ Cluster ready!"

## Install ArgoCD
install-argocd:
	@echo "📦 Installing ArgoCD..."
	@kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
	@kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
	@echo "   Waiting for ArgoCD to be ready..."
	@kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s
	@kubectl wait --for=condition=available deployment/argocd-repo-server -n argocd --timeout=300s
	@echo "✅ ArgoCD installed!"

## Deploy kagent via ArgoCD (GitOps)
deploy-kagent:
	@echo "🤖 Deploying kagent via ArgoCD (v$(KAGENT_VERSION))..."
	@kubectl create namespace $(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	@kubectl apply -f deploy/argocd/kagent-app.yaml
	@echo "   Syncing kagent application..."
	@sleep 5
	@for i in $$(seq 1 30); do \
		STATUS=$$(kubectl get application kagent -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null); \
		HEALTH=$$(kubectl get application kagent -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null); \
		echo "   [$$i/30] Sync: $$STATUS | Health: $$HEALTH"; \
		if [ "$$HEALTH" = "Healthy" ]; then break; fi; \
		sleep 10; \
	done
	@echo "✅ kagent deployed via ArgoCD!"

## Deploy m3 MCP server via ArgoCD (GitOps)
deploy-m3:
	@echo "🏥 Deploying m3 MCP server via ArgoCD..."
	@kubectl apply -f deploy/argocd/m3-app.yaml
	@echo "   Syncing m3 application..."
	@sleep 5
	@for i in $$(seq 1 20); do \
		STATUS=$$(kubectl get application m3 -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null); \
		HEALTH=$$(kubectl get application m3 -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null); \
		echo "   [$$i/20] Sync: $$STATUS | Health: $$HEALTH"; \
		if [ "$$HEALTH" = "Healthy" ]; then break; fi; \
		sleep 10; \
	done
	@echo "✅ m3 deployed via ArgoCD!"

## Deploy agentregistry via ArgoCD (GitOps)
deploy-agentregistry:
	@echo "📚 Deploying agentregistry via ArgoCD..."
	@kubectl apply -f deploy/argocd/agentregistry-app.yaml
	@echo "   Syncing agentregistry application..."
	@sleep 5
	@for i in $$(seq 1 30); do \
		STATUS=$$(kubectl get application agentregistry -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null); \
		HEALTH=$$(kubectl get application agentregistry -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null); \
		echo "   [$$i/30] Sync: $$STATUS | Health: $$HEALTH"; \
		if [ "$$HEALTH" = "Healthy" ]; then break; fi; \
		sleep 10; \
	done
	@echo "✅ agentregistry deployed via ArgoCD!"

## Apply kagent Agent CRDs (medical-data-agent)
apply-agent-resources:
	@echo "🧠 Applying kagent agent resources..."
	@kubectl apply -f deploy/kagent-resources/
	@echo "✅ Agent resources applied!"

# =============================================================================
# 🔧 INTERNAL TARGETS
# =============================================================================

_check-prereqs:
	@echo "🔍 Checking prerequisites..."
	@command -v kind >/dev/null    || (echo "❌ kind not installed. Run: brew install kind"; exit 1)
	@command -v kubectl >/dev/null || (echo "❌ kubectl not installed. Run: brew install kubectl"; exit 1)
	@command -v helm >/dev/null    || (echo "❌ helm not installed. Run: brew install helm"; exit 1)
	@if [ -z "$$OPENAI_API_KEY" ]; then \
		echo "❌ OPENAI_API_KEY not set. Export it or create .env file"; \
		echo "   echo 'OPENAI_API_KEY=sk-your-key' > .env"; \
		exit 1; \
	fi
	@echo "✅ Prerequisites OK"

_create-secrets:
	@echo "🔐 Creating secrets..."
	@kubectl create namespace $(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	@CLEAN_KEY=$$(echo $$OPENAI_API_KEY | tr -d '"'); \
	kubectl create secret generic kagent-openai \
		--from-literal=OPENAI_API_KEY="$$CLEAN_KEY" \
		-n $(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	@echo "✅ Secrets created"

_wait-kagent:
	@echo "⏳ Waiting for kagent pods..."
	@for i in $$(seq 1 30); do \
		READY=$$(kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=kagent,app.kubernetes.io/component=controller -o jsonpath='{.items[0].status.phase}' 2>/dev/null); \
		if [ "$$READY" = "Running" ]; then echo "✅ kagent controller running!"; break; fi; \
		echo "   [$$i/30] Waiting for kagent controller... ($$READY)"; \
		sleep 10; \
	done

_wait-m3:
	@echo "⏳ Waiting for m3 pods..."
	@for i in $$(seq 1 20); do \
		READY=$$(kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=m3 -o jsonpath='{.items[0].status.phase}' 2>/dev/null); \
		if [ "$$READY" = "Running" ]; then echo "✅ m3 running!"; break; fi; \
		echo "   [$$i/20] Waiting for m3... ($$READY)"; \
		sleep 10; \
	done

_wait-agentregistry:
	@echo "⏳ Waiting for agentregistry pods..."
	@for i in $$(seq 1 30); do \
		READY=$$(kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=agentregistry -o jsonpath='{.items[0].status.phase}' 2>/dev/null); \
		if [ "$$READY" = "Running" ]; then echo "✅ agentregistry running!"; break; fi; \
		echo "   [$$i/30] Waiting for agentregistry... ($$READY)"; \
		sleep 10; \
	done

# =============================================================================
# 📖 HELP
# =============================================================================

## Show this help
help:
	@echo ""
	@echo "🏥 MCP Clinical Platform — GitOps + MCP + AgentGateway"
	@echo "======================================================="
	@echo ""
	@echo "QUICK START:"
	@echo "  export OPENAI_API_KEY=sk-your-key"
	@echo "  make create      Setup cluster + deploy everything (GitOps)"
	@echo "  make ports       Start all port-forwards"
	@echo "  make gateway     Start agentgateway (separate terminal)"
	@echo "  make demo        Show demo commands"
	@echo ""
	@echo "COMPONENTS:"
	@echo "  make create-cluster        Kind cluster only"
	@echo "  make install-argocd        ArgoCD only"
	@echo "  make deploy-kagent         kagent via ArgoCD"
	@echo "  make deploy-m3             m3 MCP server via ArgoCD"
	@echo "  make apply-agent-resources Agent CRDs"
	@echo ""
	@echo "OPERATIONS:"
	@echo "  make status      Cluster + service status"
	@echo "  make logs        Stream kagent/m3 logs"
	@echo "  make stop        Stop port-forwards + gateway"
	@echo "  make destroy     Tear down cluster"
	@echo ""
	@echo "ARCHITECTURE:"
	@echo "  VS Code → agentgateway(:4000) → kagent MCP(:8083) + m3 MCP(:3000)"
	@echo "             ↕                      ↕                    ↕"
	@echo "  MCP federation              K8s AI agents        Medical data"
	@echo ""
