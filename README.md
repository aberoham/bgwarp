# unwarp

Emergency disconnect tool for Cloudflare WARP on macOS. Enables privileged incident responders to forcefully disconnect WARP during outages when the control and/or data plane are unresponsive.

## What running unwarp does

After interactive local authentication, `unwarp` immediately disconnects WARP by executing these commands:

```bash
warp-cli disconnect
killall -9 'Cloudflare WARP'
killall -9 warp-svc
killall -9 warp-taskbar
dscacheutil -flushcache
route -n flush
killall -HUP mDNSResponder
```
After disconnection, `unwarp` further schedules an automatic WARP service reconnection to occur in a few hours, hopefully after the precipitating incident has been resolved. The reconnect timeout includes a randomised offset to avoid mass simultaneous reconnections across all users.

## ⚠️ Important Notice

This tool is designed for advanced incident responders with physical device access. It requires Touch ID or password authentication at runtime and can only be installed with administrator privileges or via MDM.

## Features

- Touch ID or password authentication
- Test mode by default (requires `--liveincident` flag for actual disconnect)
- Automatic local network connectivity recovery after WARP disconnect
- Configurable auto-reconnection with randomised delays
- WARP taskbar GUI restart after reconnection
- Comprehensive logging for operational analysis and usage introspection by other security tools

## Requirements

- macOS 10.x or later (Intel or Apple Silicon)
- Cloudflare WARP client installed
- MDM or administrator privileges for installation
- Physical access to device (Touch ID or password via live terminal)

## Architecture Support

`unwarp` is distributed as a universal binary that runs natively on:
- Intel-based Macs (x86_64)
- Apple Silicon Macs (arm64/M1/M2/M3)

Pre-built releases include:
- **Universal packages** - Recommended for most deployments (works on all Mac architectures)
- **Architecture-specific packages** - Available for environments requiring single-architecture binaries
- **Raw binaries** - For manual installation or custom deployment workflows

## Installation

### Method 1: Build from Source

Prerequisites:
- Xcode Command Line Tools (`xcode-select --install`)
- Administrator privileges

```bash
# Clone the repository
git clone https://github.com/aberoham/unwarp.git
cd unwarp

# Build the tool
./build.sh

# Install with administrator privileges
sudo ./install.sh
```

`unwarp` will be installed to `/usr/local/libexec/.unwarp` with setuid root permissions.

### Method 2: Enterprise Deployment (JAMF/MDM)

For organizations using JAMF Pro or similar MDM solutions:

1. Download a pre-built package from the [latest release](https://github.com/aberoham/unwarp/releases/latest):
   - **Recommended**: `unwarp-X.X.X.X-universal.pkg` (works on all Mac architectures)
   - Alternative: Architecture-specific packages for Intel or Apple Silicon

2. Upload the package to your MDM distribution point

3. Deploy to incident responders' managed devices following your organization's deployment procedures

See [packaging/JAMF_DEPLOYMENT.md](packaging/JAMF_DEPLOYMENT.md) for detailed JAMF Pro deployment instructions.

## Usage

### Test Mode (Default)
```bash
# Test mode (default) - preview without disconnecting
/usr/local/libexec/.unwarp
```

### Live Incident Mode
```bash
# Execute during an actual incident
/usr/local/libexec/.unwarp --liveincident

# With custom reconnection time (5 minutes)
/usr/local/libexec/.unwarp --liveincident --reconnect 300
```

### Options

- `--liveincident` - Execute in live mode (performs actual disconnection)
- `--reconnect <seconds>` - Set reconnect base time in seconds (60-43200, default: 7200)
- `--help` - Display help information

## Debugging

View unwarp logs:
```bash
log show --predicate 'process == "logger" AND eventMessage CONTAINS "unwarp"' --last 1h
```

List active recovery jobs:
```bash
launchctl list | grep unwarp.recovery
```

Check binary architecture:
```bash
# Check installed binary
lipo -info /usr/local/libexec/.unwarp

# Check version and architecture
/usr/local/libexec/.unwarp --version
```

## Contributing

We welcome all feedback and contributions. Please fork the repo, create a feature branch (`git checkout -b feature/improvement`), 
use clear commit messages and submit a PR.

### Guidelines

- Maintain the security model (emphasis on Touch ID or similar secure local auth)
- Test thoroughly in test mode and consider including anonymised logs in the PR thread to help speed up evaluation
- Document any new command-line options following the existing convention of in-situ `--help`
- Follow existing code style and conventions, beware of AI slop

## Security

As a tool to forcefully remove a control while operating as a privileged user, `unwarp` has significant security implications.

- **Setuid binary**: Only runs with root privileges when absolutely needed
- **Touch ID requirement**: Attempts to ensure physical presence
- **Obscure, hidden installation**: Attempts to reduce surface area for misuse
- **Test mode default**: Prevents accidental execution

If you discover a security issue, please report it privately to the maintainers.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

Thank you to the Cloudflare team for their work on WARP and for [incident response scenarios](https://www.cloudflarestatus.com/incidents/25r9t0vz99rp) that motivated this tool's development.
