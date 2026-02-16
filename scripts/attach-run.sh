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

# ── Find attack file and extract fork block ──────────────────
ATTACK_FILE_PATH=$(grep -rl --include="*.sol" "contract ${LEARN_ATTACK_CONTRACT}\b" ./test | head -n 1)
FORK_BLOCK=""
EVM_VERSION_FLAG=""

if [ -n "$ATTACK_FILE_PATH" ]; then
    # Extract block number from createSelectFork call (strip Solidity underscores)
    FORK_BLOCK=$(grep -oP 'createSelectFork\([^,]+,\s*\K[\d_]+' "$ATTACK_FILE_PATH" | tr -d '_' | head -n 1 || true)

    TEST_DIR=$(dirname "$ATTACK_FILE_PATH")
    README_PATH="${TEST_DIR}/README.md"

    if [ -f "$README_PATH" ]; then
        # Check if network is Ethereum
        if grep -q 'network:' "$README_PATH" && grep 'network:' "$README_PATH" | grep -qi 'ethereum'; then
            # Only calculate EVM version for Ethereum
            ATTACK_BLOCK=${FORK_BLOCK:-0}

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

if [ -z "$FORK_BLOCK" ]; then
    echo "WARNING: Could not extract fork block from $ATTACK_FILE_PATH"
    echo "The RPC proxy requires FORK_BLOCK to serve the correct chain metadata."
    exit 1
fi

# Resolve chain ID from rpc_cache/blocks/<chainId>/<block>/ directory
CHAIN_ID=""
for chain_dir in rpc_cache/blocks/*/; do
  if [ -d "${chain_dir}${FORK_BLOCK}" ]; then
    CHAIN_ID=$(basename "$chain_dir")
    break
  fi
done

if [ -z "$CHAIN_ID" ]; then
    echo "ERROR: No rpc_cache/blocks/<chainId>/$FORK_BLOCK/ directory found."
    echo "Run warm_all.sh first to populate the cache."
    exit 1
fi

echo "Fork block: $FORK_BLOCK (chain $CHAIN_ID)"

# ── Start the RPC proxy ──────────────────────────────────────
# Kill any existing proxy
pkill -f "node scripts/mock_rpc_proxy.js" 2>/dev/null || true

FORK_BLOCK="$FORK_BLOCK" CHAIN_ID="$CHAIN_ID" node scripts/mock_rpc_proxy.js &
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
