# JAMF Pro Deployment Guide for bgwarp Emergency Tool

## Overview

This guide provides step-by-step instructions for deploying the bgwarp emergency tool through JAMF Pro. The bgwarp tool is an emergency utility that allows authorized IT staff to disconnect Cloudflare WARP when normal administrative access is unavailable.

**Important**: This tool should only be deployed to designated incident response personnel, not to all users.

## Getting the Package

Download pre-built packages from the [bgwarp releases page](https://github.com/aberoham/bgwarp/releases/latest). Choose the appropriate package for your deployment:
- **Universal package** (recommended): Works on all Mac architectures
- **Architecture-specific packages**: Available if your environment requires single-architecture binaries

## Prerequisites

- JAMF Pro administrator access
- A bgwarp installer package downloaded from [GitHub Releases](https://github.com/aberoham/bgwarp/releases/latest)
  - Recommended: `bgwarp-X.X.X.X-universal.pkg` (works on all Mac architectures)
  - Alternative: Architecture-specific packages if required by your environment
- A distribution point configured in JAMF Pro
- A Smart Group for targeting incident response staff

## Step 1: Upload the Package to JAMF

1. Log in to JAMF Pro
2. Navigate to **Computer Management** → **Packages**
3. Click **New**
4. Fill in the package information:
   - **Display Name**: bgwarp Emergency Tool
   - **Filename**: Use the package filename from GitHub (e.g., bgwarp-2025.6.1.0-universal.pkg)
   - **Category**: Utilities (or create an "Emergency Tools" category)
   - **Info**: Emergency tool for disconnecting Cloudflare WARP
   - **Notes**: Only for incident response personnel
   - **Package ID**: com.github.aberoham.bgwarp (or your organization's identifier)
5. Click **Save**
6. Upload the package file when prompted

## Step 2: Create a Smart Group for Incident Response Staff

1. Navigate to **Computer Management** → **Smart Computer Groups**
2. Click **New**
3. Configure the Smart Group:
   - **Display Name**: Incident Response Computers
   - **Criteria**: Choose one of these options:
     - **Option A**: Username is [list of incident response usernames]
     - **Option B**: Department is "IT Security" or "Infrastructure"
     - **Option C**: Computer Name contains specific patterns
     - **Option D**: Static group membership (manually maintained)
4. Click **Save**

## Step 3: Create the Deployment Policy

1. Navigate to **Computer Management** → **Policies**
2. Click **New**
3. Configure the policy:

### General Tab
- **Display Name**: Deploy bgwarp Emergency Tool
- **Enabled**: Yes
- **Category**: Utilities
- **Trigger**: Check-in (or Self Service if preferred)
- **Execution Frequency**: Once per computer

### Packages Tab
1. Click **Configure**
2. Add the bgwarp package
3. Set **Action** to "Install"

### Scope Tab
1. Click **Configure**
2. Under **Target Computers**, add your "Incident Response Computers" Smart Group
3. Leave **Limitations** and **Exclusions** empty unless needed

### Self Service Tab (Optional)
If you want users to install on-demand:
1. Check **Make the policy available in Self Service**
2. Set **Display Name**: Install bgwarp Emergency Tool
3. Add **Description**: 
   ```
   Installs the bgwarp emergency tool for disconnecting Cloudflare WARP 
   during network incidents. This tool requires Touch ID authentication 
   and should only be used during confirmed WARP outages.
   ```
4. Set **Category**: Emergency Tools
5. Add an icon if desired

### Options Tab
1. Under **Files and Processes**, you can add:
   - **Execute Command**: 
     ```bash
     /usr/bin/logger -t bgwarp "Emergency tool deployed via JAMF to $(whoami)"
     ```

4. Click **Save**

## Step 4: Testing the Deployment

1. Add a test computer to your Smart Group
2. Run `sudo jamf policy` on the test computer or wait for check-in
3. Verify installation:
   ```bash
   ls -la /usr/local/libexec/.bgwarp
   ```
   Should show: `-rwsr-xr-x  1 root  wheel  [size] [date] .bgwarp`

## Step 5: Monitoring and Compliance

### Creating an Extension Attribute
To track which computers have bgwarp installed:

1. Navigate to **Computer Management** → **Extension Attributes**
2. Click **New**
3. Configure:
   - **Display Name**: bgwarp Installed
   - **Data Type**: String
   - **Input Type**: Script
   - **Script**:
     ```bash
     #!/bin/bash
     if [ -f "/usr/local/libexec/.bgwarp" ]; then
         echo "<result>Installed</result>"
     else
         echo "<result>Not Installed</result>"
     fi
     ```

### Creating a Compliance Report
1. Navigate to **Computer Management** → **Advanced Computer Searches**
2. Create a search for:
   - Criteria: "bgwarp Installed" is "Installed"
   - Display fields: Computer Name, Username, Last Check-in

## Usage Instructions for End Users

Once deployed, provide these instructions to your incident response team:

### During a WARP Outage

1. Open Terminal
2. Run the emergency tool:
   ```
   /usr/local/libexec/.bgwarp --liveincident
   ```
3. Authenticate with Touch ID when prompted
4. The tool will:
   - Disconnect WARP
   - Clear network issues
   - Schedule automatic reconnection in 2-4 hours

### Testing the Tool
To verify the tool works without making changes:
```
/usr/local/libexec/.bgwarp
```
(This runs in test mode and shows what would happen)

## Security Considerations

- **Limited Deployment**: Only deploy to authorized incident response staff
- **Audit Trail**: All usage is logged to system logs
- **Authentication Required**: Touch ID or password required for every use
- **Hidden Location**: Tool is installed in a hidden location (note the dot in `.bgwarp`)
- **Automatic Recovery**: WARP automatically reconnects after 2-4 hours

## Troubleshooting

### Package Installation Fails
- Check JAMF distribution point connectivity
- Verify package uploaded correctly
- Review `/var/log/jamf.log` on client

### Permissions Not Set Correctly
- The postinstall script should set permissions automatically
- If needed, create a policy to run:
  ```bash
  chown root:wheel /usr/local/libexec/.bgwarp
  chmod 4755 /usr/local/libexec/.bgwarp
  ```

### Tool Not Working
- Verify Touch ID is enabled on the device
- Check system logs: `log show --predicate 'subsystem == "bgwarp"' --last 1h`
- Ensure user is physically at the computer (not remote)

## Support

For issues with:
- **JAMF deployment**: Contact your JAMF administrator
- **bgwarp tool itself**: Review logs and contact your security team
- **WARP connectivity**: Follow standard WARP troubleshooting procedures