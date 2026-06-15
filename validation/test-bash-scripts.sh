#!/bin/bash
# Test bash scripts in cloud-init template — syntax check + expansion validation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
SCRIPTS_DIR="$REPO_ROOT/hcloud-terraform/infra/scripts"

source "$SCRIPT_DIR/lib/render-helpers.sh"

echo "=== Testing bash scripts in cloud-init template ==="
echo

# Create temp directory for rendered scripts
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# ── Test provision-wireguard.sh ────────────────────────────────────────────
echo ">>> Testing provision-wireguard.sh..."

# Render with dummy terraform values
render_wireguard_script "$TMPDIR/provision-wireguard.sh" \
    '$2b$12$dummy.hash.value.here.aaaaaaaaaaaaaaaaaaa' \
    '51820'

# Bash syntax check
if bash -n "$TMPDIR/provision-wireguard.sh" 2>/dev/null; then
  echo "✓ Syntax OK"
else
  echo "✗ Syntax error in provision-wireguard.sh"
  exit 1
fi

# Shellcheck (if available, non-fatal if absent)
if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck -S warning "$TMPDIR/provision-wireguard.sh" 2>&1 | grep -qv "^$"; then
    # shellcheck found warnings/errors but we only warn, not fail
    echo "⚠ Shellcheck warnings (non-fatal):"
    shellcheck -S warning "$TMPDIR/provision-wireguard.sh" || true
  else
    echo "✓ Shellcheck passed"
  fi
fi

# ── Test provision-shell.sh ────────────────────────────────────────────────
echo ">>> Testing provision-shell.sh..."

# No substitution needed — it's pure bash
if bash -n "$SCRIPTS_DIR/provision-shell.sh" 2>/dev/null; then
  echo "✓ Syntax OK"
else
  echo "✗ Syntax error in provision-shell.sh"
  exit 1
fi

# Shellcheck (if available, non-fatal if absent)
if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck -S warning "$SCRIPTS_DIR/provision-shell.sh" 2>&1 | grep -qv "^$"; then
    echo "⚠ Shellcheck warnings (non-fatal):"
    shellcheck -S warning "$SCRIPTS_DIR/provision-shell.sh" || true
  else
    echo "✓ Shellcheck passed"
  fi
fi

# ── Regression checks ──────────────────────────────────────────────────────
echo ">>> Regression checks..."

# Ensure the unquoted CONFEOF heredoc is still present and unquoted
if grep -q "cat > admin/wg0.conf << CONFEOF" "$SCRIPTS_DIR/provision-wireguard.sh.tftpl"; then
  echo "✓ Unquoted CONFEOF heredoc present"
else
  echo "✗ CONFEOF heredoc is missing or quoted"
  exit 1
fi

# Ensure no dangerous $$ escaping was reintroduced
if grep -E '\$\$ADMIN_PRIVKEY|\$\$SERVER_PUBKEY|\$\$SERVER_IP' "$SCRIPTS_DIR/provision-wireguard.sh.tftpl" >/dev/null; then
  echo "✗ Dangerous \$\$ escaping detected (would break bash expansion)"
  exit 1
else
  echo "✓ No dangerous \$\$ escaping"
fi

echo
echo "=== All tests passed ==="
