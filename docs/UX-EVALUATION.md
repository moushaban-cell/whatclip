# UX evaluation and menu-bar design (2026-11-18)

## What you asked for
"Top bar" means the menu bar: WhatClip should reach everything from the menu-bar icon, not only the history window, the way Gemini and similar apps do. Finder access means a Services item, so any file or text can be sent to WhatClip from the right-click menu.

## What the MIT references do (read from source, commit SHAs in docs/PROJECT_STATUS.md)
| Project | Menu bar | Popup and panel | Features we lack |
|---|---|---|---|
| Kelsiito/clipboard (MIT, ebd0abf) | Full menu: history, stack start and next, favourites, GIF, screenshot, pause for a duration, clear, settings | Floating panel with preview, image edit, extract text (OCR), appearance light and dark, private-view authentication | Stack, favourites, extract text, pause durations, appearance |
| p0deje/Maccy (MIT, f0b571e) | Status item, menu items, quit | Panel positioned at the menu icon, the cursor, the window centre or the last position | Panel placement options |
| ClipHistory (MIT, b198104) | Menu with live hotkey hint, onboarding, update check | Popup window controller, theme | Onboarding for permissions |
| Clipy (MIT, ff6b3b8) | Menu-first design | Alternative menu UI | Menu-first access |

Our current build has a status item with history, pause, clear, Help, Quit, plus screenshot, GIF and the history window. Compared with Kelsiito it is missing stacks, favourites, extract text, pause durations, appearance choice, panel placement, and onboarding.

## Design decisions (my calls, as you asked)
1. **Menu bar is the hub.** The status item menu has: Open picker (⌘⇧V), Open history window, Snippets (submenu of the latest 10), Boards (submenu), Stack (start, next, clear), Capture (area screenshot, GIF, annotate last image), Pause (5 min, 1 hour, until resumed), Ignore next copy, Recent items (8), Clear history, Settings, Help, Quit. Right-clicking the icon opens the same menu.
2. **Finder and other apps:** a Services entry, "Save to WhatClip", on text and files in any app. Sending a file adds it as a file item; sending text adds a text item. This needs an NSServices entry in Info.plist and a small handler.
3. **Panel placement** as a setting: at the menu icon (default), at the cursor, or screen centre. Taken from Maccy's approach, rewritten for our code.
4. **Look:** one accent colour (teal from the icon), system font, light and dark following the system, compact rows with the source app icon and a relative time ("2 min ago"), kind badges, a preview pane that shows the full item, and empty states that explain what to do.
5. **Onboarding:** a first-run window that explains what needs permission and why, with a button per permission. Taken from ClipHistory's idea.

## Honest status
- The menu, placement options, Services entry and onboarding are not built yet. They are the next code work.
- The visual design above is a plan. I have not produced mock-ups, so the look is still unproven until I screenshot it.

## Design pass (2026-11-18)
- Spacing, radius and type tokens in `Design.swift` (Space, Radius, rowHeight) used by the picker and history rows.
- Emoji status marks replaced with SF Symbols (pin, star, lock); no emoji as UI icons.
- Empty states with a symbol, heading and help text, in the picker and the list.
- Picker top spacing reduced; footer hint shortened so it fits the width.
- Checked on screen: empty picker and populated picker.
- Still open for the SaaS feel: group headers in the history sidebar, grouped settings cards, a first-run tour, and a motion pass with reduced-motion support.
