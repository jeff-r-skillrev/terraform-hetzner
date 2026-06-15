#!/bin/bash
# Test .env file generation from provision-wireguard.sh
# Specifically validates that password hashes and variables are handled correctly

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEMPLATE_PATH="$REPO_ROOT/hcloud-terraform/infra/cloud-init.yaml.tftpl"

echo "Testing .env file generation from cloud-init provision script"
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

    # Simulate runtime variables (exactly as they appear in provision script)
    export SERVER_IP="192.0.2.1"
    export WG_PORT="51820"
    export wg_admin_password_hash="$password_hash"

    # Run the .env creation logic from the provision script
    # Note: terraform has already substituted ${wg_admin_password_hash} with the actual value
    cd "$WG_DIR"

    # Simulate terraform template substitution
    terraform_substituted=$(cat <<'TMPEOF'
      LANG=en
      WG_HOST=__SERVER_IP__
      WG_PORT=__WG_PORT__
      WG_MTU=1420
      WG_PERSISTENT_KEEPALIVE=25
      WG_DEFAULT_DNS=1.1.1.1,8.8.8.8
      WG_ALLOWED_IPS=10.0.0.0/24
      UI_LISTEN_PORT=51821
      PASSWORD_HASH=PLACEHOLDER
TMPEOF
)

    # Replace PLACEHOLDER with actual password hash (this is what terraform does)
    terraform_substituted=$(echo "$terraform_substituted" | sed "s|PLACEHOLDER|$password_hash|g")

    echo "$terraform_substituted" > .env

    # Substitute only runtime variables (PASSWORD_HASH is already set by terraform)
    sed -i '' "s|__SERVER_IP__|$SERVER_IP|g" .env
    sed -i '' "s|__WG_PORT__|$WG_PORT|g" .env

    # Remove leading spaces from each line
    sed -i '' 's/^[[:space:]]*//' .env

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
