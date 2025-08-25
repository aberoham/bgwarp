#!/bin/bash

# test_helpers.sh - Shared utilities for unwarp test harness
# Provides common functions for test execution, validation, and mocking

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Test configuration
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$TEST_DIR")"
BIN_DIR="${TEST_DIR}/bin"
TEST_BINARY="${BIN_DIR}/unwarp_test"
PROD_BINARY="${PROJECT_ROOT}/unwarp"
MOCK_DIR="${TEST_DIR}/mocks"
OUTPUT_DIR="${TEST_DIR}/output"
LOG_FILE="${OUTPUT_DIR}/test.log"

# Initialize test environment
init_test_env() {
    mkdir -p "$MOCK_DIR" "$OUTPUT_DIR" "$BIN_DIR"
    > "$LOG_FILE"
    echo "Test environment initialized at $(date)" >> "$LOG_FILE"
}

# Cleanup test environment
cleanup_test_env() {
    if [[ -d "$MOCK_DIR" ]]; then
        rm -rf "$MOCK_DIR"
    fi
    if [[ -f "$TEST_BINARY" ]]; then
        rm -f "$TEST_BINARY"
    fi
    # Clean up any temp files in output dir but keep the dir
    if [[ -d "$OUTPUT_DIR" ]]; then
        find "$OUTPUT_DIR" -type f -name "*.tmp" -delete 2>/dev/null || true
    fi
    echo "Test environment cleaned up at $(date)" >> "$LOG_FILE"
}

# Log message to file and optionally to stdout
log_message() {
    local message="$1"
    local show_stdout="${2:-true}"
    
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $message" >> "$LOG_FILE"
    if [[ "$show_stdout" == "true" ]]; then
        echo "$message"
    fi
}

# Run a test case
run_test() {
    local test_name="$1"
    local test_function="$2"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    echo -n "  Running: $test_name ... "
    
    # Capture test output
    local output_file="${OUTPUT_DIR}/${test_name}.out"
    local error_file="${OUTPUT_DIR}/${test_name}.err"
    
    if $test_function > "$output_file" 2> "$error_file"; then
        echo -e "${GREEN}PASS${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        log_message "Test PASSED: $test_name" false
        return 0
    else
        echo -e "${RED}FAIL${NC}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        log_message "Test FAILED: $test_name" false
        
        # Show error details
        if [[ -s "$error_file" ]]; then
            echo "    Error output:"
            sed 's/^/      /' "$error_file"
        fi
        return 1
    fi
}

# Skip a test with reason
skip_test() {
    local test_name="$1"
    local reason="$2"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    
    echo -e "  Skipping: $test_name ... ${YELLOW}SKIP${NC} ($reason)"
    log_message "Test SKIPPED: $test_name - Reason: $reason" false
}

# Assert command output contains expected text
assert_contains() {
    local actual="$1"
    local expected="$2"
    local message="${3:-Output should contain expected text}"
    
    if [[ "$actual" == *"$expected"* ]]; then
        return 0
    else
        echo "Assertion failed: $message" >&2
        echo "Expected to contain: '$expected'" >&2
        echo "Actual output: '$actual'" >&2
        return 1
    fi
}

# Assert command output matches regex
assert_matches() {
    local actual="$1"
    local pattern="$2"
    local message="${3:-Output should match pattern}"
    
    if [[ "$actual" =~ $pattern ]]; then
        return 0
    else
        echo "Assertion failed: $message" >&2
        echo "Expected pattern: '$pattern'" >&2
        echo "Actual output: '$actual'" >&2
        return 1
    fi
}

# Assert command exit code
assert_exit_code() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Exit code should match expected}"
    
    if [[ "$actual" -eq "$expected" ]]; then
        return 0
    else
        echo "Assertion failed: $message" >&2
        echo "Expected exit code: $expected" >&2
        echo "Actual exit code: $actual" >&2
        return 1
    fi
}

