#!/bin/bash
# Test that terraform template will render cloud-init correctly
# Simulates what terraform will send to the server by replacing variables
#
# This catches regressions:
# 1. Quoted heredoc ('CONFEOF') that prevents variable expansion
# 2. Double-dollar escaping ($$) that becomes PID in bash
# 3. Missing variable references

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEMPLATE_PATH="$REPO_ROOT/hcloud-terraform/infra/cloud-init.yaml.tftpl"

echo "=== Testing terraform template rendering ==="
echo

echo ">>> Simulating terraform template render..."

# Read the template
RENDERED=$(cat "$TEMPLATE_PATH")

# Replace terraform variables with test values (simulating what terraform does)
RENDERED="${RENDERED//\${wg_server_port}/51820}"
RENDERED="${RENDERED//\${wg_admin_password_hash}/\$2b\$12\$test.hash.value.here.aaaa}"

# Save to temp file for testing
TEMP_FILE=$(mktemp)
trap "rm -f $TEMP_FILE" EXIT

echo "$RENDERED" > "$TEMP_FILE"

echo ">>> Validating rendered template..."

# Check for incorrect $$ escaping
# After terraform processes the file, we should NOT see $$ - only single $
if grep 'PrivateKey.*\$\$ADMIN_PRIVKEY\|PublicKey.*\$\$SERVER_PUBKEY\|Endpoint.*\$\$SERVER_IP' "$TEMP_FILE" >/dev/null; then
  echo "✗ REGRESSION: Template has \$\$ escaping!"
  echo "   When this runs on the server, bash will interpret \$\$ as the PID"
  echo "   Result: PrivateKey = 12345ADMIN_PRIVKEY (where 12345 is PID)"
  grep -E 'PrivateKey|PublicKey|Endpoint' "$TEMP_FILE" | head -3
  exit 1
else
  echo "✓ No \$\$ escaping in template"
fi

# Check for quoted heredoc (prevents variable expansion)
if grep -q "cat > admin/wg0.conf << 'CONFEOF'" "$TEMP_FILE"; then
  echo "✗ REGRESSION: Heredoc uses quoted 'CONFEOF'"
  echo "   This prevents bash variable expansion"
  echo "   Result: PrivateKey = \$ADMIN_PRIVKEY (literal)"
  exit 1
else
  echo "✓ Heredoc is unquoted (allows variable expansion)"
fi

# The rendered output should have single $ for bash variable expansion
if grep -q 'PrivateKey = $ADMIN_PRIVKEY' "$TEMP_FILE"; then
  echo "✓ PrivateKey has \$ADMIN_PRIVKEY for bash expansion"
else
  echo "✗ PrivateKey line incorrect in template"
  grep "PrivateKey" "$TEMP_FILE" || echo "   (not found)"
  exit 1
fi

if grep -q 'PublicKey = $SERVER_PUBKEY' "$TEMP_FILE"; then
  echo "✓ PublicKey has \$SERVER_PUBKEY for bash expansion"
else
  echo "✗ PublicKey line incorrect in template"
  exit 1
fi

if grep -q 'Endpoint = $SERVER_IP:$WG_PORT' "$TEMP_FILE"; then
  echo "✓ Endpoint has \$SERVER_IP:\$WG_PORT for bash expansion"
else
  echo "✗ Endpoint line incorrect in template"
  exit 1
fi

echo
echo "=== Terraform template rendering is correct ==="
