#!/bin/bash

# Script to manage Panini Everest Engine
# Must be run with sudo privileges

# Fail loudly if any command in a pipeline fails (e.g. curl | grep)
set -o pipefail

# Debug mode flag
DEBUG=false
VERBOSE=false
ACTION=""

# --- Configuration (single source of truth) -------------------------------
PLIST="/Library/LaunchDaemons/com.panini.everestengine.plist"
ENGINE_DIR="/usr/local/bin/everestengine"
SERVICE_PORT=44343
SERVICE_URL="https://localhost:${SERVICE_PORT}"
PROCESS_PATTERN="everestengine"
STARTUP_TIMEOUT=60   # seconds to wait for the service to come up
SHUTDOWN_TIMEOUT=10  # seconds to wait for a graceful stop

# launchd targeting (modern launchctl uses domain/service-target syntax)
LAUNCHD_DOMAIN="system"
DAEMON_LABEL="$(basename "$PLIST" .plist)"        # e.g. com.panini.everestengine
SERVICE_TARGET="${LAUNCHD_DOMAIN}/${DAEMON_LABEL}"
# --------------------------------------------------------------------------

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

# Escalate to root for a specific action that needs it (start/stop/restart).
# We re-exec sudo with the already-resolved action so the privileged run goes
# straight to work instead of re-showing the menu. Read-only checks (status,
# health probes) never trigger this — only an actual fix prompts for a password.
escalate_if_needed() {
    local action="$1"
    [ "$EUID" -eq 0 ] && return 0

    echo "Administrator privileges are required to ${action} the service."
    if [ ! -t 0 ]; then
        echo "Non-interactive shell detected. Re-run with:"
        echo "  sudo $SCRIPT_PATH $action"
        exit 1
    fi

    echo "Re-running with sudo..."
    sudo -v || { echo "Failed to obtain sudo privileges."; exit 1; }

    # Forward the debug/verbose flags so the privileged run behaves the same.
    local extra=""
    [ "$DEBUG" = true ] && extra="$extra --debug"
    [ "$VERBOSE" = true ] && extra="$extra --verbose"
    # shellcheck disable=SC2086  # intentional word-splitting of known-safe flags
    exec sudo "$SCRIPT_PATH" "$action" $extra
}

# --- Modern launchctl wrappers --------------------------------------------
# macOS deprecated `launchctl load/unload` in favor of bootstrap/bootout/
# kickstart against a domain target (e.g. system/com.panini.everestengine).
# Each wrapper falls back to the legacy verb so the script still works on
# older systems. All of these require root.

# Load the daemon (bootstrap), falling back to legacy load.
daemon_bootstrap() {
    launchctl bootstrap "$LAUNCHD_DOMAIN" "$PLIST" 2>/dev/null \
        || launchctl load "$PLIST"
}

# Unload the daemon (bootout), falling back to legacy unload.
daemon_bootout() {
    launchctl bootout "$SERVICE_TARGET" 2>/dev/null \
        || launchctl bootout "$LAUNCHD_DOMAIN" "$PLIST" 2>/dev/null \
        || launchctl unload "$PLIST" 2>/dev/null
}

# Kill and immediately restart the running service in one step.
daemon_kickstart() {
    launchctl kickstart -k "$SERVICE_TARGET"
}

