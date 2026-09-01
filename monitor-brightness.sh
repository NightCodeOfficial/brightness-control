#!/usr/bin/env bash
#
# Control external monitor brightness via DDC/CI using ddcutil.
# Linux counterpart to MonitorBrightness.ps1.

set -euo pipefail

BRIGHTNESS=50
MONITOR_INDEX=1
LIST=false

usage() {
    cat <<'EOF'
Usage: monitor-brightness.sh [OPTIONS]

Control external monitor brightness via DDC/CI.

Options:
  --list, -l                  List detected monitors and current brightness
  --brightness, -b <0-100>    Target brightness (default: 50)
  --monitor-index, -m <n>     Zero-based monitor index (default: 1)
  --help, -h                  Show this help message

Examples:
  monitor-brightness.sh --list
  monitor-brightness.sh --brightness 75
  monitor-brightness.sh --monitor-index 0 --brightness 30
EOF
}

require_ddcutil() {
    if ! command -v ddcutil &>/dev/null; then
        echo "Error: ddcutil is required but not installed." >&2
        echo "  Debian/Ubuntu: sudo apt install ddcutil" >&2
        echo "  Fedora:          sudo dnf install ddcutil" >&2
        echo "  Arch:            sudo pacman -S ddcutil" >&2
        exit 1
    fi
}

# Returns display numbers (1-based, as ddcutil uses) one per line.
get_display_numbers() {
    ddcutil detect --terse 2>/dev/null \
        | sed -n 's/^Display \([0-9]*\).*/\1/p' \
        || true
}

get_monitor_name() {
    local display="$1"
    ddcutil detect 2>/dev/null \
        | awk -v d="$display" '
            $0 ~ "^Display " d "$" { found=1; next }
            found && /^   Model:/ { print $3; for (i=4; i<=NF; i++) printf " %s", $i; print ""; exit }
            found && /^Display / { exit }
        '
}

get_brightness() {
    local display="$1"
    local output

    if ! output=$(ddcutil --display "$display" getvcp 10 --terse 2>/dev/null); then
        return 1
    fi

    # Terse format: feature_code current_value max_value ...
    echo "$output" | awk '{ print $2, $3 }'
}

list_monitors() {
    local index=0
    local display

    printf "%-5s %-30s %-20s %-18s %-13s %s\n" \
        "Index" "Name" "BrightnessSupported" "CurrentBrightness" "MinBrightness" "MaxBrightness"

    while IFS= read -r display; do
        [[ -z "$display" ]] && continue

        local name
        name=$(get_monitor_name "$display")
        [[ -z "$name" ]] && name="Display $display"

        local brightness_info
        if brightness_info=$(get_brightness "$display"); then
            local current max
            current=$(echo "$brightness_info" | awk '{ print $1 }')
            max=$(echo "$brightness_info" | awk '{ print $2 }')
            printf "%-5s %-30s %-20s %-18s %-13s %s\n" \
                "$index" "$name" "True" "$current" "0" "$max"
        else
            printf "%-5s %-30s %-20s %-18s %-13s %s\n" \
                "$index" "$name" "False" "" "" ""
        fi

        index=$((index + 1))
    done < <(get_display_numbers)

    if [[ "$index" -eq 0 ]]; then
        echo "No DDC/CI-capable monitors detected." >&2
        exit 1
    fi
}

set_brightness() {
    if [[ "$BRIGHTNESS" -lt 0 || "$BRIGHTNESS" -gt 100 ]]; then
        echo "Error: Brightness must be between 0 and 100." >&2
        exit 1
    fi

    local displays=()
    while IFS= read -r display; do
        [[ -n "$display" ]] && displays+=("$display")
    done < <(get_display_numbers)

    if [[ "${#displays[@]}" -eq 0 ]]; then
        echo "Error: No DDC/CI-capable monitors detected." >&2
        exit 1
    fi

    if [[ "$MONITOR_INDEX" -lt 0 || "$MONITOR_INDEX" -ge "${#displays[@]}" ]]; then
        echo "Error: Invalid monitor index. Use --list to see available indexes." >&2
        exit 1
    fi

    local display="${displays[$MONITOR_INDEX]}"

    if ! ddcutil --display "$display" setvcp 10 "$BRIGHTNESS" &>/dev/null; then
        echo "Error: Failed to set brightness. The monitor may not support DDC/CI brightness control, or DDC/CI may be disabled in the monitor menu." >&2
        exit 1
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --list|-l|-List)
            LIST=true
            shift
            ;;
        --brightness|-b|-Brightness)
            BRIGHTNESS="${2:?Error: --brightness requires a value}"
            shift 2
            ;;
        --monitor-index|-m|-MonitorIndex)
            MONITOR_INDEX="${2:?Error: --monitor-index requires a value}"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Error: Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

require_ddcutil

if $LIST; then
    list_monitors
else
    set_brightness
fi