# Assert file exists
assert_file_exists() {
    local file="$1"
    local message="${2:-File should exist}"
    
    if [[ -f "$file" ]]; then
        return 0
    else
        echo "Assertion failed: $message" >&2
        echo "File not found: $file" >&2
        return 1
    fi
}

# Create a mock command
create_mock_command() {
    local cmd_name="$1"
    local mock_behavior="$2"
    
    local mock_path="${MOCK_DIR}/${cmd_name}"
    
    cat > "$mock_path" << EOF
#!/bin/bash
# Mock for $cmd_name
$mock_behavior
EOF
    
    chmod +x "$mock_path"
    log_message "Created mock command: $cmd_name" false
}

# Setup PATH to use mocks
setup_mock_path() {
    export ORIGINAL_PATH="$PATH"
    export PATH="${MOCK_DIR}:${PATH}"
    log_message "Mock PATH configured" false
}

# Restore original PATH
restore_path() {
    if [[ -n "${ORIGINAL_PATH:-}" ]]; then
        export PATH="$ORIGINAL_PATH"
        unset ORIGINAL_PATH
        log_message "Original PATH restored" false
    fi
}

# Build test binary (without setuid)
build_test_binary() {
    echo "Building test binary (without setuid)..."
    
    cd "$PROJECT_ROOT"
    
    # Get version for test build
    local version="test-$(date +%Y%m%d-%H%M%S)"
    
    clang -framework Foundation \
          -framework LocalAuthentication \
          -framework Security \
          -framework SystemConfiguration \
          -fobjc-arc \
          -O0 \
          -g \
          -DUNWARP_VERSION="\"$version\"" \
          -o "$TEST_BINARY" \
          unwarp.m
    
    if [[ $? -eq 0 ]]; then
        echo "Test binary built successfully: $TEST_BINARY"
        return 0
    else
        echo "Failed to build test binary" >&2
        return 1
    fi
}

# Check if running as root
is_root() {
    [[ $EUID -eq 0 ]]
}

# Check if binary has setuid bit
has_setuid() {
    local binary="$1"
    
    if [[ -f "$binary" ]]; then
        local perms=$(stat -f "%p" "$binary" 2>/dev/null || stat -c "%a" "$binary" 2>/dev/null)
        # Extract last 4 digits to get octal permissions
        perms="${perms: -4}"
        # Check if setuid bit (4xxx) is set
        [[ "${perms:0:1}" == "4" ]]
    else
        return 1
    fi
}

# Print test summary
print_summary() {
    echo
    echo "========================================="
    echo "Test Summary"
    echo "========================================="
    echo "Total tests run: $TESTS_RUN"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
    echo -e "Skipped: ${YELLOW}$TESTS_SKIPPED${NC}"
    echo "========================================="
    
    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo -e "${RED}TEST SUITE FAILED${NC}"
        return 1
    elif [[ $TESTS_PASSED -eq 0 ]]; then
        echo -e "${YELLOW}NO TESTS PASSED${NC}"
        return 1
    else
        echo -e "${GREEN}ALL TESTS PASSED${NC}"
        return 0
    fi
}

# Test group header
test_group() {
    local group_name="$1"
    echo
    echo "========================================="
    echo "$group_name"
    echo "========================================="
    log_message "Starting test group: $group_name" false
}

# Simulate user input
simulate_input() {
    local input="$1"
    echo "$input"
}

# Wait for user confirmation (for manual tests)
wait_for_confirmation() {
    local prompt="$1"
    
    if [[ -t 0 ]]; then
        echo -e "${YELLOW}$prompt${NC}"
        echo "Press ENTER to continue or Ctrl+C to abort..."
        read -r
    else
        echo "Skipping manual confirmation (non-interactive mode)"
    fi
}

# Export all functions for use in test scripts
export -f init_test_env cleanup_test_env log_message run_test skip_test
export -f assert_contains assert_matches assert_exit_code assert_file_exists
export -f create_mock_command setup_mock_path restore_path
export -f build_test_binary is_root has_setuid
export -f print_summary test_group simulate_input wait_for_confirmation