# Return success if the daemon is currently bootstrapped into launchd.
# (Reading the system domain requires root.)
daemon_is_loaded() {
    launchctl print "$SERVICE_TARGET" >/dev/null 2>&1
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

# Function to check if the service is responding.
# Quiet by design (returns status only) so it can be polled cheaply; callers
# print human-readable output. Optional arg overrides the request timeout.
check_service() {
    local max_time=${1:-6}
    debug_log "Probing ${SERVICE_URL} (max-time ${max_time}s)"
    if curl -s -k --connect-timeout 3 --max-time "$max_time" "$SERVICE_URL" > /dev/null 2>&1; then
        debug_log "Service check successful"
        return 0
    else
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
    local pid=$(pgrep -f "$PROCESS_PATTERN")
    if [ -n "$pid" ]; then
        echo "Checking Mono process logs for PID $pid..."
        lsof -p $pid 2>/dev/null
        ps -p $pid -o %cpu,%mem,command
    fi
}

# Function to wait for service with timeout
wait_for_service() {
    local timeout=$1
    local interval=2
    local elapsed=0

    echo "Waiting for service to start (timeout: ${timeout}s)..."
    while [ $elapsed -lt $timeout ]; do
        # Use a short probe timeout while polling: the engine binds the port
        # before it can answer, so a long timeout would stall each iteration.
        if check_service 4; then
            echo "✓ Service is responding (after ${elapsed}s)"
            return 0
        fi
        sleep $interval
        elapsed=$((elapsed + interval))
        if [ $((elapsed % 6)) -eq 0 ]; then
            echo "Still waiting... (${elapsed}s elapsed)"
        fi
        if [ "$DEBUG" = true ]; then
            check_mono_logs
        fi
    done
    return 1
}

# Function to start the service
start_service() {
    echo "Starting Panini Everest Engine..."

    # The LaunchDaemon plist must exist or launchctl load is a silent no-op
    if [ ! -f "$PLIST" ]; then
        echo "✗ LaunchDaemon not found: $PLIST"
        echo "  The Panini Everest Engine may not be installed correctly."
        return 1
    fi

    # Check if already running and responding
    if check_process "$PROCESS_PATTERN"; then
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

    # Bring the daemon up. If it's already bootstrapped, kickstart it (kill +
    # restart) rather than bootstrap again (which would error "already loaded").
    if daemon_is_loaded; then
        echo "Daemon already loaded; kickstarting it..."
        debug_log "kickstart -k $SERVICE_TARGET"
        daemon_kickstart
    else
        echo "Bootstrapping Panini LaunchDaemon..."
        debug_log "bootstrap $LAUNCHD_DOMAIN $PLIST"
        daemon_bootstrap
    fi
    check_status "Started Panini services"

    # Wait for service to start
    if wait_for_service "$STARTUP_TIMEOUT"; then
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
    if ! check_process "$PROCESS_PATTERN"; then
        echo "Service is not running."
        return 0
    fi

    # Stop the service via launchctl first
    debug_log "bootout $SERVICE_TARGET"
    daemon_bootout
    check_status "Stopped Panini services"

    # Wait briefly for graceful shutdown
    local timeout=$SHUTDOWN_TIMEOUT
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if ! check_process "$PROCESS_PATTERN"; then
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
    local pids=$(pgrep -f "$PROCESS_PATTERN")
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
    local panini_pids=$(lsof +D "$ENGINE_DIR" 2>/dev/null | awk 'NR>1 {print $2}' | sort -u)
    if [ -n "$panini_pids" ]; then
        echo "Force killing processes using Panini directory: $panini_pids"
        kill -9 $panini_pids 2>/dev/null
        killed_any=true
    fi

    # Kill any processes listening on the service port
    local port_pids=$(lsof -ti:"$SERVICE_PORT" 2>/dev/null)
    if [ -n "$port_pids" ]; then
        echo "Force killing processes on port $SERVICE_PORT: $port_pids"
        kill -9 $port_pids 2>/dev/null
        killed_any=true
    fi

    if [ "$killed_any" = true ]; then
        sleep 3  # Give time for processes to die
    fi

    # Final check
    if ! check_process "$PROCESS_PATTERN"; then
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

    if [ ! -f "$PLIST" ]; then
        echo "✗ LaunchDaemon not found: $PLIST"
        echo "  The Panini Everest Engine may not be installed correctly."
        return 1
    fi

    # Fast path: if the daemon is loaded, kickstart -k kills and relaunches it
    # in a single launchd call — no unload/sleep/load dance.
    if daemon_is_loaded; then
        echo "Kickstarting service (kill + relaunch)..."
        debug_log "kickstart -k $SERVICE_TARGET"
        if daemon_kickstart && wait_for_service "$STARTUP_TIMEOUT"; then
            echo "✓ Panini Everest Engine restarted successfully!"
            return 0
        fi
        echo "Kickstart did not bring the service up; falling back to full stop/start..."
    fi

    # Fallback: full stop (with force-kill) then start.
    stop_service
    debug_log "Waiting for system to settle..."
    sleep 3
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
    if check_process "$PROCESS_PATTERN"; then
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
    
    # Show LaunchDaemon status. Querying the system domain needs root, so when
    # unprivileged we say so rather than reporting a misleading "Not Loaded".
    echo -n "LaunchDaemon Status: "
    if [ "$EUID" -ne 0 ]; then
        echo "? (run with sudo to query the system domain)"
    elif daemon_is_loaded; then
        echo "✓ Loaded ($SERVICE_TARGET)"
    else
        echo "✗ Not Loaded"
    fi
    
    # Show process details if running and in debug mode
    if [ "$DEBUG" = true ] && check_process "$PROCESS_PATTERN"; then
        echo -e "\nProcess Details:"
        check_mono_logs
    fi
}

# Main execution
debug_log "Script started with DEBUG=$DEBUG, VERBOSE=$VERBOSE, ACTION=$ACTION"

# Mono is a hard prerequisite; check it up front (no privileges needed).
if ! check_mono; then
    echo "Error: Mono is not installed. Please install Mono first."
    exit 1
fi

# No explicit action: diagnose first (read-only, no sudo), then act.
# If the service is unhealthy we offer to restart immediately and only then
# escalate to sudo — so the password prompt appears exactly when a fix is needed.
if [ -z "$ACTION" ]; then
    echo "============================="
    echo "Panini Everest Engine Manager"
    echo "============================="
    echo "Checking current status..."
    echo ""
    show_status
    echo ""

    if check_process "$PROCESS_PATTERN" && check_service; then
        echo "✓ Panini is up and responding."
        show_menu
    else
        echo "⚠ Panini is not running/responding."
        read -r -p "Restart the service now? [Y/n]: " resp
        resp=${resp:-Y}
        case "$resp" in
            [Yy]*) ACTION="restart" ;;
            *)     show_menu ;;
        esac
    fi
fi

# Mutating actions need root; escalate now, carrying the resolved action across
# the sudo boundary. Status is read-only and never prompts for a password.
case $ACTION in
    start|stop|restart) escalate_if_needed "$ACTION" ;;
esac

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