#!/bin/bash
set -euo pipefail
APP="$RUNNER_TEMP/UIPreview/Build/Products/Debug-iphonesimulator/CCSUT.app"
OUT="$RUNNER_TEMP/ui-screenshots"
RUNTIME=$(xcrun simctl list runtimes -j | python3 -c 'import json,sys; print(next(r["identifier"] for r in json.load(sys.stdin)["runtimes"] if r.get("isAvailable") and "iOS" in r["name"]))')
for kind in compact ipad; do
  TYPE=$(xcrun simctl list devicetypes -j | python3 -c 'import json,sys; types=json.load(sys.stdin)["devicetypes"]; kind=sys.argv[1]; print(next(r["identifier"] for r in types if (r["name"]=="iPhone SE (3rd generation)" if kind=="compact" else r["name"].startswith("iPad (A16)"))))' "$kind")
  DEVICE=$(xcrun simctl create "CCSUT Campus $kind" "$TYPE" "$RUNTIME")
  xcrun simctl boot "$DEVICE"
  xcrun simctl bootstatus "$DEVICE" -b
  xcrun simctl install "$DEVICE" "$APP"
  xcrun simctl status_bar "$DEVICE" override --time '9:41' --batteryState charged --batteryLevel 100
  for page in campus-leave campus-travel campus-form-leave campus-form-departure campus-electricity; do
    xcrun simctl launch --terminate-running-process "$DEVICE" com.imzhien.ccsut --preview-ui --preview-page "$page"
    sleep 3
    xcrun simctl io "$DEVICE" screenshot "$OUT/$page-$kind.png"
  done
  xcrun simctl shutdown "$DEVICE"
done
