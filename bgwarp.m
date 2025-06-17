#import <Foundation/Foundation.h>
#import <LocalAuthentication/LocalAuthentication.h>
#import <unistd.h>
#import <sys/types.h>
#import <signal.h>
#import <stdlib.h>
#import <stdio.h>
#import <string.h>
#import <errno.h>
#import <sys/stat.h>

#define WARP_CLI_PATH "/usr/local/bin/warp-cli"
#define MAX_CMD_OUTPUT 4096

// Global flag for live incident mode (default is test mode)
static BOOL liveMode = NO;

// Global setting for reconnect base time in seconds (default is 2 hours = 7200 seconds)
static int reconnectBaseSeconds = 7200;

// Forward declarations
static void performInteractiveRecovery(const char *wifiInterface, const char *ethernetInterface);
static void performNetworkRecovery(void);
static void showHelp(const char *programName);

// Function to execute shell commands and capture output
static int executeCommand(const char *command, char *output, size_t outputSize) {
    if (!liveMode) {
        printf("[TEST MODE] Would execute: %s\n", command);
        // Check if we would have permission to run privileged commands
        if (strstr(command, "killall") != NULL || 
            strstr(command, "route") != NULL ||
            strstr(command, "ifconfig") != NULL ||
            strstr(command, "ipconfig") != NULL ||
            strstr(command, "dscacheutil") != NULL) {
            printf("[TEST MODE] Permission check: %s (euid=%u, uid=%u)\n", 
                   geteuid() == 0 ? "PASS" : "FAIL", geteuid(), getuid());
        }
        return 0; // Simulate success in test mode
    }
    
    FILE *pipe = popen(command, "r");
    if (!pipe) {
        return -1;
    }
    
    size_t bytesRead = 0;
    if (output && outputSize > 0) {
        bytesRead = fread(output, 1, outputSize - 1, pipe);
        output[bytesRead] = '\0';
    }
    
    int status = pclose(pipe);
    return WEXITSTATUS(status);
}

// Helper function to build privileged commands (with or without sudo based on euid)
static void buildPrivilegedCommand(char *dest, size_t destSize, const char *command) {
    if (geteuid() == 0) {
        // Already running as root, no need for sudo
        snprintf(dest, destSize, "%s", command);
    } else {
        // Not root, need sudo
        snprintf(dest, destSize, "sudo %s", command);
    }
}

// Function to perform WARP cleanup operations
static void performWarpCleanup(void) {
    char output[MAX_CMD_OUTPUT];
    
    printf("[*] Starting WARP emergency disconnect...\n");
    
    // Step 1: Disconnect WARP
    printf("[*] Disconnecting WARP...\n");
    int result = executeCommand(WARP_CLI_PATH " disconnect", output, sizeof(output));
    if (result == 0) {
        printf("[+] WARP disconnected successfully\n");
    } else {
        printf("[!] WARP disconnect failed (code: %d), continuing anyway...\n", result);
    }
    
    // Step 2: Kill WARP processes
    printf("[*] Terminating WARP processes...\n");
    char cmd[256];
    buildPrivilegedCommand(cmd, sizeof(cmd), "killall -9 'Cloudflare WARP' 2>/dev/null");
    executeCommand(cmd, NULL, 0);
    buildPrivilegedCommand(cmd, sizeof(cmd), "killall -9 warp-svc 2>/dev/null");
    executeCommand(cmd, NULL, 0);
    buildPrivilegedCommand(cmd, sizeof(cmd), "killall -9 warp-taskbar 2>/dev/null");
    executeCommand(cmd, NULL, 0);
    printf("[+] WARP processes terminated\n");
    
    // Step 3: Flush DNS cache
    printf("[*] Flushing DNS cache...\n");
    result = executeCommand("dscacheutil -flushcache", output, sizeof(output));
    if (result == 0) {
        printf("[+] DNS cache flushed\n");
    } else {
        printf("[!] DNS flush failed (code: %d)\n", result);
    }
    
    // Step 4: Reset network routes (suppress errors for missing routes)
    printf("[*] Resetting network routes...\n");
    buildPrivilegedCommand(cmd, sizeof(cmd), "route -n flush 2>/dev/null");
    executeCommand(cmd, NULL, 0);
    printf("[+] Network routes reset\n");
    
    // Step 5: Restart mDNSResponder
    printf("[*] Restarting mDNSResponder...\n");
    buildPrivilegedCommand(cmd, sizeof(cmd), "killall -HUP mDNSResponder 2>/dev/null");
    executeCommand(cmd, NULL, 0);
    printf("[+] mDNSResponder restarted\n");
    
    printf("\n[+] WARP emergency disconnect completed!\n");
    
    // Attempt automatic network recovery
    performNetworkRecovery();
}

