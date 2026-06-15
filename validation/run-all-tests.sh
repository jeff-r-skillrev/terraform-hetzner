#!/bin/bash
# Master validation test runner
# Runs all validation tests to ensure cloud-init correctness

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

tests=(
    "test-cloud-init.sh"
    "test-env-generation.sh"
    "test-terraform-render.sh"
    "test-bash-scripts.sh"
)

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Hetzner Terraform Validation Test Suite                  ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

failed_tests=()
passed_tests=()

for test in "${tests[@]}"; do
    test_path="$SCRIPT_DIR/$test"
    if [ ! -f "$test_path" ]; then
        echo "⚠ SKIP: $test (not found)"
        continue
    fi

    echo "────────────────────────────────────────────────────────────"
    echo "Running: $test"
    echo "────────────────────────────────────────────────────────────"
    echo ""

    if bash "$test_path"; then
        passed_tests+=("$test")
        echo ""
    else
        failed_tests+=("$test")
        echo ""
        echo "✗ FAILED: $test"
        echo ""
    fi
done

echo "════════════════════════════════════════════════════════════"
echo "Test Results"
echo "════════════════════════════════════════════════════════════"
echo "Passed: ${#passed_tests[@]} tests"
for test in "${passed_tests[@]}"; do
    echo "  ✓ $test"
done

if [ ${#failed_tests[@]} -gt 0 ]; then
    echo ""
    echo "Failed: ${#failed_tests[@]} tests"
    for test in "${failed_tests[@]}"; do
        echo "  ✗ $test"
    done
    echo ""
    exit 1
else
    echo ""
    echo "✓ All validation tests passed!"
    exit 0
fi
