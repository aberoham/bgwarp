# Cloudflare Warp local Break Glass

## Architecture & Task Description

### Problem Context
During Cloudflare outages, administrators lose access to the Zero Trust dashboard and cannot trigger global WARP override. Local WARP clients maintain connections, preventing users from accessing resources.

### Key Constraints
- End users lack sudo/admin privileges
- Standard privilege escalation uses external JAMF dependencies (too slow during incidents)
- Must preserve existing security controls for routine admin access
- Incident responders have physical access to devices with Touch ID

### Solution Architecture

**Component 1: Local Emergency Disconnect**
- Setuid binary requiring Touch ID authentication
- Uses macOS LocalAuthentication framework with Secure Enclave
- Bypasses normal privilege escalation paths
- Hidden installation path for incident responders only

**Component 2: Network Cleanup Sequence**
```
1. warp-cli disconnect
2. warp-cli delete
3. killall "Cloudflare WARP"
4. dscacheutil -flushcache
5. Route table restoration
```

**Component 3: API Fallback**
```
PATCH /client/v4/accounts/{account_id}/devices/settings
{"warp_override": true}
```

### Implementation Requirements
- Objective-C for LocalAuthentication integration
- LAPolicyDeviceOwnerAuthenticationWithBiometrics policy
- Synchronous authentication before privilege escalation
- Compiled binary (not interpretable script)
- No external dependencies beyond system frameworks

This creates an emergency bypass specifically for incident response without weakening day-to-day security controls.