// Function to detect active network interfaces
static void detectNetworkInterfaces(char *wifiInterface, size_t wifiSize, char *ethernetInterface, size_t ethSize) {
    char output[MAX_CMD_OUTPUT];
    wifiInterface[0] = '\0';
    ethernetInterface[0] = '\0';
    
    // Get network interfaces
    if (executeCommand("networksetup -listallhardwareports", output, sizeof(output)) == 0) {
        // Parse output to find Wi-Fi and Ethernet interfaces
        char *line = strtok(output, "\n");
        char currentPort[256] = "";
        char currentDevice[256] = "";
        
        while (line != NULL) {
            if (strstr(line, "Hardware Port:")) {
                strncpy(currentPort, line + 15, sizeof(currentPort) - 1);
            } else if (strstr(line, "Device:")) {
                strncpy(currentDevice, line + 8, sizeof(currentDevice) - 1);
                
                // Check if this is Wi-Fi or Ethernet
                if (strstr(currentPort, "Wi-Fi") || strstr(currentPort, "AirPort")) {
                    strncpy(wifiInterface, currentDevice, wifiSize - 1);
                } else if (strstr(currentPort, "Ethernet") || strstr(currentPort, "USB") || 
                          strstr(currentPort, "Thunderbolt") || strstr(currentPort, "Display")) {
                    strncpy(ethernetInterface, currentDevice, ethSize - 1);
                }
            }
            line = strtok(NULL, "\n");
        }
    }
}

// Function to check if we can reach the default gateway
static BOOL canReachGateway(void) {
    char output[MAX_CMD_OUTPUT];
    
    // Get default gateway (suppress route errors)
    if (executeCommand("route -n get default 2>/dev/null | grep gateway | awk '{print $2}'", output, sizeof(output)) == 0) {
        char *gateway = strtok(output, "\n");
        if (gateway && strlen(gateway) > 0) {
            char pingCmd[256];
            snprintf(pingCmd, sizeof(pingCmd), "ping -c 1 -t 2 %s >/dev/null 2>&1", gateway);
            return executeCommand(pingCmd, NULL, 0) == 0;
        }
    }
    return NO;
}

