#!/usr/bin/env bash
# Three calls against fetch_citation_source: a legitimate lookup, a direct
# (no-gateway) proof that the tool's own code has no destination check, and
# a laundering attempt made through agentgateway, where the mcpGuardrails
# policy in config.yaml rejects it before the fetch happens.
#
# Requires an `agentgateway` binary on PATH (or set AGENTGATEWAY_BIN)
# built from a commit containing the mcpGuardrails CEL processor
# (unreleased as of 2026-10-12; see README for the build command).
set -euo pipefail
cd "$(dirname "$0")/.."

AGENTGATEWAY_BIN="${AGENTGATEWAY_BIN:-agentgateway}"
INSPECTOR="npx -y @modelcontextprotocol/inspector --cli"
MCP_URL="http://localhost:13100/mcp"
mkdir -p captures

echo "--- starting mock citation-api (8081) and attacker-target (8082) ---"
python3 services/citation-api/server.py 8081 > captures/citation-api.log 2>&1 &
CITATION_PID=$!
python3 services/attacker-target/server.py 8082 > captures/attacker-target.log 2>&1 &
ATTACKER_PID=$!
cleanup() {
  kill "$CITATION_PID" "$ATTACKER_PID" "${GW_PID:-}" 2>/dev/null || true
}
trap cleanup EXIT
sleep 1

echo
echo "--- 1. DIRECT (no gateway): the tool's own fetch logic, called with no MCP framing ---"
echo "Legitimate call, citation-api:"
node mcp-server/direct-fetch.js http://localhost:8081/works/10.1234/example | tee captures/01-direct-legit.txt
echo "Laundered call, attacker-target, same code path, no check:"
node mcp-server/direct-fetch.js http://localhost:8082/ | tee captures/02-direct-laundered.txt
echo "attacker-target saw:"
curl -s http://localhost:8082/stats | tee captures/02b-attacker-stats-after-direct.json
echo

echo "--- starting agentgateway (config.yaml) ---"
"$AGENTGATEWAY_BIN" -f config.yaml > captures/gateway.log 2>&1 &
GW_PID=$!
for i in $(seq 1 30); do
  if curl -s -o /dev/null "http://localhost:13100/mcp"; then
    break
  fi
  sleep 0.5
done

echo
echo "--- 2. THROUGH THE GATEWAY: legitimate citation lookup ---"
$INSPECTOR "$MCP_URL" --method tools/call --tool-name fetch_citation_source \
  --tool-arg source_url=http://localhost:8081/works/10.1234/example \
  | tee captures/03-gateway-allowed.json

echo
echo "--- 3. THROUGH THE GATEWAY: laundering attempt at attacker-target ---"
BEFORE=$(curl -s http://localhost:8082/stats)
echo "attacker-target before: $BEFORE"
$INSPECTOR "$MCP_URL" --method tools/call --tool-name fetch_citation_source \
  --tool-arg source_url=http://localhost:8082/ \
  | tee captures/04-gateway-rejected.json || true
AFTER=$(curl -s http://localhost:8082/stats)
echo "attacker-target after:  $AFTER"
echo "$AFTER" > captures/05-attacker-stats-after-gateway.json

echo
echo "--- gateway log ---"
cat captures/gateway.log
