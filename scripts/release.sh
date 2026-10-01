#!/bin/zsh
# Builds a Developer ID signed, notarized NetTrail-<version>-<arch>.dmg (size-optimized).
# Env: ARCH (arm64|x86_64), APP_VERSION, SIGN_IDENTITY, APP_PROFILE, FILTER_PROFILE
# (paths to Developer ID .provisioningprofile files), ASC_KEY_PATH/ASC_KEY_ID/ASC_ISSUER_ID.
set -euo pipefail
cd "$(dirname "$0")/.."
ARCH="${ARCH:-arm64}"
APP_VERSION="${APP_VERSION:?}"
TEAM_ID="$(sed -nE 's/^TRACE_TEAM_ID *= *//p' Config/Base.xcconfig)"
BUNDLE_ID="$(sed -nE 's/^TRACE_BUNDLE_ID *= *//p' Config/Base.xcconfig)"
OUT="build/release-$ARCH"
rm -rf "$OUT"; mkdir -p "$OUT"

profile_name() { security cms -D -i "$1" | plutil -extract Name raw -o - -; }
install_profile() {
  local dir="$HOME/Library/MobileDevice/Provisioning Profiles"; mkdir -p "$dir"
  local uuid; uuid="$(security cms -D -i "$1" | plutil -extract UUID raw -o - -)"
  cp "$1" "$dir/$uuid.provisionprofile"
}
install_profile "$APP_PROFILE"; install_profile "$FILTER_PROFILE"

xcodegen generate
# Unsigned archive; signing happens at export with the Developer ID profiles.
xcodebuild archive -project Trace.xcodeproj -scheme Trace -configuration Release \
  -archivePath "$OUT/NetTrail.xcarchive" ARCHS="$ARCH" ONLY_ACTIVE_ARCH=NO \
  MARKETING_VERSION="$APP_VERSION" CURRENT_PROJECT_VERSION="${BUILD_NUMBER:-1}" \
  CODE_SIGNING_ALLOWED=NO

cat > "$OUT/export.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>$SIGN_IDENTITY</string>
  <key>provisioningProfiles</key><dict>
    <key>$BUNDLE_ID</key><string>$(profile_name "$APP_PROFILE")</string>
    <key>$BUNDLE_ID.filter</key><string>$(profile_name "$FILTER_PROFILE")</string>
  </dict>
</dict></plist>
PLIST
xcodebuild -exportArchive -archivePath "$OUT/NetTrail.xcarchive" \
  -exportOptionsPlist "$OUT/export.plist" -exportPath "$OUT/export"

APP="$OUT/export/NetTrail.app"
DMG="build/NetTrail-$APP_VERSION-$ARCH.dmg"
STAGE="$OUT/dmg"; mkdir -p "$STAGE"
ditto "$APP" "$STAGE/NetTrail.app"; ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
# ULMO = LZMA, the smallest DMG compression (macOS 10.15+).
hdiutil create -volname NetTrail -srcfolder "$STAGE" -ov -format ULMO "$DMG"
codesign --force --sign "$SIGN_IDENTITY" "$DMG"

xcrun notarytool submit "$DMG" --key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" \
  --issuer "$ASC_ISSUER_ID" --wait
xcrun stapler staple "$DMG"
echo "Built $DMG ($(du -h "$DMG" | cut -f1))"
