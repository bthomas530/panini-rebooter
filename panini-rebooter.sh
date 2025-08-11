#!/bin/bash

# Script to manage Panini Everest Engine
# Must be run with sudo privileges

# Debug mode flag
DEBUG=false
VERBOSE=false
ACTION=""

# Resolve absolute script path robustly (works with direct exec or via bash)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --debug) DEBUG=true ;;
        --verbose) VERBOSE=true ;;
        start|stop|restart|status) ACTION=$1 ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

# Function to log debug messages
debug_log() {
    if [ "$DEBUG" = true ]; then
        echo "[DEBUG] $(date '+%Y-%m-%d %H:%M:%S') - $1"
    fi
}

# Function to log verbose messages
verbose_log() {
    if [ "$VERBOSE" = true ]; then
        echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $1"
    fi
}

# Ensure the script is running with superuser privileges.
# If not, prompt to re-run with sudo and preserve DEBUG/VERBOSE env vars.
ensure_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "This script requires administrator privileges."
        if [ -t 0 ]; then
            read -r -p "Re-run with sudo now? [Y/n]: " response
            response=${response:-Y}
            case "$response" in
                [Yy]*)
                    echo "Re-running with sudo..."
                    # Prompt for sudo upfront to fail fast if not allowed
                    sudo -v || { echo "Failed to obtain sudo privileges."; exit 1; }
                    exec sudo --preserve-env=DEBUG,VERBOSE "$SCRIPT_PATH" "$@"
                    ;;
                *)
                    echo "Exiting. Please run this script with sudo."
                    exit 1
                    ;;
            esac
        else
            echo "Non-interactive shell detected. Please run with sudo:"
            echo "  sudo $SCRIPT_PATH $*"
            exit 1
        fi
    fi
}

# Function to check if a command succeeded
check_status() {
    if [ $? -eq 0 ]; then
        echo "✓ $1"
        debug_log "Command succeeded: $1"
    else
        echo "✗ $1"
        debug_log "Command failed: $1"
        return 1
    fi
}

# Function to check if the service is responding
check_service() {
    debug_log "Attempting to connect to https://localhost:44343"
    if curl -s -k --connect-timeout 10 --max-time 15 https://localhost:44343 > /dev/null 2>&1; then
        echo "✓ Service is responding"
        debug_log "Service check successful"
        return 0
    else
        echo "✗ Service is not responding"
        debug_log "Service check failed"
        return 1
    fi
}

# Function to check process status
check_process() {
    local process_name=$1
    debug_log "Checking process: $process_name"
    if pgrep -f "$process_name" > /dev/null; then
        verbose_log "Process $process_name is running"
        return 0
    else
        verbose_log "Process $process_name is not running"
        return 1
    fi
}

# Function to check if Mono is installed
check_mono() {
    debug_log "Checking Mono installation"
    if command -v mono >/dev/null 2>&1; then
        verbose_log "Mono is installed"
        return 0
    else
        verbose_log "Mono is not installed"
        return 1
    fi
}

# Function to check Mono process logs
check_mono_logs() {
    local pid=$(pgrep -f "everestengine")
    if [ -n "$pid" ]; then
        echo "Checking Mono process logs for PID $pid..."
        lsof -p $pid 2>/dev/null
        ps -p $pid -o %cpu,%mem,command
    fi
}

# Function to wait for service with timeout
wait_for_service() {
    local timeout=$1
    local interval=5
    local elapsed=0
    
    echo "Waiting for service to start (timeout: ${timeout}s)..."
    while [ $elapsed -lt $timeout ]; do
        if check_service; then
            return 0
        fi
        sleep $interval
        elapsed=$((elapsed + interval))
        echo "Still waiting... (${elapsed}s elapsed)"
        if [ "$DEBUG" = true ]; then
            check_mono_logs
        fi
    done
    return 1
}

# Function to start the service
start_service() {
    echo "Starting Panini Everest Engine..."
    
    # Check if already running and responding
    if check_process "everestengine"; then
        echo "Process is already running, checking service response..."
        if check_service; then
            echo "✓ Service is already running and responding correctly."
            return 0
        else
            echo "Process is running but service is not responding."
            echo "Stopping existing process for clean restart..."
            stop_service
            sleep 2
        fi
    fi
    
    # Ensure LaunchDaemon is unloaded first (clean slate)
    debug_log "Ensuring clean state by unloading LaunchDaemon first"
    launchctl unload /Library/LaunchDaemons/com.panini.everestengine.plist 2>/dev/null
    sleep 2
    
    # Start the service
    echo "Loading Panini LaunchDaemon..."
    debug_log "Attempting to load: /Library/LaunchDaemons/com.panini.everestengine.plist"
    launchctl load /Library/LaunchDaemons/com.panini.everestengine.plist
    check_status "Started Panini services"
    
    # Wait for service to start
    if wait_for_service 60; then
        echo "✓ Panini Everest Engine started successfully!"
        return 0
    else
        echo "✗ Service failed to start within timeout period"
        echo "Checking for any running processes..."
        check_mono_logs
        return 1
    fi
}

