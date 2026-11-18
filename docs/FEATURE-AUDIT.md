# Feature audit against docs/SPEC-original.txt (2026-11-18)

Status: **built** = code exists and runs; **tested** = covered by unit tests; **verified** = seen working on this Mac; **unverified** = code exists, not run in the real environment; **missing** = not built.

| Spec section | Feature | Status |
|---|---|---|
| 4.1 | System-wide capture (NSPasteboard) | built, verified (text, URL, image, file) |
| 4.1 | Plain text, rich text (RTF), URLs | built, tested |
| 4.1 | HTML | missing |
| 4.1 | Images PNG/TIFF/JPEG | built, verified (PNG) |
| 4.1 | Animated GIF capture and preview | unverified (needs Screen Recording) |
| 4.1 | File and folder references | built, verified (file) |
| 4.1 | Source app name and bundle ID | built (stored, shown in history window) |
| 4.1 | Duplicate detection | tested, verified |
| 4.1 | Search, sort newest/oldest | search built; sort order fixed to newest only |
| 4.1 | Filters by type, date, source app, pinned, OCR | type and pinned built; date, source-app and OCR filters missing |
| 4.1 | History limit and retention | built, tested |
| 4.1 | Multi-select and batch delete | missing |
| 4.1 | Clear all / clear unpinned | built (menu) |
| 4.1 | Pin, favourites, permanent Library | pin built; favourites and Library missing |
| 4.1 | Restore to clipboard, direct paste, plain-text paste | built (direct paste needs Accessibility, unverified) |
| 4.2 | Global shortcut ⌘⇧V, conflict detection | built (hotkey unverified); conflict message built |
| 4.2 | Floating panel, search, keyboard nav, Return, Esc, click-outside | built, Esc and arrows in code, verified layout |
| 4.2 | ⌘1–9 quick pick | built (unverified keystroke) |
| 4.2 | Multi-monitor and Spaces | unverified |
| 4.2 | Quick preview | built |
| 4.3 | Visual cards by type, thumbnails, colour cards, Markdown/code preview | partly: icons and text preview; thumbnails and colour cards missing |
| 4.3 | Quick Look integration | built (⌘Y), unverified |
| 4.4 | Clipboard queue (FIFO, pause, batch, separators) | partly: add (⌥Return) and paste next built; batch and separators missing |
| 4.5 | Boards and collections | built (create, add, list); colours and import/export missing |
| 4.5 | Permanent text Library | missing |
| 4.6 | Snippets with folders, tags, favourites, variables | built (folder, favourite, variables); tags missing; auto text expansion missing |
| 4.7 | Screenshot of an area | built via system tool (Screen Recording unverified) |
| 4.7 | Annotation (pen, line, arrow, rectangle, undo, clear) | built (line is missing; arrow, rectangle, pen, undo, clear built) |
| 4.7 | GIF screen recording with size and frame controls | built basic (5 s, fixed settings), unverified |
| 4.7 | Local OCR and OCR search | built, search verified in tests |
| 4.8 | Smart recognition: emails, phones, URLs, dates, colours, paths | built (addresses, JSON, code, Markdown detection missing) |
| 4.9 | Text tools (case, trim, lines, JSON, URL, Base64, stats) | built, tested; hashes and text compare missing |
| 4.10 | Privacy: local-only, no telemetry, concealed/transient filtering, app exclusions, pause, ignore next | built, tested |
| 4.10 | Retention, pins excluded from cleanup, encryption at rest, Keychain key | built, tested |
| 4.10 | Touch ID or password before opening | built, unverified (needs a finger) |
| 4.11 | Menu bar, launch at login, shortcut configuration UI | built (launch at login unverified); shortcut configuration UI missing |
| 4.12 | iCloud sync, imports, plugins, AI actions | missing (sync and AI intentionally deferred; no paid account) |
| 5 | Browser and app QA matrix | queued (needs apps and people) |
| 6 | Architecture: SQLite, NSPasteboard, Vision, CryptoKit, Keychain | matches |
| 7 | Visual design, icon | icon built; full design system not built |
| 8 | GitHub docs and automation | docs built; CI workflow written, not pushed (token scope) |

## Summary
Built and partly tested: most of sections 4.1, 4.2, 4.5, 4.6, 4.7, 4.8, 4.9 and 4.10.
Missing: multi-select, date/source/OCR filters, favourites, the permanent Library, HTML capture, thumbnails and colour cards, batch queue with separators, shortcut configuration UI, hashes and text compare, extra smart recognition, and tags.
Deferred on purpose: iCloud sync, AI actions, plugins, import from other apps, and a paid-account release.
