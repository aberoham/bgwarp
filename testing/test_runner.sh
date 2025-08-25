#!/bin/bash

# test_runner.sh - Main test orchestrator for unwarp test harness
# Executes all test suites and provides comprehensive reporting

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Source test helpers
source "${SCRIPT_DIR}/test_helpers.sh"

# Test suite configuration
declare -a TEST_SUITES=(
    "unit_tests.sh:Unit Tests:required"
    "security_tests.sh:Security Tests:required"
    "integration_tests.sh:Integration Tests:required"
    "acceptance_tests.sh:Acceptance Tests:optional"
)

# Results tracking (using parallel arrays for bash 3.2 compatibility)
declare -a SUITE_NAMES
declare -a SUITE_STATUSES
TOTAL_SUITES=0
PASSED_SUITES=0
FAILED_SUITES=0
SKIPPED_SUITES=0

# Parse command line arguments
SKIP_OPTIONAL=false
SUITE_FILTER=""
VERBOSE=false
INTERACTIVE=true

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Main test orchestrator for unwarp test harness.

OPTIONS:
    -h, --help          Show this help message
    -s, --suite SUITE   Run only specified test suite
    -q, --quick         Skip optional tests (acceptance tests)
    -n, --non-interactive  Run in non-interactive mode
    -v, --verbose       Verbose output
    -c, --clean         Clean test environment before running

EXAMPLES:
    $0                  # Run all tests
    $0 --quick          # Run only required tests
    $0 --suite unit     # Run only unit tests
    $0 --non-interactive  # Run without prompts

EOF
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            ;;
        -s|--suite)
            SUITE_FILTER="$2"
            shift 2
            ;;
        -q|--quick)
            SKIP_OPTIONAL=true
            shift
            ;;
        -n|--non-interactive)
            INTERACTIVE=false
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -c|--clean)
            cleanup_test_env
            shift
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Print banner
print_banner() {
    echo
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║           UNWARP TEST HARNESS v1.0                        ║"
    echo "║                                                            ║"
    echo "║  Testing emergency WARP disconnect tool                   ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo
    echo "Date: $(date)"
    echo "System: $(uname -srm)"
    echo "User: $USER"
    echo
}

# Check prerequisites
check_prerequisites() {
    echo "Checking prerequisites..."
    
    # Check for required tools
    local missing_tools=()
    
    for tool in clang otool plutil; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        echo "WARNING: Missing tools: ${missing_tools[*]}"
        echo "Some tests may be skipped"
    fi
    
    # Check for source file
    if [[ ! -f "$PROJECT_ROOT/unwarp.m" ]]; then
        echo "ERROR: Source file unwarp.m not found in $PROJECT_ROOT"
        return 1
    fi
    
    # Check for build script
    if [[ ! -f "$PROJECT_ROOT/build.sh" ]]; then
        echo "ERROR: Build script not found in $PROJECT_ROOT"
        return 1
    fi
    
    echo "Prerequisites check completed"
    return 0
}

# Run a test suite
run_test_suite() {
    local suite_file="$1"
    local suite_name="$2"
    local suite_type="$3"
    
    TOTAL_SUITES=$((TOTAL_SUITES + 1))
    
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Running: $suite_name"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    local suite_path="${SCRIPT_DIR}/${suite_file}"
    
    if [[ ! -f "$suite_path" ]]; then
        echo "ERROR: Test suite not found: $suite_path"
        SUITE_NAMES+=("$suite_name")
        SUITE_STATUSES+=("MISSING")
        FAILED_SUITES=$((FAILED_SUITES + 1))
        return 1
    fi
    
    # Make suite executable
    chmod +x "$suite_path"
    
    # Run the suite
    local start_time=$(date +%s)
    local exit_code=0
    
    if [[ "$INTERACTIVE" == "false" ]]; then
        # Non-interactive mode
        "$suite_path" 2>&1 | tee "${OUTPUT_DIR}/${suite_file%.sh}.log" || exit_code=$?
    else
        # Interactive mode
        "$suite_path" || exit_code=$?
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo "Duration: ${duration} seconds"
    
    if [[ $exit_code -eq 0 ]]; then
        SUITE_NAMES+=("$suite_name")
        SUITE_STATUSES+=("PASSED")
        PASSED_SUITES=$((PASSED_SUITES + 1))
        echo "Result: ✓ PASSED"
    else
        SUITE_NAMES+=("$suite_name")
        SUITE_STATUSES+=("FAILED")
        FAILED_SUITES=$((FAILED_SUITES + 1))
        echo "Result: ✗ FAILED (exit code: $exit_code)"
    fi
    
    return $exit_code
}

