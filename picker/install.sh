#!/bin/bash
# Builds ~/Applications/Game Picker.app and opens it. To have it start at login, add it
# in System Settings > General > Login Items.
set -euo pipefail
cd "$(dirname "$0")"
app="$HOME/Applications/Game Picker.app"

build=$(mktemp -d)
trap 'rm -rf "$build"' EXIT
mkdir -p "$build/Game Picker.app/Contents/MacOS"
cat > "$build/Game Picker.app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.bryanfrds.game-picker</string>
  <key>CFBundleName</key><string>Game Picker</string>
  <key>CFBundleExecutable</key><string>GamePicker</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
swiftc -O -swift-version 5 -o "$build/Game Picker.app/Contents/MacOS/GamePicker" Choice.swift main.swift
codesign --force --sign - "$build/Game Picker.app"

pkill -x GamePicker 2>/dev/null || true
mkdir -p "$HOME/Applications"
rm -rf "$app"
mv "$build/Game Picker.app" "$app"
open "$app"
echo "Game Picker is running: look for the game controller in the menu bar."
