#!/bin/sh
# Builds DriveManager.app in build/, for Apple Silicon and Intel Macs.
#
#   ./scripts/make-app.sh            build/DriveManager.app
#   ./scripts/make-app.sh --install  also copy it to /Applications
#   ./scripts/make-app.sh --zip      also make build/DriveManager-<version>.zip
#                                    to share with friends
#
# The app is signed with the "DriveManager Local Signing" certificate when
# scripts/make-signing-cert.sh has created it, so macOS keeps permissions
# such as Full Disk Access across rebuilds. Otherwise it gets a throwaway
# signature that works on this Mac only.
set -eu
cd "$(dirname "$0")/.."

version=0.3
build=3
identity="DriveManager Local Signing"

install=no
zip=no
for arg in "$@"; do
    case "$arg" in
        --install) install=yes ;;
        --zip) zip=yes ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done

arch_flags="--arch arm64 --arch x86_64"
# shellcheck disable=SC2086
swift build -c release --product DriveManager $arch_flags
# shellcheck disable=SC2086
bin_dir=$(swift build -c release $arch_flags --show-bin-path)

app=build/DriveManager.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/DriveManager" "$app/Contents/MacOS/DriveManager"

# The icon: every size macOS asks for, made from the 1024-pixel original.
iconset=build/AppIcon.iconset
rm -rf "$iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
    sips -z $size $size Resources/AppIcon.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z $double $double Resources/AppIcon.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"
rm -rf "$iconset"

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>DriveManager</string>
    <key>CFBundleDisplayName</key><string>DriveManager</string>
    <key>CFBundleIdentifier</key><string>com.oss42.drivemanager</string>
    <key>CFBundleExecutable</key><string>DriveManager</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleShortVersionString</key><string>$version</string>
    <key>CFBundleVersion</key><string>$build</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHumanReadableCopyright</key><string>Made by OSS-42 for personal use.</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

if security find-identity -v -p codesigning 2>/dev/null | grep -q "\"$identity\""; then
    codesign --force --sign "$identity" "$app"
    echo "Signed with \"$identity\"."
else
    codesign --force --sign - "$app"
    echo "Signed for this Mac only. Run ./scripts/make-signing-cert.sh once so Full Disk Access survives rebuilds."
fi
echo "Built $app ($version)"

if [ "$install" = yes ]; then
    osascript -e 'quit app "DriveManager"' >/dev/null 2>&1 || true
    rm -rf /Applications/DriveManager.app
    ditto "$app" /Applications/DriveManager.app
    echo "Installed /Applications/DriveManager.app"
fi

if [ "$zip" = yes ]; then
    archive="build/DriveManager-$version.zip"
    rm -f "$archive"
    ditto -c -k --keepParent "$app" "$archive"
    echo "Made $archive"
fi
