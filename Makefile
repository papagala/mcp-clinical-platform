# MCP Clinical Platform
# Usage: make create && make ports && make registry-seed
# The demo itself runs in Claude Code — see index.html
.PHONY: create destroy ports stop status logs registry-seed approve claude-model substrate substrate-status

CLUSTER  := mcp-clinical
NS       := kagent
GWNS     := agentgateway-system
# Agent Substrate (opt-in) — gVisor actor image, must match the substrate chart version
SUBSTRATE_VERSION := v0.0.6
ATEOM_IMAGE       := ghcr.io/kagent-dev/substrate/ateom-gvisor:$(SUBSTRATE_VERSION)

-include .env
export

# --- Main targets ---

create: _prereqs _cluster _argocd _gateway-api _secrets _deploy _agentgateway _wait _agents
	@echo "\n✅ MCP Clinical Platform is ready!"
	@echo "  next: make ports → make registry-seed"
	@echo "  then open index.html and drive the demo from Claude Code\n"

destroy: stop
	@kind delete cluster --name $(CLUSTER) 2>/dev/null || true

registry-seed:
	@./deploy/registry-seed.sh

# Open the most recent gated tool call awaiting approval. kagent has no global
# approvals inbox — a parked call lives in the chat session that created it, and
# the session id goes in the URL path (a ?session= query param does not work).
approve:
	@S=$$(curl -s -m 5 localhost:8083/api/sessions 2>/dev/null \
		| jq -r '[.data[] | select(.agent_id | test("clinical_ops"))][0] | "\(.id)\t\(.name)\t\(.created_at)"' 2>/dev/null); \
	SID=$$(echo "$$S" | cut -f1); NAME=$$(echo "$$S" | cut -f2); TS=$$(echo "$$S" | cut -f3); \
	if [ -z "$$SID" ] || [ "$$SID" = "null" ]; then \
		echo "❌ no clinical-ops-agent sessions found (is 'make ports' running?)"; exit 1; \
	fi; \
	STATE=$$(curl -s "localhost:8083/api/sessions/$$SID/tasks" | jq -r '.data[].status.state' 2>/dev/null | head -1); \
	if [ "$$STATE" = "input-required" ]; then \
		URL="http://localhost:8090/agents/kagent/clinical-ops-agent/chat/$$SID"; \
		echo "⏸  Approval pending — $$NAME"; \
		echo "   $$URL"; \
		open "$$URL" 2>/dev/null || true; \
	else \
		echo "ℹ️  Most recent session is '$$STATE' — nothing to approve."; \
		echo "   The agent answered without calling a gated tool."; \
	fi

claude-model:
	@[ -n "$$ANTHROPIC_API_KEY" ] || (echo "❌ ANTHROPIC_API_KEY not set"; exit 1)
	@CLEAN_KEY=$$(echo $$ANTHROPIC_API_KEY | tr -d '"'); \
	kubectl create secret generic kagent-anthropic \
		--from-literal=ANTHROPIC_API_KEY="$$CLEAN_KEY" \
		-n $(NS) --dry-run=client -o yaml | kubectl apply -f -
	@kubectl apply -f deploy/kagent-resources/optional/claude-modelconfig.yaml
	@echo "✅ claude-model ModelConfig applied"
	@echo "   Swap an agent onto Claude with one patch:"
	@echo "   kubectl patch agent clinical-ops-agent -n $(NS) --type=merge \\"
	@echo "     -p '{\"spec\":{\"declarative\":{\"modelConfig\":\"claude-model\"}}}'"

