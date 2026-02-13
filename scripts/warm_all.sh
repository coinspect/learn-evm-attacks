#!/bin/bash
set -euo pipefail
# warm_all.sh — Iterate over all devcontainer attacks, extract block numbers
# and chain info, and call cache_warm.sh for each.
#
# Requires RPC URLs as env vars:
#   ETH_RPC_URL          — Ethereum mainnet
#   BSC_RPC_URL          — Binance Smart Chain
#   POLYGON_RPC_URL      — Polygon
#   ARBITRUM_RPC_URL     — Arbitrum
#   FANTOM_RPC_URL       — Fantom
#   GNOSIS_RPC_URL       — Gnosis Chain
#
# Usage:
#   export ETH_RPC_URL="https://eth-mainnet.g.alchemy.com/v2/..."
#   export BSC_RPC_URL="https://bsc-dataseed.binance.org"
#   ... etc
#   bash scripts/warm_all.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_DIR"

SUCCEEDED=0
FAILED=0
SKIPPED=0
FAILURES=""

# Map network name (lowercase) → env var name
get_rpc_for_network() {
  local network
  network=$(echo "$1" | tr '[:upper:]' '[:lower:]' | xargs)
  case "$network" in
    ethereum)               echo "${ETH_RPC_URL:-}" ;;
    "binance smart chain")  echo "${BSC_RPC_URL:-}" ;;
    polygon)                echo "${POLYGON_RPC_URL:-}" ;;
    arbitrum)               echo "${ARBITRUM_RPC_URL:-}" ;;
    fantom)                 echo "${FANTOM_RPC_URL:-}" ;;
    "gnosis chain")         echo "${GNOSIS_RPC_URL:-}" ;;
    *)                      echo "" ;;
  esac
}

for devcontainer in .devcontainer/*/devcontainer.json; do
  DIR_NAME=$(basename "$(dirname "$devcontainer")")

  # Extract contract name from devcontainer.json
  CONTRACT=$(grep -oP '"LEARN_ATTACK_CONTRACT"\s*:\s*"\K[^"]+' "$devcontainer" || true)
  if [ -z "$CONTRACT" ]; then
    echo "[$DIR_NAME] SKIP: no LEARN_ATTACK_CONTRACT in devcontainer.json"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  # Find the Solidity test file (restrict to .sol to avoid matching READMEs)
  ATTACK_FILE=$(grep -rl --include="*.sol" "contract ${CONTRACT}\b" ./test 2>/dev/null | head -n 1 || true)
  if [ -z "$ATTACK_FILE" ]; then
    echo "[$DIR_NAME] SKIP: contract $CONTRACT not found in test/"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  # Extract block number from createSelectFork (strip Solidity underscores)
  BLOCK=$(grep -oP 'createSelectFork\([^,]+,\s*\K[\d_]+' "$ATTACK_FILE" | tr -d '_' | head -n 1 || true)

  # If no literal block number, try to find a constant variable
  if [ -z "$BLOCK" ]; then
    VAR_NAME=$(grep -oP 'createSelectFork\([^,]+,\s*\K[A-Z_]+' "$ATTACK_FILE" | head -n 1 || true)
    if [ -n "$VAR_NAME" ]; then
      BLOCK=$(grep -oP "${VAR_NAME}\s*=\s*\K[\d_]+" "$ATTACK_FILE" | tr -d '_' | head -n 1 || true)
    fi
  fi

  if [ -z "$BLOCK" ]; then
    echo "[$DIR_NAME] SKIP: could not extract block number from $ATTACK_FILE"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  # Get network from README.md
  TEST_DIR=$(dirname "$ATTACK_FILE")
  README="$TEST_DIR/README.md"
  NETWORK=""
  if [ -f "$README" ]; then
    # Extract first network from the list (handles [ethereum, moonbeam] → ethereum)
    NETWORK=$(grep 'network:' "$README" | sed 's/.*\[//;s/\].*//;s/,.*//;s/"//g' | xargs || true)
  fi

  if [ -z "$NETWORK" ]; then
    echo "[$DIR_NAME] SKIP: no network found in $README"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  RPC_URL=$(get_rpc_for_network "$NETWORK")
  if [ -z "$RPC_URL" ]; then
    echo "[$DIR_NAME] SKIP: no RPC URL for network '$NETWORK'"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  echo ""
  echo "=============================================="
  echo "[$DIR_NAME] Contract: $CONTRACT | Block: $BLOCK | Network: $NETWORK"
  echo "=============================================="

  if bash "$SCRIPT_DIR/cache_warm.sh" "$RPC_URL" "$BLOCK" "$CONTRACT"; then
    SUCCEEDED=$((SUCCEEDED + 1))
    echo "[$DIR_NAME] OK"
  else
    FAILED=$((FAILED + 1))
    FAILURES="$FAILURES  - $DIR_NAME ($CONTRACT at block $BLOCK on $NETWORK)\n"
    echo "[$DIR_NAME] FAILED (continuing...)"
  fi
done

echo ""
echo "=============================================="
echo "Summary: $SUCCEEDED succeeded, $FAILED failed, $SKIPPED skipped"
if [ -n "$FAILURES" ]; then
  echo ""
  echo "Failures:"
  printf "$FAILURES"
fi
echo "=============================================="
