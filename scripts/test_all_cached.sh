#!/bin/bash
set -euo pipefail
# test_all_cached.sh — Verify all cached attacks run offline.
# Simulates the devcontainer flow locally:
#   1. Wipe Foundry's cache
#   2. Restore from committed rpc_cache/foundry/
#   3. For each attack: start proxy, run forge test, record result
#
# Usage:
#   bash scripts/test_all_cached.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_DIR"

# EVM version boundaries (Ethereum only)
LONDON_BLOCK=12965000
PARIS_BLOCK=15537394
SHANGHAI_BLOCK=17034870
CANCUN_BLOCK=19426587
PETRA_BLOCK=22431084

SUCCEEDED=0
FAILED=0
SKIPPED=0
FAILURES=""

# ── Step 1: Wipe and restore Foundry cache ────────────────────
echo "Wiping ~/.foundry/cache/ ..."
rm -rf "$HOME/.foundry/cache"

if [ ! -d "rpc_cache/foundry" ]; then
  echo "ERROR: rpc_cache/foundry/ not found. Run warm_all.sh first."
  exit 1
fi

mkdir -p "$HOME/.foundry/cache"
cp -r rpc_cache/foundry/* "$HOME/.foundry/cache/"
echo "Foundry RPC cache restored."
echo ""

# ── Step 2: Test each attack ──────────────────────────────────
for devcontainer in .devcontainer/*/devcontainer.json; do
  DIR_NAME=$(basename "$(dirname "$devcontainer")")

  # Extract contract name
  CONTRACT=$(grep -oP '"LEARN_ATTACK_CONTRACT"\s*:\s*"\K[^"]+' "$devcontainer" || true)
  if [ -z "$CONTRACT" ]; then
    echo "[$DIR_NAME] SKIP: no LEARN_ATTACK_CONTRACT"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  # Find the .sol file
  ATTACK_FILE=$(grep -rl --include="*.sol" "contract ${CONTRACT}\b" ./test 2>/dev/null | head -n 1 || true)
  if [ -z "$ATTACK_FILE" ]; then
    echo "[$DIR_NAME] SKIP: contract $CONTRACT not found in test/"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  # Extract block number from createSelectFork (strip Solidity underscores)
  FORK_BLOCK=$(grep -oP 'createSelectFork\([^,]+,\s*\K[\d_]+' "$ATTACK_FILE" | tr -d '_' | head -n 1 || true)

  # Fallback: constant variable
  if [ -z "$FORK_BLOCK" ]; then
    VAR_NAME=$(grep -oP 'createSelectFork\([^,]+,\s*\K[A-Z_]+' "$ATTACK_FILE" | head -n 1 || true)
    if [ -n "$VAR_NAME" ]; then
      FORK_BLOCK=$(grep -oP "${VAR_NAME}\s*=\s*\K[\d_]+" "$ATTACK_FILE" | tr -d '_' | head -n 1 || true)
    fi
  fi

  if [ -z "$FORK_BLOCK" ]; then
    echo "[$DIR_NAME] SKIP: could not extract block number"
    SKIPPED=$((SKIPPED + 1))
    continue
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
    echo "[$DIR_NAME] SKIP: no rpc_cache/blocks/<chainId>/$FORK_BLOCK/ directory"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  # Determine EVM version flag (Ethereum only)
  EVM_VERSION_FLAG=""
  TEST_DIR=$(dirname "$ATTACK_FILE")
  README="$TEST_DIR/README.md"
  if [ -f "$README" ] && grep -q 'network:' "$README" && grep 'network:' "$README" | grep -qi 'ethereum'; then
    BLOCK_NUM=${FORK_BLOCK}
    if (( BLOCK_NUM < LONDON_BLOCK )); then EVM_VERSION_FLAG="--evm-version berlin";
    elif (( BLOCK_NUM < PARIS_BLOCK )); then EVM_VERSION_FLAG="--evm-version london";
    elif (( BLOCK_NUM < SHANGHAI_BLOCK )); then EVM_VERSION_FLAG="--evm-version paris";
    elif (( BLOCK_NUM < CANCUN_BLOCK )); then EVM_VERSION_FLAG="--evm-version shanghai";
    elif (( BLOCK_NUM < PETRA_BLOCK )); then EVM_VERSION_FLAG="--evm-version cancun";
    else EVM_VERSION_FLAG="--evm-version prague"; fi
  fi

  # Kill any leftover proxy
  pkill -f "node scripts/mock_rpc_proxy.js" 2>/dev/null || true
  sleep 0.2

  # Start proxy for this attack
  FORK_BLOCK="$FORK_BLOCK" CHAIN_ID="$CHAIN_ID" node scripts/mock_rpc_proxy.js &
  PROXY_PID=$!

  # Wait for proxy
  PROXY_OK=false
  for i in $(seq 1 10); do
    if curl -s localhost:8546 -X POST -H "Content-Type: application/json" \
      -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' > /dev/null 2>&1; then
      PROXY_OK=true
      break
    fi
    sleep 1
  done

  if [ "$PROXY_OK" != "true" ]; then
    echo "[$DIR_NAME] FAIL: proxy did not start for chain $CHAIN_ID block $FORK_BLOCK"
    kill "$PROXY_PID" 2>/dev/null || true
    FAILED=$((FAILED + 1))
    FAILURES="$FAILURES  - $DIR_NAME (proxy failed, chain $CHAIN_ID block $FORK_BLOCK)\n"
    continue
  fi

  # Run the test
  echo ""
  echo "=============================================="
  echo "[$DIR_NAME] $CONTRACT | chain $CHAIN_ID block $FORK_BLOCK $EVM_VERSION_FLAG"
  echo "=============================================="

  if RPC_URL="http://localhost:8546" forge test --match-contract "$CONTRACT" -vvv $EVM_VERSION_FLAG; then
    echo "[$DIR_NAME] OK"
    SUCCEEDED=$((SUCCEEDED + 1))
  else
    echo "[$DIR_NAME] FAIL"
    FAILED=$((FAILED + 1))
    FAILURES="$FAILURES  - $DIR_NAME ($CONTRACT at chain $CHAIN_ID block $FORK_BLOCK)\n"
  fi

  # Stop proxy
  kill "$PROXY_PID" 2>/dev/null || true
  wait "$PROXY_PID" 2>/dev/null || true
done

# Final cleanup
pkill -f "node scripts/mock_rpc_proxy.js" 2>/dev/null || true

echo ""
echo "=============================================="
echo "Results: $SUCCEEDED passed, $FAILED failed, $SKIPPED skipped"
if [ -n "$FAILURES" ]; then
  echo ""
  echo "Failures:"
  printf "$FAILURES"
fi
echo "=============================================="
