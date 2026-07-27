#!/bin/zsh

set -euo pipefail

if [[ "$#" -ne 3 ]]; then
    print -u2 "Usage: capture_studioquest_root_states.sh <simulator-udid> <app-path> <output-prefix>"
    exit 64
fi

simulator_id="$1"
app_path="$2"
output_prefix="$3"
bundle_id="com.alexmalaimare.practicebuddy"
destinations=(today quest community you)

xcrun simctl bootstatus "$simulator_id" -b
xcrun simctl install "$simulator_id" "$app_path"
xcrun simctl status_bar "$simulator_id" override \
    --time "9:41" \
    --batteryState charged \
    --batteryLevel 100 \
    --wifiBars 3 \
    --cellularBars 4

for appearance in light dark; do
    for destination_index in {0..3}; do
        destination_name="${destinations[$((destination_index + 1))]}"
        output_path="${output_prefix}-${destination_name}-${appearance}.png"

        xcrun simctl launch \
            --terminate-running-process \
            "$simulator_id" \
            "$bundle_id" \
            --qa-skip-onboarding \
            --qa-skip-version-gate \
            --qa-destination "$destination_index" \
            --qa-community-populated \
            --qa-populated \
            --qa-appearance "$appearance"
        sleep 3
        xcrun simctl io "$simulator_id" screenshot "$output_path"
    done
done

xcrun simctl terminate "$simulator_id" "$bundle_id" || true
