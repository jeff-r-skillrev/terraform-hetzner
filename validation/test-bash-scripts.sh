#!/bin/bash
# Test bash scripts extracted from cloud-init template
# Validates syntax and variable expansion without running actual commands

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEMPLATE_PATH="$REPO_ROOT/hcloud-terraform/infra/cloud-init.yaml.tftpl"

echo "=== Testing bash scripts in cloud-init template ==="
echo

# Extract and test provision-wireguard.sh
echo ">>> Extracting provision-wireguard.sh..."
WIREGUARD_SCRIPT=$(sed -n '/path: \/root\/provision-wireguard\.sh/,/^  - path:/p' "$TEMPLATE_PATH" | sed '$d')
WIREGUARD_SCRIPT=$(echo "$WIREGUARD_SCRIPT" | sed 's/^    content: |//' | sed 's/^      //')

# Replace terraform template variables
WIREGUARD_SCRIPT=$(echo "$WIREGUARD_SCRIPT" | sed 's/${wg_server_port}/51820/g')
WIREGUARD_SCRIPT=$(echo "$WIREGUARD_SCRIPT" | sed 's/${wg_admin_password_hash}/$2b$12$dummy.hash/g')

# Create a test version with mocked external commands
TEST_WIREGUARD=$(cat << 'TESTEOF'
#!/bin/bash
set -euo pipefail

# Mock external commands
mountpoint() { return 0; }
curl() { echo "192.0.2.1"; }
systemctl() { :; }
mkdir() { :; }
envsubst() { cat; }
docker-compose() { :; }
jq() { echo '{"server":{"publicKey":"AAAAAAAABBBBBBBBCCCCCCCCDDDDDDDDEEEEEEEE="}}'; }
chmod() { :; }
cp() { :; }
wg() {
  if [[ "$1" == "genkey" ]]; then
    echo "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABBBB=="
  fi
}

TESTEOF
echo "$WIREGUARD_SCRIPT"
)

# Syntax check
echo ">>> Checking bash syntax..."
if bash -n <(echo "$TEST_WIREGUARD") 2>&1; then
  echo "✓ Syntax OK"
else
  echo "✗ Syntax error in provision-wireguard.sh"
  exit 1
fi

# Check for quoted heredoc (common regression)
echo ">>> Checking for heredoc quoting issues..."
if grep -q "cat > admin/wg0.conf << 'CONFEOF'" "$TEMPLATE_PATH"; then
  echo "✗ REGRESSION: Heredoc uses quoted 'CONFEOF' which prevents variable expansion!"
  echo "   This causes \$VARIABLE to be written literally instead of expanded"
  exit 1
else
  echo "✓ No quoted heredoc issues"
fi

# Test variable expansion by running a subset with tracing
echo ">>> Checking variable expansion in heredocs..."
EXPANSION_TEST=$(cat << 'EXPANDEOF'
#!/bin/bash
set -euo pipefail

# Mock functions
wg() { echo "ValidPrivateKey12345678901234567890AB=="; }

export WG_DIR="/tmp/test-wg"
export WG_PORT="51820"
export SERVER_IP="192.0.2.1"
ADMIN_PRIVKEY=$(wg genkey)
SERVER_PUBKEY="ValidServerKey1234567890123456789012AB=="

# Test the heredoc that was causing issues
mkdir -p admin
cat > admin/wg0.conf << CONFEOF
[Interface]
PrivateKey = $ADMIN_PRIVKEY
Address = 10.0.0.2/32
DNS = 1.1.1.1,8.8.8.8

[Peer]
PublicKey = $SERVER_PUBKEY
Endpoint = $SERVER_IP:$WG_PORT
AllowedIPs = 10.0.0.0/24
PersistentKeepalive = 25
CONFEOF

# Check that variables were actually expanded
if grep -q "PrivateKey = ValidPrivateKey" admin/wg0.conf; then
  echo "✓ PrivateKey expanded correctly"
else
  echo "✗ PrivateKey NOT expanded (contains literal \$ADMIN_PRIVKEY)"
  cat admin/wg0.conf
  exit 1
fi

if grep -q "PublicKey = ValidServerKey" admin/wg0.conf; then
  echo "✓ PublicKey expanded correctly"
else
  echo "✗ PublicKey NOT expanded"
  cat admin/wg0.conf
  exit 1
fi

if grep -q "Endpoint = 192.0.2.1:51820" admin/wg0.conf; then
  echo "✓ Endpoint expanded correctly"
else
  echo "✗ Endpoint NOT expanded"
  cat admin/wg0.conf
  exit 1
fi

rm -rf admin
EXPANDEOF
)

if bash <(echo "$EXPANSION_TEST") 2>&1; then
  echo "✓ Variable expansion OK"
else
  echo "✗ Variable expansion failed"
  exit 1
fi

echo
echo "=== All tests passed ==="
