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
  Sources/CommentWatcher.swift \
  Sources/Notifier.swift \
  Sources/AppDelegate.swift \
  Sources/main.swift \
  -o "$STAGE/Contents/MacOS/PRBar"

cp Resources/MenuBarIconTemplate.png Resources/MenuBarIconTemplate@2x.png \
   Resources/PRBar.icns "$STAGE/Contents/Resources/"

# The bundle id is deliberately not com.priyashinde.prbar. That identifier picked
# up a corrupt Notification Center record which survives reinstalls, re-signing and
# lsregister, and which renders every banner's icon as a generic PNG document.
# A fresh identifier gets a clean record and the app icon appears correctly.
cat > "$STAGE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>PRBar</string>
    <key>CFBundleIdentifier</key><string>com.pshinde9.prbar</string>
    <key>CFBundleName</key><string>PRBar</string>
    <key>CFBundleIconFile</key><string>PRBar</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>3</string>
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

# Notification Center caches an app's icon by bundle id and won't notice that a
# reinstall changed it. Re-registering nudges it to read the bundle again.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$DEST"

echo "Installed $DEST"
