# Windows Port Planning Document for bgwarp

## Executive Summary

This document outlines the plan to port the bgwarp (break glass WARP) utility from macOS to Windows. After analyzing the codebase and researching cross-platform approaches used by similar utilities (including Cloudflare's own tools), we recommend creating a separate Windows-specific implementation rather than attempting to share code between platforms.

## Current macOS Implementation Overview

The macOS version of bgwarp is a 1,100-line Objective-C program that:
- Uses Touch ID authentication via LocalAuthentication framework
- Runs as a setuid binary for privilege escalation
- Forcefully disconnects Cloudflare WARP during outages
- Implements auto-recovery with randomized reconnection delays (2-4 hours)
- Includes comprehensive security controls (rate limiting, signal blocking, etc.)

## Windows Architecture Proposal

### Fundamental Differences

Windows lacks several macOS constructs that bgwarp relies on:
- **No setuid binaries**: Windows uses different privilege models
- **No Touch ID framework**: Windows Hello provides biometric authentication
- **No launchd**: Windows Task Scheduler handles scheduled tasks
- **Different network stack**: Network commands and APIs differ completely

### Recommended Architecture: Service/Client Model

```
┌─────────────────────┐     Named Pipe IPC    ┌─────────────────────┐
│   BgwarpClient.exe  │◄──────────────────────►│  BgwarpService.exe  │
│  (User Interface)   │                        │   (SYSTEM Service)  │
│ - Windows Hello Auth│                        │ - WARP Operations   │
│ - User Interaction  │                        │ - Network Recovery  │
│ - Rate Limiting     │                        │ - Privileged Actions│
└─────────────────────┘                        └─────────────────────┘
```

### Technology Stack

**Language Options:**
1. **C# (.NET)** - Recommended
   - Native Windows Hello API support
   - Excellent Windows Service framework
   - Strong security features
   - Easier maintenance

2. **C++** - Alternative
   - Smaller binary size
   - Direct Win32 API access
   - More complex development

**Key Components:**
- **Authentication**: Windows Hello for Business API
- **IPC**: Named Pipes with encryption
- **Scheduling**: Windows Task Scheduler API
- **Logging**: Windows Event Log (Application log)
- **Installer**: MSI package for enterprise deployment

## Feature Mapping

| macOS Feature | Windows Equivalent | Complexity |
|--------------|-------------------|------------|
| Touch ID auth | Windows Hello API | High |
| setuid binary | Windows Service | High |
| launchd scheduling | Task Scheduler | Medium |
| syslog logging | Event Log | Low |
| Network commands | netsh/PowerShell | Medium |
| Signal blocking | Service isolation | Low |
| File permissions | Windows ACLs | Medium |

## Implementation Plan

### Phase 1: Core Service (Weeks 1-3)
1. Create Windows Service project structure
2. Implement service installation/uninstallation
3. Add named pipe server for IPC
4. Implement WARP detection logic
5. Create network recovery functions

### Phase 2: Client Application (Weeks 4-5)
1. Create WPF or Console client application
2. Integrate Windows Hello authentication
3. Implement named pipe client
4. Add rate limiting logic
5. Create user interface for test/live modes

### Phase 3: Security Features (Weeks 6-7)
1. Implement authentication timeout (30 seconds)
2. Add console user verification
3. Create audit logging to Event Log
4. Implement environment sanitization
5. Add anti-tampering protections

### Phase 4: Auto-Recovery (Week 8)
1. Create Task Scheduler integration
2. Implement randomized delay (2-4 hours)
3. Add recovery task self-deletion
4. Create recovery status checking

### Phase 5: Deployment (Weeks 9-10)
1. Create MSI installer package
2. Add Group Policy templates
3. Write enterprise deployment guide
4. Create PowerShell deployment scripts
5. Implement silent installation options

## Security Considerations

### Windows-Specific Security Features
1. **Service Hardening**
   - Run with minimal privileges
   - Disable network access
   - Use service isolation

2. **Authentication**
   - Require physical presence (no RDP)
   - Implement secure credential storage
   - Use Windows Credential Manager

3. **Code Signing**
   - Sign all binaries with EV certificate
   - Implement installer signature verification

4. **Audit Trail**
   - Log all operations to Security event log
   - Include user SID and session information
   - Track parent process information

## Development Requirements

### Environment Setup
- Windows 10/11 development machine
- Visual Studio 2022 or later
- Windows SDK
- Administrative privileges for testing

### Testing Requirements
- Multiple Windows versions (10, 11, Server 2019/2022)
- Domain and non-domain environments
- Various WARP configurations
- Windows Hello hardware (or TPM for testing)

## Project Structure

```
bgwarp-windows/
├── src/
│   ├── BgwarpService/      # Windows Service project
│   ├── BgwarpClient/       # Client application
│   ├── BgwarpCommon/       # Shared utilities
│   └── BgwarpInstaller/    # MSI installer project
├── tests/
│   ├── ServiceTests/
│   ├── ClientTests/
│   └── IntegrationTests/
├── docs/
│   ├── deployment-guide.md
│   ├── security-model.md
│   └── troubleshooting.md
└── scripts/
    ├── install.ps1
    ├── uninstall.ps1
    └── test-deployment.ps1
```

## Success Criteria

1. **Feature Parity**: All macOS features work on Windows
2. **Security**: Meets or exceeds macOS security controls
3. **Reliability**: 99.9% success rate for disconnect operations
4. **Performance**: Authentication completes within 5 seconds
5. **Compatibility**: Works on Windows 10+ and Server 2019+

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Windows Hello unavailable | High | Implement password fallback |
| Service fails to start | High | Add automatic recovery |
| Network detection differs | Medium | Test multiple WARP versions |
| GPO conflicts | Medium | Document policy requirements |
| Anti-virus false positives | Low | Pre-submit to major vendors |

## Alternative Approaches Considered

### 1. Shared Codebase with Go
- **Pros**: Single codebase, cloudflared uses this approach
- **Cons**: Limited Windows Hello support, larger binary size
- **Decision**: Rejected due to authentication limitations

### 2. PowerShell Script
- **Pros**: No compilation needed, easy deployment
- **Cons**: Security concerns, requires execution policy changes
- **Decision**: Rejected due to enterprise security policies

### 3. Electron/Node.js Application
- **Pros**: Cross-platform UI, web technologies
- **Cons**: Large deployment size, privilege escalation issues
- **Decision**: Rejected due to security and size concerns

## Conclusion

Creating a separate Windows-specific implementation of bgwarp is the recommended approach. While this requires maintaining two codebases, it allows each version to fully leverage platform-specific security features and provides the best user experience on each operating system.

The Windows version will achieve functional parity with the macOS version while respecting Windows security models and enterprise deployment requirements. The service/client architecture actually provides better privilege separation than the macOS setuid approach, making it arguably more secure.

## Next Steps

1. Review and approve this planning document
2. Set up Windows development environment
3. Create bgwarp-windows repository
4. Begin Phase 1 implementation
5. Schedule weekly progress reviews

## Appendix: Sample Code Structure

### Service Communication Protocol
```csharp
// Message format for named pipe communication
public class BgwarpMessage {
    public string Command { get; set; }  // "disconnect", "status", "recover"
    public bool TestMode { get; set; }
    public string UserSid { get; set; }
    public DateTime Timestamp { get; set; }
    public byte[] AuthToken { get; set; }
}
```

### Windows Hello Authentication
```csharp
// Simplified authentication flow
public async Task<bool> AuthenticateUser() {
    var result = await WindowsHelloAuthentication.RequestVerificationAsync(
        "Bgwarp requires authentication to disconnect WARP");
    
    if (result == UserConsentVerificationResult.Verified) {
        LogAuthentication(true);
        return true;
    }
    
    // Fall back to password
    return await FallbackPasswordAuth();
}
```

### Task Scheduler Integration
```csharp
// Schedule recovery task
public void ScheduleRecovery(int delaySeconds) {
    using (TaskService ts = new TaskService()) {
        TaskDefinition td = ts.NewTask();
        td.RegistrationInfo.Description = "Bgwarp WARP Recovery";
        td.Principal.RunLevel = TaskRunLevel.Highest;
        
        td.Triggers.Add(new TimeTrigger {
            StartBoundary = DateTime.Now.AddSeconds(delaySeconds),
            Enabled = true
        });
        
        td.Actions.Add(new ExecAction("bgwarp.exe", "--recover"));
        td.Settings.DeleteExpiredTaskAfter = TimeSpan.FromMinutes(5);
        
        ts.RootFolder.RegisterTaskDefinition(
            $"BgwarpRecovery_{Process.GetCurrentProcess().Id}", 
            td);
    }
}
```
