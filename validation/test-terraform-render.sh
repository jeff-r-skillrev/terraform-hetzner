#!/bin/bash
# Test terraform rendering — validate variable expansion in heredocs

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
SCRIPTS_DIR="$REPO_ROOT/hcloud-terraform/infra/scripts"

source "$SCRIPT_DIR/lib/render-helpers.sh"

echo "=== Testing terraform template rendering ==="
echo

# Create temp directory
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# Simulate terraform's template render with dummy vars
echo ">>> Simulating terraform template render..."
render_wireguard_script "$TMPDIR/provision-wireguard.sh" \
    '$2b$12$dummy.hash.value.here.aaaaaaaaaaaaaaaaaaa' \
    '51820'

# Validate basic render structure
echo ">>> Validating rendered template..."

if grep -q 'PASSWORD_HASH=\$2b\$12\$dummy' "$TMPDIR/provision-wireguard.sh"; then
  echo "✓ Terraform vars correctly substituted (password hash)"
else
  echo "✗ Terraform vars not substituted correctly"
  exit 1
fi

if grep -q 'export WG_PORT="51820"' "$TMPDIR/provision-wireguard.sh"; then
  echo "✓ Terraform vars correctly substituted (WG_PORT)"
else
  echo "✗ WG_PORT not substituted correctly"
  exit 1
fi

# ── Test actual function expansion ─────────────────────────────────────────
echo ">>> Testing admin config generation (with variable expansion)..."

# Create test environment with mocks
mkdir -p "$TMPDIR/test-admin"
cd "$TMPDIR/test-admin"
mkdir -p admin

# Source the script (guard prevents main from running)
source "$TMPDIR/provision-wireguard.sh"

# Mock the wg genkey function
wg() {
  if [[ "$1" == "genkey" ]]; then
    echo "AAAAAAAAABBBBBBBBCCCCCCCCDDDDDDDDEEEEEEEE="
  fi
}
export -f wg

# Mock cp and chmod to avoid writing to /root (doesn't exist in test environment)
cp() {
  # Only mock the /root/wireguard-admin.conf copy
  if [[ "$*" == */root/wireguard-admin.conf* ]]; then
    return 0
  fi
  # For other copies, use the real cp
  command cp "$@"
}
export -f cp

chmod() {
  # Only mock the /root/wireguard-admin.conf chmod
  if [[ "$*" == */root/wireguard-admin.conf* ]]; then
    return 0
  fi
  # For other chmod, use the real command
  command chmod "$@"
}
export -f chmod

# Set up runtime variables
export SERVER_IP="203.0.113.42"
export WG_PORT="51820"
SERVER_PUBKEY="Nm4bsQzK5mKp7L8M9N0O1P2Q3R4S5T6U7V8W9X0="

# Call the function
generate_admin_config "$SERVER_PUBKEY"

# Verify the output file has correct expansions
if grep -q "^PrivateKey = AAAAAAAAABBBBBBBBCCCCCCCCDDDDDDDDEEEEEEEE=\$" admin/wg0.conf; then
  echo "✓ PrivateKey expanded correctly"
else
  echo "✗ PrivateKey not expanded correctly"
  cat admin/wg0.conf
  exit 1
fi

if grep -q "^PublicKey = Nm4bsQzK5mKp7L8M9N0O1P2Q3R4S5T6U7V8W9X0=\$" admin/wg0.conf; then
  echo "✓ PublicKey expanded correctly"
else
  echo "✗ PublicKey not expanded correctly"
  cat admin/wg0.conf
  exit 1
fi

if grep -q "^Endpoint = 203.0.113.42:51820\$" admin/wg0.conf; then
  echo "✓ Endpoint (SERVER_IP:WG_PORT) expanded correctly"
else
  echo "✗ Endpoint not expanded correctly"
  cat admin/wg0.conf
  exit 1
fi

# ── Regression checks ──────────────────────────────────────────────────────
echo ">>> Regression checks..."

if grep -q "cat > admin/wg0.conf << CONFEOF" "$SCRIPTS_DIR/provision-wireguard.sh.tftpl"; then
  echo "✓ Unquoted CONFEOF heredoc (allows variable expansion)"
else
  echo "✗ CONFEOF heredoc is missing or quoted (would break expansion)"
  exit 1
fi

if grep -E '\$\$ADMIN_PRIVKEY|\$\$SERVER_PUBKEY|\$\$SERVER_IP' "$SCRIPTS_DIR/provision-wireguard.sh.tftpl" >/dev/null; then
  echo "✗ Dangerous \$\$ escaping detected (would break bash expansion)"
  exit 1
else
  echo "✓ No dangerous \$\$ escaping in expansion variables"
fi

echo
echo "=== Terraform template rendering is correct ==="
