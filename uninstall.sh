#!/bin/bash
#
# uninstall.sh — Remove the vd-wifi-watcher launchd agent.
# Part of vd-wifi-watcher — auto-disables Wi-Fi while Virtual Desktop Streamer runs.
#
# This script:
#   1. Unloads the launchd agent (stops the watcher)
#   2. Removes the plist from ~/Library/LaunchAgents/
#   3. Removes the script from ~/bin/
#   4. Cleans up the log file

set -euo pipefail

SCRIPT_NAME="vd-wifi-watcher.sh"
PLIST_NAME="local.vd-wifi-watcher.plist"
INSTALL_DIR="$HOME/bin"
PLIST_DIR="$HOME/Library/LaunchAgents"

echo "Uninstalling vd-wifi-watcher..."

# Unload the agent (ignore errors if not loaded)
launchctl unload "$PLIST_DIR/$PLIST_NAME" 2>/dev/null || true
echo "  Agent unloaded."

# Remove files
rm -f "$PLIST_DIR/$PLIST_NAME"
echo "  Removed $PLIST_DIR/$PLIST_NAME"

rm -f "$INSTALL_DIR/$SCRIPT_NAME"
echo "  Removed $INSTALL_DIR/$SCRIPT_NAME"

rm -f /tmp/vd-wifi-watcher.log
echo "  Removed /tmp/vd-wifi-watcher.log"

echo ""
echo "Done. vd-wifi-watcher has been completely removed."
