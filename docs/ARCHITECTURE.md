# Architecture

- `Sources/WhatClipCore` (no UI): classification, fingerprint, privacy policy, secret detector and mask, bundle-ID list, settings, SQLite store.
- `Sources/WhatClip` (AppKit): menu-bar app, pasteboard monitor (polls the change count every 0.4 s), picker, settings window, global hotkey (Carbon).
- `scripts/build-app.sh` builds and assembles `build/WhatClip.app`. `scripts/test.sh` runs the tests.
- The store has one lock; the monitor runs on the main actor.
