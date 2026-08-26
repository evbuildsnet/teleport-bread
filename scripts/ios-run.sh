#!/usr/bin/env bash
# Boot the simulator, install the app, run it with its console attached.
# Ctrl-C ends the app in the simulator, not just this script.
set -euo pipefail

sim_name=$1
app=$2
bundle=dev.ev.inboxzero.app

udid=$(xcrun simctl list devices available | grep -F "$sim_name (" | head -1 | sed -E 's/.*\(([0-9A-F-]+)\).*/\1/')
if [[ -z $udid ]]; then
  echo "No available simulator named '$sim_name'. Pick one: xcrun simctl list devices available" >&2
  exit 1
fi

xcrun simctl boot "$udid" 2>/dev/null || true # already booted is fine
open -a Simulator
xcrun simctl install "$udid" "$app"

trap 'xcrun simctl terminate "$udid" "$bundle" 2>/dev/null || true' INT TERM EXIT
echo "▶ $sim_name · ⌃C to quit"
xcrun simctl launch --console-pty "$udid" "$bundle"
