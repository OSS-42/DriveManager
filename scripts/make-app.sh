#!/bin/sh
# Builds DriveManager.app in build/, signed for this Mac only (no Apple
# developer account needed). Open it with: open build/DriveManager.app
set -eu
cd "$(dirname "$0")/.."

swift build -c release --product DriveManager
bin_dir=$(swift build -c release --show-bin-path)

app=build/DriveManager.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$bin_dir/DriveManager" "$app/Contents/MacOS/DriveManager"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>DriveManager</string>
    <key>CFBundleIdentifier</key><string>com.oss42.drivemanager</string>
    <key>CFBundleExecutable</key><string>DriveManager</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.2</string>
    <key>CFBundleVersion</key><string>2</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$app"
echo "Built $app"
