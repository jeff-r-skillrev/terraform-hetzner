#!/bin/bash
# Test .env file generation from provision-wireguard.sh
# Validates that password hashes and variables are handled correctly

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
SCRIPTS_DIR="$REPO_ROOT/hcloud-terraform/infra/scripts"

source "$SCRIPT_DIR/lib/render-helpers.sh"

echo "Testing .env file generation from provision-wireguard.sh"
echo "=============================================================="

# Create test environment
TEST_DIR=$(mktemp -d)
trap "rm -rf $TEST_DIR" EXIT

cd "$TEST_DIR"
mkdir -p wireguard/{config,admin,logs}
export WG_DIR="$TEST_DIR/wireguard"

# Test cases with different bcrypt hashes
test_hashes=(
    '$2b$12$Y.GVNUEbx6FjebdOvfFQZOPqgsGB8zE3m9IieyBEXVDMp4A0zDUJq'
    '$2b$12$2u3R9K7x4L5M6N7O8P9Q0a1b2c3d4e5f6g7h8i9j0k1l2m3n4o'
)

test_count=0
pass_count=0

for password_hash in "${test_hashes[@]}"; do
    test_count=$((test_count + 1))

    echo ""
    echo "Test $test_count: Password hash preservation"
    echo "  Hash: $password_hash"

    # Simulate runtime variables
    export SERVER_IP="192.0.2.1"
    export WG_PORT="51820"
    export wg_admin_password_hash="$password_hash"

    # Render the script with terraform variables
    SCRIPT_RENDERED="$TEST_DIR/provision-wireguard-$test_count.sh"
    render_wireguard_script "$SCRIPT_RENDERED" "$password_hash" "51820"

    # Source the script (guard at bottom prevents main from running)
    source "$SCRIPT_RENDERED"

    # Override WG_DIR to use our test directory (script sets it to /mnt/persist/wireguard)
    export WG_DIR="$TEST_DIR/wireguard"

    # Mock sed -i to handle both macOS (BSD sed) and Linux (GNU sed)
    # The script uses sed -i which requires different syntax on different systems
    sed() {
      # Check if this is a sed -i command
      local args=("$@")
      local new_args=()
      local i=0

      while [ $i -lt ${#args[@]} ]; do
        if [[ "${args[$i]}" == "-i" ]]; then
          # Found -i flag; add it with empty string for macOS
          new_args+=("-i" "")
          i=$((i + 1))
        else
          # Regular argument
          new_args+=("${args[$i]}")
          i=$((i + 1))
        fi
      done

      # Call sed with the modified arguments
      command sed "${new_args[@]}"
    }
    export -f sed

    # Run write_env_file in the test environment
    cd "$WG_DIR"
    write_env_file

    env_file="$WG_DIR/.env"

    # Validate WG_HOST
    if grep -q "^WG_HOST=$SERVER_IP\$" "$env_file"; then
        echo "  ✓ WG_HOST correctly set"
    else
        echo "  ✗ WG_HOST not correctly set"
        cat "$env_file"
        continue
    fi

    # Validate WG_PORT
    if grep -q "^WG_PORT=$WG_PORT\$" "$env_file"; then
        echo "  ✓ WG_PORT correctly set"
    else
        echo "  ✗ WG_PORT not correctly set"
        cat "$env_file"
        continue
    fi

    # Critical test: PASSWORD_HASH must be preserved exactly as-is
    # This catches the regression where $Y, $2, etc. were being stripped by envsubst
    if grep -q "^PASSWORD_HASH=$password_hash\$" "$env_file"; then
        echo "  ✓ PASSWORD_HASH preserved exactly"
        pass_count=$((pass_count + 1))
    else
        echo "  ✗ PASSWORD_HASH was corrupted!"
        actual=$(grep "^PASSWORD_HASH=" "$env_file" || echo "NOT FOUND")
        echo "    Expected: PASSWORD_HASH=$password_hash"
        echo "    Got:      $actual"
        echo ""
        echo "  Full .env file:"
        cat "$env_file"
    fi

    # Clean up for next iteration
    rm -f "$env_file"
done

echo ""
echo "=============================================================="
echo "Results: $pass_count/$test_count tests passed"

if [ $pass_count -eq $test_count ]; then
    echo "✓ All .env generation tests passed"
    exit 0
else
    echo "✗ Some tests failed"
    exit 1
fi
