#!/bin/bash
#
# vd-wifi-watcher.sh
#
# Automatically disables Wi-Fi when Virtual Desktop Streamer launches and
# restores it when the streamer quits.
#
# Why: Virtual Desktop Streamer on macOS enumerates active en* interfaces and
# latches onto the Wi-Fi one (typically en0) because it appears first or has
# an active address on the LAN subnet. It does this even when Ethernet is
# connected and responding, which causes the streamer's About page to show
# "PC Ethernet: No". The macOS network service order (System Settings →
# Network → Set Service Order) does NOT fix this — it affects the kernel
# routing table only; VD's detection logic ignores it. Disabling Wi-Fi is the
# only reliable workaround: it removes the competing interface entirely.
#
# How it works:
#   - Polls for the VD Streamer process every POLL_INTERVAL seconds.
#   - On detection (VD just launched):
#       1. Records whether Wi-Fi was on.
#       2. Turns Wi-Fi off if it was on.
#   - On disappearance (VD just quit):
#       1. Restores Wi-Fi to its previous state.
#   - If VD is already running when this script starts, it tracks the process
#     but does NOT toggle Wi-Fi (we can't know what state Wi-Fi was in before).
#   - All state transitions are logged via `logger` (viewable in Console.app
#     or `log show --predicate 'eventMessage contains "vd-wifi-watcher"'`).
#
# Requirements:
#   - macOS with networksetup (ships with macOS)
#   - Wi-Fi interface must be en0 (default on virtually all Macs — both Intel
#     and Apple Silicon)
#   - Ethernet adapter (USB-C, Thunderbolt, or built-in)
#
# Usage:
#   Intended to run as a launchd agent (see local.vd-wifi-watcher.plist).
#   Can also be run manually: ./vd-wifi-watcher.sh

POLL_INTERVAL=5           # Seconds between process checks
WIFI_DEVICE="en0"         # macOS Wi-Fi interface (always en0)
VD_PROCESS="Virtual Desktop Streamer"
LOG_TAG="vd-wifi-watcher"

# --- Helper functions --------------------------------------------------------

log_msg() { logger -t "$LOG_TAG" "$1"; }

wifi_is_on() {
    # networksetup returns a line like "Wi-Fi Power (en0): On"
    [[ "$(networksetup -getairportpower "$WIFI_DEVICE" 2>/dev/null)" == *"On"* ]]
}

vd_is_running() {
    pgrep -f "$VD_PROCESS" >/dev/null 2>&1
}

# --- State tracking ----------------------------------------------------------

WIFI_WAS_ON=false       # Was Wi-Fi on before VD launched?
VD_WAS_RUNNING=false    # Was VD running on the previous poll?

# If VD is already running at script start, track it but don't touch Wi-Fi.
# We don't know what state Wi-Fi was in before we started.
if vd_is_running; then
    VD_WAS_RUNNING=true
    log_msg "Started — VD already running, monitoring without toggling"
else
    log_msg "Started — watching for VD Streamer"
fi

# --- Main loop ---------------------------------------------------------------

while true; do
    if vd_is_running; then
        if [[ "$VD_WAS_RUNNING" == false ]]; then
            # Transition: VD just launched
            if wifi_is_on; then
                WIFI_WAS_ON=true
                networksetup -setairportpower "$WIFI_DEVICE" off
                log_msg "VD launched — Wi-Fi disabled"
            else
                log_msg "VD launched — Wi-Fi was already off"
            fi
            VD_WAS_RUNNING=true
        fi
    else
        if [[ "$VD_WAS_RUNNING" == true ]]; then
            # Transition: VD just quit
            if [[ "$WIFI_WAS_ON" == true ]]; then
                networksetup -setairportpower "$WIFI_DEVICE" on
                log_msg "VD quit — Wi-Fi restored"
            else
                log_msg "VD quit — Wi-Fi was off before, leaving it off"
            fi
            WIFI_WAS_ON=false
            VD_WAS_RUNNING=false
        fi
    fi
    sleep "$POLL_INTERVAL"
done
