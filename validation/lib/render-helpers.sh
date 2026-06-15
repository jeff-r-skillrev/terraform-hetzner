#!/bin/bash
# =============================================================================
# validation/lib/render-helpers.sh
#
# Shared helper functions for validation tests that render terraform templates
# with dummy values (mimicking what terraform's templatefile() does).
# =============================================================================

# Render provision-wireguard.sh.tftpl with dummy terraform values.
# Arguments:
#   $1 = output file path
#   $2 = bcrypt hash (default: dummy bcrypt containing $ chars)
#   $3 = WG_PORT (default: 51820)
render_wireguard_script() {
  local out="$1"
  local hash="${2:-\$2b\$12\$dummy.hash.value.here.aaaaaaaaaaaaaaaaaaa}"
  local port="${3:-51820}"

  sed -e "s|\${wg_server_port}|$port|g" \
      -e "s|\${wg_admin_password_hash}|$hash|g" \
      "$SCRIPTS_DIR/provision-wireguard.sh.tftpl" > "$out"
}
