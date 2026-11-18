# Contributing

- Build and test: `./scripts/test.sh` (Swift Testing; no Xcode needed). Build the app: `./scripts/build-app.sh`.
- Run the app's own self-test on a scratch folder: create a folder, put an empty file named `.selftest-ok` in it, then start the app with `WHATCLIP_DATA=<that folder> WHATCLIP_SELFTEST=1`. It writes `selftest.txt` with PASS, FAIL or SKIP lines. Never point it at your real history: it deletes unpinned items in that folder.
- Translations: the strings are in `Sources/WhatClip/LocalizationUI.swift`, one table per language. Change the text for the same key in the language you know, keep the key, and run the tests. To add a language, add a column for every key and tell us in the pull request. Native-speaker review is welcome.
- Pull requests: say what changed and why, list the tests you ran, and say which checks you could not run (for example, clicking a window).
- Every change needs a test. Test data must be synthetic: never real keys, card numbers or the clipboard contents of anyone.
- Do not add code copied from another project. If you adapt MIT code, keep its notice and add it to docs/REUSED_COMPONENTS.md.
- Keep the app local-only: no network calls and no telemetry.
