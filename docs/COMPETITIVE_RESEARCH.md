# Competitive research (2026-11-17)

Reviewed: the nine MIT projects and the GPL/AGPL projects listed in docs/LICENSE_AUDIT.md. Clones are local only (research/, not committed).

Features learned and how WhatClip handles them:
- Local history with duplicate detection (Maccy, ClipHistory): implemented independently with a SHA-256 fingerprint.
- Keyboard-first picker (Maccy, Whisk): implemented independently with AppKit.
- Pause and ignore-next-copy (Maccy): implemented independently.
- Concealed and transient markers (ClipHistory and others): implemented from the public nspasteboard.org convention.
- Encrypted storage with Keychain key (ClipHistory, Kelsiito): **not in 0.1**; the database is plain SQLite with file mode 0600.
- Queue and batch paste (FlowClip): planned for a later version.

Gaps in the research: the Maccy and Clipy SHAs are recorded, but the Flycut, pesty and clipflow source was only shallow-cloned and not read in depth.
