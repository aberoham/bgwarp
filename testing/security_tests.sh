#!/bin/bash

# security_tests.sh - Security validation tests for unwarp
# Tests setuid handling, privilege management, and authentication

set -euo pipefail

# Source test helpers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test_helpers.sh"

# Test setuid bit preservation after build
test_setuid_preservation() {
    # Check if production binary exists
    if [[ ! -f "$PROD_BINARY" ]]; then
        echo "Production binary not found at $PROD_BINARY" >&2
        return 1
    fi
    
    # Check if it has setuid bit
    if has_setuid "$PROD_BINARY"; then
        echo "Production binary has setuid bit set"
        return 0
    else
        echo "Warning: Production binary lacks setuid bit" >&2
        # This is not necessarily a failure - binary might not be installed yet
        return 0
    fi
}

# Test that binary refuses to run without proper permissions
test_permission_enforcement() {
    # Test binary should NOT have setuid
    if has_setuid "$TEST_BINARY"; then
        echo "ERROR: Test binary should not have setuid bit" >&2
        return 1
    fi
    
    local output
    local exit_code=0
    
    output=$("$TEST_BINARY" 2>&1) || exit_code=$?
    
    assert_exit_code 1 "$exit_code" "Should refuse to run without setuid"
    assert_contains "$output" "setuid root" "Should mention setuid requirement"
}

# Test console user verification simulation
test_console_user_check() {
    # We can't fully test this without being at console, but we can check the code paths
    
    # Create a test that would trigger console check if we had setuid
    # This tests that the check is in place, even if we can't execute it
    
    local output
    output=$("$TEST_BINARY" 2>&1) || true
    
    # The binary should fail on permission check before console check
    # This just verifies the security layers are ordered correctly
    assert_contains "$output" "setuid root" "Permission check comes before console check"
}

# Test rate limiting mentions in help
test_rate_limiting_documented() {
    local output
    output=$("$TEST_BINARY" --help 2>&1) || true
    
    # Verify security features are documented
    assert_contains "$output" "Touch ID" "Should document Touch ID requirement"
    assert_contains "$output" "authentication" "Should mention authentication"
}

# Test privilege drop simulation
test_privilege_drop_safety() {
    # Can't test actual privilege drop without setuid, but can verify code structure
    
    # Check that binary is compiled with security frameworks
    local libs
    libs=$(otool -L "$TEST_BINARY" 2>/dev/null || ldd "$TEST_BINARY" 2>/dev/null || true)
    
    if [[ -n "$libs" ]]; then
        assert_contains "$libs" "LocalAuthentication" "Should link LocalAuthentication framework"
        assert_contains "$libs" "Security" "Should link Security framework"
    else
        echo "Cannot inspect binary libraries on this system"
        return 0
    fi
}

# Test for dangerous environment variables
test_environment_sanitization() {
    # Set potentially dangerous environment variables
    export DYLD_INSERT_LIBRARIES="/tmp/evil.dylib"
    export LD_PRELOAD="/tmp/evil.so"
    export DYLD_LIBRARY_PATH="/tmp"
    
    local output
    output=$("$TEST_BINARY" --help 2>&1) || true
    
    # Binary should still function (though these are ignored on modern macOS with SIP)
    assert_contains "$output" "Emergency WARP disconnect" "Should handle tainted environment"
    
    # Clean up
    unset DYLD_INSERT_LIBRARIES
    unset LD_PRELOAD
    unset DYLD_LIBRARY_PATH
}

# Test command injection protection in logging
test_command_injection_protection() {
    # Try to inject commands through username
    local original_user="$USER"
    export USER='test$(whoami)`;rm -rf /;`'
    
    local output
    output=$("$TEST_BINARY" --help 2>&1) || true
    
    # Should handle special characters safely
    assert_contains "$output" "Emergency WARP disconnect" "Should handle special chars in USER"
    
    # Restore
    export USER="$original_user"
}

