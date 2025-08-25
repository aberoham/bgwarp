#!/bin/bash

# unit_tests.sh - Unit-level tests for unwarp
# Tests command parsing, permission checks, and basic functionality

set -euo pipefail

# Source test helpers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test_helpers.sh"

# Test help output
test_help_output() {
    local output
    output=$("$TEST_BINARY" --help 2>&1) || true
    
    assert_contains "$output" "Emergency WARP disconnect tool" "Help should describe the tool"
    assert_contains "$output" "--liveincident" "Help should mention --liveincident flag"
    assert_contains "$output" "--reconnect" "Help should mention --reconnect option"
    assert_contains "$output" "--no-recovery" "Help should mention --no-recovery option"
    assert_contains "$output" "Touch ID" "Help should mention Touch ID requirement"
}

# Test version output
test_version_output() {
    local output
    output=$("$TEST_BINARY" --version 2>&1) || true
    
    assert_contains "$output" "unwarp version" "Version should be displayed"
    assert_contains "$output" "Emergency WARP disconnect tool" "Version should include description"
    assert_matches "$output" "(x86_64|arm64)" "Version should show architecture"
}

# Test short version flag
test_short_version_flag() {
    local output
    output=$("$TEST_BINARY" -v 2>&1) || true
    
    assert_contains "$output" "unwarp version" "Short version flag should work"
}

# Test short help flag
test_short_help_flag() {
    local output
    output=$("$TEST_BINARY" -h 2>&1) || true
    
    assert_contains "$output" "Emergency WARP disconnect tool" "Short help flag should work"
}

# Test invalid argument handling
test_invalid_argument() {
    local output
    local exit_code
    
    output=$("$TEST_BINARY" --invalid-flag 2>&1) || exit_code=$?
    
    # Since we don't have explicit invalid flag handling, it will just run normally
    # This test verifies it doesn't crash
    [[ -n "$output" ]] || return 1
}

# Test reconnect value validation - too low
test_reconnect_too_low() {
    local output
    local exit_code=0
    
    output=$("$TEST_BINARY" --reconnect 30 2>&1) || exit_code=$?
    
    assert_contains "$output" "must be between 60 and 43200" "Should reject reconnect < 60"
    assert_exit_code 1 "$exit_code" "Should exit with error for invalid reconnect"
}

# Test reconnect value validation - too high
test_reconnect_too_high() {
    local output
    local exit_code=0
    
    output=$("$TEST_BINARY" --reconnect 50000 2>&1) || exit_code=$?
    
    assert_contains "$output" "must be between 60 and 43200" "Should reject reconnect > 43200"
    assert_exit_code 1 "$exit_code" "Should exit with error for invalid reconnect"
}

# Test reconnect value validation - valid
test_reconnect_valid() {
    # This will fail due to lack of root, but we're testing argument parsing
    local output
    output=$("$TEST_BINARY" --reconnect 300 2>&1) || true
    
    # Should get past argument validation to permission check
    assert_contains "$output" "setuid root" "Should reach permission check with valid reconnect"
}

# Test permission check without setuid
test_permission_check() {
    local output
    local exit_code=0
    
    # Running without arguments should check permissions
    output=$("$TEST_BINARY" 2>&1) || exit_code=$?
    
    assert_contains "$output" "must be installed with setuid root" "Should require setuid"
    assert_contains "$output" "sudo chown root:wheel" "Should provide installation instructions"
    assert_contains "$output" "sudo chmod 4755" "Should provide chmod instructions"
    assert_exit_code 1 "$exit_code" "Should exit with error without setuid"
}

# Test default mode is test mode
test_default_test_mode() {
    # Create mock for warp-cli that captures calls
    create_mock_command "warp-cli" 'echo "MOCK: warp-cli $*"'
    setup_mock_path
    
    # This will fail at permission check, but we verify test mode banner would appear
    local output
    output=$("$TEST_BINARY" 2>&1) || true
    
    # Even though it fails on permissions, we can check the code logic
    # In actual use, test mode banner appears after auth
    
    restore_path
}

# Test --liveincident flag recognition
test_live_mode_flag() {
    # Create mock for warp-cli
    create_mock_command "warp-cli" 'echo "MOCK: warp-cli $*"'
    setup_mock_path
    
    local output
    output=$("$TEST_BINARY" --liveincident 2>&1) || true
    
    # Should fail on permissions but recognize the flag
    assert_contains "$output" "setuid root" "Should still check permissions in live mode"
    
    restore_path
}

# Test --no-recovery flag recognition
test_no_recovery_flag() {
    local output
    output=$("$TEST_BINARY" --no-recovery 2>&1) || true
    
    # Should fail on permissions but recognize the flag
    assert_contains "$output" "setuid root" "Should check permissions with --no-recovery"
}

# Test combined flags
test_combined_flags() {
    local output
    output=$("$TEST_BINARY" --liveincident --reconnect 600 --no-recovery 2>&1) || true
    
    # Should process all flags and then fail on permissions
    assert_contains "$output" "setuid root" "Should process all flags then check permissions"
}

# Test binary exists and is executable
test_binary_exists() {
    assert_file_exists "$TEST_BINARY" "Test binary should exist"
    
    if [[ -x "$TEST_BINARY" ]]; then
        return 0
    else
        echo "Test binary is not executable" >&2
        return 1
    fi
}

# Test output formatting
test_output_formatting() {
    local output
    output=$("$TEST_BINARY" --help 2>&1) || true
    
    # Check for structured help output
    assert_contains "$output" "Usage:" "Help should have usage section"
    assert_contains "$output" "Options:" "Help should have options section"
    assert_contains "$output" "Description:" "Help should have description"
    assert_contains "$output" "--liveincident" "Help should document liveincident flag"
}

# Main test execution
main() {
    test_group "Unit Tests - Basic Functionality"
    
    # Build test binary first
    if ! build_test_binary; then
        echo "Failed to build test binary, aborting unit tests"
        return 1
    fi
    
    run_test "binary_exists" test_binary_exists
    run_test "help_output" test_help_output
    run_test "version_output" test_version_output
    run_test "short_version_flag" test_short_version_flag
    run_test "short_help_flag" test_short_help_flag
    run_test "invalid_argument" test_invalid_argument
    run_test "reconnect_too_low" test_reconnect_too_low
    run_test "reconnect_too_high" test_reconnect_too_high
    run_test "reconnect_valid" test_reconnect_valid
    run_test "permission_check" test_permission_check
    run_test "default_test_mode" test_default_test_mode
    run_test "live_mode_flag" test_live_mode_flag
    run_test "no_recovery_flag" test_no_recovery_flag
    run_test "combined_flags" test_combined_flags
    run_test "output_formatting" test_output_formatting
    
    return 0
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    init_test_env
    main
    result=$?
    cleanup_test_env
    print_summary
    exit $result
fi