// Function to perform network recovery
static void performNetworkRecovery(void) {
    printf("\n[*] Attempting automatic network recovery...\n");
    
    char wifiInterface[32];
    char ethernetInterface[32];
    detectNetworkInterfaces(wifiInterface, sizeof(wifiInterface), ethernetInterface, sizeof(ethernetInterface));
    
    printf("[*] Detected interfaces: Wi-Fi=%s, Ethernet=%s\n", 
           strlen(wifiInterface) > 0 ? wifiInterface : "none",
           strlen(ethernetInterface) > 0 ? ethernetInterface : "none");
    
    // First, try to ping the gateway
    if (canReachGateway()) {
        printf("[+] Network connectivity verified - can reach default gateway\n");
        return;
    }
    
    printf("[!] Cannot reach default gateway, attempting recovery...\n");
    
    // Try Wi-Fi recovery first
    if (strlen(wifiInterface) > 0) {
        printf("[*] Cycling Wi-Fi interface %s...\n", wifiInterface);
        
        char cmd[256];
        char baseCmd[256];
        snprintf(baseCmd, sizeof(baseCmd), "ifconfig %s down", wifiInterface);
        buildPrivilegedCommand(cmd, sizeof(cmd), baseCmd);
        executeCommand(cmd, NULL, 0);
        
        sleep(2); // Wait for interface to fully shut down
        
        snprintf(baseCmd, sizeof(baseCmd), "ifconfig %s up", wifiInterface);
        buildPrivilegedCommand(cmd, sizeof(cmd), baseCmd);
        executeCommand(cmd, NULL, 0);
        
        printf("[*] Waiting for Wi-Fi to reconnect...\n");
        sleep(5); // Give Wi-Fi time to reconnect
        
        if (canReachGateway()) {
            printf("[+] Network recovery successful via Wi-Fi!\n");
            return;
        }
    }
    
    // Try Ethernet recovery if Wi-Fi didn't work
    if (strlen(ethernetInterface) > 0) {
        printf("[*] Cycling Ethernet interface %s...\n", ethernetInterface);
        
        char cmd[256];
        char baseCmd[256];
        snprintf(baseCmd, sizeof(baseCmd), "ifconfig %s down", ethernetInterface);
        buildPrivilegedCommand(cmd, sizeof(cmd), baseCmd);
        executeCommand(cmd, NULL, 0);
        
        sleep(1);
        
        snprintf(baseCmd, sizeof(baseCmd), "ifconfig %s up", ethernetInterface);
        buildPrivilegedCommand(cmd, sizeof(cmd), baseCmd);
        executeCommand(cmd, NULL, 0);
        
        sleep(3); // Ethernet usually connects faster
        
        if (canReachGateway()) {
            printf("[+] Network recovery successful via Ethernet!\n");
            return;
        }
    }
    
    // If automatic recovery failed, provide manual instructions
    if (!liveMode) {
        printf("\n[TEST MODE] Would show manual recovery instructions\n");
        return;
    }
    
    printf("\n");
    printf("╔════════════════════════════════════════════════════════════╗\n");
    printf("║           MANUAL NETWORK RECOVERY REQUIRED                 ║\n");
    printf("╠════════════════════════════════════════════════════════════╣\n");
    printf("║ Automatic recovery failed. Try these steps:                ║\n");
    printf("║                                                            ║\n");
    printf("║ 1. Turn Wi-Fi off and back on in System Settings          ║\n");
    printf("║ 2. Unplug and replug Ethernet cable (if connected)        ║\n");
    printf("║                                                            ║\n");
    printf("║ Or run these commands manually:                           ║\n");
    printf("╚════════════════════════════════════════════════════════════╝\n");
    
    if (strlen(wifiInterface) > 0) {
        printf("\nFor Wi-Fi:\n");
        printf("  sudo ifconfig %s down\n", wifiInterface);
        printf("  sleep 2\n");
        printf("  sudo ifconfig %s up\n", wifiInterface);
    }
    
    if (strlen(ethernetInterface) > 0) {
        printf("\nFor Ethernet:\n");
        printf("  sudo ifconfig %s down\n", ethernetInterface);
        printf("  sleep 1\n");  
        printf("  sudo ifconfig %s up\n", ethernetInterface);
    }
    
    printf("\nAdditional recovery commands:\n");
    printf("  sudo dscacheutil -flushcache\n");
    printf("  sudo killall -HUP mDNSResponder\n");
    printf("  networksetup -setairportpower Wi-Fi off\n");
    printf("  networksetup -setairportpower Wi-Fi on\n");
    
    // Offer interactive recovery
    printf("\n[?] Would you like me to attempt interactive recovery? (y/n): ");
    fflush(stdout);
    
    char response[10];
    if (fgets(response, sizeof(response), stdin) && (response[0] == 'y' || response[0] == 'Y')) {
        performInteractiveRecovery(wifiInterface, ethernetInterface);
    }
}