# Function to stop the service
stop_service() {
    echo "Stopping Panini Everest Engine..."
    
    # Check if running
    if ! check_process "everestengine"; then
        echo "Service is not running."
        return 0
    fi
    
    # Stop the service via launchctl first
    debug_log "Attempting to unload: /Library/LaunchDaemons/com.panini.everestengine.plist"
    launchctl unload /Library/LaunchDaemons/com.panini.everestengine.plist 2>/dev/null
    check_status "Stopped Panini services"
    
    # Wait briefly for graceful shutdown
    local timeout=10
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if ! check_process "everestengine"; then
            echo "✓ Service stopped gracefully"
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
        if [ $((elapsed % 3)) -eq 0 ]; then
            echo "Waiting for graceful shutdown... (${elapsed}s elapsed)"
        fi
    done
    
    # Force kill all Panini-related processes
    echo "Graceful shutdown timeout, force killing all Panini processes..."
    
    # Kill by process name patterns
    local killed_any=false
    
    # Kill everestengine processes
    local pids=$(pgrep -f "everestengine")
    if [ -n "$pids" ]; then
        echo "Force killing everestengine processes: $pids"
        kill -9 $pids 2>/dev/null
        killed_any=true
    fi
    
    # Kill any mono processes running Panini executables
    local mono_pids=$(pgrep -f "mono.*Panini")
    if [ -n "$mono_pids" ]; then
        echo "Force killing Panini mono processes: $mono_pids"
        kill -9 $mono_pids 2>/dev/null
        killed_any=true
    fi
    
    # Kill any processes using the Panini directory
    local panini_pids=$(lsof +D /usr/local/bin/everestengine 2>/dev/null | awk 'NR>1 {print $2}' | sort -u)
    if [ -n "$panini_pids" ]; then
        echo "Force killing processes using Panini directory: $panini_pids"
        kill -9 $panini_pids 2>/dev/null
        killed_any=true
    fi
    
    # Kill any processes listening on port 44343
    local port_pids=$(lsof -ti:44343 2>/dev/null)
    if [ -n "$port_pids" ]; then
        echo "Force killing processes on port 44343: $port_pids"
        kill -9 $port_pids 2>/dev/null
        killed_any=true
    fi
    
    if [ "$killed_any" = true ]; then
        sleep 3  # Give time for processes to die
    fi
    
    # Final check
    if ! check_process "everestengine"; then
        echo "✓ All Panini processes stopped"
        return 0
    else
        echo "✗ Some processes may still be running"
        # Show remaining processes for debugging
        echo "Remaining Panini processes:"
        pgrep -fl "everestengine\|Panini\|EverestEngine" || echo "None found by name"
        return 1
    fi
}

# Function to restart the service
restart_service() {
    echo "Restarting Panini Everest Engine..."
    
    # Stop first
    stop_service
    
    # Wait a moment for the system to settle
    debug_log "Waiting for system to settle..."
    sleep 5
    
    # Start again
    start_service
}

# Function to show menu
show_menu() {
    # echo "Panini Everest Engine Manager"
    echo "============================="
    echo "1) Start service"
    echo "2) Stop service"
    echo "3) Restart service"
    echo "4) Check status"
    echo "5) Exit"
    echo ""
    read -p "Please select an option (1-5): " choice
    
    case $choice in
        1) ACTION="start" ;;
        2) ACTION="stop" ;;
        3) ACTION="restart" ;;
        4) ACTION="status" ;;
        5) echo "Goodbye!"; exit 0 ;;
        *) echo "Invalid option. Please try again."; show_menu ;;
    esac
}

# Function to show status
show_status() {
    echo "============================"
    echo "Panini Everest Engine Status"
    echo "============================"
    
    # Check Mono installation
    echo -n "Mono Installation: "
    if check_mono; then
        echo "✓ Installed"
    else
        echo "✗ Not Installed"
    fi
    
    # Check process status
    echo -n "Process Status: "
    if check_process "everestengine"; then
        echo "✓ Running"
    else
        echo "✗ Not Running"
    fi
    
    # Check service status
    echo -n "Service Status: "
    if check_service; then
        echo "✓ Responding"
    else
        echo "✗ Not Responding"
    fi
    
    # Show LaunchDaemon status
    echo -n "LaunchDaemon Status: "
    local daemon_status=$(launchctl list | grep panini)
    if [ -n "$daemon_status" ]; then
        echo "✓ Loaded"
        echo "  $daemon_status"
    else
        echo "✗ Not Loaded"
    fi
    
    # Show process details if running and in debug mode
    if [ "$DEBUG" = true ] && check_process "everestengine"; then
        echo -e "\nProcess Details:"
        check_mono_logs
    fi
}

# Enforce superuser privileges before proceeding
ensure_root "$@"

# Main execution
echo "============================"
echo "Panini Everest Engine Manager"
debug_log "Script started with DEBUG=$DEBUG, VERBOSE=$VERBOSE, ACTION=$ACTION"

# Check if Mono is installed
if ! check_mono; then
    echo "Error: Mono is not installed. Please install Mono first."
    exit 1
fi

# If no action specified, show menu
if [ -z "$ACTION" ]; then
    show_menu
fi

# Execute the requested action
case $ACTION in
    start)
        start_service
        ;;
    stop)
        stop_service
        ;;
    restart)
        restart_service
        ;;
    status)
        show_status
        ;;
    *)
        echo "Invalid action: $ACTION"
        echo "Usage: $0 [start|stop|restart|status] [--debug] [--verbose]"
        exit 1
        ;;
esac

# Show final status if not just checking status
if [ "$ACTION" != "status" ]; then
    echo ""
    echo "Final Status:"
    echo "============="
    show_status
fi

echo ""
echo "Operation completed!" 