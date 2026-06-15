#!/bin/bash
# Validate cloud-init YAML syntax without installing dependencies globally

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Create and use a temporary venv
VENV="$SCRIPT_DIR/.venv"
if [ ! -d "$VENV" ]; then
    python3 -m venv "$VENV"
fi
source "$VENV/bin/activate"

# Install dependencies
pip install -q -r "$SCRIPT_DIR/requirements.txt"

# Run the validation
export TEMPLATE_PATH="$REPO_ROOT/hcloud-terraform/infra/cloud-init.yaml.tftpl"

python3 << 'PYEOF'
import re
import yaml
import sys
import os

# Read the template
template_path = os.environ.get('TEMPLATE_PATH')
with open(template_path, 'r') as f:
    template = f.read()

# Replace Terraform template variables with dummy values for testing
test_values = {
    'wg_server_port': '51820',
    'wg_admin_password_hash': '$2b$12$dummy.hash.value.here.aaaaaaaaaaaaaaaaaaa',
}

cloud_init = template
for key, value in test_values.items():
    cloud_init = cloud_init.replace('${' + key + '}', value)

# Try to parse as YAML
try:
    result = yaml.safe_load(cloud_init)
    print("✓ Cloud-init YAML is syntactically valid")

    # Basic sanity checks
    if not isinstance(result, dict):
        print("✗ Cloud-init must be a dict at root level")
        sys.exit(1)

    if 'write_files' not in result:
        print("✗ Missing 'write_files' section")
        sys.exit(1)

    print(f"✓ Found {len(result.get('write_files', []))} files to write")

    # Check that provision scripts exist
    files = {f['path']: f for f in result.get('write_files', [])}
    if '/root/provision-wireguard.sh' not in files:
        print("✗ Missing /root/provision-wireguard.sh")
        sys.exit(1)
    if '/root/provision-shell.sh' not in files:
        print("✗ Missing /root/provision-shell.sh")
        sys.exit(1)

    print("✓ All required scripts present")

    sys.exit(0)
except yaml.YAMLError as e:
    print(f"✗ Cloud-init YAML error:\n{e}")
    sys.exit(1)
PYEOF

deactivate
