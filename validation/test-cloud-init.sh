#!/bin/bash
# Validate cloud-init YAML syntax after rendering scripts via locals

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
SCRIPTS_DIR="$REPO_ROOT/hcloud-terraform/infra/scripts"
TEMPLATE_PATH="$REPO_ROOT/hcloud-terraform/infra/cloud-init.yaml.tftpl"

# Create and use a temporary venv
VENV="$SCRIPT_DIR/.venv"
if [ ! -d "$VENV" ]; then
    python3 -m venv "$VENV"
fi
source "$VENV/bin/activate"

# Install dependencies
pip install -q -r "$SCRIPT_DIR/requirements.txt"

# Render the three scripts with test values
source "$SCRIPT_DIR/lib/render-helpers.sh"

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# Render scripts (with dummy terraform values)
render_wireguard_script "$TMPDIR/provision-wireguard.sh" \
    '$2b$12$dummy.hash.value.here.aaaaaaaaaaaaaaaaaaa' \
    '51820'
cp "$SCRIPTS_DIR/provision-shell.sh" "$TMPDIR/provision-shell.sh"
cp "$SCRIPTS_DIR/sshd-hardening.conf" "$TMPDIR/sshd-hardening.conf"

# Export variables for Python subprocess
export TMPDIR
export TEMPLATE_PATH

python3 << 'PYEOF'
import re
import yaml
import sys
import os

template_path = os.environ.get('TEMPLATE_PATH')
tmpdir = os.environ.get('TMPDIR')

if not tmpdir:
    print("ERROR: TMPDIR not set", file=sys.stderr)
    sys.exit(1)

# Read the rendered scripts
with open(f'{tmpdir}/provision-wireguard.sh', 'r') as f:
    provision_wireguard_script = f.read()

with open(f'{tmpdir}/provision-shell.sh', 'r') as f:
    provision_shell_script = f.read()

with open(f'{tmpdir}/sshd-hardening.conf', 'r') as f:
    sshd_hardening_conf = f.read()

# Read the template
with open(template_path, 'r') as f:
    template = f.read()

# Apply 6-space indent to each script (all lines except first, per terraform's indent())
def indent_string(s, spaces=6):
    lines = s.split('\n')
    # First line is not indented, rest are
    if len(lines) > 1:
        return lines[0] + '\n' + '\n'.join(' ' * spaces + line if line.strip() else '' for line in lines[1:])
    return lines[0] if lines else ''

provision_wireguard_indented = indent_string(provision_wireguard_script, 6)
provision_shell_indented = indent_string(provision_shell_script, 6)
sshd_hardening_indented = indent_string(sshd_hardening_conf, 6)

# Substitute into template
cloud_init = template
cloud_init = cloud_init.replace('${indent(6, provision_wireguard_script)}', provision_wireguard_indented)
cloud_init = cloud_init.replace('${indent(6, provision_shell_script)}', provision_shell_indented)
cloud_init = cloud_init.replace('${indent(6, sshd_hardening_conf)}', sshd_hardening_indented)
cloud_init = cloud_init.replace('${wg_server_port}', '51820')

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

    # Check that all three files are present
    files = {f['path']: f for f in result.get('write_files', [])}

    required_files = [
        '/etc/ssh/sshd_config.d/99-hardening.conf',
        '/root/provision-wireguard.sh',
        '/root/provision-shell.sh'
    ]

    for fpath in required_files:
        if fpath not in files:
            print(f"✗ Missing {fpath}")
            sys.exit(1)
        print(f"✓ Found {fpath}")

    print("✓ All required scripts present")

    sys.exit(0)
except yaml.YAMLError as e:
    print(f"✗ Cloud-init YAML error:\n{e}")
    sys.exit(1)
PYEOF

deactivate