substrate:
	@echo "🧬 Installing Agent Substrate (opt-in, requires gVisor)..."
	@kubectl apply -f deploy/argocd/optional/
	@for app in substrate-crds substrate; do \
		echo "   Waiting for $$app..."; \
		for i in $$(seq 1 30); do \
			HEALTH=$$(kubectl get application $$app -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null); \
			if [ "$$HEALTH" = "Healthy" ]; then echo "   ✅ $$app healthy"; break; fi; \
			sleep 10; \
		done; \
	done
	@echo "   Pointing kagent controller at the substrate API..."
	@kubectl patch application kagent -n argocd --type=json -p '[{"op":"add","path":"/spec/sources/1/helm/parameters","value":[{"name":"controller.substrate.enabled","value":"true"},{"name":"controller.substrate.ateApiEndpoint","value":"dns:///api.ate-system.svc:443"},{"name":"controller.substrate.atenetRouterURL","value":"http://atenet-router.ate-system.svc:80"},{"name":"controller.substrate.ateApiInsecure","value":"true"},{"name":"controller.substrate.defaultWorkerPool.name","value":"kagent-default"},{"name":"substrateWorkerPool.create","value":"true"},{"name":"substrateWorkerPool.ateomImage","value":"$(ATEOM_IMAGE)"}]}]'
	@echo "   Waiting for the worker pool..."
	@sleep 20
	@kubectl create secret generic openclaw-gateway-token \
		--from-literal=token="$${OPENCLAW_GATEWAY_TOKEN:-placeholder}" \
		-n $(NS) --dry-run=client -o yaml | kubectl apply -f -
	@kubectl apply -f deploy/kagent-resources/optional/sandbox-agent.yaml
	@kubectl apply -f deploy/kagent-resources/optional/agent-harness.yaml
	@echo "✅ Substrate applied — check with: make substrate-status"

substrate-status:
	@echo "\n🧬 Agent Substrate\n"
	@kubectl get workerpools -A --no-headers 2>/dev/null | awk '{printf "  pool  %-30s %s\n", $$2, $$3}' || echo "  (no WorkerPools — substrate not installed)"
	@kubectl get sandboxagents,agentharnesses -n $(NS) --no-headers 2>/dev/null | awk '{printf "  %-40s %s\n", $$1, $$2}' || true
	@echo ""
	@kubectl get pods -n ate-system --no-headers 2>/dev/null | awk '{printf "  %-50s %s\n", $$1, $$3}' || echo "  (ate-system namespace absent)"

