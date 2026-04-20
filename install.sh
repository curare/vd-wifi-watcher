#!/bin/bash
#
# install.sh — Install the vd-wifi-watcher launchd agent.
# Part of vd-wifi-watcher — auto-disables Wi-Fi while Virtual Desktop Streamer runs.
#
# This script:
#   1. Copies the watcher script to ~/bin/
#   2. Generates the launchd plist with the correct script path
#   3. Loads the agent so it starts immediately and on future logins

set -euo pipefail

SCRIPT_NAME="vd-wifi-watcher.sh"
PLIST_NAME="local.vd-wifi-watcher.plist"
INSTALL_DIR="$HOME/bin"
PLIST_DIR="$HOME/Library/LaunchAgents"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Installing vd-wifi-watcher..."

# Create ~/bin if it doesn't exist
mkdir -p "$INSTALL_DIR"

# Copy the watcher script
cp "$SCRIPT_DIR/$SCRIPT_NAME" "$INSTALL_DIR/$SCRIPT_NAME"
chmod +x "$INSTALL_DIR/$SCRIPT_NAME"
echo "  Installed script to $INSTALL_DIR/$SCRIPT_NAME"

# Generate the plist with the actual script path substituted in
sed "s|__SCRIPT_PATH__|$INSTALL_DIR/$SCRIPT_NAME|g" \
    "$SCRIPT_DIR/$PLIST_NAME" > "$PLIST_DIR/$PLIST_NAME"
echo "  Installed plist to $PLIST_DIR/$PLIST_NAME"

# Unload first if already loaded (ignore errors)
launchctl unload "$PLIST_DIR/$PLIST_NAME" 2>/dev/null || true

# Load the agent
launchctl load "$PLIST_DIR/$PLIST_NAME"
echo "  Agent loaded."

echo ""
echo "Done. The watcher is now running and will start automatically on login."
echo "Check logs: cat /tmp/vd-wifi-watcher.log"
