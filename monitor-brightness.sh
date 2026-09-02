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
  --brightness, -b <0-100>    Target brightness percentage (default: 50)
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
    local output
    if ! output=$(ddcutil detect --terse 2>&1); then
        echo "Error: ddcutil could not detect monitors:" >&2
        echo "$output" >&2
        return 1
    fi

    printf '%s\n' "$output" \
        | sed -n 's/^Display[[:space:]]\+\([0-9]\+\).*/\1/p'
}

get_monitor_name() {
    local display="$1"
    ddcutil detect 2>/dev/null \
        | awk -v d="$display" '
            $0 ~ "^Display[[:space:]]+" d "[[:space:]]*$" { found=1; next }
            found && $0 ~ "^[[:space:]]*Model:" {
                sub(/^[[:space:]]*Model:[[:space:]]*/, "")
                print
                exit
            }
            found && /^Display[[:space:]]+[0-9]+/ { exit }
        '
}

# Prints: current_value max_value
get_brightness() {
    local display="$1"
    local output

    if ! output=$(ddcutil --display "$display" getvcp 10 --terse 2>/dev/null); then
        return 1
    fi

    # ddcutil continuous-feature terse format:
    #   VCP 10 C 50 100
    printf '%s\n' "$output" \
        | awk '
            toupper($1) == "VCP" &&
            (toupper($2) == "10" || toupper($2) == "0X10") &&
            toupper($3) == "C" {
                print $4, $5
                found=1
                exit
            }
            END { if (!found) exit 1 }
        '
}

percent_to_value() {
    local percent="$1"
    local maximum="$2"

    awk -v p="$percent" -v max="$maximum" '
        BEGIN {
            value = (max * p / 100.0)
            printf "%d\n", int(value + 0.5)
        }
    '
}

list_monitors() {
    local index=0
    local display
    local display_output

    if ! display_output=$(get_display_numbers); then
        exit 1
    fi

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
            current=$(awk '{ print $1 }' <<<"$brightness_info")
            max=$(awk '{ print $2 }' <<<"$brightness_info")
            printf "%-5s %-30s %-20s %-18s %-13s %s\n" \
                "$index" "$name" "True" "$current" "0" "$max"
        else
            printf "%-5s %-30s %-20s %-18s %-13s %s\n" \
                "$index" "$name" "False" "" "" ""
        fi

        index=$((index + 1))
    done <<<"$display_output"

    if [[ "$index" -eq 0 ]]; then
        echo "No DDC/CI-capable external monitors detected." >&2
        echo "Try: ddcutil environment" >&2
        exit 1
    fi
}

set_brightness() {
    if ! [[ "$BRIGHTNESS" =~ ^[0-9]+$ ]] || [[ "$BRIGHTNESS" -lt 0 || "$BRIGHTNESS" -gt 100 ]]; then
        echo "Error: Brightness must be an integer between 0 and 100." >&2
        exit 1
    fi

    if ! [[ "$MONITOR_INDEX" =~ ^[0-9]+$ ]]; then
        echo "Error: Monitor index must be a non-negative integer." >&2
        exit 1
    fi

    local display_output
    if ! display_output=$(get_display_numbers); then
        exit 1
    fi

    local displays=()
    while IFS= read -r display; do
        [[ -n "$display" ]] && displays+=("$display")
    done <<<"$display_output"

    if [[ "${#displays[@]}" -eq 0 ]]; then
        echo "Error: No DDC/CI-capable external monitors detected." >&2
        echo "Try: ddcutil environment" >&2
        exit 1
    fi

    if [[ "$MONITOR_INDEX" -ge "${#displays[@]}" ]]; then
        echo "Error: Invalid monitor index. Use --list to see available indexes." >&2
        exit 1
    fi

    local display="${displays[$MONITOR_INDEX]}"
    local brightness_info
    if ! brightness_info=$(get_brightness "$display"); then
        echo "Error: Display $display did not return VCP brightness feature 0x10." >&2
        echo "Check that DDC/CI is enabled in the monitor menu." >&2
        exit 1
    fi

    local maximum
    maximum=$(awk '{ print $2 }' <<<"$brightness_info")
    local target
    target=$(percent_to_value "$BRIGHTNESS" "$maximum")

    local output
    if ! output=$(ddcutil --display "$display" setvcp 10 "$target" 2>&1); then
        echo "Error: Failed to set brightness on Display $display." >&2
        [[ -n "$output" ]] && echo "$output" >&2
        echo "Check DDC/CI, I2C permissions, and the monitor connection." >&2
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
