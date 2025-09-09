#!/bin/bash

# Script to create devcontainer subdirectories for each attack directory
# Each devcontainer will be in .devcontainer/<attack_name>/

set -e

# Script is in ./scripts/, project root is one level up
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "Using project directory: $PROJECT_DIR"
DEVCONTAINER_BASE_DIR="${PROJECT_DIR}/.devcontainer"

# Ensure .devcontainer directory exists
mkdir -p "${DEVCONTAINER_BASE_DIR}"

# Get list of attack directories from test/{category}/{attack_name} structure
# Skip utils, modules, and interfaces subdirectories
attack_dirs=$(find "${PROJECT_DIR}/test" -maxdepth 2 -type d | grep -v "/test$" | grep -v "/utils" | grep -v "/modules" | grep -v "/interfaces" | sed 's|.*/test/[^/]*/||' | grep -v "^$" | sort -u)

echo "Creating devcontainer subdirectories for attack directories..."

for attack_dir in ${attack_dirs}; do
    # Find the full path for this attack directory
    attack_full_path=$(find "${PROJECT_DIR}/test" -name "${attack_dir}" -type d | head -1)
    if [ -z "${attack_full_path}" ]; then
        echo "  Warning: Could not find directory for ${attack_dir}"
        continue
    fi
    
    # Skip if devcontainer subdir already exists
    if [ -d "${DEVCONTAINER_BASE_DIR}/${attack_dir}" ]; then
        echo "  Skipping ${attack_dir} - devcontainer subdir already exists"
        continue
    fi
    
    echo "  Creating devcontainer for: ${attack_dir}"
    
    # Try to find the README.md file for this attack
    readme_path="${attack_full_path}/README.md"
    
    # Extract contract name from reproduction_command
    contract_name=""
    if [ -f "${readme_path}" ]; then
        # Extract the contract name from "forge test --match-contract ContractName -vvv"
        contract_name=$(grep "reproduction_command:" "${readme_path}" | sed 's/.*--match-contract \([^ ]*\).*/\1/')
        if [ -z "${contract_name}" ]; then
            echo "    Warning: Could not extract contract name from ${readme_path}, using default"
            contract_name="Exploit_${attack_dir}"
        fi
    else
        echo "    Warning: README not found at ${readme_path}, using default contract name"
        contract_name="Exploit_${attack_dir}"
    fi
    
    echo "    Using contract name: ${contract_name}"
    
    # Find the main attack code file (.attack.sol or .report.sol)
    attack_code_file=""
    if [ -f "${attack_full_path}"/*.attack.sol ]; then
        attack_code_file=$(ls "${attack_full_path}"/*.attack.sol | head -1)
    elif [ -f "${attack_full_path}"/*.report.sol ]; then
        attack_code_file=$(ls "${attack_full_path}"/*.report.sol | head -1)
    fi
    
    if [ -n "${attack_code_file}" ]; then
        # Get relative path from project root
        relative_code_file="${attack_code_file#${PROJECT_DIR}/}"
        echo "    Found attack code file: ${relative_code_file}"
    else
        echo "    Warning: No .attack.sol or .report.sol file found in ${attack_full_path}"
        relative_code_file="${attack_full_path#${PROJECT_DIR}/}/README.md"
    fi
    
    # Create the devcontainer subdirectory
    mkdir -p "${DEVCONTAINER_BASE_DIR}/${attack_dir}"
    
    # Create devcontainer.json exactly like Cork_Finance template
    cat > "${DEVCONTAINER_BASE_DIR}/${attack_dir}/devcontainer.json" << EOF
{
  "name": "${attack_dir}",
  "image": "mcr.microsoft.com/devcontainers/base:ubuntu-22.04",
  "remoteEnv": {
    "LEARN_ATTACK_CONTRACT": "${contract_name}",
    "PATH": "\${containerEnv:PATH}:/home/vscode/.foundry/bin"
  },
  "customizations": {
    "codespaces": { "openFiles": ["${relative_code_file}"] }
  },
  "postCreateCommand": "bash scripts/postCreateCommand.sh",
  "postAttachCommand": "bash scripts/attach-run.sh",
}
EOF
done

echo "Done! Created devcontainer subdirectories for all attack directories."
echo "Each devcontainer is located at: .devcontainer/<attack_name>/"