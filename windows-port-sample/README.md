# Windows Port Sample for bgwarp

This directory contains sample C# code demonstrating how bgwarp could be ported to Windows. The implementation consists of two main components:

## Architecture Overview

### 1. BgwarpService.cs
A Windows Service that runs with SYSTEM privileges and handles the actual WARP disconnection operations. Key features:
- Runs continuously in the background
- Listens on a named pipe for commands
- Handles privileged operations (process termination, network reset)
- Implements auto-recovery scheduling via Task Scheduler

### 2. BgwarpClient.cs
A command-line client application that users run to trigger emergency disconnect. Key features:
- Handles Windows Hello authentication
- Enforces console-only access (no remote sessions)
- Implements rate limiting to prevent brute force
- Communicates with service via named pipe

## Key Differences from macOS Version

### Authentication
- **macOS**: LocalAuthentication framework with Touch ID
- **Windows**: Windows Hello API with credential dialog fallback
- **Note**: The Windows Hello API requires UWP/WinRT, so a full implementation would need additional work

### Privilege Model
- **macOS**: Setuid binary with privilege dropping
- **Windows**: Service/client architecture with named pipe IPC
- **Benefit**: Better privilege separation on Windows

### Process Management
- **macOS**: `killall` command
- **Windows**: Process API with explicit process name matching

### Network Recovery
- **macOS**: Unix commands (`ifconfig`, `route`, `dscacheutil`)
- **Windows**: Windows-specific commands (`ipconfig`, `netsh`) and WMI

### Scheduling
- **macOS**: launchd plist files
- **Windows**: Task Scheduler XML tasks

### Logging
- **macOS**: syslog and logger command
- **Windows**: Windows Event Log API

## Security Considerations

1. **Named Pipe Security**: The pipe is configured to only allow Administrators and SYSTEM
2. **Console Session Check**: Uses WTSGetActiveConsoleSessionId to ensure physical presence
3. **Rate Limiting**: Stored in registry with per-user isolation
4. **Audit Trail**: All operations logged to Windows Event Log

## Building and Deployment

### Prerequisites
- .NET 6.0 or later
- Windows SDK for Windows Hello APIs
- Administrator privileges for installation

### Build Commands
```powershell
# Build the service
dotnet build BgwarpService.cs -o bin\Service

# Build the client
dotnet build BgwarpClient.cs -o bin\Client
```

### Installation
```powershell
# Install the service
sc create BgwarpEmergencyService binPath= "C:\Path\To\BgwarpService.exe"
sc config BgwarpEmergencyService start= auto
sc start BgwarpEmergencyService

# Copy client to system directory
copy bin\Client\bgwarp.exe C:\Windows\System32\
```

## Usage

### Test Mode (default)
```cmd
bgwarp.exe
```

### Live Mode
```cmd
bgwarp.exe --liveincident
```

### Custom Reconnect Time
```cmd
bgwarp.exe --liveincident --reconnect 300
```

## Limitations of This Sample

1. **Windows Hello**: The authentication code is simplified and would need proper P/Invoke declarations
2. **Credential Dialog**: Password fallback is not fully implemented
3. **Error Handling**: Production code would need more robust error handling
4. **Installer**: Would need a proper MSI installer for deployment
5. **Code Signing**: Binaries should be signed with a code certificate

## Next Steps for Production Implementation

1. **Complete Windows Hello Integration**: Implement full biometric authentication
2. **Credential Provider**: Add proper password authentication fallback
3. **Service Installer**: Create MSI package with WiX Toolset
4. **Enhanced Security**: Add mutual authentication for named pipe
5. **Testing**: Comprehensive testing on various Windows versions
6. **Documentation**: Create detailed deployment and troubleshooting guides

