#!/bin/zsh
# Builds a Development-signed Trace.app and installs it to /Applications
# (system extensions only activate from /Applications).
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug \
  -derivedDataPath build -allowProvisioningUpdates build | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
pkill -x Trace 2>/dev/null || true
rm -rf /Applications/Trace.app
ditto build/Build/Products/Debug/Trace.app /Applications/Trace.app
codesign -dv --entitlements - /Applications/Trace.app 2>&1 | grep -E "TeamIdentifier|networkextension|system-extension"
open /Applications/Trace.app