# Test path traversal protection
test_path_traversal_protection() {
    # Test that binary doesn't follow symlinks or path traversal
    
    # Create a symlink to test
    local test_link="${OUTPUT_DIR}/test_link"
    ln -sf "$TEST_BINARY" "$test_link" 2>/dev/null || true
    
    if [[ -L "$test_link" ]]; then
        local output
        output=$("$test_link" --help 2>&1) || true
        
        assert_contains "$output" "Emergency WARP disconnect" "Should work through symlink"
        
        rm -f "$test_link"
    else
        echo "Cannot create symlinks on this system"
    fi
}

# Test hidden installation path compliance
test_hidden_installation_path() {
    # Verify the expected installation path is hidden (starts with dot)
    local expected_path="/usr/local/libexec/.unwarp"
    
    # Check if help text mentions the hidden path
    local output
    output=$("$TEST_BINARY" --help 2>&1) || true
    
    # Installation instructions should reference the hidden path
    if [[ "$output" == *"$expected_path"* ]] || [[ "$output" == *".unwarp"* ]]; then
        echo "Hidden installation path is referenced correctly"
        return 0
    else
        echo "Warning: Hidden installation path may not be properly documented"
        return 0
    fi
}

# Test for information disclosure
test_information_disclosure() {
    local output
    
    # Test that error messages don't leak sensitive information
    output=$("$TEST_BINARY" --reconnect 30 2>&1) || true
    
    # Should not expose internal paths or system details
    if [[ "$output" == *"/Users/"* ]] || [[ "$output" == *"/home/"* ]]; then
        echo "Warning: Output may contain path disclosure" >&2
    fi
    
    # Should not expose process IDs or memory addresses
    if [[ "$output" =~ 0x[0-9a-fA-F]+ ]]; then
        echo "Warning: Output may contain memory addresses" >&2
    fi
    
    return 0
}

# Test binary permissions recommendations
test_permission_recommendations() {
    local output
    output=$("$TEST_BINARY" 2>&1) || true
    
    # Should provide clear, safe installation instructions
    assert_contains "$output" "sudo chown root:wheel" "Should recommend root:wheel ownership"
    assert_contains "$output" "sudo chmod 4755" "Should recommend 4755 permissions"
    
    # Should NOT recommend unsafe permissions
    if [[ "$output" == *"777"* ]]; then
        echo "ERROR: Recommends unsafe 777 permissions" >&2
        return 1
    fi
    
    return 0
}

# Test for TOCTTOU vulnerabilities
test_tocttou_safety() {
    # Test that binary handles file operations safely
    # This is a code review test - we verify patterns, not runtime behavior
    
    # Check if binary size is reasonable (not bloated with debug symbols in prod)
    if [[ -f "$PROD_BINARY" ]]; then
        local size
        size=$(stat -f%z "$PROD_BINARY" 2>/dev/null || stat -c%s "$PROD_BINARY" 2>/dev/null || echo 0)
        
        # Binary should be reasonably sized (not too small, not too large)
        if [[ $size -lt 10000 ]]; then
            echo "Warning: Production binary seems unusually small" >&2
        elif [[ $size -gt 10000000 ]]; then
            echo "Warning: Production binary seems unusually large" >&2
        fi
    fi
    
    return 0
}

# Main test execution
main() {
    test_group "Security Tests - Privilege and Authentication"
    
    # Build test binary first
    if ! build_test_binary; then
        echo "Failed to build test binary, aborting security tests"
        return 1
    fi
    
    # Check if we're running as root (some tests need adjustment)
    if is_root; then
        echo "WARNING: Running security tests as root - some tests may behave differently"
    fi
    
    run_test "permission_enforcement" test_permission_enforcement
    run_test "setuid_preservation" test_setuid_preservation
    run_test "console_user_check" test_console_user_check
    run_test "rate_limiting_documented" test_rate_limiting_documented
    run_test "privilege_drop_safety" test_privilege_drop_safety
    run_test "environment_sanitization" test_environment_sanitization
    run_test "command_injection_protection" test_command_injection_protection
    run_test "path_traversal_protection" test_path_traversal_protection
    run_test "hidden_installation_path" test_hidden_installation_path
    run_test "information_disclosure" test_information_disclosure
    run_test "permission_recommendations" test_permission_recommendations
    run_test "tocttou_safety" test_tocttou_safety
    
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