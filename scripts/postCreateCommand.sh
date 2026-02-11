#!/usr/bin/env bash
set -euo pipefail

# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
export PATH="$HOME/.foundry/bin:$PATH"

# Update to latest toolchain
foundryup

# Install forge dependencies (git submodules)
forge install

# Restore the pre-warmed Foundry RPC cache
if [ -d "foundry_rpc_cache" ]; then
  mkdir -p "$HOME/.foundry/cache"
  cp -r foundry_rpc_cache/* "$HOME/.foundry/cache/"
  echo "Foundry RPC cache restored."
else
  echo "WARNING: foundry_rpc_cache/ not found — attacks will need a live RPC."
fi
