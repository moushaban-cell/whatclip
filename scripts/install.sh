#!/bin/sh
# One command: build WhatClip from source and install it to /Applications.
#   ./scripts/install.sh
# Needs macOS 14+ and the Command Line Tools (xcode-select --install). No Xcode, no paid account.
set -e
cd "$(dirname "$0")/.."
./scripts/test.sh >/dev/null && echo "Tests passed."
./scripts/build-app.sh
rm -rf /Applications/WhatClip.app
cp -R build/WhatClip.app /Applications/WhatClip.app
echo "Installed to /Applications/WhatClip.app. Open it, then press ⇧⌘V to see your history."
