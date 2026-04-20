# vd-wifi-watcher

Automatically disables Wi-Fi when [Virtual Desktop Streamer](https://www.vrdesktop.net/) launches on macOS, and restores it when the streamer quits.

## The Problem

On macOS, when both Wi-Fi and Ethernet are active on the same subnet, Virtual Desktop Streamer fails to detect the Ethernet connection. The streamer's About page shows **"PC Ethernet: No"** even though the Ethernet adapter is connected and responding.

The root cause: VD enumerates active `en*` interfaces and latches onto the Wi-Fi one (typically `en0`) because it appears first or has an active address on the LAN subnet. It does this regardless of which adapter is actually carrying traffic.

Setting the macOS network service order (System Settings → Network → Set Service Order) does **not** fix this — it affects the kernel routing table only; VD's interface detection logic bypasses it entirely with its own enumeration. Disabling Wi-Fi removes the competing interface, which is the only reliable workaround.

## How It Works

A lightweight background script polls for the Virtual Desktop Streamer process every 5 seconds:

- **VD launches:** Records whether Wi-Fi was on, then turns it off.
- **VD quits:** Restores Wi-Fi to its previous state (only turns it back on if it was on before).
- **VD already running at script start:** Monitors without toggling (since prior Wi-Fi state is unknown).

The script runs as a macOS [launchd](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html) user agent — it starts on login and restarts automatically if it crashes.

## Requirements

- macOS (tested on macOS 15.4 Sequoia / Apple Silicon)
- Virtual Desktop Streamer for Mac
- Ethernet adapter (USB-C, Thunderbolt, or built-in)
- Wi-Fi on the default `en0` interface

## Install

```bash
git clone https://github.com/curare/vd-wifi-watcher.git
cd vd-wifi-watcher
chmod +x install.sh
./install.sh
```

This copies the watcher script to `~/bin/`, installs the launchd plist to `~/Library/LaunchAgents/`, and starts the agent immediately.

## Uninstall

```bash
cd vd-wifi-watcher
chmod +x uninstall.sh
./uninstall.sh
```

## Logs

Events are logged to the macOS system log and to a file:

```bash
# Log file
cat /tmp/vd-wifi-watcher.log

# System log (last 10 minutes)
log show --predicate 'eventMessage contains "vd-wifi-watcher"' --last 10m
```

Example log output:
```
VD launched — Wi-Fi disabled
VD quit — Wi-Fi restored
```

## Configuration

Edit these variables at the top of `vd-wifi-watcher.sh`:

| Variable | Default | Description |
|----------|---------|-------------|
| `POLL_INTERVAL` | `5` | Seconds between process checks |
| `WIFI_DEVICE` | `en0` | Wi-Fi network interface (always `en0` on Mac) |
| `VD_PROCESS` | `Virtual Desktop Streamer` | Process name to watch for |

## License

MIT
