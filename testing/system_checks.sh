#!/bin/bash

# system_checks.sh - System prerequisite checks for unwarp testing
# Detects WARP installation and other system requirements

set -euo pipefail

# Source test helpers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test_helpers.sh"

# Check results
WARP_INSTALLED=false
WARP_CLI_PATH=""
WARP_APP_PATH=""
WARP_RUNNING=false
SYSTEM_READY=true
WARNINGS=()

# Color codes
CHECKMARK="${GREEN}✓${NC}"
CROSSMARK="${RED}✗${NC}"
WARNING="${YELLOW}⚠${NC}"

# Check for WARP CLI
check_warp_cli() {
    echo -n "Checking for warp-cli... "
    
    # Check standard location
    if [[ -L "/usr/local/bin/warp-cli" ]]; then
        # It's a symlink, check if target exists
        local target=$(readlink "/usr/local/bin/warp-cli" 2>/dev/null || true)
        if [[ -n "$target" ]] && [[ -e "$target" ]]; then
            WARP_CLI_PATH="/usr/local/bin/warp-cli"
            WARP_INSTALLED=true
            echo -e "$CHECKMARK Found at $WARP_CLI_PATH"
            return 0
        else
            echo -e "$WARNING Broken symlink at /usr/local/bin/warp-cli"
            WARNINGS+=("WARP CLI symlink exists but target is missing")
            return 1
        fi
    fi
    
    # Check if warp-cli is in PATH
    if command -v warp-cli >/dev/null 2>&1; then
        WARP_CLI_PATH=$(command -v warp-cli)
        WARP_INSTALLED=true
        echo -e "$CHECKMARK Found at $WARP_CLI_PATH"
        return 0
    fi
    
    echo -e "$CROSSMARK Not found"
    WARNINGS+=("WARP CLI not installed - some tests will be skipped")
    return 1
}

# Check for WARP application
check_warp_app() {
    echo -n "Checking for Cloudflare WARP app... "
    
    if [[ -d "/Applications/Cloudflare WARP.app" ]]; then
        WARP_APP_PATH="/Applications/Cloudflare WARP.app"
        echo -e "$CHECKMARK Found at $WARP_APP_PATH"
        return 0
    fi
    
    echo -e "$CROSSMARK Not found"
    WARNINGS+=("WARP application not installed")
    return 1
}

# Check if WARP service is running
check_warp_service() {
    echo -n "Checking if WARP service is running... "
    
    if [[ "$WARP_INSTALLED" != "true" ]]; then
        echo -e "$CROSSMARK WARP not installed"
        return 1
    fi
    
    # Check for warp-svc process
    if pgrep -x "warp-svc" >/dev/null 2>&1; then
        WARP_RUNNING=true
        echo -e "$CHECKMARK Service is running"
        return 0
    fi
    
    echo -e "$WARNING Service not running"
    WARNINGS+=("WARP service is not running - connection tests will fail")
    return 1
}

# Check WARP connection status
check_warp_connection() {
    echo -n "Checking WARP connection status... "
    
    if [[ "$WARP_INSTALLED" != "true" ]]; then
        echo -e "$CROSSMARK WARP not installed"
        return 1
    fi
    
    if [[ "$WARP_RUNNING" != "true" ]]; then
        echo -e "$CROSSMARK Service not running"
        return 1
    fi
    
    # Try to get WARP status
    local status
    status=$("$WARP_CLI_PATH" status 2>/dev/null || echo "error")
    
    if [[ "$status" == *"Connected"* ]]; then
        echo -e "$CHECKMARK Connected"
        WARNINGS+=("WARP is currently connected - disconnect tests may affect connectivity")
        return 0
    elif [[ "$status" == *"Disconnected"* ]]; then
        echo -e "$WARNING Disconnected"
        return 0
    else
        echo -e "$CROSSMARK Unable to determine status"
        return 1
    fi
}

# Check system permissions
check_system_permissions() {
    echo -n "Checking system permissions... "
    
    # Check if we can use sudo without password (for testing)
    if sudo -n true 2>/dev/null; then
        echo -e "$CHECKMARK Passwordless sudo available"
        return 0
    else
        echo -e "$WARNING Sudo requires password"
        WARNINGS+=("Some tests may require manual authentication")
        return 0
    fi
}

# Check Touch ID availability
check_touch_id() {
    echo -n "Checking Touch ID availability... "
    
    # Check if the system has Touch ID hardware
    if system_profiler SPiBridgeDataType 2>/dev/null | grep -q "Touch ID" || \
       system_profiler SPHardwareDataType 2>/dev/null | grep -q "Touch ID"; then
        echo -e "$CHECKMARK Touch ID hardware detected"
        return 0
    else
        echo -e "$WARNING Touch ID not available"
        WARNINGS+=("Touch ID not available - will fall back to password authentication")
        return 0
    fi
}

# Check for required tools
check_required_tools() {
    echo "Checking required tools..."
    
    local required_tools=("clang" "otool" "plutil" "networksetup" "ifconfig")
    local missing_tools=()
    
    for tool in "${required_tools[@]}"; do
        echo -n "  $tool... "
        if command -v "$tool" >/dev/null 2>&1; then
            echo -e "$CHECKMARK"
        else
            echo -e "$CROSSMARK"
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        WARNINGS+=("Missing tools: ${missing_tools[*]}")
        SYSTEM_READY=false
    fi
}

# Generate system report
generate_report() {
    echo
    echo "========================================="
    echo "System Check Summary"
    echo "========================================="
    
    echo "WARP Installation: $(if [[ "$WARP_INSTALLED" == "true" ]]; then echo -e "$CHECKMARK Installed"; else echo -e "$CROSSMARK Not installed"; fi)"
    echo "WARP Service: $(if [[ "$WARP_RUNNING" == "true" ]]; then echo -e "$CHECKMARK Running"; else echo -e "$CROSSMARK Not running"; fi)"
    echo "System Ready: $(if [[ "$SYSTEM_READY" == "true" ]]; then echo -e "$CHECKMARK Yes"; else echo -e "$CROSSMARK No"; fi)"
    
    if [[ ${#WARNINGS[@]} -gt 0 ]]; then
        echo
        echo "Warnings:"
        for warning in "${WARNINGS[@]}"; do
            echo -e "  $WARNING $warning"
        done
    fi
    
    echo "========================================="
}

# Export check results for use by other scripts
export_results() {
    cat > "${OUTPUT_DIR}/system_check_results.sh" << EOF
# System check results - generated $(date)
export WARP_INSTALLED="$WARP_INSTALLED"
export WARP_CLI_PATH="$WARP_CLI_PATH"
export WARP_APP_PATH="$WARP_APP_PATH"
export WARP_RUNNING="$WARP_RUNNING"
export SYSTEM_READY="$SYSTEM_READY"
EOF
}

# Main execution
main() {
    echo "========================================="
    echo "System Prerequisite Checks"
    echo "========================================="
    echo
    
    # Ensure output directory exists
    mkdir -p "$OUTPUT_DIR"
    
    # Run checks
    check_warp_cli || true
    check_warp_app || true
    check_warp_service || true
    check_warp_connection || true
    check_system_permissions || true
    check_touch_id || true
    check_required_tools || true
    
    # Generate report
    generate_report
    
    # Export results
    export_results
    
    # Return status
    if [[ "$SYSTEM_READY" == "true" ]]; then
        return 0
    else
        return 1
    fi
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi