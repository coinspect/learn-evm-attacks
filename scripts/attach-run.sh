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

# Prompt for RPC_URL if missing, with feedback + persistence
if [[ -z "${RPC_URL:-}" ]]; then
  echo
  echo "No RPC_URL found."
  echo "You need an HTTPS RPC endpoint for the correct chain (e.g., Ethereum Mainnet or Sepolia)."
  echo "Get one by creating a free project at providers like:"
  echo "  • Alchemy  • Infura  • Ankr  • QuickNode  • Cloudflare/LlamaNodes"
  echo "Then copy the HTTPS URL for your network (e.g., https://eth-sepolia.g.alchemy.com/v2/<key>)."
  echo

  while true; do
    read -r -p "Enter RPC_URL: " RPC_URL_INPUT
    if [[ -z "$RPC_URL_INPUT" ]]; then
      echo "Empty. Try again."; continue
    fi
    if [[ ! "$RPC_URL_INPUT" =~ ^https?:// ]]; then
      echo "Warning: value does not look like an http(s) URL"
    fi
    
    # Export for this session and persist for future shells
    export RPC_URL="$RPC_URL_INPUT"
    sed -i '/^export RPC_URL=/d' "$HOME/.bashrc"
    printf 'export RPC_URL="%s"\n' "$RPC_URL_INPUT" >> "$HOME/.bashrc"
    echo "RPC_URL saved."
    break
  done
else
  echo "Using saved RPC_URL (…${RPC_URL: -6})"
fi

ATTACK_FILE_PATH=$(grep -rl "contract ${LEARN_ATTACK_CONTRACT}\b" ./test | head -n 1)

if [ -n "$ATTACK_FILE_PATH" ]; then
    TEST_DIR=$(dirname "$ATTACK_FILE_PATH")
    README_PATH="${TEST_DIR}/README.md"
    if [ -f "$README_PATH" ]; then
        if grep 'network:' "$README_PATH" | grep -qv 'ethereum'; then
            EVM_VERSION="london"
        else
            ATTACK_BLOCK=$(grep -A 2 'attack_block:' "$README_PATH" | grep -o '[0-9]\+' | head -n 1 || true)
            ATTACK_BLOCK=${ATTACK_BLOCK:-0}
            if [ -n "$ATTACK_BLOCK" ]; then
                if (( ATTACK_BLOCK < LONDON_BLOCK )); then EVM_VERSION="berlin";
                elif (( ATTACK_BLOCK < PARIS_BLOCK )); then EVM_VERSION="london";
                elif (( ATTACK_BLOCK < SHANGHAI_BLOCK )); then EVM_VERSION="paris";
                elif (( ATTACK_BLOCK < CANCUN_BLOCK )); then EVM_VERSION="shanghai";
                elif (( ATTACK_BLOCK < PETRA_BLOCK )); then EVM_VERSION="cancun";
                else EVM_VERSION="prague";fi;
                EVM_VERSION_FLAG="--evm-version $EVM_VERSION"
                echo "Using EVM Version: $EVM_VERSION"
            fi
        fi
    fi
fi

printf "\n▶ Running exploit: %s\n\n" "$LEARN_ATTACK_CONTRACT"
forge test --match-contract "$LEARN_ATTACK_CONTRACT" -vvv --evm-version "$EVM_VERSION"
echo
echo "✅ Done. Opening interactive shell..."
exec bash -l