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
regression_cache=${CI_REGRESSION_CACHE_DIR:-"$regression_dir/compiler"}
mkdir -p "$regression_cache"
if [[ "${CI_REGRESSION_CACHE_HIT:-false}" != true || ! -x "$regression_cache/regressions" ]]; then
  xcrun swiftc -swift-version 6 -parse-as-library -target "$(uname -m)-apple-macosx14.0" \
  -module-cache-path "$regression_dir/ModuleCache" \
  ChatAPIAdmin/Models/Models.swift \
  ChatAPIAdmin/Models/AIAssist.swift \
  ChatAPIAdmin/App/AppLock.swift \
  ChatAPIAdmin/App/AppSettings.swift \
  ChatAPIAdmin/Services/APIClient.swift \
  ChatAPIAdmin/Services/KeychainStore.swift \
  ChatAPIAdmin/Services/InstanceStore.swift \
  ChatAPIAdmin/Services/WorkspaceConnection.swift \
  ChatAPIAdmin/Services/AIAssistClient.swift \
  ChatAPIAdmin/Services/AIComposerController.swift \
  Tests/CoreRegressions.swift Tests/AuthenticationRegressions.swift Tests/AIAssistRegressions.swift -o "$regression_cache/regressions"
  printf 'Compiled regression executable for this input.\n'
else
  printf 'Reusing regression executable from an exact toolchain/source cache.\n'
fi
# Always execute the assertions against a fresh server, including on a cache hit.
"$regression_cache/regressions" "$(cat "$regression_dir/port")"