# Print final summary
print_final_summary() {
    echo
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║                    FINAL TEST SUMMARY                      ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo
    echo "Test Suites Run: $TOTAL_SUITES"
    echo -e "Passed: ${GREEN}$PASSED_SUITES${NC}"
    echo -e "Failed: ${RED}$FAILED_SUITES${NC}"
    echo -e "Skipped: ${YELLOW}$SKIPPED_SUITES${NC}"
    echo
    echo "Suite Results:"
    echo "──────────────"
    
    local i
    for ((i=0; i<${#SUITE_NAMES[@]}; i++)); do
        local suite_name="${SUITE_NAMES[$i]}"
        local result="${SUITE_STATUSES[$i]}"
        case "$result" in
            PASSED)
                echo -e "  $suite_name: ${GREEN}✓ PASSED${NC}"
                ;;
            FAILED)
                echo -e "  $suite_name: ${RED}✗ FAILED${NC}"
                ;;
            SKIPPED)
                echo -e "  $suite_name: ${YELLOW}○ SKIPPED${NC}"
                ;;
            MISSING)
                echo -e "  $suite_name: ${RED}✗ MISSING${NC}"
                ;;
        esac
    done
    
    echo
    echo "Test logs available in: $OUTPUT_DIR"
    echo
    
    if [[ $FAILED_SUITES -gt 0 ]]; then
        echo -e "${RED}╔════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║                    TEST HARNESS FAILED                     ║${NC}"
        echo -e "${RED}╚════════════════════════════════════════════════════════════╝${NC}"
        return 1
    else
        echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║                    ALL TESTS PASSED                        ║${NC}"
        echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
        return 0
    fi
}

# Main execution
main() {
    # Print banner
    print_banner
    
    # Initialize test environment
    init_test_env
    
    # Check prerequisites
    if ! check_prerequisites; then
        echo "Prerequisites check failed, aborting"
        exit 1
    fi
    
    # Build test binary once for all suites
    echo
    echo "Building test binary..."
    if ! build_test_binary; then
        echo "Failed to build test binary, aborting"
        exit 1
    fi
    
    # Run test suites
    for suite_entry in "${TEST_SUITES[@]}"; do
        IFS=':' read -r suite_file suite_name suite_type <<< "$suite_entry"
        
        # Check if suite should be skipped
        if [[ -n "$SUITE_FILTER" ]] && [[ "$suite_file" != *"$SUITE_FILTER"* ]]; then
            echo "Skipping $suite_name (filtered)"
            SUITE_NAMES+=("$suite_name")
            SUITE_STATUSES+=("SKIPPED")
            SKIPPED_SUITES=$((SKIPPED_SUITES + 1))
            continue
        fi
        
        if [[ "$SKIP_OPTIONAL" == "true" ]] && [[ "$suite_type" == "optional" ]]; then
            echo "Skipping $suite_name (optional)"
            SUITE_NAMES+=("$suite_name")
            SUITE_STATUSES+=("SKIPPED")
            SKIPPED_SUITES=$((SKIPPED_SUITES + 1))
            continue
        fi
        
        # Run the suite
        run_test_suite "$suite_file" "$suite_name" "$suite_type" || true
    done
    
    # Print final summary
    print_final_summary
    result=$?
    
    # Cleanup
    if [[ "$VERBOSE" != "true" ]]; then
        cleanup_test_env
    fi
    
    exit $result
}

# Signal handlers
trap 'echo "Test runner interrupted"; cleanup_test_env; exit 130' INT TERM

# Run main
main "$@"