ports:
	@pkill -f "kubectl port-forward" 2>/dev/null || true
	@sleep 1
	@kubectl port-forward svc/agentgateway-proxy -n $(GWNS) 4000:80 >/dev/null 2>&1 &
	@kubectl port-forward svc/kagent-ui -n $(NS) 8090:8080 >/dev/null 2>&1 &
	@kubectl port-forward svc/argocd-server -n argocd 8080:443 >/dev/null 2>&1 &
	@kubectl port-forward svc/agentregistry -n $(NS) 12121:12121 >/dev/null 2>&1 &
	@kubectl port-forward svc/kagent-controller -n $(NS) 8083:8083 >/dev/null 2>&1 &
	@sleep 2
	@echo "✅ Port-forwards running"
	@echo "  agentgateway MCP: http://localhost:4000/mcp"
	@echo "  kagent UI:        http://localhost:8090"
	@echo "  kagent API:       http://localhost:8083 (task states / approvals)"
	@echo "  agentregistry UI: http://localhost:12121"
	@ARGOCD_PW=$$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d); \
	echo "  ArgoCD:           https://localhost:8080 (admin/$$ARGOCD_PW)"
	@COUNT=$$(curl -s -m 3 http://localhost:12121/v0/servers 2>/dev/null | jq -r '.servers | length' 2>/dev/null); \
	if [ "$$COUNT" = "0" ] || [ -z "$$COUNT" ]; then \
		echo "\n  ℹ️  registry catalog is empty → run: make registry-seed"; \
	fi

stop:
	@pkill -f "kubectl port-forward" 2>/dev/null || true
	@echo "✅ Stopped"

status:
	@kubectl get pods -n $(NS) --no-headers 2>/dev/null | awk '{printf "  %-50s %s\n", $$1, $$3}'
	@kubectl get pods -n $(GWNS) --no-headers 2>/dev/null | awk '{printf "  %-50s %s\n", $$1, $$3}'
	@echo ""
	@kubectl get applications -n argocd --no-headers 2>/dev/null | awk '{printf "  %-20s sync=%-10s health=%s\n", $$1, $$2, $$3}'

logs:
	kubectl logs -f -n $(NS) -l 'app.kubernetes.io/name in (kagent-controller,m3,agentregistry)' --all-containers --max-log-requests=10

# --- Internal targets ---

_prereqs:
	@command -v kind >/dev/null    || (echo "❌ kind not found"; exit 1)
	@command -v kubectl >/dev/null || (echo "❌ kubectl not found"; exit 1)
	@command -v helm >/dev/null    || (echo "❌ helm not found"; exit 1)
	@[ -n "$$OPENAI_API_KEY" ]    || (echo "❌ OPENAI_API_KEY not set"; exit 1)

_cluster:
	@echo "🏗️  Creating Kind cluster..."
	@kind delete cluster --name $(CLUSTER) 2>/dev/null || true
	@kind create cluster --config deploy/kind/cluster-config.yaml --wait 120s

_argocd:
	@echo "📦 Installing ArgoCD..."
	@kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
	@kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
	@kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s
	@kubectl wait --for=condition=available deployment/argocd-repo-server -n argocd --timeout=300s

_gateway-api:
	@echo "🌐 Installing Gateway API CRDs..."
	@kubectl apply --server-side --force-conflicts -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.0/standard-install.yaml

_secrets:
	@kubectl create namespace $(NS) --dry-run=client -o yaml | kubectl apply -f -
	@CLEAN_KEY=$$(echo $$OPENAI_API_KEY | tr -d '"'); \
	kubectl create secret generic kagent-openai \
		--from-literal=OPENAI_API_KEY="$$CLEAN_KEY" \
		-n $(NS) --dry-run=client -o yaml | kubectl apply -f -

_deploy:
	@echo "🚀 Deploying kagent + m3 + agentregistry + agentgateway via ArgoCD..."
	@kubectl create namespace $(NS) --dry-run=client -o yaml | kubectl apply -f -
	@kubectl apply -f deploy/argocd/
	@for app in agentgateway-crds agentgateway kagent m3 agentregistry; do \
		echo "   Waiting for $$app..."; \
		for i in $$(seq 1 30); do \
			HEALTH=$$(kubectl get application $$app -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null); \
			if [ "$$HEALTH" = "Healthy" ]; then echo "   ✅ $$app healthy"; break; fi; \
			sleep 10; \
		done; \
	done

_agentgateway:
	@echo "🌐 Deploying agentgateway Gateway + MCP federation..."
	@kubectl apply -f deploy/agentgateway/k8s-resources.yaml
	@for i in $$(seq 1 30); do \
		READY=$$(kubectl get deployment agentgateway-proxy -n $(GWNS) -o jsonpath='{.status.readyReplicas}' 2>/dev/null); \
		if [ "$$READY" = "1" ]; then echo "   ✅ agentgateway-proxy running"; break; fi; \
		sleep 5; \
	done

_wait:
	@for label in "app.kubernetes.io/name=kagent,app.kubernetes.io/component=controller" "app.kubernetes.io/name=m3" "app.kubernetes.io/name=agentregistry"; do \
		for i in $$(seq 1 30); do \
			PHASE=$$(kubectl get pods -n $(NS) -l "$$label" -o jsonpath='{.items[0].status.phase}' 2>/dev/null); \
			if [ "$$PHASE" = "Running" ]; then echo "   ✅ $$label running"; break; fi; \
			sleep 10; \
		done; \
	done

_agents:
	@echo "⏳ Waiting for kagent CRDs..."
	@for i in $$(seq 1 30); do \
		kubectl get crd agents.kagent.dev >/dev/null 2>&1 && break; \
		sleep 5; \
	done
	@kubectl apply -f deploy/kagent-resources/
	@echo "   ✅ medical-data-agent applied"