// Function to perform interactive recovery with user guidance
static void performInteractiveRecovery(const char *wifiInterface, const char *ethernetInterface) {
    printf("\n[*] Starting interactive recovery...\n");
    
    // More aggressive network reset
    printf("[*] Performing comprehensive network reset...\n");
    
    // Reset all network services
    char cmd[256];
    buildPrivilegedCommand(cmd, sizeof(cmd), "dscacheutil -flushcache");
    executeCommand(cmd, NULL, 0);
    buildPrivilegedCommand(cmd, sizeof(cmd), "killall -HUP mDNSResponder");
    executeCommand(cmd, NULL, 0);
    buildPrivilegedCommand(cmd, sizeof(cmd), "killall -HUP configd");
    executeCommand(cmd, NULL, 0);
    
    // Clear DHCP leases - use actual interface names if available
    if (strlen(wifiInterface) > 0) {
        char baseCmd[256];
        snprintf(baseCmd, sizeof(baseCmd), "ipconfig set %s NONE", wifiInterface);
        buildPrivilegedCommand(cmd, sizeof(cmd), baseCmd);
        executeCommand(cmd, NULL, 0);
    }
    if (strlen(ethernetInterface) > 0) {
        char baseCmd[256];
        snprintf(baseCmd, sizeof(baseCmd), "ipconfig set %s NONE", ethernetInterface);
        buildPrivilegedCommand(cmd, sizeof(cmd), baseCmd);
        executeCommand(cmd, NULL, 0);
    }
    
    sleep(2);
    
    // Re-enable DHCP
    if (strlen(wifiInterface) > 0) {
        char baseCmd[256];
        snprintf(baseCmd, sizeof(baseCmd), "ipconfig set %s DHCP", wifiInterface);
        buildPrivilegedCommand(cmd, sizeof(cmd), baseCmd);
        executeCommand(cmd, NULL, 0);
    }
    if (strlen(ethernetInterface) > 0) {
        char baseCmd[256];
        snprintf(baseCmd, sizeof(baseCmd), "ipconfig set %s DHCP", ethernetInterface);
        buildPrivilegedCommand(cmd, sizeof(cmd), baseCmd);
        executeCommand(cmd, NULL, 0);
    }
    
    // Use networksetup for more thorough reset
    if (strlen(wifiInterface) > 0) {
        executeCommand("networksetup -setairportpower Wi-Fi off", NULL, 0);
        sleep(3);
        executeCommand("networksetup -setairportpower Wi-Fi on", NULL, 0);
    }
    
    printf("[*] Waiting for network to stabilize...\n");
    sleep(5);
    
    // Final connectivity check
    if (canReachGateway()) {
        printf("[+] Interactive recovery successful!\n");
    } else {
        printf("[!] Network still unreachable. You may need to:\n");
        printf("    - Restart your Mac\n");
        printf("    - Check with your IT department\n");
        printf("    - Verify physical network connections\n");
    }
}

// Function to authenticate with Touch ID
static BOOL authenticateWithTouchID(void) {
    // Save current effective UID/GID
    uid_t saved_euid = geteuid();
    gid_t saved_egid = getegid();
    
    // Temporarily drop to real user privileges for authentication
    uid_t real_uid = getuid();
    gid_t real_gid = getgid();
    
    if (seteuid(real_uid) != 0 || setegid(real_gid) != 0) {
        fprintf(stderr, "Failed to drop privileges for authentication\n");
        return NO;
    }
    
    LAContext *context = [[LAContext alloc] init];
    NSError *error = nil;
    
    // Check if Touch ID is available
    if (![context canEvaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics error:&error]) {
        NSLog(@"Touch ID not available: %@", error.localizedDescription);
        
        // Fall back to password authentication if Touch ID is not available
        if ([context canEvaluatePolicy:LAPolicyDeviceOwnerAuthentication error:&error]) {
            NSLog(@"Falling back to password authentication...");
            
            dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
            __block BOOL authenticated = NO;
            
            [context evaluatePolicy:LAPolicyDeviceOwnerAuthentication
                    localizedReason:@"Authenticate to perform emergency WARP disconnect"
                              reply:^(BOOL success, NSError *authError) {
                if (success) {
                    authenticated = YES;
                } else {
                    NSLog(@"Authentication failed: %@", authError.localizedDescription);
                }
                dispatch_semaphore_signal(semaphore);
            }];
            
            dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
            
            // Restore root privileges
            if (seteuid(saved_euid) != 0 || setegid(saved_egid) != 0) {
                fprintf(stderr, "Failed to restore privileges after authentication\n");
                return NO;
            }
            
            return authenticated;
        }
        
        // Restore root privileges even in error case
        if (seteuid(saved_euid) != 0 || setegid(saved_egid) != 0) {
            fprintf(stderr, "Failed to restore privileges after authentication\n");
        }
        
        return NO;
    }
    
    // Perform Touch ID authentication
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block BOOL authenticated = NO;
    
    [context evaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics
            localizedReason:@"Authenticate to perform emergency WARP disconnect"
                      reply:^(BOOL success, NSError *authError) {
        if (success) {
            authenticated = YES;
        } else {
            NSLog(@"Touch ID authentication failed: %@", authError.localizedDescription);
        }
        dispatch_semaphore_signal(semaphore);
    }];
    
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    
    // Restore root privileges
    if (seteuid(saved_euid) != 0 || setegid(saved_egid) != 0) {
        fprintf(stderr, "Failed to restore privileges after authentication\n");
        return NO;
    }
    
    return authenticated;
}

