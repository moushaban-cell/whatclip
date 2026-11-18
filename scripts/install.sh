#!/bin/sh
# One command: build WhatClip from source and install it to /Applications.
#   ./scripts/install.sh
# Needs macOS 14+ and the Command Line Tools (xcode-select --install). No Xcode, no paid account.
set -e
cd "$(dirname "$0")/.."
./scripts/test.sh >/dev/null && echo "Tests passed."
./scripts/build-app.sh
# A copy that is already running keeps running after an install, so quit it first and open the new one afterwards.
osascript -e 'tell application "WhatClip" to quit' >/dev/null 2>&1 || true
sleep 1
pkill -f "/Applications/WhatClip.app/Contents/MacOS/WhatClip" >/dev/null 2>&1 || true
rm -rf /Applications/WhatClip.app
cp -R build/WhatClip.app /Applications/WhatClip.app
echo "Installed to /Applications/WhatClip.app. Opening it now; press ⌘X to see your history."
open /Applications/WhatClip.app
