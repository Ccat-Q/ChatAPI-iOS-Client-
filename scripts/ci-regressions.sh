#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
regression_dir=$(mktemp -d)
fixture_pid=""
cleanup() {
  if [[ -n "$fixture_pid" ]]; then kill "$fixture_pid" 2>/dev/null || true; fi
  rm -rf "$regression_dir"
}
trap cleanup EXIT
python3 Tests/Fixtures/server.py "$regression_dir/port" &
fixture_pid=$!
for ((attempt=0; attempt<100; attempt++)); do
  [[ -s "$regression_dir/port" ]] && break
  sleep 0.05
done
[[ -s "$regression_dir/port" ]]
xcrun swiftc -swift-version 6 -parse-as-library -target "$(uname -m)-apple-macosx14.0" \
  ChatAPIAdmin/Models/Models.swift \
  ChatAPIAdmin/App/AppSettings.swift \
  ChatAPIAdmin/Services/APIClient.swift \
  ChatAPIAdmin/Services/KeychainStore.swift \
  ChatAPIAdmin/Services/InstanceStore.swift \
  ChatAPIAdmin/Services/WorkspaceConnection.swift \
  Tests/CoreRegressions.swift -o "$regression_dir/regressions"
"$regression_dir/regressions" "$(cat "$regression_dir/port")"