// Function to verify system state and permissions
static void performTestMode(void) {
    // Check permissions
    printf("[TEST] Permission Status:\n");
    printf("  - Real UID: %u\n", getuid());
    printf("  - Effective UID: %u %s\n", geteuid(), geteuid() == 0 ? "(root)" : "(non-root)");
    printf("  - Real GID: %u\n", getgid());
    printf("  - Effective GID: %u\n", getegid());
    
    // Check if binary has setuid bit
    struct stat fileStat;
    if (stat("/proc/self/exe", &fileStat) == 0 || stat(getenv("_"), &fileStat) == 0) {
        printf("  - Setuid bit: %s\n", (fileStat.st_mode & S_ISUID) ? "SET" : "NOT SET");
    }
    
    // Check for required binaries
    printf("\n[TEST] Binary Availability:\n");
    const char *binaries[] = {
        WARP_CLI_PATH,
        "/usr/bin/killall",
        "/usr/bin/dscacheutil",
        "/sbin/route",
        "/sbin/ifconfig"
    };
    
    for (int i = 0; i < 5; i++) {
        if (access(binaries[i], X_OK) == 0) {
            printf("  ✓ %s - FOUND\n", binaries[i]);
        } else {
            printf("  ✗ %s - NOT FOUND or not executable\n", binaries[i]);
        }
    }
    
    printf("\n[TEST] Commands that would be executed:\n");
}

