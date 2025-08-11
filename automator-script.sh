#!/bin/bash

# Path to the panini-rebooter.sh script
PANINI_SCRIPT="/Users/bthomas/dev/GitHub/zOLD/panini-rebooter/panini-rebooter.sh"

# Check if the script exists
if [ ! -f "$PANINI_SCRIPT" ]; then
    echo "Error: panini-rebooter.sh not found at $PANINI_SCRIPT"
    echo "Please update the PANINI_SCRIPT path in this automator app"
    read -p "Press Enter to exit..."
    exit 1
fi

# Make sure the script is executable
chmod +x "$PANINI_SCRIPT"

# Clear screen and show header
clear
echo "🚀 Panini Everest Engine Manager"
echo "================================="
echo "This will run the Panini management script with sudo privileges."
echo ""

# Run the script with sudo (will prompt for password)
sudo "$PANINI_SCRIPT"

# Keep terminal open
echo ""
echo "✅ Script completed. Press Enter to close this window..."
read 