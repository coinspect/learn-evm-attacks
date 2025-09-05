#!/usr/bin/env bash
set -euo pipefail

# Install Foundry
curl -L https://foundry.paradigm.xyz | bash

export PATH="$HOME/.foundry/bin:$PATH"

# Update to latest toolchain
foundryup

# Install forge
forge install 