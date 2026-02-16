#!/bin/bash
set -euo pipefail
# cache_warm.sh <real_rpc> <block_number> <attack_test_contract>
# One-time build step: warms Foundry's RPC cache and captures block/method
# responses so attacks can run fully offline via the mock RPC proxy.
#
# Outputs:
#   .block_cache/<block_number>/block.json        — full block response
#   .block_cache/<block_number>/eth_chainId.json   — chain metadata
#   .block_cache/<block_number>/eth_gasPrice.json
#   .block_cache/<block_number>/net_version.json
#   foundry_rpc_cache/                             — Foundry's internal RPC cache

REAL_RPC="${1:?Usage: cache_warm.sh <real_rpc> <block_number> <test_contract>}"
BLOCK="${2:?Usage: cache_warm.sh <real_rpc> <block_number> <test_contract>}"
BLOCK="${BLOCK//_/}"
TEST="${3:?Usage: cache_warm.sh <real_rpc> <block_number> <test_contract>}"
PORT=8546

BLOCK_DIR=".block_cache/$BLOCK"
mkdir -p "$BLOCK_DIR"

# 1. Start anvil forked from real RPC on the same port the proxy will use,
#    so Foundry's cache is keyed to http://localhost:8546
anvil --fork-url "$REAL_RPC" --fork-block-number "$BLOCK" --port "$PORT" &
ANVIL_PID=$!

# Wait for anvil to be ready (up to 30s)
echo "Waiting for anvil on port $PORT..."
for i in $(seq 1 30); do
  if curl -sf "http://localhost:$PORT" -X POST -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' > /dev/null 2>&1; then
    echo "anvil ready after ${i}s"
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "ERROR: anvil failed to start within 30s"
    kill -9 "$ANVIL_PID" 2>/dev/null || true
    exit 1
  fi
  sleep 1
done

BLOCK_HEX=$(printf '0x%x' "$BLOCK")

# 2. Capture the block response
curl -s "http://localhost:$PORT" -X POST -H "Content-Type: application/json" \
  -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"$BLOCK_HEX\", true],\"id\":1}" \
  > "$BLOCK_DIR/block.json"

# 3. Capture chain metadata method responses
for method in eth_gasPrice eth_chainId net_version; do
  curl -s "http://localhost:$PORT" -X POST -H "Content-Type: application/json" \
    -d "{\"jsonrpc\":\"2.0\",\"method\":\"$method\",\"params\":[],\"id\":1}" \
    > "$BLOCK_DIR/$method.json"
  echo "Captured $method"
done

# 4. Snapshot clean state
SNAP=$(curl -s "http://localhost:$PORT" -X POST -H "Content-Type: application/json" \
  -d '{"method":"evm_snapshot","params":[],"id":1,"jsonrpc":"2.0"}' | jq -r '.result')

# 5. Run attack through localhost:8546 — warms Foundry cache keyed to this URL
RPC_URL="http://localhost:$PORT" forge test --match-contract "$TEST" -vvv 2>&1 || true

# 6. Revert to clean state
curl -s "http://localhost:$PORT" -X POST -H "Content-Type: application/json" \
  -d "{\"method\":\"evm_revert\",\"params\":[\"$SNAP\"],\"id\":1,\"jsonrpc\":\"2.0\"}" > /dev/null

# 7. Stop anvil — use kill -9 and wait with || true so the script doesn't abort
kill -9 "$ANVIL_PID" 2>/dev/null || true
wait "$ANVIL_PID" 2>/dev/null || true

# 8. Copy Foundry's RPC cache (keyed to localhost:8546)
mkdir -p ./foundry_rpc_cache
cp -r ~/.foundry/cache/* ./foundry_rpc_cache/

echo "Cache warmed for block $BLOCK. Files:"
ls -la "$BLOCK_DIR/"
