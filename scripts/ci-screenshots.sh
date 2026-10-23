#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
preview_dir=$(mktemp -d)
preview_device=""
cleanup() {
  if [[ -n "$preview_device" ]]; then xcrun simctl shutdown "$preview_device" >/dev/null 2>&1 || true; fi
  rm -rf "$preview_dir"
}
trap cleanup EXIT
mkdir -p build/screenshots
xcodebuild -project ChatAPIAdmin.xcodeproj -scheme ChatAPIAdmin -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$preview_dir/DerivedData" build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
xcrun simctl list devices available -j > "$preview_dir/devices.json"
preview_device=$(python3 - "$preview_dir/devices.json" <<'PY'
import json,sys
with open(sys.argv[1], encoding='utf-8') as source:
    devices = json.load(source)['devices']
for runtime in sorted(devices, reverse=True):
    if '.iOS-' not in runtime:
        continue
    for device in devices[runtime]:
        if device['name'].startswith('iPhone') and device.get('isAvailable'):
            print(device['udid'])
            sys.exit(0)
raise SystemExit('No available iPhone simulator runtime')
PY
)
xcrun simctl boot "$preview_device"
xcrun simctl bootstatus "$preview_device" -b
xcrun simctl ui "$preview_device" appearance light
xcrun simctl status_bar "$preview_device" override --time '9:41' --batteryState charged --batteryLevel 100
xcrun simctl install "$preview_device" "$preview_dir/DerivedData/Build/Products/Debug-iphonesimulator/ChatAPIAdmin.app"
for preview in lock reply toolCall toolOutput; do
  SIMCTL_CHILD_CHATAPI_UI_PREVIEW="$preview" xcrun simctl launch --terminate-running-process "$preview_device" com.ccat.chatapiadmin
  sleep 3
  xcrun simctl io "$preview_device" screenshot "build/screenshots/$preview.png"
done
xcrun simctl ui "$preview_device" appearance dark
SIMCTL_CHILD_CHATAPI_UI_PREVIEW=reply xcrun simctl launch --terminate-running-process "$preview_device" com.ccat.chatapiadmin
sleep 3
xcrun simctl io "$preview_device" screenshot build/screenshots/reply-dark.png
