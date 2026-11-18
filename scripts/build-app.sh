#!/bin/sh
# Builds WhatClip.app from the SwiftPM executable. Menu-bar only (no Dock icon). Ad-hoc signed unless WHATCLIP_SIGN_ID names a certificate.
set -e
cd "$(dirname "$0")/.."
set -o pipefail
swift build -c release 2>&1 | grep -v "ld: warning"
BIN=$(swift build -c release --show-bin-path 2>/dev/null)/WhatClip
APP=build/WhatClip.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/WhatClip"
mkdir -p "$APP/Contents/Resources" && cp Resources/WhatClip.icns "$APP/Contents/Resources/WhatClip.icns"
cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>app.whatclip.WhatClip</string>
<key>CFBundleName</key><string>WhatClip</string>
<key>CFBundleExecutable</key><string>WhatClip</string>
<key>CFBundleIconFile</key><string>WhatClip</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFBundleVersion</key><string>100</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHumanReadableCopyright</key><string>MIT</string>
<key>NSServices</key><array><dict>
<key>NSMenuItem</key><dict><key>default</key><string>Save to WhatClip</string></dict>
<key>NSMessage</key><string>saveToWhatClip</string>
<key>NSPortName</key><string>WhatClip</string>
<key>NSSendTypes</key><array><string>public.utf8-plain-text</string><string>public.file-url</string></array>
</dict></array>
</dict></plist>
PL
# Sign with a local certificate when one is set up; otherwise ad-hoc (works, but macOS asks for permissions again after each rebuild).
ID="${WHATCLIP_SIGN_ID:-Clipdat Local Development}"
if ! security find-identity -v -p codesigning 2>/dev/null | grep -q "$ID"; then ID="-"; fi
codesign --force --sign "$ID" "$APP" 2>&1 | tail -1
echo "Built $APP"
