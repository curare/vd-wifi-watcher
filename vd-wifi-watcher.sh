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
#   - All state transitions are logged to /tmp/vd-wifi-watcher.log with timestamps.
#   - A heartbeat is logged every 5 minutes so you can verify the script is alive.
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

POLL_INTERVAL=5                            # Seconds between process checks
WIFI_DEVICE="en0"                          # macOS Wi-Fi interface (always en0)
VD_PROCESS="Virtual Desktop Streamer"
LOG_FILE="/tmp/vd-wifi-watcher.log"
POLL_COUNT=0                                # Counter for heartbeat logging
HEARTBEAT_INTERVAL=60                       # Log heartbeat every 60 polls (5 min at 5s interval)
CONSECUTIVE_ERRORS=0                        # Track consecutive networksetup failures
MAX_CONSECUTIVE_ERRORS=10                   # Exit after N consecutive failures

# --- Helper functions --------------------------------------------------------

# Initialize or open log file
if [[ ! -f "$LOG_FILE" ]]; then
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"
fi

log_msg() {
    local msg="$1"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $msg" >> "$LOG_FILE"
}

wifi_is_on() {
    # networksetup returns a line like "Wi-Fi Power (en0): On"
    [[ "$(networksetup -getairportpower "$WIFI_DEVICE" 2>/dev/null)" == *"On"* ]]
}

vd_is_running() {
    # Use -x for exact name matching to avoid false positives
    # If exact match fails, fall back to pattern match with validation
    pgrep -x "$VD_PROCESS" >/dev/null 2>&1 || \
    pgrep -f "^.*/.*$VD_PROCESS" >/dev/null 2>&1
}

# --- State tracking ----------------------------------------------------------

WIFI_WAS_ON=false       # Was Wi-Fi on before VD launched?
VD_WAS_RUNNING=false    # Was VD running on the previous poll?

# Log startup
log_msg "Started vd-wifi-watcher (PID: $$)"

# If VD is already running at script start, track it but don't touch Wi-Fi.
# We don't know what state Wi-Fi was in before we started.
if vd_is_running; then
    VD_WAS_RUNNING=true
    log_msg "VD already running on startup; monitoring without toggling"
else
    log_msg "Watching for VD Streamer to launch"
fi

# --- Main loop ---------------------------------------------------------------

while true; do
    ((POLL_COUNT++))
    
    # Log heartbeat every HEARTBEAT_INTERVAL polls (helps verify script is alive)
    if (( POLL_COUNT % HEARTBEAT_INTERVAL == 0 )); then
        log_msg "Heartbeat: monitoring (VD_WAS_RUNNING=$VD_WAS_RUNNING, WIFI_WAS_ON=$WIFI_WAS_ON)"
    fi
    
    if vd_is_running; then
        if [[ "$VD_WAS_RUNNING" == false ]]; then
            # Transition: VD just launched
            if wifi_is_on; then
                WIFI_WAS_ON=true
                if networksetup -setairportpower "$WIFI_DEVICE" off 2>/tmp/vd-wifi-watcher.err; then
                    log_msg "VD launched — Wi-Fi disabled"
                    CONSECUTIVE_ERRORS=0  # Reset error counter on success
                else
                    ((CONSECUTIVE_ERRORS++))
                    log_msg "ERROR: Failed to disable Wi-Fi. $(cat /tmp/vd-wifi-watcher.err 2>/dev/null || echo 'Unknown error') [attempt $CONSECUTIVE_ERRORS/$MAX_CONSECUTIVE_ERRORS]"
                    if (( CONSECUTIVE_ERRORS >= MAX_CONSECUTIVE_ERRORS )); then
                        log_msg "FATAL: Too many consecutive errors. Exiting. Check networksetup permissions: id -G | grep -q 80"
                        sleep 2  # Brief delay before exit to avoid rapid restart loops
                        exit 1
                    fi
                fi
            else
                log_msg "VD launched — Wi-Fi was already off"
                CONSECUTIVE_ERRORS=0  # Reset error counter
            fi
            VD_WAS_RUNNING=true
        fi
    else
        if [[ "$VD_WAS_RUNNING" == true ]]; then
            # Transition: VD just quit
            if [[ "$WIFI_WAS_ON" == true ]]; then
                if networksetup -setairportpower "$WIFI_DEVICE" on 2>/tmp/vd-wifi-watcher.err; then
                    log_msg "VD quit — Wi-Fi restored"
                    CONSECUTIVE_ERRORS=0  # Reset error counter on success
                else
                    ((CONSECUTIVE_ERRORS++))
                    log_msg "ERROR: Failed to restore Wi-Fi. $(cat /tmp/vd-wifi-watcher.err 2>/dev/null || echo 'Unknown error') [attempt $CONSECUTIVE_ERRORS/$MAX_CONSECUTIVE_ERRORS]"
                    if (( CONSECUTIVE_ERRORS >= MAX_CONSECUTIVE_ERRORS )); then
                        log_msg "FATAL: Too many consecutive errors. Exiting. Check networksetup permissions: id -G | grep -q 80"
                        sleep 2  # Brief delay before exit to avoid rapid restart loops
                        exit 1
                    fi
                fi
            else
                log_msg "VD quit — Wi-Fi was off before, leaving it off"
                CONSECUTIVE_ERRORS=0  # Reset error counter
            fi
            WIFI_WAS_ON=false
            VD_WAS_RUNNING=false
        fi
    fi
    sleep "$POLL_INTERVAL"
done
