#!/usr/bin/env bash
set -euo pipefail
# Configuration block number
LONDON_BLOCK=12965000  
PARIS_BLOCK=15537394
SHANGHAI_BLOCK=17034870
CANCUN_BLOCK=19426587
PETRA_BLOCK=22431084

# Ensure Foundry is on PATH for non-interactive shells (like VS Code hooks)
export PATH="$PATH:$HOME/.foundry/bin"

# Required: which exploit contract to run
: "${LEARN_ATTACK_CONTRACT:?Missing LEARN_ATTACK_CONTRACT}"

# ── Start the RPC proxy ──────────────────────────────────────
# Kill any existing proxy
pkill -f "node scripts/mock_rpc_proxy.js" 2>/dev/null || true

node scripts/mock_rpc_proxy.js &
PROXY_PID=$!
trap "kill $PROXY_PID 2>/dev/null || true" EXIT

# Wait for proxy to be ready (up to 10s)
echo "Waiting for RPC proxy..."

for i in $(seq 1 10); do
  if curl -s localhost:8546 -X POST -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' > /dev/null 2>&1; then
    break
  fi
  if [ "$i" -eq 10 ]; then
    echo "ERROR: RPC proxy failed to start within 10s"
    exit 1
  fi
  sleep 1
done

echo "RPC proxy running on :8546"
export RPC_URL="http://localhost:8546"

echo "Running reproduction using RPC cache."
echo "If you want to modify the attack's code with new calls, manually set the RPC_URL env var providing an active RPC endpoint."

# Initialize empty - will only be set for Ethereum
EVM_VERSION_FLAG=""

ATTACK_FILE_PATH=$(grep -rl "contract ${LEARN_ATTACK_CONTRACT}\b" ./test | head -n 1)
if [ -n "$ATTACK_FILE_PATH" ]; then
    TEST_DIR=$(dirname "$ATTACK_FILE_PATH")
    README_PATH="${TEST_DIR}/README.md"
    
    if [ -f "$README_PATH" ]; then
        # Check if network is Ethereum
        if grep -q 'network:' "$README_PATH" && grep 'network:' "$README_PATH" | grep -q 'ethereum'; then
            # Only calculate EVM version for Ethereum
            ATTACK_BLOCK=$(grep -A 2 'attack_block:' "$README_PATH" | grep -o '[0-9]\+' | head -n 1 || true)
            ATTACK_BLOCK=${ATTACK_BLOCK:-0}
            
            if [ -n "$ATTACK_BLOCK" ] && [ "$ATTACK_BLOCK" -gt 0 ]; then
                if (( ATTACK_BLOCK < LONDON_BLOCK )); then EVM_VERSION="berlin";
                elif (( ATTACK_BLOCK < PARIS_BLOCK )); then EVM_VERSION="london";
                elif (( ATTACK_BLOCK < SHANGHAI_BLOCK )); then EVM_VERSION="paris";
                elif (( ATTACK_BLOCK < CANCUN_BLOCK )); then EVM_VERSION="shanghai";
                elif (( ATTACK_BLOCK < PETRA_BLOCK )); then EVM_VERSION="cancun";
                else EVM_VERSION="prague"; fi
                
                EVM_VERSION_FLAG="--evm-version $EVM_VERSION"
                echo "Using EVM Version: $EVM_VERSION (Ethereum block $ATTACK_BLOCK)"
            fi
        else
            # Non-Ethereum network: let Foundry auto-detect
            NETWORK=$(grep 'network:' "$README_PATH" | sed 's/.*network:[[:space:]]*//' | head -n 1 || echo "unknown")
            echo "Network: $NETWORK (using default EVM version)"
        fi
    fi
fi

printf "\n▶ Running exploit: %s\n\n" "$LEARN_ATTACK_CONTRACT"

# Run with or without --evm-version flag
if [ -n "$EVM_VERSION_FLAG" ]; then
    forge test --match-contract "$LEARN_ATTACK_CONTRACT" -vvv $EVM_VERSION_FLAG
else
    forge test --match-contract "$LEARN_ATTACK_CONTRACT" -vvv
fi

echo
echo "✅ Done. Opening interactive shell..."

exec bash -l