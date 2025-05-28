# panini-rebooter

# Panini Everest Engine Manager

A comprehensive shell script for managing the Panini Everest Engine service on macOS. This script provides easy start, stop, restart, and status checking functionality for the Panini document scanning service.

## Features

- **Start Service**: Intelligently starts the service if not running
- **Stop Service**: Gracefully stops the service with aggressive fallback killing
- **Restart Service**: Complete stop and start cycle for troubleshooting
- **Status Check**: Comprehensive status reporting of all components
- **Interactive Menu**: User-friendly menu interface
- **Debug Mode**: Detailed logging for troubleshooting
- **Timeout Protection**: Prevents hanging on unresponsive services

## Prerequisites

- macOS with Mono Framework installed
- Panini Everest Engine installed in `/usr/local/bin/everestengine/`
- LaunchDaemon configured at `/Library/LaunchDaemons/com.panini.everestengine.plist`
- Administrator privileges (script requires `sudo`)

## Installation

1. Clone or download the script:
   ```bash
   git clone <repository-url>
   cd panini-rebooter
   ```

2. Make the script executable:
   ```bash
   chmod +x panini-rebooter.sh
   ```

## Usage

### Interactive Mode
Run the script without parameters to access the interactive menu:
```bash
sudo ./panini-rebooter.sh
```

This will display:
```
Panini Everest Engine Manager
=============================
1) Start service
2) Stop service
3) Restart service
4) Check status
5) Exit

Please select an option (1-5):
```

### Command Line Mode
Run specific actions directly:

```bash
# Start the service
sudo ./panini-rebooter.sh start

# Stop the service
sudo ./panini-rebooter.sh stop

# Restart the service (recommended for troubleshooting)
sudo ./panini-rebooter.sh restart

# Check service status
sudo ./panini-rebooter.sh status
```

### Debug and Verbose Options
Add debugging information to any command:

```bash
# Enable debug logging
sudo ./panini-rebooter.sh restart --debug

# Enable verbose output
sudo ./panini-rebooter.sh start --verbose

# Enable both debug and verbose
sudo ./panini-rebooter.sh stop --debug --verbose
```

## What Each Command Does

### Start
- Checks if the service is already running and responding
- If running but not responding, performs a clean restart
- Ensures LaunchDaemon is properly loaded
- Waits up to 60 seconds for service to become responsive
- Reports success or failure with detailed status

### Stop
- Attempts graceful shutdown via LaunchDaemon unload
- Waits 10 seconds for graceful shutdown
- If graceful shutdown fails, aggressively kills:
  - All `everestengine` processes
  - All Mono processes running Panini executables
  - All processes using the Panini directory
  - All processes listening on port 44343
- Provides detailed feedback on what was killed

### Restart
- Performs a complete stop operation
- Waits for system to settle (5 seconds)
- Performs a complete start operation
- Most reliable option for resolving service issues

### Status
- **Mono Installation**: Checks if Mono Framework is installed
- **Process Status**: Verifies if Panini processes are running
- **Service Status**: Tests if the web service responds on port 44343
- **LaunchDaemon Status**: Shows LaunchDaemon load status and PID
- **Process Details**: (Debug mode) Shows detailed process information

## Troubleshooting

### Service Not Responding
If the process is running but the service isn't responding:
```bash
sudo ./panini-rebooter.sh restart --debug
```

### Service Won't Stop
The script includes aggressive process killing that should handle stuck processes. If issues persist:
```bash
sudo ./panini-rebooter.sh stop --debug
```

### Mono Not Found
Ensure Mono Framework is installed:
```bash
# Check if Mono is installed
which mono

# Install Mono if needed (visit mono-project.com for installer)
```

### Permission Issues
The script requires administrator privileges:
```bash
# Always run with sudo
sudo ./panini-rebooter.sh [command]
```

## Technical Details

### Service Architecture
- **Main Process**: Mono runtime executing `EverestEngine.exe`
- **Web Service**: HTTPS service on port 44343
- **LaunchDaemon**: macOS system service for automatic startup
- **Working Directory**: `/usr/local/bin/everestengine/Sandbox`

### Timeouts
- **Service Response Check**: 15 seconds
- **Graceful Shutdown**: 10 seconds
- **Service Startup Wait**: 60 seconds
- **Process Settlement**: 5 seconds (between stop/start)

### Process Detection
The script identifies Panini processes by:
- Process name containing "everestengine"
- Mono processes running Panini executables
- Processes using the `/usr/local/bin/everestengine/` directory
- Processes listening on port 44343

## Log Files

Panini logs are typically found at:
```
/usr/local/bin/everestengine/Logs/
```

Use debug mode to see detailed process information and log file locations.

## Version History

- **v1.0**: Basic restart functionality
- **v2.0**: Added start/stop/status commands and interactive menu
- **v2.1**: Improved process killing and timeout handling
- **v2.2**: Enhanced status reporting and debug capabilities

## Support

For issues with the Panini Everest Engine itself, contact Panini support.
For issues with this management script, check the debug output and process status.

## License

This script is provided as-is for managing Panini Everest Engine installations. 