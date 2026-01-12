#!/bin/bash
#
# elgato-light.sh - Automatic Elgato Key Light control based on camera state
#
# Automatically turns your light on when your Mac's camera activates.
# For full documentation, see README.md
#
# QUICK START:
#   ./elgato-light.sh install      # Install automatic control
#   ./elgato-light.sh uninstall    # Remove automatic control
#   ./elgato-light.sh --help       # Show all commands
#
# CONFIGURATION:
#   Settings are stored in elgato-light.conf (same directory as this script)
#   See "QUICK SETTINGS" section below to edit values directly in this script.
#

set -euo pipefail

# =============================================================================
# QUICK SETTINGS - Edit common values directly here
# =============================================================================
# These values override the config file if uncommented.
# Uncomment (remove #) and set your preferred values.
#
# Light discovery:
#   LIGHT_HOST="elgato-key-light-air-2378.local"  # Your light's hostname (or leave empty for auto)
#
# Manual brightness/temperature (when auto-adjust is disabled):
#   BRIGHTNESS=50                                  # 0-100
#   TEMPERATURE=250                                # 143 (warm) to 344 (cool)
#
# Time-based temperature schedule:
#   TEMP_EARLY_MORNING=200                        # 5-8am: Warm for wake-up
#   TEMP_MIDDAY=280                               # 9am-5pm: Cool for focus
#   TEMP_EVENING=220                              # 5-9pm: Warm for evening
#   TEMP_NIGHT=180                                # 9pm-5am: Very warm for night
#
# Enable/disable features:
#   AUTO_ADJUST_TEMPERATURE=true                  # Time-based color temp
#   AUTO_ADJUST_BRIGHTNESS=true                   # Ambient light adjustment
#
# For all settings, edit: elgato-light.conf (same directory as this script)
# =============================================================================

# =============================================================================
# CONFIGURATION LOADER
# =============================================================================
# All settings can be customized in elgato-light.conf (same directory as script)
# Default values are defined below and used if config file doesn't exist.

# Configuration file location (same directory as this script)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/elgato-light.conf"

# Default configuration values (used if config file doesn't exist)
# These match the values in the default config file
DEFAULT_LIGHT_HOST=""
DEFAULT_BRIGHTNESS=43
DEFAULT_TEMPERATURE=290
DEFAULT_AUTO_ADJUST_TEMPERATURE=true
DEFAULT_TEMP_EARLY_MORNING=200
DEFAULT_TEMP_MIDDAY=280
DEFAULT_TEMP_EVENING=220
DEFAULT_TEMP_NIGHT=180
DEFAULT_MAX_RETRIES=3
DEFAULT_RETRY_DELAY=1
DEFAULT_AUTO_ADJUST_BRIGHTNESS=true
DEFAULT_BRIGHTNESS_MIN=15
DEFAULT_BRIGHTNESS_MAX=100
DEFAULT_ENABLE_DEBUG_LOGS=false

# Load configuration from file, or use defaults
load_config() {
    # Initialize all variables with defaults
    LIGHT_HOST="$DEFAULT_LIGHT_HOST"
    BRIGHTNESS="$DEFAULT_BRIGHTNESS"
    TEMPERATURE="$DEFAULT_TEMPERATURE"
    AUTO_ADJUST_TEMPERATURE="$DEFAULT_AUTO_ADJUST_TEMPERATURE"
    TEMP_EARLY_MORNING="$DEFAULT_TEMP_EARLY_MORNING"
    TEMP_MIDDAY="$DEFAULT_TEMP_MIDDAY"
    TEMP_EVENING="$DEFAULT_TEMP_EVENING"
    TEMP_NIGHT="$DEFAULT_TEMP_NIGHT"
    MAX_RETRIES="$DEFAULT_MAX_RETRIES"
    RETRY_DELAY="$DEFAULT_RETRY_DELAY"
    AUTO_ADJUST_BRIGHTNESS="$DEFAULT_AUTO_ADJUST_BRIGHTNESS"
    BRIGHTNESS_MIN="$DEFAULT_BRIGHTNESS_MIN"
    BRIGHTNESS_MAX="$DEFAULT_BRIGHTNESS_MAX"
    ENABLE_DEBUG_LOGS="$DEFAULT_ENABLE_DEBUG_LOGS"

    # If config file exists, source it to override defaults
    if [[ -f "$CONFIG_FILE" ]]; then
        # Source the config file safely (only load valid shell variable assignments)
        # shellcheck disable=SC1090
        source "$CONFIG_FILE"
    fi
}

