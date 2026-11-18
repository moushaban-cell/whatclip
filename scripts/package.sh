#!/bin/sh
# Builds WhatClip and packages it as dist/WhatClip-<version>.zip for a GitHub release.
set -e
cd "$(dirname "$0")/.."
./scripts/build-app.sh
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" build/WhatClip.app/Contents/Info.plist)
mkdir -p dist
rm -f "dist/WhatClip-$VERSION.zip"
ditto -c -k --keepParent build/WhatClip.app "dist/WhatClip-$VERSION.zip"
shasum -a 256 "dist/WhatClip-$VERSION.zip" > "dist/WhatClip-$VERSION.zip.sha256"
echo "Packaged dist/WhatClip-$VERSION.zip"
