# bgwarp - "Break Glass WARP"

Emergency disconnect tool for Cloudflare WARP on macOS. Enables privileged incident responders to forcefully disconnect WARP during outages when the Cloudflare WARP control and/or data plane are misbehaving.

## What bgwarp Does

After authentication, `bgwarp` immediately disconnects WARP by executing these commands:

```bash
warp-cli disconnect
killall -9 'Cloudflare WARP'
killall -9 warp-svc
killall -9 warp-taskbar
dscacheutil -flushcache
route -n flush
killall -HUP mDNSResponder
```
After disconnection, `bgwarp` schedules an automatic WARP service reconnection to occur in a few hours, hopefully after the precipitating incident has been resolved. The reconnect timeout includes a random offset to avoid mass simultaneous reconnections across your fleet.

## ⚠️ Important Notice

This tool is designed for advanced incident responders with physical device access. It requires Touch ID or password authentication at runtime and can only be installed with administrator privileges.

## Features

- Touch ID authentication with password fallback
- Safe test mode by default (requires `--liveincident` flag to trigger a real disconnect)
- Automatic local network connectivity recovery after WARP disconnect
- Configurable auto-reconnection with randomized delays
- WARP taskbar GUI restart after reconnection
- Comprehensive logging for operational analysis and usage introspection by other security tools

## Requirements

- macOS 10.x or later
- Cloudflare WARP client installed
- Administrator privileges for installation
- Physical access to device (Touch ID)

## Installation from Source

```bash
# Clone the repository
git clone https://github.com/aberoham/bgwarp.git
cd bgwarp

# Build the tool
./build.sh

# Install with administrator privileges
sudo ./install.sh
```

`bgwarp` will be installed to `/usr/local/libexec/.bgwarp` with setuid root permissions.

## Usage

### Test Mode (Default)
```bash
# Run in test mode to see what would happen
/usr/local/libexec/.bgwarp
```

### Live Incident Mode
```bash
# Execute during an actual incident
/usr/local/libexec/.bgwarp --liveincident

# With custom reconnection time (5 minutes)
/usr/local/libexec/.bgwarp --liveincident --reconnect 300
```

### Options

- `--liveincident` - Execute in live mode (performs actual disconnection)
- `--reconnect <seconds>` - Set reconnect base time in seconds (60-43200, default: 7200)
- `--help` - Display help information

## Debugging

View bgwarp logs:
```bash
log show --predicate 'process == "logger" AND eventMessage CONTAINS "bgwarp"' --last 1h
```

List active recovery jobs:
```bash
launchctl list | grep bgwarp.recovery
```

## Contributing

We welcome all feedback and contributions. Please fork the repo, create a feature branch (`git checkout -b feature/improvement`), use clear commit messages and submit a PR.

### Guidelines

- Maintain the security model (emphasis on Touch ID or similar secure local auth)
- Test thoroughly in test mode and consider including anonymized logs in the PR thread to help speed up evaluation
- Document any new command-line options following the existing convention of in-situ `--help`
- Follow existing code style and conventions, beware of AI slop

## Security

As a tool to forcefully remove a control while operating as a privileged user, `bgwarp` has significant security implications.

- **Setuid binary**: Only runs with root privileges when absolutely needed
- **Touch ID requirement**: Attempts to ensure physical presence
- **Obscure, hidden installation**: Attempts to reduce surface area for misuse
- **Test mode default**: Prevents accidental execution

If you discover a security issue, please report it privately to the maintainers.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

Thank you to Cloudflare's Worker KV team for [giving us an excuse](https://www.cloudflarestatus.com/incidents/25r9t0vz99rp) to use Claude Opus-4 via `claude` and install setuid binaries on our worldwide fleet of macOS laptops.
