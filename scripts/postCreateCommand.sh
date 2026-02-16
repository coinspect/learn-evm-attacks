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
if [ -d "rpc_cache/foundry" ]; then
  mkdir -p "$HOME/.foundry/cache"
  cp -r rpc_cache/foundry/* "$HOME/.foundry/cache/"
  echo "Foundry RPC cache restored."
else
  echo "WARNING: rpc_cache/foundry/ not found — attacks will need a live RPC."
fi