# Generate default configuration file if it doesn't exist
generate_default_config() {
    mkdir -p "$(dirname "$CONFIG_FILE")"

    cat > "$CONFIG_FILE" <<'EOF'
# Elgato Key Light Camera Sync - Configuration File
# This file contains all user-configurable settings for the automation script.
# It should be in the same directory as elgato-light.sh
# After editing, restart the service: ./elgato-light.sh install

# =============================================================================
# LIGHT DISCOVERY
# =============================================================================

# Your light's hostname (run './elgato-light.sh discover' to find it)
# Leave empty for auto-discovery (uses 24-hour cache for performance)
# Example: LIGHT_HOST="elgato-key-light-air-2378.local"
LIGHT_HOST=""

# =============================================================================
# LIGHT SETTINGS
# =============================================================================

# Base brightness level (0-100)
# Only used when AUTO_ADJUST_BRIGHTNESS is false
BRIGHTNESS=43

# Base color temperature in mireds (143 = very warm/candlelight, 344 = very cool/daylight)
# Only used when AUTO_ADJUST_TEMPERATURE is false
TEMPERATURE=290

# =============================================================================
# AUTO COLOR TEMPERATURE (TIME-BASED)
# =============================================================================

# Automatically adjust color temperature based on time of day
# true = use time-based schedule below, false = use fixed TEMPERATURE above
AUTO_ADJUST_TEMPERATURE=true

# Time-based temperature schedule (24-hour format, temperature in mireds)
# Warmer temperatures (lower values) are easier on eyes in morning/evening
# Cooler temperatures (higher values) promote alertness during work hours
TEMP_EARLY_MORNING=200   # 5:00 AM - 8:59 AM   Warm for gentle wake-up
TEMP_MIDDAY=280          # 9:00 AM - 4:59 PM   Cool for alertness/focus
TEMP_EVENING=220         # 5:00 PM - 8:59 PM   Warm for comfortable evening
TEMP_NIGHT=180           # 9:00 PM - 4:59 AM   Very warm for late night


# =============================================================================
# LOGGING
# =============================================================================

# Enable verbose debug logging
# true = log every camera check and decision, false = only log state changes
# Debug logs are written to /tmp/elgato-light.log
ENABLE_DEBUG_LOGS=false
EOF
}

# Load the configuration
load_config

# =============================================================================
# END CONFIGURATION
# =============================================================================

# =============================================================================
# SCRIPT CONSTANTS
# =============================================================================
# These values are fixed and should not be changed

SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"  # Full path to this script
PLIST_NAME="com.local.elgato-camera-light"                     # LaunchAgent identifier
PLIST_PATH="$HOME/Library/LaunchAgents/${PLIST_NAME}.plist"   # LaunchAgent plist location
LOG_FILE="/tmp/elgato-light.log"                               # Log file path
LIGHT_PORT=9123                                                # Elgato light API port (fixed)

# =============================================================================
# LOGGING UTILITIES
# =============================================================================

# Log to both console and file (used for important events)
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Log only to file (used for less important events)
log_quiet() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

