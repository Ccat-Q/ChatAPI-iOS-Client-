#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
preview_cache="$PWD/.ci-cache/screenshots"
mkdir -p build/screenshots
# Partial Xcode caches may contain images for older inputs. Only exact keys may
# reuse them; missing or damaged image files force a fresh simulator run.
if [[ "${CI_SCREENSHOTS_CACHE_HIT:-false}" == true ]] && python3 - "$preview_cache/images" <<'PY'
from pathlib import Path
import struct,sys
folder = Path(sys.argv[1])
for name in ['lock', 'reply', 'toolCall', 'toolOutput', 'reply-dark']:
    path = folder / f'{name}.png'
    if not path.is_file():
        raise SystemExit(1)
    header = path.read_bytes()[:24]
    if len(header) != 24 or header[:8] != b'\x89PNG\r\n\x1a\n' or not all(struct.unpack('>II', header[16:24])):
        raise SystemExit(1)
PY
then
  cp "$preview_cache/images/"*.png build/screenshots/
  printf 'Reused five screenshots from an exact toolchain/source cache; no new simulator capture.\n'
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    printf 'Screenshots: reused from an exact input cache (no new simulator run).\n' >> "$GITHUB_STEP_SUMMARY"
  fi
  exit 0
fi

preview_dir=$(mktemp -d)
preview_device=""
cleanup() {
  if [[ -n "$preview_device" ]]; then xcrun simctl shutdown "$preview_device" >/dev/null 2>&1 || true; fi
  rm -rf "$preview_dir"
}
trap cleanup EXIT
# Never leave old images eligible for a new input's cache on a partial restore.
rm -rf "$preview_cache/images"
rm -f build/screenshots/*.png
# Cold simulator migration can block Xcode's destination discovery for minutes.
# Keep these serial within this job; regressions and archive run on other runners.
xcodebuild -project ChatAPIAdmin.xcodeproj -scheme ChatAPIAdmin -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$preview_cache/DerivedData" build \
  ARCHS="$(uname -m)" ONLY_ACTIVE_ARCH=YES SWIFT_OPTIMIZATION_LEVEL=-Onone \
  DEBUG_INFORMATION_FORMAT=dwarf COMPILER_INDEX_STORE_ENABLE=NO \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
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
xcrun simctl install "$preview_device" "$preview_cache/DerivedData/Build/Products/Debug-iphonesimulator/ChatAPIAdmin.app"
for preview in lock reply toolCall toolOutput; do
  SIMCTL_CHILD_CHATAPI_UI_PREVIEW="$preview" xcrun simctl launch --terminate-running-process "$preview_device" com.ccat.chatapiadmin
  sleep 3
  xcrun simctl io "$preview_device" screenshot "build/screenshots/$preview.png"
done
xcrun simctl ui "$preview_device" appearance dark
SIMCTL_CHILD_CHATAPI_UI_PREVIEW=reply xcrun simctl launch --terminate-running-process "$preview_device" com.ccat.chatapiadmin
sleep 3
xcrun simctl io "$preview_device" screenshot build/screenshots/reply-dark.png
mkdir -p "$preview_cache/images"
cp build/screenshots/*.png "$preview_cache/images/"
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  printf 'Screenshots: captured five fresh images on the simulator.\n' >> "$GITHUB_STEP_SUMMARY"
fi
