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
if [ -n "${GITHUB_ENV:-}" ]; then echo "CCSUT_PREVIEW_DEVICE=$DEVICE" >> "$GITHUB_ENV"; fi
APP="$RUNNER_TEMP/UIPreview/Build/Products/Debug-iphonesimulator/CCSUT.app"
OUT="$RUNNER_TEMP/ui-screenshots"
mkdir -p "$OUT"
xcrun simctl boot "$DEVICE" || true
xcrun simctl bootstatus "$DEVICE" -b
xcrun simctl status_bar "$DEVICE" override --time '9:41' --batteryState charged --batteryLevel 100
xcrun simctl install "$DEVICE" "$APP"
if [ "${1:-}" = "--boot-only" ]; then exit 0; fi

capture() {
  xcrun simctl ui "$DEVICE" appearance "$2"
  if [ "${3:-}" = "legacy" ]; then
    xcrun simctl launch --terminate-running-process "$DEVICE" com.imzhien.ccsut --preview-ui --preview-page "$1" --legacy-top-blur
  else
    xcrun simctl launch --terminate-running-process "$DEVICE" com.imzhien.ccsut --preview-ui --preview-page "$1"
  fi
  sleep 3
  xcrun simctl io "$DEVICE" screenshot "$OUT/$1-$2${3:+-$3}.png"
}

capture schedule light
capture schedule dark
capture academic light
capture academic dark
xcrun simctl ui "$DEVICE" appearance light
xcrun simctl launch --terminate-running-process "$DEVICE" com.imzhien.ccsut --preview-ui --preview-page academic --preview-no-upcoming
sleep 3
xcrun simctl io "$DEVICE" screenshot "$OUT/academic-empty-light.png"
capture loading light
capture scores light
capture exams light
capture electives light
capture electives dark
capture account light
capture course light
capture conflict light
capture header-hidden light
capture header-hidden dark
capture schedule light legacy
capture schedule dark legacy
capture header-hidden light legacy
capture header-hidden dark legacy
xcrun simctl ui "$DEVICE" appearance light
xcrun simctl launch --terminate-running-process "$DEVICE" com.imzhien.ccsut --preview-ui --preview-page header-motion
xcrun simctl io "$DEVICE" recordVideo --codec=h264 "$OUT/header-motion.mp4" &
VIDEO_PID=$!
sleep 7
kill -INT "$VIDEO_PID"
wait "$VIDEO_PID" || true
xcrun simctl io "$DEVICE" screenshot "$OUT/header-revealed-light.png"
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
  xcrun simctl launch --terminate-running-process "$SMALL" com.imzhien.ccsut --preview-ui --preview-page bottom
  sleep 3
  xcrun simctl io "$SMALL" screenshot "$OUT/schedule-compact-bottom.png"
fi
