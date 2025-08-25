#!/bin/bash

# acceptance_tests.sh - User acceptance tests for unwarp
# Interactive tests requiring manual verification

set -euo pipefail

# Source test helpers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test_helpers.sh"

# Check if running interactively
is_interactive() {
    [[ -t 0 ]] && [[ -t 1 ]]
}

# Manual test: Touch ID authentication flow
test_touch_id_auth() {
    if ! is_interactive; then
        echo "Skipping - requires interactive terminal"
        return 0
    fi
    
    echo
    echo "=== Manual Touch ID Authentication Test ==="
    echo "This test requires a properly installed unwarp binary with setuid."
    echo
    echo "Instructions:"
    echo "1. Run: sudo $PROJECT_ROOT/install.sh (if not already installed)"
    echo "2. Run: /usr/local/libexec/.unwarp"
    echo "3. Verify Touch ID prompt appears"
    echo "4. Authenticate with Touch ID or password"
    echo "5. Verify test mode banner appears after authentication"
    echo
    
    wait_for_confirmation "Ready to test Touch ID authentication?"
    
    echo "Please run the command and verify the authentication flow."
    echo "Did Touch ID authentication work correctly? (y/n): "
    read -r response
    
    if [[ "$response" == "y" ]] || [[ "$response" == "Y" ]]; then
        echo "Touch ID authentication test passed"
        return 0
    else
        echo "Touch ID authentication test failed or was not completed" >&2
        return 1
    fi
}

# Manual test: Network recovery verification
test_network_recovery() {
    if ! is_interactive; then
        echo "Skipping - requires interactive terminal"
        return 0
    fi
    
    echo
    echo "=== Manual Network Recovery Test ==="
    echo "This test verifies network recovery after WARP disconnect."
    echo
    echo "Instructions:"
    echo "1. Note your current network connectivity status"
    echo "2. Run: /usr/local/libexec/.unwarp --liveincident"
    echo "3. Authenticate when prompted"
    echo "4. Observe the network recovery process"
    echo "5. Verify network connectivity is restored"
    echo
    
    wait_for_confirmation "Ready to test network recovery?"
    
    echo "Please run the command and verify network recovery."
    echo "Was network connectivity successfully restored? (y/n): "
    read -r response
    
    if [[ "$response" == "y" ]] || [[ "$response" == "Y" ]]; then
        echo "Network recovery test passed"
        return 0
    else
        echo "Network recovery test failed or was not completed" >&2
        return 1
    fi
}

# Manual test: Output formatting verification
test_output_formatting() {
    if ! is_interactive; then
        echo "Skipping - requires interactive terminal"
        return 0
    fi
    
    echo
    echo "=== Manual Output Formatting Test ==="
    echo "This test verifies the visual output formatting."
    echo
    echo "Instructions:"
    echo "1. Run: $TEST_BINARY --help"
    echo "2. Verify box drawing characters display correctly"
    echo "3. Check text alignment and readability"
    echo "4. Run: $TEST_BINARY --version"
    echo "5. Verify version information is properly formatted"
    echo
    
    wait_for_confirmation "Ready to verify output formatting?"
    
    # Show the output for review
    echo
    echo "Help output:"
    echo "----------------------------------------"
    "$TEST_BINARY" --help 2>&1 || true
    echo "----------------------------------------"
    echo
    echo "Version output:"
    echo "----------------------------------------"
    "$TEST_BINARY" --version 2>&1 || true
    echo "----------------------------------------"
    echo
    
    echo "Is the output formatting correct and readable? (y/n): "
    read -r response
    
    if [[ "$response" == "y" ]] || [[ "$response" == "Y" ]]; then
        echo "Output formatting test passed"
        return 0
    else
        echo "Output formatting test failed" >&2
        return 1
    fi
}

# Manual test: Emergency scenario walkthrough
test_emergency_scenario() {
    if ! is_interactive; then
        echo "Skipping - requires interactive terminal"
        return 0
    fi
    
    echo
    echo "=== Emergency Scenario Walkthrough ==="
    echo "This test simulates an actual WARP outage scenario."
    echo
    echo "Scenario: WARP is unresponsive and blocking network access."
    echo
    echo "Instructions:"
    echo "1. Imagine WARP dashboard is inaccessible"
    echo "2. Run: /usr/local/libexec/.unwarp (test mode first)"
    echo "3. Review what would happen"
    echo "4. If comfortable, run: /usr/local/libexec/.unwarp --liveincident"
    echo "5. Verify WARP is disconnected"
    echo "6. Verify auto-recovery is scheduled"
    echo
    
    wait_for_confirmation "Ready for emergency scenario walkthrough?"
    
    echo "Please complete the scenario walkthrough."
    echo "Did the emergency disconnect work as expected? (y/n): "
    read -r response
    
    if [[ "$response" == "y" ]] || [[ "$response" == "Y" ]]; then
        echo "Emergency scenario test passed"
        return 0
    else
        echo "Emergency scenario test failed or was not completed" >&2
        return 1
    fi
}

