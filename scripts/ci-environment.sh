#!/bin/bash
set -euo pipefail
xcodebuild -version
xcrun --sdk iphoneos --show-sdk-version | awk -F. '{ if ($1 < 26) exit 1 }'
# Do not restore compiler outputs across Xcode, SDK, OS build or CPU changes.
toolchain_key=$({
  xcodebuild -version
  xcrun swift --version
  xcrun --sdk iphoneos --show-sdk-version
  xcrun --sdk iphonesimulator --show-sdk-version
  sw_vers -buildVersion
  uname -m
  printf '%s\n' "${ImageOS:-unknown}" "${ImageVersion:-unknown}"
} | shasum -a 256 | awk '{ print $1 }')
printf 'toolchain=%s\n' "$toolchain_key" >> "$GITHUB_OUTPUT"
