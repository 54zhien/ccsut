#!/bin/bash
set -euo pipefail

# A real simulator render of the shipping SwiftUI views, with DEBUG-only fixtures.
DEVICE=$(xcrun simctl list devices available -j | python3 -c '
import json,sys
devices=[d for group in json.load(sys.stdin)["devices"].values() for d in group if "iPhone" in d["name"]]
if not devices: raise SystemExit("No available iPhone simulator")
devices.sort(key=lambda d: ("Pro" in d["name"], "Max" not in d["name"], d["name"]), reverse=True)
print(devices[0]["udid"])
')
APP="$RUNNER_TEMP/UIPreview/Build/Products/Debug-iphonesimulator/CCSUT.app"
OUT="$RUNNER_TEMP/ui-screenshots"
mkdir -p "$OUT"
xcrun simctl boot "$DEVICE" || true
xcrun simctl bootstatus "$DEVICE" -b
xcrun simctl status_bar "$DEVICE" override --time '9:41' --batteryState charged --batteryLevel 100
xcrun simctl install "$DEVICE" "$APP"

capture() {
  xcrun simctl ui "$DEVICE" appearance "$2"
  xcrun simctl launch --terminate-running-process "$DEVICE" com.imzhien.ccsut --preview-ui --preview-page "$1"
  sleep 3
  xcrun simctl io "$DEVICE" screenshot "$OUT/$1-$2.png"
}

capture schedule light
capture schedule dark
capture academic light
capture account light
capture course light
xcrun simctl terminate "$DEVICE" com.imzhien.ccsut

# Exercise the minimum-width timetable on a small native phone if available.
RUNTIME=$(xcrun simctl list runtimes -j | python3 -c 'import json,sys; print(next(r["identifier"] for r in json.load(sys.stdin)["runtimes"] if r.get("isAvailable") and "iOS" in r["name"]))')
TYPE=$(xcrun simctl list devicetypes -j | python3 -c 'import json,sys; print(next((r["identifier"] for r in json.load(sys.stdin)["devicetypes"] if r["name"]=="iPhone SE (3rd generation)"),""))')
if [ -n "$TYPE" ]; then
  SMALL=$(xcrun simctl create 'CCSUT Compact Preview' "$TYPE" "$RUNTIME")
  xcrun simctl boot "$SMALL"
  xcrun simctl bootstatus "$SMALL" -b
  xcrun simctl install "$SMALL" "$APP"
  xcrun simctl status_bar "$SMALL" override --time '9:41' --batteryState charged --batteryLevel 100
  xcrun simctl ui "$SMALL" appearance light
  xcrun simctl launch "$SMALL" com.imzhien.ccsut --preview-ui --preview-page schedule
  sleep 3
  xcrun simctl io "$SMALL" screenshot "$OUT/schedule-compact.png"
fi