# Manual test: Auto-recovery verification
test_auto_recovery_scheduling() {
    if ! is_interactive; then
        echo "Skipping - requires interactive terminal"
        return 0
    fi
    
    echo
    echo "=== Auto-Recovery Scheduling Test ==="
    echo "This test verifies auto-recovery scheduling."
    echo
    echo "Instructions:"
    echo "1. Run: /usr/local/libexec/.unwarp --liveincident --reconnect 60"
    echo "2. After completion, check for recovery job:"
    echo "   launchctl list | grep unwarp.recovery"
    echo "3. Note the PID if present"
    echo "4. Check plist file in /tmp/com.unwarp.recovery.*.plist"
    echo "5. Optionally wait for reconnection or cancel with:"
    echo "   launchctl unload /tmp/com.unwarp.recovery.*.plist"
    echo
    
    wait_for_confirmation "Ready to test auto-recovery scheduling?"
    
    echo "Please run the commands and verify auto-recovery."
    echo "Was auto-recovery correctly scheduled? (y/n): "
    read -r response
    
    if [[ "$response" == "y" ]] || [[ "$response" == "Y" ]]; then
        echo "Auto-recovery scheduling test passed"
        return 0
    else
        echo "Auto-recovery scheduling test failed" >&2
        return 1
    fi
}

# Manual test: Permission denial verification
test_permission_denial() {
    if ! is_interactive; then
        echo "Skipping - requires interactive terminal"
        return 0
    fi
    
    echo
    echo "=== Permission Denial Test ==="
    echo "This test verifies the binary refuses to run without proper setup."
    echo
    echo "Instructions:"
    echo "1. Build a fresh binary: $PROJECT_ROOT/build.sh"
    echo "2. Try to run WITHOUT sudo: $PROJECT_ROOT/unwarp"
    echo "3. Verify it shows permission error"
    echo "4. Verify it provides installation instructions"
    echo
    
    wait_for_confirmation "Ready to test permission denial?"
    
    # Show what happens without permissions
    echo
    echo "Output without setuid:"
    echo "----------------------------------------"
    "$PROD_BINARY" 2>&1 || true
    echo "----------------------------------------"
    echo
    
    echo "Did the binary correctly refuse to run and show instructions? (y/n): "
    read -r response
    
    if [[ "$response" == "y" ]] || [[ "$response" == "Y" ]]; then
        echo "Permission denial test passed"
        return 0
    else
        echo "Permission denial test failed" >&2
        return 1
    fi
}

# Main test execution
main() {
    test_group "User Acceptance Tests - Manual Verification"
    
    # Build test binary first
    if ! build_test_binary; then
        echo "Failed to build test binary, aborting acceptance tests"
        return 1
    fi
    
    if ! is_interactive; then
        echo "WARNING: Running in non-interactive mode"
        echo "Most acceptance tests will be skipped"
        echo "Run this script directly in a terminal for full testing"
        echo
    fi
    
    # Check if production binary exists
    if [[ ! -f "$PROD_BINARY" ]]; then
        echo "Production binary not found. Run: $PROJECT_ROOT/build.sh"
    fi
    
    # Interactive tests
    if is_interactive; then
        echo
        echo "This suite contains manual tests requiring user interaction."
        echo "You will be prompted to perform actions and verify results."
        echo
        wait_for_confirmation "Ready to begin manual acceptance tests?"
        
        run_test "output_formatting" test_output_formatting
        run_test "permission_denial" test_permission_denial
        
        # These tests require a properly installed binary
        echo
        echo "The following tests require a properly installed unwarp binary."
        echo "Have you run 'sudo ./install.sh'? (y/n): "
        read -r installed
        
        if [[ "$installed" == "y" ]] || [[ "$installed" == "Y" ]]; then
            run_test "touch_id_auth" test_touch_id_auth
            run_test "network_recovery" test_network_recovery
            run_test "auto_recovery_scheduling" test_auto_recovery_scheduling
            run_test "emergency_scenario" test_emergency_scenario
        else
            skip_test "touch_id_auth" "Requires installed binary"
            skip_test "network_recovery" "Requires installed binary"
            skip_test "auto_recovery_scheduling" "Requires installed binary"
            skip_test "emergency_scenario" "Requires installed binary"
        fi
    else
        skip_test "output_formatting" "Requires interactive terminal"
        skip_test "permission_denial" "Requires interactive terminal"
        skip_test "touch_id_auth" "Requires interactive terminal"
        skip_test "network_recovery" "Requires interactive terminal"
        skip_test "auto_recovery_scheduling" "Requires interactive terminal"
        skip_test "emergency_scenario" "Requires interactive terminal"
    fi
    
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