#!/bin/zsh
# Builds a Development-signed NetTrail.app and installs it to /Applications
# (system extensions only activate from /Applications). A fresh build number per install
# lets the app notice the bundled extension changed and replace the running one.
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug \
  -derivedDataPath build -allowProvisioningUpdates \
  CURRENT_PROJECT_VERSION="$(date +%s)" build | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
pkill -x NetTrail 2>/dev/null || true
pkill -x Trace 2>/dev/null || true  # builds from before the rename
rm -rf /Applications/NetTrail.app /Applications/Trace.app
ditto build/Build/Products/Debug/NetTrail.app /Applications/NetTrail.app
codesign -dv --entitlements - /Applications/NetTrail.app 2>&1 | grep -E "TeamIdentifier|networkextension|system-extension"
open /Applications/NetTrail.app
