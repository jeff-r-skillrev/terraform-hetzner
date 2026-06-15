#!/bin/bash
# Shared regression checks for shell script validation

# Ensure the unquoted CONFEOF heredoc is still present and unquoted
# This prevents the regression where variable expansion was broken by quoting
check_confeof_unquoted() {
  local tftpl_file="$1"
  if grep -q "cat > admin/wg0.conf << CONFEOF" "$tftpl_file"; then
    return 0  # Pass
  else
    echo "✗ CONFEOF heredoc is missing or quoted"
    return 1
  fi
}

# Ensure no dangerous $$ escaping was reintroduced
# This prevents the regression where $$ADMIN_PRIVKEY caused PID substitution
check_no_dangerous_escaping() {
  local tftpl_file="$1"
  if grep -E '\$\$ADMIN_PRIVKEY|\$\$SERVER_PUBKEY|\$\$SERVER_IP' "$tftpl_file" >/dev/null; then
    echo "✗ Dangerous \$\$ escaping detected (would break bash expansion)"
    return 1
  else
    return 0  # Pass
  fi
}
