# CLAUDE.md - Project Context for unwarp

## Project Overview
unwarp is an emergency tool for macOS that allows IT administrators to forcefully disconnect Cloudflare WARP during outages when the dashboard is inaccessible. It uses Touch ID authentication and setuid privileges for secure operation. A sample, unfinished Windows port exits within the subdirectory windows-port-sample/.

## Key Design Principles

### 1. Safety First
- **Default to test mode**: The tool runs in test mode by default, requiring an explicit `--liveincident` flag for destructive operations
- **Touch ID required**: Authentication is mandatory even in test mode to ensure the full auth flow is tested
- **Auto-recovery**: Implements automatic WARP reconnection after 2-4 hours with randomised timing to prevent synchronised reconnections

### 2. Security Architecture
- **Setuid binary**: Installed with root:wheel ownership and 4755 permissions
- **Hidden location**: Installed at `/usr/local/libexec/.unwarp` (note the dot prefix)
- **LocalAuthentication framework**: Uses macOS native Touch ID with local password fallback
- **Audit logging**: All operations logged to system logs via `logger` command

### 3. Naming Conventions
- **Binary name**: `unwarp` - short name for emergency WARP disconnect
- **Log tag**: Use `unwarp` for all logger calls
- **Recovery jobs**: Named as `com.unwarp.recovery.{PID}` for uniqueness

## Code Style Guidelines

### Objective-C Specifics
- Use `static` for all internal functions to prevent external linkage
- Function prototypes should include `(void)` for parameterless functions
- Format specifiers: Use `%u` for `uid_t` and `gid_t` types (not `%d`)
- Avoid variable shadowing in blocks (rename `error` to `authError` in callbacks)

### Build Configuration
```bash
clang -framework Foundation \
      -framework LocalAuthentication \
      -framework Security \
      -fobjc-arc \
      -O2 \
      -Weverything \
      -Wno-padded \
      -Wno-gnu-statement-expression \
      -Wno-poison-system-directories \
      -Wno-declaration-after-statement \
      -o unwarp \
      unwarp.m
```

### Error Handling Philosophy
- Continue execution even if individual commands fail
- Log failures but don't stop the recovery process
- Provide clear feedback about what would happen in test mode

## Implementation Details

### Touch ID Authentication
- Always attempt Touch ID first
- Fall back to password if Touch ID unavailable
- Use dispatch semaphores for synchronous authentication flow
- Clear error messages for authentication failures

### Auto-Recovery Mechanism
```c
// Random delay between 2-4 hours
int randomDelay = 7200 + arc4random_uniform(7201); // 7200-14400 seconds
```
- Uses `arc4random_uniform()` for cryptographically secure randomness
- Creates temporary launchd plist in `/tmp/`
- Self-cleaning job that unloads itself after execution
- Unique job names using PID to prevent conflicts

### Command Execution Pattern
```c
static int executeCommand(const char *command, char *output, size_t outputSize) {
    if (!liveMode) {
        printf("[TEST MODE] Would execute: %s\n", command);
        // Show permission checks for privileged commands
        if (strstr(command, "sudo") != NULL || strstr(command, "pkill") != NULL) {
            printf("[TEST MODE] Permission check: %s (euid=%u, uid=%u)\n", 
                   geteuid() == 0 ? "PASS" : "FAIL", geteuid(), getuid());
        }
        return 0; // Simulate success in test mode
    }
    // ... actual execution code
}
```

## Testing Commands

### Build and Test
```bash
./build.sh                          # Compile the tool
./unwarp                           # Test without setuid (will fail)
sudo ./install.sh                  # Install with proper permissions
/usr/local/libexec/.unwarp         # Run in test mode (default)
/usr/local/libexec/.unwarp --liveincident  # Live mode (destructive)
```

### Verification
```bash
# Check logs
log show --predicate 'subsystem == "unwarp"' --last 1h

# List recovery jobs
launchctl list | grep unwarp.recovery

# Manual recovery disable
launchctl unload /tmp/com.unwarp.recovery.*.plist
```

## Important Notes

1. **Never create files proactively** - especially documentation or README files
2. **Maintain existing code style** - this project uses specific formatting for banners and output
3. **Test mode is default** - this prevents accidental execution
4. **Hidden installation** - the dot prefix in `.unwarp` is intentional for security by obscurity

## Future Considerations

- The auto-recovery mechanism could be enhanced with retry logic
- Network state validation could be added before attempting reconnection
