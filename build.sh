#!/bin/sh
# Builds FMRephraser.app in the project directory.
set -e
cd "$(dirname "$0")"
swift build -c release
APP=FMRephraser.app
BUILD_ID=$(git -C "$(dirname "$0")" describe --always --dirty 2>/dev/null || echo unknown)
BUILD_TIME=$(date '+%Y-%m-%d %H:%M')
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/FMRephraser "$APP/Contents/MacOS/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>local.fm-rephraser</string>
    <key>CFBundleName</key><string>FMRephraser</string>
    <key>CFBundleVersion</key><string>$BUILD_ID</string>
    <key>FMRBuildTime</key><string>$BUILD_TIME</string>
    <key>CFBundleExecutable</key><string>FMRephraser</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
SIGN_IDENTITY="${FMR_SIGN_IDENTITY:-FMRephraser Local}"
if ! security find-identity -p codesigning | grep -q "\"$SIGN_IDENTITY\""; then
    echo "Signing identity \"$SIGN_IDENTITY\" not found, falling back to ad-hoc signing"
    SIGN_IDENTITY=-
fi
codesign --force --sign "$SIGN_IDENTITY" "$APP"
echo "Signed with identity: $SIGN_IDENTITY"
echo "Built $APP"
