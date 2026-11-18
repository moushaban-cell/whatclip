# QA matrix (updated 2026-11-18)

Status: **verified** = run on this Mac and checked; **unit-tested** = covered by Swift Testing; **queued** = needs a person at the screen or a permission; **unverified** = code written, not run here.

| Area | Check | Status |
|---|---|---|
| Core | 52 unit tests (store, privacy, detector, masking, settings, text tools, smart actions, templates, boards, snippets, encryption, OCR search, payloads) | unit-tested |
| Capture | Text and URL from the real pasteboard | verified |
| Capture | Duplicate counted, not repeated | verified |
| Capture | Secret stored as expiring item | verified |
| Capture | PNG image and copied file from the real pasteboard | verified |
| Capture | URL copied right after a file copy | open: one miss, recheck |
| Privacy | Database and journal files mode 0600 | unit-tested |
| Privacy | Encrypted payloads opaque on disk | unit-tested |
| Privacy | Password manager content skipped (concealed marker) | queued: 1Password, Bitwarden |
| Picker | Window appearance, focus, filters, previews | queued |
| Picker | ⌘⇧V opens it; ⌘1–9, ⌘P, ⌘⌫, ⌘Y, Option-Return queue | queued |
| Picker | Touch ID before history opens | unverified (needs a finger) |
| History window | Sidebar, boards, detail actions, text tools, smart actions | queued |
| Snippets | Create, edit, insert with variables | unit-tested (logic); queued (UI) |
| Screenshot | Area capture via the system tool into history | queued (needs Screen Recording) |
| Annotation | Pen, rectangle, arrow, undo, clear, save as item | unverified |
| GIF | 5-second recording via ScreenCaptureKit | unverified (needs Screen Recording) |
| OCR | Text read from a copied image | unverified on real images (synthetic image gives empty text) |
| Login item | Start at login | unverified (needs app in /Applications and a restart) |
| Build | `swift test` on CI (macos-15) | configured, not run yet |
| Browsers and apps | Safari, Chrome, Firefox, Finder, Notes, Slack | queued |

## On-screen checks (2026-11-18)
- Menu-bar menu: opened and captured; items, submenus and shortcuts display correctly. Shown with the app's own test flag.
- Picker placement: opens centred under the menu-bar clipboard icon, below the menu bar. Captured.
- Picker content: text items, source app, time, filters, preview. Captured.
- History window: list, detail buttons, sidebar, cards view with a colour swatch and a text card. Captured.
- Welcome window: text and buttons fit. Captured.
- Image capture: an image copy is saved; text recognition runs in the background. Verified with a synthetic image.
- Not yet checked: Services entry in other apps; Touch ID with a finger; screen recording (needs the permission); the shortcut recorder by hand; Dock behaviour toggling.