// Function to show help information
static void showHelp(const char *programName) {
    printf("Emergency WARP disconnect tool for macOS\n");
    printf("\n");
    printf("Usage: %s [OPTIONS]\n", programName);
    printf("\n");
    printf("Options:\n");
    printf("  --liveincident    Execute in live mode (destructive actions)\n");
    printf("  --reconnect <seconds> Set reconnect base time in seconds (60-43200)\n");
    printf("                        Default: 7200 (2 hours)\n");
    printf("                        Actual reconnect: random between base and 2x base\n");
    printf("  --help, -h        Print this help message\n");
    printf("\n");
    printf("Description:\n");
    printf("  bgwarp (break glass WARP) is an emergency tool that forcefully\n");
    printf("  disconnects Cloudflare WARP during outages when the dashboard\n");
    printf("  is inaccessible. It requires Touch ID authentication and must\n");
    printf("  be installed with setuid root privileges.\n");
    printf("\n");
    printf("Features:\n");
    printf("  - Safe by default: Runs in test mode unless --liveincident is specified\n");
    printf("  - Touch ID authentication required (with password fallback)\n");
    printf("  - Automatic network recovery after WARP disconnection\n");
    printf("  - Auto-reconnection to WARP after base time (randomized between base and 2x base)\n");
    printf("  - Automatic restart of WARP GUI application after reconnection\n");
    printf("  - Interactive recovery mode if automatic recovery fails\n");
    printf("\n");
    printf("Test Mode (default):\n");
    printf("  Shows what commands would be executed without making changes\n");
    printf("  Authentication is still required to test the full flow\n");
    printf("\n");
    printf("Live Mode (--liveincident):\n");
    printf("  WARNING: Destructive operation that will:\n");
    printf("  - Disconnect and delete WARP configuration\n");
    printf("  - Terminate all WARP processes\n");
    printf("  - Reset network routes and DNS\n");
    printf("  - Attempt automatic network recovery\n");
    printf("  - Schedule WARP reconnection (configurable with --reconnect)\n");
    printf("\n");
    printf("Network Recovery:\n");
    printf("  After disconnecting WARP, the tool will:\n");
    printf("  1. Detect Wi-Fi and Ethernet interfaces\n");
    printf("  2. Test connectivity to default gateway\n");
    printf("  3. Cycle network interfaces if needed\n");
    printf("  4. Offer interactive recovery if automatic fails\n");
    printf("\n");
    printf("Installation:\n");
    printf("  sudo chown root:wheel %s\n", programName);
    printf("  sudo chmod 4755 %s\n", programName);
    printf("\n");
    printf("Example:\n");
    printf("  %s                  # Run in test mode\n", programName);
    printf("  %s --liveincident   # Run in live mode (use during outages)\n", programName);
    printf("  %s --liveincident --reconnect 300  # 5 min base reconnect time\n", programName);
    printf("\n");
    printf("Debugging:\n");
    printf("  View bgwarp logs:\n");
    printf("    log show --predicate 'subsystem == \"bgwarp\"' --last 1h\n");
    printf("    log show --predicate 'process == \"logger\" AND eventMessage CONTAINS \"bgwarp\"' --last 1h\n");
    printf("\n");
    printf("  List active recovery jobs:\n");
    printf("    launchctl list | grep bgwarp.recovery\n");
    printf("\n");
    printf("  View recovery job details:\n");
    printf("    launchctl print gui/$(id -u)/com.bgwarp.recovery.PID\n");
    printf("\n");
    printf("  Manually cancel recovery:\n");
    printf("    launchctl unload /tmp/com.bgwarp.recovery.*.plist\n");
    printf("\n");
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // Check for help flag first
        for (int i = 1; i < argc; i++) {
            if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
                showHelp(argv[0]);
                return 0;
            }
        }
        
        // Parse command line arguments
        for (int i = 1; i < argc; i++) {
            if (strcmp(argv[i], "--liveincident") == 0) {
                liveMode = YES;
            } else if (strcmp(argv[i], "--reconnect") == 0 && i + 1 < argc) {
                int seconds = atoi(argv[i + 1]);
                if (seconds < 60 || seconds > 43200) {
                    fprintf(stderr, "Error: --reconnect value must be between 60 and 43200 seconds\n");
                    fprintf(stderr, "       You specified: %d seconds\n", seconds);
                    return 1;
                }
                reconnectBaseSeconds = seconds;
                i++; // Skip the next argument since we consumed it
            }
        }
        
        // Check if running with effective root privileges
        if (geteuid() != 0) {
            fprintf(stderr, "Error: This program must be installed with setuid root.\n");
            fprintf(stderr, "Please ensure proper installation with:\n");
            fprintf(stderr, "  sudo chown root:wheel %s\n", argv[0]);
            fprintf(stderr, "  sudo chmod 4755 %s\n", argv[0]);
            return 1;
        }
        
        // Display appropriate banner
        if (!liveMode) {
            printf("\n");
            printf("╔════════════════════════════════════════════════════════════╗\n");
            printf("║                    TEST MODE ACTIVE                        ║\n");
            printf("╠════════════════════════════════════════════════════════════╣\n");
            printf("║ This is a test run. Commands will be shown but NOT        ║\n");
            printf("║ executed. Authentication will be required as normal.       ║\n");
            printf("╚════════════════════════════════════════════════════════════╝\n");
            printf("\n");
        } else {
            printf("\n");
            printf("╔════════════════════════════════════════════════════════════╗\n");
            printf("║         ⚠️  LIVE INCIDENT MODE - DESTRUCTIVE ACTION ⚠️      ║\n");
            printf("╠════════════════════════════════════════════════════════════╣\n");
            printf("║ WARNING: This tool will forcefully disconnect WARP and     ║\n");
            printf("║ remove all configuration. Use only during outages when     ║\n");
            printf("║ the dashboard is inaccessible.                             ║\n");
            printf("╚════════════════════════════════════════════════════════════╝\n");
            printf("\n");
        }
        
        // Require Touch ID authentication in both modes
        printf("[*] Authenticating with Touch ID...\n");
        
        if (!authenticateWithTouchID()) {
            fprintf(stderr, "[!] Authentication failed. Access denied.\n");
            return 1;
        }
        
        printf("[+] Authentication successful\n\n");
        
        // If in test mode, show additional information before cleanup
        if (!liveMode) {
            performTestMode();
        }
        
        // Log the action for audit purposes
        char *username = getenv("USER");
        if (!username) username = "unknown";
        
        char logCmd[512];
        snprintf(logCmd, sizeof(logCmd), 
                 "logger -t bgwarp 'Emergency WARP disconnect initiated by user %s (uid=%u)'", 
                 username, getuid());
        system(logCmd);
        
        // Perform the WARP cleanup
        performWarpCleanup();
        
        if (liveMode) {
            // Log completion
            snprintf(logCmd, sizeof(logCmd), 
                     "logger -t bgwarp 'Emergency WARP disconnect completed for user %s'", 
                     username);
            system(logCmd);
            
            // Schedule auto-recovery with random delay between base and 2x base
            int randomDelay = reconnectBaseSeconds + (int)arc4random_uniform((uint32_t)(reconnectBaseSeconds + 1));
            int hours = randomDelay / 3600;
            int minutes = (randomDelay % 3600) / 60;
            int seconds = randomDelay % 60;
            
            // Enhanced logging for debugging
            printf("\n[+] Auto-recovery scheduling details:\n");
            printf("    Base time: %d seconds\n", reconnectBaseSeconds);
            printf("    Randomized delay: %d seconds\n", randomDelay);
            printf("    Will reconnect WARP and restart GUI application\n");
            printf("    Scheduled in: ");
            if (hours > 0) {
                printf("%d hour%s ", hours, hours == 1 ? "" : "s");
            }
            if (minutes > 0) {
                printf("%d minute%s ", minutes, minutes == 1 ? "" : "s");
            }
            if (seconds > 0 || (hours == 0 && minutes == 0)) {
                printf("%d second%s", seconds, seconds == 1 ? "" : "s");
            }
            printf("\n");
            
            // Create launchd plist for recovery
            char plistPath[256];
            snprintf(plistPath, sizeof(plistPath), "/tmp/com.bgwarp.recovery.%d.plist", getpid());
            
            FILE *plist = fopen(plistPath, "w");
            if (plist) {
                fprintf(plist, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
                fprintf(plist, "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n");
                fprintf(plist, "<plist version=\"1.0\">\n");
                fprintf(plist, "<dict>\n");
                fprintf(plist, "    <key>Label</key>\n");
                fprintf(plist, "    <string>com.bgwarp.recovery.%d</string>\n", getpid());
                fprintf(plist, "    <key>ProgramArguments</key>\n");
                fprintf(plist, "    <array>\n");
                fprintf(plist, "        <string>/bin/sh</string>\n");
                fprintf(plist, "        <string>-c</string>\n");
                fprintf(plist, "        <string>sleep %d; logger -t bgwarp 'Auto-recovery: starting WARP reconnect after %d seconds'; %s connect 2>&1 | logger -t bgwarp; logger -t bgwarp 'Auto-recovery: warp-cli connect returned $?'; sleep 2; open -a 'Cloudflare WARP' 2>&1 | logger -t bgwarp; logger -t bgwarp 'Auto-recovery: launched WARP GUI'; launchctl unload %s</string>\n", 
                        randomDelay, randomDelay, WARP_CLI_PATH, plistPath);
                fprintf(plist, "    </array>\n");
                fprintf(plist, "    <key>RunAtLoad</key>\n");
                fprintf(plist, "    <true/>\n");
                fprintf(plist, "    <key>AbandonProcessGroup</key>\n");
                fprintf(plist, "    <true/>\n");
                fprintf(plist, "</dict>\n");
                fprintf(plist, "</plist>\n");
                fclose(plist);
                
                // Load the launchd job
                char loadCmd[512];
                snprintf(loadCmd, sizeof(loadCmd), "launchctl load %s 2>/dev/null", plistPath);
                system(loadCmd);
                
                snprintf(logCmd, sizeof(logCmd), 
                         "logger -t bgwarp 'Auto-recovery scheduled: base=%ds, actual=%ds (%dh %dm %ds), pid=%d'", 
                         reconnectBaseSeconds, randomDelay, hours, minutes, seconds, getpid());
                system(logCmd);
                
                printf("    LaunchD job: com.bgwarp.recovery.%d\n", getpid());
                printf("    Plist location: %s\n", plistPath);
            }
        } else {
            printf("\n[TEST] Test mode completed. No actual commands were executed.\n");
            if (reconnectBaseSeconds != 7200) {
                printf("[TEST] Would use custom reconnect base time: %d seconds\n", reconnectBaseSeconds);
                int testRandomDelay = reconnectBaseSeconds + (int)arc4random_uniform((uint32_t)(reconnectBaseSeconds + 1));
                printf("[TEST] Example randomized delay would be: %d seconds\n", testRandomDelay);
            }
            printf("\nTo execute in a live incident, run with: --liveincident\n");
        }
        
        return 0;
    }
}
