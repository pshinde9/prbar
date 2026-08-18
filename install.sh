#!/bin/bash
# Builds PRBar and installs it to /Applications. Installing to a stable
# location matters: launch-at-login registration is tied to the bundle path.
set -euo pipefail
cd "$(dirname "$0")"

STAGE="build/PRBar.app"
DEST="/Applications/PRBar.app"

rm -rf build
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"

swiftc -O \
  Sources/GitHubClient.swift \
  Sources/Notifier.swift \
  Sources/AppDelegate.swift \
  Sources/main.swift \
  -o "$STAGE/Contents/MacOS/PRBar"

cp Resources/MenuBarIconTemplate.png Resources/MenuBarIconTemplate@2x.png \
   Resources/PRBar.icns "$STAGE/Contents/Resources/"

cat > "$STAGE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>PRBar</string>
    <key>CFBundleIdentifier</key><string>com.priyashinde.prbar</string>
    <key>CFBundleName</key><string>PRBar</string>
    <key>CFBundleIconFile</key><string>PRBar</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>2</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc signature: required for notification delivery and SMAppService.
codesign --force --sign - "$STAGE"

killall PRBar 2>/dev/null || true
sleep 1
rm -rf "$DEST"
cp -R "$STAGE" "$DEST"

echo "Installed $DEST"