# Log debug information (only if ENABLE_DEBUG_LOGS is true)
log_debug() {
    if [[ "$ENABLE_DEBUG_LOGS" == "true" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] DEBUG: $*" >> "$LOG_FILE"
    fi
}

# Print error message and exit
die() {
    echo "Error: $*" >&2
    exit 1
}

# =============================================================================
# AMBIENT LIGHT SENSOR
# =============================================================================

# Read ambient light level from Mac's built-in light sensor
# Returns: 0-100 scale representing ambient light level (0 = dark, 100 = very bright)
# How it works:
#   1. Queries macOS IORegistry for the ambient light sensor hardware
#   2. Reads raw lux value (light intensity measurement)
#   3. Converts to 0-100 scale for easier brightness calculations
get_ambient_light_level() {
    local lux

    # Primary method: Read from ALSSensor (Ambient Light Sensor)
    # This is available on most modern Macs
    lux=$(ioreg -r -k "ALSSensor" 2>/dev/null | grep -o '"ALSSensor" = [0-9]*' | awk '{print $3}' | head -1)

    if [[ -z "$lux" ]]; then
        # Fallback: Try reading from AppleLMUController (older Macs)
        lux=$(ioreg -r -c "AppleLMUController" 2>/dev/null | grep -o '"lux" = [0-9]*' | awk '{print $3}' | head -1)
    fi

    if [[ -z "$lux" ]]; then
        # No sensor available (desktop Macs don't have one)
        # Return middle value as safe default
        log_debug "Ambient light sensor not found, using mid-range brightness"
        echo "50"
        return 0
    fi

    # Convert raw lux reading to 0-100 scale
    # Typical indoor lighting ranges from 100-1000 lux
    # We cap at 500 lux and map that to 100 (anything brighter is also 100)
    local scaled
    scaled=$(awk "BEGIN {print int(($lux / 500.0) * 100); if ($lux / 500.0 * 100 > 100) print 100}")

    log_debug "Ambient light: ${lux} lux (scaled: ${scaled}/100)"
    echo "$scaled"
}

# =============================================================================
# BRIGHTNESS CALCULATION
# =============================================================================

# Calculate appropriate brightness based on ambient light
# Uses inverse relationship: bright room = dimmer light, dark room = brighter light
# This provides better illumination - in a dark room you need more light,
# in a bright room you only need a subtle fill light.
#
# Returns: Brightness percentage (BRIGHTNESS_MIN to BRIGHTNESS_MAX)
get_brightness_for_ambient() {
    # If auto-adjustment is disabled, use fixed brightness from config
    if [[ "$AUTO_ADJUST_BRIGHTNESS" != "true" ]]; then
        echo "$BRIGHTNESS"
        return 0
    fi

    local ambient_level
    ambient_level=$(get_ambient_light_level)

    # Calculate brightness using inverse formula:
    # brightness = MAX - (ambient_percentage × range)
    # Example: If ambient is 80/100 (bright room) and range is 15-100:
    #   brightness = 100 - (0.8 × 85) = 100 - 68 = 32% (dimmer light)
    local brightness
    brightness=$(awk "BEGIN {
        ambient = $ambient_level / 100.0
        range = $BRIGHTNESS_MAX - $BRIGHTNESS_MIN
        result = $BRIGHTNESS_MAX - (ambient * range)
        print int(result)
    }")

    # Safety bounds check (should never trigger, but just in case)
    if (( brightness < BRIGHTNESS_MIN )); then
        brightness=$BRIGHTNESS_MIN
    elif (( brightness > BRIGHTNESS_MAX )); then
        brightness=$BRIGHTNESS_MAX
    fi

    log_debug "Calculated brightness: ${brightness}% (ambient: ${ambient_level}/100)"
    echo "$brightness"
}

# =============================================================================
# COLOR TEMPERATURE CALCULATION
# =============================================================================

# Calculate appropriate color temperature based on current time of day
# Implements circadian-friendly lighting:
#   - Warmer (lower mireds) in morning/evening = easier on eyes, promotes relaxation
#   - Cooler (higher mireds) during day = promotes alertness and focus
#
# Returns: Temperature value in mireds (143-344 range)
get_temperature_for_time() {
    # If auto-adjustment is disabled, use fixed temperature from config
    if [[ "$AUTO_ADJUST_TEMPERATURE" != "true" ]]; then
        echo "$TEMPERATURE"
        return 0
    fi

    # Get current hour (0-23) and remove leading zero for comparison
    local hour=$(date +%H | sed 's/^0//')
    local temp

    # Select temperature based on time of day
    if (( hour >= 5 && hour < 9 )); then
        # Early morning (5 AM - 8:59 AM): Warm light for gentle wake-up
        temp=$TEMP_EARLY_MORNING
        log_debug "Time: ${hour}:xx - Using early morning temperature: ${temp} mireds"
    elif (( hour >= 9 && hour < 17 )); then
        # Midday (9 AM - 4:59 PM): Cool light for alertness and productivity
        temp=$TEMP_MIDDAY
        log_debug "Time: ${hour}:xx - Using midday temperature: ${temp} mireds"
    elif (( hour >= 17 && hour < 21 )); then
        # Evening (5 PM - 8:59 PM): Warm light for comfortable evening
        temp=$TEMP_EVENING
        log_debug "Time: ${hour}:xx - Using evening temperature: ${temp} mireds"
    else
        # Night (9 PM - 4:59 AM): Very warm light for late night, minimal blue light
        temp=$TEMP_NIGHT
        log_debug "Time: ${hour}:xx - Using night temperature: ${temp} mireds"
    fi

    echo "$temp"
}

# =============================================================================
# CONFIGURATION VALIDATION
# =============================================================================

# Validate all configuration values are within acceptable ranges
# Called before executing commands that use the configuration
# Exits with error message if validation fails
validate_config() {
    if [[ -n "$BRIGHTNESS" ]] && (( BRIGHTNESS < 0 || BRIGHTNESS > 100 )); then
        die "BRIGHTNESS must be between 0 and 100 (got: $BRIGHTNESS)"
    fi

    if [[ -n "$TEMPERATURE" ]] && (( TEMPERATURE < 143 || TEMPERATURE > 344 )); then
        die "TEMPERATURE must be between 143 and 344 (got: $TEMPERATURE)"
    fi

    # Validate time-based temperatures
    for temp_var in TEMP_EARLY_MORNING TEMP_MIDDAY TEMP_EVENING TEMP_NIGHT; do
        local temp_value="${!temp_var}"
        if (( temp_value < 143 || temp_value > 344 )); then
            die "$temp_var must be between 143 and 344 (got: $temp_value)"
        fi
    done

    log_debug "Configuration validated successfully"
}

# Run a command with a timeout (macOS compatible)
run_with_timeout() {
    local secs=$1
    shift
    # Run command in background, kill after timeout
    "$@" &
    local pid=$!
    (sleep "$secs" && kill "$pid" 2>/dev/null) &
    local killer=$!
    wait "$pid" 2>/dev/null
    kill "$killer" 2>/dev/null
    wait "$killer" 2>/dev/null
}

# Discover Elgato lights on the network using dns-sd
discover_lights() {
    local timeout_secs=${1:-5}
    local found_lights=""

    echo "Searching for Elgato lights (${timeout_secs}s timeout)..."

    # Method 1: Use dns-sd to browse for Elgato lights (_elg._tcp service)
    # dns-sd runs continuously, so we capture output in background and kill after timeout
    echo "Trying service browse..."
    local tmpfile="/tmp/elgato-dnssd-$$"

    # dns-sd outputs to stdout - need to capture properly
    (dns-sd -B _elg._tcp local 2>&1) > "$tmpfile" &
    local dnssd_pid=$!
    sleep "$timeout_secs"
    kill "$dnssd_pid" 2>/dev/null || true
    wait "$dnssd_pid" 2>/dev/null || true

    if [[ -s "$tmpfile" ]]; then
        while IFS= read -r line; do
            # Match lines like: 15:12:14.670  Add  2  14 local.  _elg._tcp.  Elgato Key Light Air 664D
            # Format: Timestamp  Add  Flags  if  Domain  ServiceType  InstanceName
            if [[ "$line" =~ Add[[:space:]]+[0-9]+[[:space:]]+[0-9]+[[:space:]]+local\.[[:space:]]+_elg\._tcp\.[[:space:]]+(.+)$ ]]; then
                local name="${BASH_REMATCH[1]}"
                name=$(echo "$name" | xargs)  # trim whitespace
                if [[ -n "$name" ]]; then
                    # Resolve the service instance to get hostname
                    local resolve_file="/tmp/elgato-resolve-$$"
                    (dns-sd -L "$name" _elg._tcp local 2>&1) > "$resolve_file" &
                    local resolve_pid=$!
                    sleep 2
                    kill "$resolve_pid" 2>/dev/null || true
                    wait "$resolve_pid" 2>/dev/null || true

                    if [[ -s "$resolve_file" ]]; then
                        # Look for "can be reached at hostname.local.:port" pattern
                        local hostname
                        hostname=$(grep -o 'can be reached at [^ ]*' "$resolve_file" | head -1 | sed 's/can be reached at //' | sed 's/:.*$//' | sed 's/\.$//')
                        if [[ -z "$hostname" ]]; then
                            # Fallback: look for any .local hostname
                            hostname=$(grep -o '[a-zA-Z0-9_-]*\.local' "$resolve_file" | head -1)
                        fi
                        [[ -n "$hostname" ]] && found_lights="${found_lights}${hostname}"$'\n'
                        rm -f "$resolve_file"
                    fi
                fi
            fi
        done < "$tmpfile"
        rm -f "$tmpfile"
    fi

    # Method 2: Try direct mDNS query using dns-sd -Q for PTR records
    if [[ -z "$found_lights" ]]; then
        echo "Trying PTR query..."
        tmpfile="/tmp/elgato-ptr-$$"
        dns-sd -Q _elg._tcp.local PTR > "$tmpfile" 2>/dev/null &
        dnssd_pid=$!
        sleep 3
        kill "$dnssd_pid" 2>/dev/null || true
        wait "$dnssd_pid" 2>/dev/null || true

        if [[ -f "$tmpfile" ]]; then
            while IFS= read -r line; do
                # Look for PTR records pointing to service instances
                if [[ "$line" =~ ([a-zA-Z0-9._-]+)\._elg\._tcp\.local ]]; then
                    local instance="${BASH_REMATCH[1]}"
                    # Try to resolve this instance
                    local resolve_file="/tmp/elgato-resolve2-$$"
                    dns-sd -L "$instance" _elg._tcp local > "$resolve_file" 2>/dev/null &
                    local resolve_pid=$!
                    sleep 2
                    kill "$resolve_pid" 2>/dev/null || true
                    wait "$resolve_pid" 2>/dev/null || true

                    if [[ -f "$resolve_file" ]]; then
                        local hostname
                        hostname=$(grep -o '[a-zA-Z0-9_-]*\.local\.' "$resolve_file" | head -1 | sed 's/\.$//')
                        [[ -n "$hostname" ]] && found_lights="${found_lights}${hostname}"$'\n'
                        rm -f "$resolve_file"
                    fi
                fi
            done < "$tmpfile"
            rm -f "$tmpfile"
        fi
    fi

    # Method 3: Scan common ports on local subnet for Elgato API
    if [[ -z "$found_lights" ]]; then
        echo "Trying network scan on port ${LIGHT_PORT}..."
        # Get local IP and subnet - try multiple interfaces
        local local_ip
        local_ip=$(ipconfig getifaddr en0 2>/dev/null || true)
        [[ -z "$local_ip" ]] && local_ip=$(ipconfig getifaddr en1 2>/dev/null || true)
        [[ -z "$local_ip" ]] && local_ip=$(route get default 2>/dev/null | grep interface | awk '{print $2}' | xargs ipconfig getifaddr 2>/dev/null || true)

        if [[ -n "$local_ip" && "$local_ip" =~ ^([0-9]+\.[0-9]+\.[0-9]+)\.[0-9]+$ ]]; then
            local subnet="${BASH_REMATCH[1]}"
            local scan_results="/tmp/elgato-scan-$$"
            : > "$scan_results"

            # Parallel scan using background jobs (check ~50 at a time for speed)
            for i in {1..254}; do
                local ip="${subnet}.${i}"
                (
                    if curl -s --connect-timeout 0.3 --max-time 0.5 "http://${ip}:${LIGHT_PORT}/elgato/accessory-info" >/dev/null 2>&1; then
                        # Found something! Try to get its mDNS name
                        local mdns_name
                        mdns_name=$(dig +short -x "$ip" @224.0.0.251 -p 5353 2>/dev/null | head -1 | sed 's/\.$//')
                        if [[ -n "$mdns_name" ]]; then
                            echo "$mdns_name" >> "$scan_results"
                        else
                            echo "$ip" >> "$scan_results"
                        fi
                    fi
                ) &
                # Limit concurrent jobs
                if (( i % 50 == 0 )); then
                    wait
                fi
            done
            wait

            if [[ -s "$scan_results" ]]; then
                found_lights=$(cat "$scan_results")
            fi
            rm -f "$scan_results"
        fi
    fi

    # Remove duplicates and empty lines
    found_lights=$(echo "$found_lights" | grep -v '^$' | sort -u)

    if [[ -z "$found_lights" ]]; then
        echo ""
        echo "No Elgato lights found on the network."
        echo ""
        echo "Troubleshooting tips:"
        echo "  1. Ensure your light is powered on and connected to the same network"
        echo "  2. Try the Elgato Control Center app to verify connectivity"
        echo "  3. Manually find the IP in Control Center, then run:"
        echo "     dig -x <IP> @224.0.0.251 -p 5353"
        echo "  4. Or just set LIGHT_HOST to the IP address directly in this script"
        return 1
    fi

    local light_count
    light_count=$(echo "$found_lights" | wc -l | xargs)
    echo ""
    echo "Found ${light_count} light(s):"

    local first_light=""
    while IFS= read -r light; do
        [[ -z "$light" ]] && continue
        [[ -z "$first_light" ]] && first_light="$light"
        echo "  - $light"
        # Try to get more info
        if curl -s --connect-timeout 2 "http://${light}:${LIGHT_PORT}/elgato/accessory-info" >/dev/null 2>&1; then
            local info
            info=$(curl -s --connect-timeout 2 "http://${light}:${LIGHT_PORT}/elgato/accessory-info" 2>/dev/null || echo "{}")
            local display_name
            display_name=$(echo "$info" | grep -o '"displayName"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
            [[ -n "$display_name" ]] && echo "    Display name: $display_name"
        fi
    done <<< "$found_lights"

    echo ""
    echo "To use a specific light, edit LIGHT_HOST in this script:"
    echo "  LIGHT_HOST=\"${first_light}\""

    # Return the first light found for auto-discovery
    echo "$first_light"
}

# Get the light hostname (configured or auto-discovered)
get_light_host() {
    if [[ -n "$LIGHT_HOST" ]]; then
        echo "$LIGHT_HOST"
        return 0
    fi

    # Auto-discover (cache result for this session)
    local cache_file="/tmp/elgato-light-host.cache"
    local cache_max_age=86400  # 24 hours (lights don't move often)

    if [[ -f "$cache_file" ]]; then
        local cache_age=$(($(date +%s) - $(stat -f %m "$cache_file")))
        if [[ $cache_age -lt $cache_max_age ]]; then
            local cached_host
            cached_host=$(cat "$cache_file")
            if [[ -n "$cached_host" ]]; then
                log_debug "Using cached light hostname: $cached_host"
                echo "$cached_host"
                return 0
            fi
        fi
    fi

    # Discover and cache
    log_debug "Discovering light (no cache or expired)..."
    local host
    host=$(discover_lights 3 2>/dev/null | tail -1)
    if [[ -n "$host" && "$host" =~ \.local$ ]]; then
        echo "$host" > "$cache_file"
        log_debug "Discovered and cached: $host"
        echo "$host"
        return 0
    fi

    log_debug "Failed to discover light"
    return 1
}

# Send a command to the light with retries
light_request() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"

    local host
    host=$(get_light_host) || die "Could not find Elgato light. Run '$0 discover' or set LIGHT_HOST in script."

    local url="http://${host}:${LIGHT_PORT}${endpoint}"
    local attempt=1

    while [[ $attempt -le $MAX_RETRIES ]]; do
        local response
        local http_code

        if [[ -n "$data" ]]; then
            response=$(curl -s -w "\n%{http_code}" -X "$method" \
                --connect-timeout 5 \
                --max-time 10 \
                -H "Content-Type: application/json" \
                -d "$data" \
                "$url" 2>/dev/null) || true
        else
            response=$(curl -s -w "\n%{http_code}" -X "$method" \
                --connect-timeout 5 \
                --max-time 10 \
                "$url" 2>/dev/null) || true
        fi

        http_code=$(echo "$response" | tail -1)
        response=$(echo "$response" | sed '$d')

        if [[ "$http_code" =~ ^2[0-9][0-9]$ ]]; then
            echo "$response"
            return 0
        fi

        log_quiet "Request failed (attempt $attempt/$MAX_RETRIES): HTTP $http_code"
        ((attempt++))
        [[ $attempt -le $MAX_RETRIES ]] && sleep "$RETRY_DELAY"
    done

    log "Failed to reach light at $url after $MAX_RETRIES attempts"
    return 1
}

# Turn light on or off
set_light() {
    local state="$1"  # "on" or "off"
    local brightness="${2:-}"  # Optional brightness override
    local quiet="${3:-false}"  # Optional quiet mode (suppress logs)
    local on_value=0

    [[ "$state" == "on" ]] && on_value=1

    # Get appropriate temperature based on time of day
    local temp
    temp=$(get_temperature_for_time)

    # Get brightness (use provided value or calculate from ambient)
    if [[ -z "$brightness" ]]; then
        brightness=$(get_brightness_for_ambient)
    fi

    local data
    data=$(cat <<EOF
{"lights":[{"brightness":${brightness},"temperature":${temp},"on":${on_value}}],"numberOfLights":1}
EOF
)

    if light_request "PUT" "/elgato/lights" "$data" >/dev/null; then
        if [[ "$quiet" != "true" ]]; then
            if [[ "$state" == "on" ]]; then
                log "Light turned on (brightness: ${brightness}%, temperature: ${temp} mireds)"
            else
                log "Light turned off"
            fi
        fi
        return 0
    else
        log "Failed to turn light $state"
        return 1
    fi
}

# Get light status
get_status() {
    local response
    response=$(light_request "GET" "/elgato/lights") || return 1

    echo "Light status:"
    echo "$response" | python3 -m json.tool 2>/dev/null || echo "$response"
}

# Check if light is currently on (returns 0 if on, 1 if off)
is_light_on() {
    local response
    response=$(light_request "GET" "/elgato/lights" 2>/dev/null) || return 1

    # Check if "on":1 appears in response
    if echo "$response" | grep -q '"on"[[:space:]]*:[[:space:]]*1'; then
        return 0  # Light is on
    else
        return 1  # Light is off
    fi
}

# Test connection to the light
test_connection() {
    echo "Testing connection to Elgato light..."

    local host
    if ! host=$(get_light_host); then
        echo "FAILED: Could not find light"
        return 1
    fi

    echo "Found light: $host"

    # Test accessory info endpoint
    echo -n "Testing API connection... "
    if light_request "GET" "/elgato/accessory-info" >/dev/null 2>&1; then
        echo "OK"
    else
        echo "FAILED"
        return 1
    fi

    # Test light control endpoint
    echo -n "Testing light control... "
    if light_request "GET" "/elgato/lights" >/dev/null 2>&1; then
        echo "OK"
    else
        echo "FAILED"
        return 1
    fi

    echo ""
    echo "All tests passed! Ready to install."
    get_status
}

# =============================================================================
# CAMERA MONITOR - EVENT-BASED DETECTION
# =============================================================================

# Monitor camera state using event-based detection (macOS Tahoe+)
# This is the main function that runs as a background service via LaunchAgent
#
# MONITORING STRATEGY:
#   - Uses macOS log stream to detect camera events in real-time
#   - Listens for ControlCenter "Frame publisher cameras changed" events
#   - Camera ON: cameras array has entries [app: [uuid]]
#   - Camera OFF: cameras array is empty [:]
#   - Event-based approach = instant response + 0% CPU when idle
#
# FEATURES:
#   - Works with BOTH built-in and external cameras
#   - Instant response (event-driven, no polling delay)
#   - Zero CPU overhead when camera is idle
#   - Auto brightness: adjusts based on ambient light sensor
#   - Auto temperature: adjusts based on time of day
monitor_camera() {
    log "Starting camera monitor (event-based detection)..."
    log "Detection: macOS ControlCenter frame publisher events"

    # Log feature status
    if [[ "$AUTO_ADJUST_TEMPERATURE" == "true" ]]; then
        log "Auto temperature adjustment ENABLED"
        log "  Early morning (5-8am): ${TEMP_EARLY_MORNING} mireds"
        log "  Midday (9am-4pm): ${TEMP_MIDDAY} mireds"
        log "  Evening (5-8pm): ${TEMP_EVENING} mireds"
        log "  Night (9pm-4am): ${TEMP_NIGHT} mireds"
    else
        log "Fixed temperature: ${TEMPERATURE} mireds"
    fi

    if [[ "$AUTO_ADJUST_BRIGHTNESS" == "true" ]]; then
        log "Auto brightness adjustment ENABLED (range: ${BRIGHTNESS_MIN}-${BRIGHTNESS_MAX}%)"
    fi

    # Trap signals for graceful shutdown
    trap 'log "Monitor shutting down..."; exit 0' SIGTERM SIGINT

    log "Listening for camera events (0% CPU when idle)..."

    # Stream ControlCenter camera events
    # Note: Must use /usr/bin/log to avoid conflict with our log() function
    /usr/bin/log stream --predicate 'subsystem == "com.apple.controlcenter" and eventMessage contains "Frame publisher cameras"' 2>/dev/null | \
    while IFS= read -r line; do
        # Skip header lines
        [[ "$line" =~ ^(Filtering|Timestamp|---) ]] && continue

        log_debug "Event: $line"

        # Camera OFF: "Frame publisher cameras changed to [:]"
        # Camera ON: "Frame publisher cameras changed to [com.google.Chrome: ["UUID"]]"

        if echo "$line" | grep -q "Frame publisher cameras changed to \[:"; then
            # Cameras array is empty = all cameras off
            log "Camera OFF (event) → Light OFF"
            set_light off
        elif echo "$line" | grep -q "Frame publisher cameras changed to"; then
            # Cameras array has content = camera is on
            log "Camera ON (event) → Light ON"
            set_light on
        fi
    done

    # If log stream exits unexpectedly, log and exit
    log "ERROR: Log stream exited unexpectedly. Restarting..."
    exit 1
}

# Generate the LaunchAgent plist
generate_plist() {
    cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${PLIST_NAME}</string>
    <key>ServiceDescription</key>
    <string>Elgato Key Light camera sync</string>
    <key>ProgramArguments</key>
    <array>
        <string>${SCRIPT_PATH}</string>
        <string>monitor</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/elgato-light-stdout.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/elgato-light-stderr.log</string>
    <key>ThrottleInterval</key>
    <integer>5</integer>
</dict>
</plist>
EOF
}

# Check if script is in a macOS protected location (requires Gatekeeper approval)
check_gatekeeper() {
    local script_dir
    script_dir=$(dirname "$SCRIPT_PATH")

    # Protected locations that require special permissions for LaunchAgents
    local protected_paths=("$HOME/Desktop" "$HOME/Downloads" "$HOME/Documents")

    for protected in "${protected_paths[@]}"; do
        if [[ "$script_dir" == "$protected"* ]]; then
            return 0  # Is in protected location
        fi
    done
    return 1  # Not in protected location
}

# Remove quarantine attribute from script
remove_quarantine() {
    if xattr -l "$SCRIPT_PATH" 2>/dev/null | grep -q "com.apple.quarantine"; then
        echo "Removing quarantine attribute..."
        xattr -d com.apple.quarantine "$SCRIPT_PATH" 2>/dev/null || true
    fi
}

# Install the LaunchAgent
install_agent() {
    echo "Installing Elgato Light camera sync..."
    echo ""

    # Generate default config file if it doesn't exist
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "Creating default configuration file at $CONFIG_FILE"
        generate_default_config
        echo "You can customize settings by editing this file."
        echo ""
    fi

    # Test connection first
    if ! test_connection; then
        echo ""
        echo "Cannot proceed with installation - light connection failed."
        echo "Please fix the connection issue and try again."
        return 1
    fi

    echo ""

    # Remove quarantine attribute (in case downloaded from internet)
    remove_quarantine

    # Check for macOS security restrictions
    # LaunchAgents cannot execute scripts from Desktop/Downloads/Documents
    # due to TCC (Transparency, Consent, and Control) restrictions
    if check_gatekeeper; then
        echo ""
        echo "WARNING: Script is in a macOS protected location."
        echo ""
        echo "LaunchAgents cannot execute scripts from Desktop, Downloads, or Documents"
        echo "due to macOS security restrictions (TCC/Gatekeeper)."
        echo ""
        echo "The script will be copied to ~/.local/bin/ for installation."
        echo ""

        # Create ~/.local/bin if needed
        local install_dir="$HOME/.local/bin"
        mkdir -p "$install_dir"

        # Copy script to safe location
        local new_script_path="$install_dir/elgato-light.sh"
        cp "$SCRIPT_PATH" "$new_script_path"
        chmod +x "$new_script_path"

        # Update SCRIPT_PATH for the plist generation
        SCRIPT_PATH="$new_script_path"

        echo "Copied to: $SCRIPT_PATH"
        echo ""
    fi

    # Unload existing agent if present
    if [[ -f "$PLIST_PATH" ]]; then
        echo "Removing existing installation..."
        launchctl unload "$PLIST_PATH" 2>/dev/null || true
    fi

    # Create LaunchAgents directory if needed
    mkdir -p "$HOME/Library/LaunchAgents"

    # Generate and install plist
    echo "Creating LaunchAgent..."
    generate_plist > "$PLIST_PATH"

    # If using auto-discovery, cache the light hostname for the LaunchAgent
    if [[ -z "$LIGHT_HOST" ]]; then
        echo "Caching light hostname for LaunchAgent..."
        local host
        host=$(get_light_host)
        if [[ -n "$host" ]]; then
            echo "$host" > /tmp/elgato-light-host.cache
            log_quiet "Cached light: $host"
        fi
    fi

    # Load the agent
    echo "Loading LaunchAgent..."
    if launchctl load -w "$PLIST_PATH"; then
        echo ""
        echo "Verifying LaunchAgent started correctly..."
        sleep 5  # Give it time to fully initialize and start monitoring

        # Check if the monitor process is actually running
        local monitor_running
        monitor_running=$(ps aux | grep "elgato-light.sh monitor" | grep -v grep | wc -l)

        if [[ "$monitor_running" -gt 0 ]]; then
            echo ""
            echo "✓ Installation complete!"
            echo ""
            echo "The light will now automatically turn on when your camera activates"
            echo "and turn off when it deactivates."
            echo ""
            echo "Features enabled:"
            [[ "$AUTO_ADJUST_TEMPERATURE" == "true" ]] && echo "  • Auto temperature (time-based)"
            [[ "$AUTO_ADJUST_BRIGHTNESS" == "true" ]] && echo "  • Auto brightness (ambient-based)"
            echo "  • Event-based detection (0% CPU when idle)"
            echo ""
            echo "Logs: $LOG_FILE"
            echo ""
            echo "To uninstall: $0 uninstall"
        else
            # Agent failed to start
            echo ""
            echo "WARNING: LaunchAgent failed to start properly"
            echo ""
            local stderr_content
            stderr_content=$(cat /tmp/elgato-light-stderr.log 2>/dev/null | tail -5)
            if [[ -n "$stderr_content" ]]; then
                echo "Error log:"
                echo "$stderr_content"
                echo ""
            fi

            if echo "$stderr_content" | grep -q "Operation not permitted"; then
                echo "This is a macOS security restriction. To fix:"
                echo ""
                echo "  1. Move the script outside Desktop/Downloads/Documents:"
                echo "     mkdir -p ~/.local/bin"
                echo "     cp \"$SCRIPT_PATH\" ~/.local/bin/"
                echo "     ~/.local/bin/elgato-light.sh install"
                echo ""
                echo "  2. Or grant Full Disk Access to /bin/bash:"
                echo "     System Settings > Privacy & Security > Full Disk Access"
                echo "     Click + and add /bin/bash (press Cmd+Shift+G to type path)"
            fi
            return 1
        fi
    else
        echo "Failed to load LaunchAgent"
        return 1
    fi
}

# Uninstall the LaunchAgent
uninstall_agent() {
    echo "Uninstalling Elgato Light camera sync..."

    if [[ -f "$PLIST_PATH" ]]; then
        launchctl unload "$PLIST_PATH" 2>/dev/null || true
        rm -f "$PLIST_PATH"
        echo "LaunchAgent removed."
    else
        echo "LaunchAgent not found (already uninstalled?)."
    fi

    # Clean up cache
    rm -f /tmp/elgato-light-host.cache

    echo "Uninstallation complete."
}

# Show usage information
usage() {
    cat <<EOF
Elgato Key Light Camera Sync - Automatic light control based on camera state

Usage: $0 <command>

Commands:
    discover    Find Elgato lights on your network
    test        Test connection to the configured light
    on          Turn the light on manually
    off         Turn the light off manually
    status      Get current light status
    install     Install LaunchAgent for automatic control
    uninstall   Remove LaunchAgent
    monitor     Run the camera monitor (used internally by LaunchAgent)

Configuration:
    All settings can be customized in:
      elgato-light.conf (same directory as this script)

    The config file will be created automatically with defaults on first run.
    After editing the config, restart the service with: $0 install

    Key settings:
      - LIGHT_HOST: Your light's hostname (or leave empty for auto-discovery)
      - AUTO_ADJUST_BRIGHTNESS: Adjust brightness based on ambient light
      - AUTO_ADJUST_TEMPERATURE: Adjust color temp based on time of day

Examples:
    $0 discover          # Find lights on your network
    $0 test              # Verify connection works
    $0 install           # Set up automatic camera sync
    $0 on                # Manually turn light on
    $0 off               # Manually turn light off

Logs:
    Main log: $LOG_FILE
    Stdout:   /tmp/elgato-light-stdout.log
    Stderr:   /tmp/elgato-light-stderr.log
EOF
}

# Main entry point
main() {
    local command="${1:-}"

    # Validate configuration for commands that need it
    case "$command" in
        on|off|status|test|install|monitor)
            validate_config
            ;;
    esac

    case "$command" in
        discover)
            discover_lights 5
            ;;
        test)
            test_connection
            ;;
        on)
            set_light on
            ;;
        off)
            set_light off
            ;;
        status)
            get_status
            ;;
        install)
            install_agent
            ;;
        uninstall)
            uninstall_agent
            ;;
        monitor)
            monitor_camera
            ;;
        -h|--help|help)
            usage
            ;;
        "")
            usage
            exit 1
            ;;
        *)
            echo "Unknown command: $command"
            echo ""
            usage
            exit 1
            ;;
    esac
}

main "$@"