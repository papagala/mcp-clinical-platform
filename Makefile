# MCP Clinical Platform
# Usage: make create && make ports && make demo
.PHONY: create destroy demo ports stop status logs

CLUSTER  := mcp-clinical
NS       := kagent
GWNS     := agentgateway-system
HEADERS  := -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream"
GW       := http://localhost:4000/mcp

-include .env
export

# --- Main targets ---

create: _prereqs _cluster _argocd _gateway-api _secrets _deploy _agentgateway _wait _agents
	@echo "\n✅ MCP Clinical Platform is ready!\n  make ports → make demo\n"

destroy: stop
	@kind delete cluster --name $(CLUSTER) 2>/dev/null || true

demo:
	@echo "\n🎯 MCP Clinical Platform — End-to-End Demo\n"
	@echo "1️⃣  Initializing MCP session..."
	@SESSION=$$(curl -si $(GW) $(HEADERS) \
		-d '{"jsonrpc":"2.0","method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"demo","version":"1.0"}},"id":1}' \
		2>&1 | grep -i 'mcp-session-id' | awk '{print $$2}' | tr -d '\r'); \
	echo "   Session: $$SESSION\n"; \
	echo "2️⃣  Federated tools (agentgateway → kagent + m3 + registry):"; \
	curl -s $(GW) $(HEADERS) -H "Mcp-Session-Id: $$SESSION" \
		-d '{"jsonrpc":"2.0","method":"tools/list","id":2}' \
		| sed 's/^data: //' | jq -r '.result.tools[] | "   ✅ \(.name)"'; \
	echo ""; \
	echo "3️⃣  Race distribution (m3 via agentgateway):"; \
	curl -s $(GW) $(HEADERS) -H "Mcp-Session-Id: $$SESSION" \
		-d '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"m3_get_race_distribution","arguments":{}},"id":3}' \
		| sed 's/^data: //' | jq -r '.result.content[0].text'; \
	echo ""; \
	echo "4️⃣  kagent agents:"; \
	curl -s $(GW) $(HEADERS) -H "Mcp-Session-Id: $$SESSION" \
		-d '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"kagent_list_agents","arguments":{}},"id":4}' \
		| sed 's/^data: //' | jq -r '.result.structuredContent.agents[] | "   🤖 \(.ref) — \(.description | split("\n")[0][0:70])"'; \
	echo ""; \
	echo "5️⃣  ICU stays (m3 via agentgateway):"; \
	curl -s $(GW) $(HEADERS) -H "Mcp-Session-Id: $$SESSION" \
		-d '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"m3_get_icu_stays","arguments":{"limit":5}},"id":5}' \
		| sed 's/^data: //' | jq -r '.result.content[0].text'; \
	echo ""; \
	echo "6️⃣  Registry health:"; \
	curl -s $(GW) $(HEADERS) -H "Mcp-Session-Id: $$SESSION" \
		-d '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"registry_registry_version","arguments":{}},"id":6}' \
		| sed 's/^data: //' | jq -r '.result.content[0].text'; \
	echo ""; \
	echo "7️⃣  Invoke medical-data-agent (kagent → m3, full agentic loop):"; \
	curl -s $(GW) $(HEADERS) -H "Mcp-Session-Id: $$SESSION" \
		-d '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"kagent_invoke_agent","arguments":{"agent":"kagent/medical-data-agent","task":"What is the average ICU length of stay?"}},"id":7}' \
		| sed 's/^data: //' | jq -r '.result.content[0].text'; \
	echo "\n✅ All endpoints working!\n"; \
	echo "UIs:"; \
	echo "  🤖 kagent:        http://localhost:8090"; \
	echo "  📚 agentregistry: http://localhost:12121"; \
	echo "  📦 ArgoCD:        https://localhost:8080"

ports:
	@pkill -f "kubectl port-forward" 2>/dev/null || true
	@sleep 1
	@kubectl port-forward svc/agentgateway-proxy -n $(GWNS) 4000:80 >/dev/null 2>&1 &
	@kubectl port-forward svc/kagent-ui -n $(NS) 8090:8080 >/dev/null 2>&1 &
	@kubectl port-forward svc/argocd-server -n argocd 8080:443 >/dev/null 2>&1 &
	@kubectl port-forward svc/agentregistry -n $(NS) 12121:12121 >/dev/null 2>&1 &
	@sleep 2
	@echo "✅ Port-forwards running"
	@echo "  agentgateway MCP: http://localhost:4000/mcp"
	@echo "  kagent UI:        http://localhost:8090"
	@echo "  agentregistry UI: http://localhost:12121"
	@ARGOCD_PW=$$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d); \
	echo "  ArgoCD:           https://localhost:8080 (admin/$$ARGOCD_PW)"

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
