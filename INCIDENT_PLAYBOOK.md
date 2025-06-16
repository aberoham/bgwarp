# bgwarp - Emergency WARP Disconnect Tool

This note contains sensitive information about emergency "break glass" tools. Knowledge and usage of such tools should be limited to incident responders.

## Overview

The `bgwarp` ("break glass" WARP) tool is an emergency utility for forcefully disconnecting Cloudflare WARP in the event of their control plane (API, dashboard, etc) is inaccessible or otherwise during an incident response process here Cloudflare Warp is getting in the way of operational recovery efforts.

### Tool Location

TODO: confirm best distribution location (may change based upon packaging or deployment method)

```
/usr/local/libexec/.bgwarp
```

### Safety Features
1. **Default Test Mode**: Tool runs in test mode by default, requiring `--liveincident` flag for actual operations
2. **Auto-Recovery**: Automatically attempts to reconnect WARP after 2-4 hours (randomized to prevent synchronized reconnections)

### When to Use

Use this tool **ONLY** when:
- Cloudflare WARP's API or in-situ administrative dashboard "break glass" methods are completely inaccessible
- WARP is causing network connectivity issues
- Normal disconnect methods have failed
- User cannot access work resources due to WARP malfunction

### Prerequisites

- macOS with Touch ID (modern Apple hardware with a secure enclave)
- Physical access to the affected machine
- User must authenticate with Touch ID or their local system password

---

## Usage Instructions

### Step 1: Open Terminal (Terminal app, iTerm2, Ghostty, etc)
- If you don't know how to open a terminal, you really shouldn't be using this tool.

### Step 2: Execute bgwarp

```bash
# LIVE INCIDENT - This will disconnect WARP
/usr/local/libexec/.bgwarp --liveincident
```

### Step 3: Authenticate
- Touch ID prompt will appear
- Place finger on Touch ID sensor
- If Touch ID fails, system password can be used as fallback

### Step 4: Wait for Completion
The tool will automatically:
1. Disconnect WARP
2. Delete WARP configuration
3. Terminate all WARP processes
4. Flush DNS cache
5. Reset network routes
6. Restart mDNSResponder
7. Schedule auto-recovery (2-4 hours later)

---

## Testing the Tool (Safe Mode)

The tool runs in test mode by default. To verify installation without affecting WARP:

```bash
# Default behavior is test mode - no commands will be executed
/usr/local/libexec/.bgwarp
```

Test mode will:
- Require Touch ID authentication (same as live mode)
- Verify setuid permissions are correct
- Check all required binaries exist
- Show what commands would be executed
- Display permission status for each operation
- NOT execute any actual commands

Example test output:
```
[TEST] Permission Status:
  - Real UID: 501
  - Effective UID: 0 (root)
  - Setuid bit: SET

[TEST] Binary Availability:
  ✓ /usr/local/bin/warp-cli - FOUND
  ✓ /usr/bin/pkill - FOUND
  ...

[TEST MODE] Would execute: /usr/local/bin/warp-cli disconnect
[TEST MODE] Permission check: PASS (euid=0, uid=501)
```

---

## What the Tool Does

1. **Authentication Check**: Requires Touch ID or password
2. **Logging**: Records action in system logs for audit
3. **WARP Disconnect**: Executes `warp-cli disconnect`
4. **Config Removal**: Executes `warp-cli delete`
5. **Process Termination**: Kills all WARP-related processes
6. **Network Cleanup**: 
   - Flushes DNS cache
   - Resets routing tables
   - Restarts mDNSResponder
7. **Auto-Recovery**: Schedules WARP reconnection after random 2-4 hour delay

---

## Post-Execution Steps

After running the tool:

1. **Verify Network Connectivity**
   ```bash
   ping 8.8.8.8
   curl https://cloudflare.com
   ```

2. **Reconnect to Corporate Network**
   - May need to manually reconnect to VPN
   - Verify access to internal resources

3. **Document the Incident**
   - Record timestamp of execution
   - Note the reason for using emergency tool
   - File incident report

4. **Check System Logs**
   ```bash
   # View emergency tool usage
   log show --predicate 'subsystem == "bgwarp"' --last 1h
   ```

5. **Monitor Auto-Recovery**
   - Tool will attempt to reconnect WARP after 2-4 hours
   - Check logs for recovery attempts
   - Manual intervention may be needed if auto-recovery fails

---

## Recovery Instructions

To reinstall WARP after incident resolution:

1. Download WARP client from IT portal
2. Run standard installation process
3. Re-authenticate with corporate credentials
4. Verify connectivity to internal resources

---

## Security Notes

- Tool requires root privileges via setuid
- All usage is logged to system logs
- Touch ID authentication prevents unauthorized use
- Binary is hidden from normal directory listings
- Should only be documented in incident playbooks

---

## Troubleshooting

### Touch ID Not Working
- Tool will fall back to password authentication
- Ensure Touch ID is enrolled in System Preferences

### Tool Not Found
```bash
# Verify installation
ls -la /usr/local/libexec/.bgwarp
```

### Disable Auto-Recovery
If you need to prevent the scheduled reconnection:
```bash
# List scheduled recovery jobs
launchctl list | grep bgwarp.recovery

# Unload specific recovery job
launchctl unload /tmp/com.bgwarp.recovery.*.plist
```

### Permission Denied
- Tool must be installed with proper setuid permissions
- Contact IT security team for reinstallation

---

## Contact Information

For issues with this tool:
- IT Security Team: [REDACTED]
- Network Operations: [REDACTED]
- Incident Response: [REDACTED]

---

**Last Updated**: [TIMESTAMP]
**Tool Version**: 1.0
**Classification**: CONFIDENTIAL - INCIDENT RESPONSE ONLY
