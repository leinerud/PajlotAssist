#!/bin/bash
# Builds PajlotAssist.app (menu bar only, no Dock icon) into ./build
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --scratch-path "${TMPDIR:-/tmp}/pajlot-build"
BIN="$(swift build -c release --scratch-path "${TMPDIR:-/tmp}/pajlot-build" --show-bin-path)/PajlotAssist"
APP="build/PajlotAssist.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/PajlotAssist"
mkdir -p "$APP/Contents/Resources"
ICONSET="${TMPDIR:-/tmp}/PajlotAssist.iconset"; rm -rf "$ICONSET"; mkdir -p "$ICONSET"
cp Resources/Assets.xcassets/AppIcon.appiconset/*.png "$ICONSET/"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>se.humblebee.PajlotAssist</string>
<key>CFBundleName</key><string>Pajlot Assist</string>
<key>CFBundleExecutable</key><string>PajlotAssist</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
</dict></plist>
P
xattr -cr "$APP"
codesign --force --sign - "$APP"
echo "Built $APP"
