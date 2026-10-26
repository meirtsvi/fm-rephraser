#!/bin/sh
# Builds FMRephraser.app in the project directory.
set -e
cd "$(dirname "$0")"
swift build -c release
APP=FMRephraser.app
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
    <key>CFBundleExecutable</key><string>FMRephraser</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"
echo "Built $APP"
