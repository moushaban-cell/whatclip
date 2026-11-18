# Licence audit (updated 2026-11-18)

## Outcome
- WhatClip is MIT licensed (LICENSE). Its code is original.
- No dependency to license: the app links only Apple's frameworks.
- The licences of the studied projects were checked through the GitHub API and their LICENSE files. See THIRD_PARTY_NOTICES.md.
- Projects under GPL-3.0 or AGPL-3.0 were used only for ideas. Their code was not copied, so MIT licensing stays intact.
- Projects with no licence (for example ClipMenu) or unclear licences (PasteBarApp) were not used.

## Rules the project follows
1. Copy only from MIT projects, with the notice kept and the change logged in docs/REUSED_COMPONENTS.md.
2. From GPL or AGPL projects, learn the behaviour, then write new code. Never copy.
3. Keep copyright and licence text in LICENSE and THIRD_PARTY_NOTICES.md.

## Open items before a public release
- Confirm that no file in Sources/ or Tests/ matches text in the studied projects (run a similarity check).
- Check the name WhatClip (the domain whatclip.com is taken; trademark search not done).
