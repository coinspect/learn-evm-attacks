#!/usr/bin/env bash
set -euo pipefail

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

printf "\n▶ Running exploit: %s\n\n" "$LEARN_ATTACK_CONTRACT"
forge test --match-contract "$LEARN_ATTACK_CONTRACT" -vvv

echo
echo "✅ Done. Opening interactive shell..."
exec bash -l