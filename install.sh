#!/bin/sh
# Builds FMRephraser from source, installs it to /Applications, adds it to login items and starts it.
set -e
cd "$(dirname "$0")"
./build.sh
pkill -x FMRephraser || true
rm -rf /Applications/FMRephraser.app
cp -R FMRephraser.app /Applications/
if ! osascript -e 'tell application "System Events" to get the name of every login item' | grep -q FMRephraser; then
    osascript -e 'tell application "System Events" to make login item at end with properties {path:"/Applications/FMRephraser.app", hidden:true}' >/dev/null
fi
open /Applications/FMRephraser.app
echo "Installed. Grant Accessibility permission to FMRephraser in System Settings → Privacy & Security → Accessibility."
