# Contributing

- Build and test: `./scripts/test.sh` (Swift Testing; no Xcode needed). Build the app: `./scripts/build-app.sh`.
- Every change needs a test. Test data must be synthetic: never real keys, card numbers or the clipboard contents of anyone.
- Do not add code copied from another project. If you adapt MIT code, keep its notice and add it to docs/REUSED_COMPONENTS.md.
- Keep the app local-only: no network calls and no telemetry.
