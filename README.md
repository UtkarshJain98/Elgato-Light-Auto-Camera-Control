# Elgato Key Light Camera Sync

![macOS](https://img.shields.io/badge/macOS-13%2B-blue)
![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-M1%20%7C%20M2%20%7C%20M3%20%7C%20M4-orange)
![License](https://img.shields.io/badge/license-MIT-green)
![Bash](https://img.shields.io/badge/bash-5.0%2B-brightgreen)

Automatically turn your Elgato Key Light on when your Mac's camera activates and off when it deactivates. Perfect for video calls, recordings, and streaming.

> ⭐ If you find this useful, please star the repo!

## Features

- **Event-Based Detection**: Instant camera detection with 0% CPU when idle
- **Built-in + External Camera Support**: Works with both Mac's built-in camera AND external USB/Thunderbolt cameras
- **Time-Based Color Temperature**: Warmer light in morning/evening, cooler during work hours (circadian-friendly)
- **Ambient Light Adjustment**: Automatically adjusts brightness based on room lighting
- **Auto-Discovery**: Finds your light automatically (no configuration needed)
- **Multi-Light Support**: Can be configured for specific lights if you have multiple
- **Zero Dependencies**: Uses only built-in macOS tools

## Compatibility

- **macOS**: Sequoia 15.0+ or Tahoe 26.0+ (required for ControlCenter event detection)
- **Hardware**: Apple Silicon Macs (M1/M2/M3/M4) and Intel Macs
- **Cameras**: Built-in FaceTime camera + External USB/Thunderbolt webcams (Opal, Logitech, etc.)
- **Lights**: Elgato Key Light, Key Light Air, Key Light Mini

> **Note**: Older macOS versions used different event subsystems and are not supported by this version.

## Quick Start

### Option 1: Clone the Repository (Recommended)

```bash
git clone https://github.com/UtkarshJain98/Elgato-Light-Auto-Camera-Control.git
cd Elgato-Light-Auto-Camera-Control
chmod +x elgato-light.sh
./elgato-light.sh test
./elgato-light.sh install
```

### Option 2: Download Files Directly

```bash
# Download all files
curl -O https://raw.githubusercontent.com/UtkarshJain98/Elgato-Light-Auto-Camera-Control/main/elgato-light.sh
curl -O https://raw.githubusercontent.com/UtkarshJain98/Elgato-Light-Auto-Camera-Control/main/elgato-light.conf
curl -O https://raw.githubusercontent.com/UtkarshJain98/Elgato-Light-Auto-Camera-Control/main/README.md
chmod +x elgato-light.sh

# Test and install
./elgato-light.sh test
./elgato-light.sh install
```

That's it! Your light will now automatically turn on when your camera activates.

## Usage

### Commands

```bash
./elgato-light.sh discover    # Find lights on your network
./elgato-light.sh test        # Test connection to light
./elgato-light.sh on          # Turn light on manually
./elgato-light.sh off         # Turn light off manually
./elgato-light.sh status      # Get current light status
./elgato-light.sh install     # Install automatic control
./elgato-light.sh uninstall   # Remove automatic control
```

### Manual Control

Even with automatic control installed, you can still use manual commands:

```bash
./elgato-light.sh on     # Override: turn on manually
./elgato-light.sh off    # Override: turn off manually
```

The automatic control will resume on the next camera state change.

## Configuration

All settings are stored in `elgato-light.conf` (same directory as the script) and can be customized:

```bash
# Edit configuration
nano elgato-light.conf

# Apply changes
./elgato-light.sh install
```

### Quick Configuration Guide

#### Basic Settings

| Setting | Default | Description |
|---------|---------|-------------|
| `LIGHT_HOST` | `""` (auto) | Light hostname (leave empty for auto-discovery) |
| `BRIGHTNESS` | `43` | Fixed brightness (0-100) when auto-adjust is off |
| `TEMPERATURE` | `290` | Fixed temperature in mireds (143-344) when auto-adjust is off |

#### Auto Color Temperature (Time-Based)

| Setting | Default | Time Range | Purpose |
|---------|---------|------------|---------|
| `AUTO_ADJUST_TEMPERATURE` | `true` | - | Enable time-based color adjustment |
| `TEMP_EARLY_MORNING` | `200` | 5:00 AM - 8:59 AM | Warm light for gentle wake-up |
| `TEMP_MIDDAY` | `280` | 9:00 AM - 4:59 PM | Cool light for alertness/focus |
| `TEMP_EVENING` | `220` | 5:00 PM - 8:59 PM | Warm light for comfortable evening |
| `TEMP_NIGHT` | `180` | 9:00 PM - 4:59 AM | Very warm light for late night |

**Temperature scale**: 143 = very warm (candlelight), 344 = very cool (daylight)

#### Auto Brightness (Ambient Light Based)

| Setting | Default | Description |
|---------|---------|-------------|
| `AUTO_ADJUST_BRIGHTNESS` | `true` | Enable ambient light adjustment |
| `BRIGHTNESS_MIN` | `15` | Minimum brightness % (used in bright rooms) |
| `BRIGHTNESS_MAX` | `100` | Maximum brightness % (used in dark rooms) |

**How it works**: Bright room = dimmer light (you need less fill light), Dark room = brighter light (you need more illumination)

#### Network & Reliability

| Setting | Default | Description |
|---------|---------|-------------|
| `MAX_RETRIES` | `3` | Retry attempts for failed requests |
| `RETRY_DELAY` | `1` | Delay between retries (seconds) |

#### Logging

| Setting | Default | Description |
|---------|---------|-------------|
| `ENABLE_DEBUG_LOGS` | `false` | Enable verbose debug logging |

### Example: Custom Settings for Specific Use Cases

#### 1. Late Night Streaming

Very warm light all the time, minimal brightness:

```bash
# In elgato-light.conf
AUTO_ADJUST_TEMPERATURE=false
TEMPERATURE=180            # Very warm
AUTO_ADJUST_BRIGHTNESS=false
BRIGHTNESS=30              # Low brightness
```

#### 2. Professional Video Calls

Consistent bright, cool light:

```bash
AUTO_ADJUST_TEMPERATURE=false
TEMPERATURE=300            # Cool/daylight
AUTO_ADJUST_BRIGHTNESS=false
BRIGHTNESS=90              # Bright
```

## How It Works

### Camera Detection Method

The script detects **both built-in and external cameras** using **event-based detection** - instant response with zero CPU overhead when idle.

#### How It Works
Listens to macOS ControlCenter system events:
- **Camera ON**: `Frame publisher cameras changed to [app: [uuid]]`
- **Camera OFF**: `Frame publisher cameras changed to [:]`

The script uses `log stream` to monitor these events in real-time:
```bash
log stream --predicate 'subsystem == "com.apple.controlcenter" and eventMessage contains "Frame publisher cameras"'
```

**Benefits:**
- **Instant response**: No polling delay - events trigger immediately when camera state changes
- **Zero CPU overhead**: 0% CPU when camera is idle (event-driven, not polling)
- **Works with all cameras**: Built-in FaceTime camera, external USB/Thunderbolt cameras (Opal, Logitech, etc.)
- **No interference**: Only listens to system events - never touches camera hardware

**Compatibility:**
- macOS Sequoia (15.0+)
- macOS Tahoe (26.0+)

Earlier macOS versions used different event subsystems (`com.apple.UVCExtension`). This approach was updated for modern macOS where ControlCenter manages camera access.

### Network Discovery

The script uses three methods to find your light:

1. **mDNS service discovery** (via `dns-sd`)
2. **PTR record queries** (fallback)
3. **Network scanning** (if above methods fail)

Once discovered, the hostname is cached for 24 hours to speed up subsequent runs.

### Light Control

The script communicates with the light using Elgato's HTTP API:

```
http://light-hostname:9123/elgato/lights
```

Commands are sent as JSON:
```json
{
  "lights": [{
    "brightness": 50,
    "temperature": 250,
    "on": 1
  }],
  "numberOfLights": 1
}
```

## Troubleshooting

### Light Not Found

```bash
# Try manual discovery
./elgato-light.sh discover

# If found, note the hostname and set it in config
nano elgato-light.conf
# Set: LIGHT_HOST="elgato-key-light-air-XXXX.local"
```

### Light Not Responding

```bash
# Check connection
./elgato-light.sh test

# Restart the light (power cycle)
# Then test again
```

### Installation Fails

If you get "Operation not permitted" errors:

**Option 1**: Move script out of protected location
```bash
mkdir -p ~/.local/bin
cp elgato-light.sh ~/.local/bin/
cd ~/.local/bin
./elgato-light.sh install
```

**Option 2**: Grant Full Disk Access to bash
1. Open System Settings > Privacy & Security > Full Disk Access
2. Click + and add `/bin/bash`
3. Try installing again

### Camera Detection Not Working

```bash
# Check if log stream is capturing events
log stream --predicate 'subsystem == "com.apple.controlcenter" and eventMessage contains "Frame publisher cameras"'
# Turn camera on/off and watch for events

# Enable debug logging
nano elgato-light.conf
# Set: ENABLE_DEBUG_LOGS=true

# Reinstall and check logs
./elgato-light.sh install
tail -f /tmp/elgato-light.log
```

### Light Not Responding to Camera

If events are detected but light doesn't respond:

```bash
# Test light manually
./elgato-light.sh on
./elgato-light.sh status

# Check if LaunchAgent is running
launchctl list | grep elgato

# Reinstall
./elgato-light.sh uninstall
./elgato-light.sh install
```

### Multiple Macs Fighting Over Light

The current version does not support multi-device coordination. If you run this on multiple Macs:
- Last command wins (the Mac that most recently changed state controls the light)
- This may cause flickering if both Macs' cameras are toggling frequently

**Workaround**: Only run the script on one Mac at a time.

## Logs

Logs are written to `/tmp/elgato-light.log`:

```bash
# View logs in real-time
tail -f /tmp/elgato-light.log

# View recent logs
tail -50 /tmp/elgato-light.log

# Clear logs
> /tmp/elgato-light.log
```

## Resource Usage

When running in the background:

- **CPU**: 0% when idle (event-based, no polling)
- **Memory**: ~2-3 MB
- **Network**: ~100 KB/hour (only when camera state changes)
- **Battery Impact**: Negligible (events are passive, no active polling)

## Uninstallation

```bash
# Remove automatic control
./elgato-light.sh uninstall

# Optionally remove config file
rm elgato-light.conf

# Optionally remove entire directory
cd ..
rm -rf Elgato-Light-Auto-Camera-Control
```

## Advanced Usage

### Running Multiple Instances

To control different lights from different scripts:

```bash
# Copy script with different name
cp elgato-light.sh elgato-light-office.sh
cp elgato-light.conf elgato-light-office.conf

# Edit the office script to use its own config
# Find line: CONFIG_FILE="$SCRIPT_DIR/elgato-light.conf"
# Change to: CONFIG_FILE="$SCRIPT_DIR/elgato-light-office.conf"

# Configure each light separately
nano elgato-light-office.conf
# Set LIGHT_HOST to specific light hostname

# Install both
./elgato-light.sh install
./elgato-light-office.sh install
```

### Custom LaunchAgent Schedule

The default LaunchAgent runs continuously. To modify:

```bash
# Edit the plist
nano ~/Library/LaunchAgents/com.local.elgato-camera-light.plist

# Add schedule restrictions (example: only during work hours)
# Reload
launchctl unload ~/Library/LaunchAgents/com.local.elgato-camera-light.plist
launchctl load ~/Library/LaunchAgents/com.local.elgato-camera-light.plist
```

### Integration with Other Tools

The script can be used in automation workflows:

```bash
# In your own scripts
/path/to/elgato-light.sh on
sleep 2
# Do something requiring light
/path/to/elgato-light.sh off
```

## FAQ

**Q: Does this work with Ring Light, Elgato Light Strip, etc?**
A: This script is designed for Elgato Key Light products. Other Elgato lights may use different APIs.

**Q: Can I control multiple lights?**
A: The script controls one light at a time. For multiple lights, you need to run multiple instances (see Advanced Usage).

**Q: Does this interfere with the Elgato Control Center app?**
A: No, both can be used simultaneously. Manual changes in Control Center will be overridden on the next camera state change.

**Q: Can I disable auto-adjustment features?**
A: Yes, set `AUTO_ADJUST_TEMPERATURE=false` and `AUTO_ADJUST_BRIGHTNESS=false` in the config file.

**Q: Why does the light sometimes flicker briefly?**
A: This can happen if other devices/apps are also controlling the light. Ensure only one automation is active at a time.

**Q: Can I use this for Zoom/Teams/Meet only, not all camera apps?**
A: No, the script detects camera hardware activation, not specific apps. Any app using the camera will trigger the light.

**Q: Does this work with external webcams?**
A: Yes! The script detects both built-in Mac cameras and external USB/Thunderbolt webcams. It uses multiple detection methods to catch any camera activation.

**Q: Will this drain my battery?**
A: Negligible impact. Event-based detection uses 0% CPU when idle - it only activates when camera state changes.

## Contributing

Contributions are welcome! Please feel free to:
- Report bugs via [GitHub Issues](https://github.com/UtkarshJain98/Elgato-Light-Auto-Camera-Control/issues)
- Submit feature requests
- Create pull requests

## Support

If you encounter issues:
1. Check the [Troubleshooting](#troubleshooting) section
2. Review [FAQ](#faq)
3. Check existing [GitHub Issues](https://github.com/UtkarshJain98/Elgato-Light-Auto-Camera-Control/issues)
4. Create a new issue with:
   - macOS version
   - Mac model
   - Light model
   - Error logs from `/tmp/elgato-light.log`

## License

MIT License - See [LICENSE](LICENSE) file for details.

This project is provided as-is for personal and commercial use. Feel free to modify and distribute.

## Credits

Created by [Utkarsh Jain](https://github.com/UtkarshJain98) for personal use and shared for community benefit.

Special thanks to the Elgato community for API documentation.

## Changelog

### v3.0.0 (Current) - Event-Based Detection
- **MAJOR**: Switched from polling to pure event-based detection
- **INSTANT**: Zero-latency camera detection (no polling delay)
- **EFFICIENT**: 0% CPU overhead when camera is idle (vs 0.08% with polling)
- **RELIABLE**: Uses macOS ControlCenter "Frame publisher cameras" events
- Works with both built-in (FaceTime) and external (Opal, Logitech, etc.) cameras
- Compatible with macOS Sequoia (15.0+) and Tahoe (26.0+)
- No interference with camera hardware - only listens to system events

### v2.2.0
- **OPTIMIZED**: Simplified camera detection for instant response (~1 second)
- **IMPROVED**: External camera detection via UVCAssistant daemon only (no false positives)
- **FIXED**: Eliminated flickering from unreliable app CPU monitoring (Chrome/Zoom/Teams)
- **FASTER**: Removed stability delays - immediate state change detection
- Works reliably with both built-in (FaceTime) and external (Opal, Logitech, etc.) cameras
- Zero interference with camera hardware - only reads daemon CPU

### v2.1.0
- **NEW**: External camera support - now detects USB/Thunderbolt webcams in addition to built-in camera
- Multi-method detection: lsof, coremediavideocaptured, system_profiler, process monitoring
- Works with any camera (built-in FaceTime, Logitech, Elgato Facecam, etc.)

### v2.0.0
- Added external configuration file support (`elgato-light.conf`)
- Improved documentation and inline comments
- Reduced polling interval to 1 second (faster response time)
- Simplified multi-device logic (removed to prevent conflicts)
- Enhanced error messages and troubleshooting guides
- Added comprehensive README with examples
- Self-contained package (all files in one directory)

### v1.0.0 (Initial Release)
- Basic camera detection via CPU monitoring
- Time-based color temperature adjustment
- Ambient light brightness adjustment
- Battery awareness features
- Auto-discovery of lights on network
- LaunchAgent-based background service

---

**Made with ❤️ for the Mac and Elgato community**