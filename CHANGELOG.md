# Changelog

## Unreleased
- Updates: when a newer release exists, **Update now** asks once more, then opens Terminal, which downloads the release from GitHub, checks its SHA-256 checksum, installs it into Applications and reopens WhatClip. Your history and settings are not touched. Nothing is installed if the checksum does not match.
- Global shortcuts for more actions: history, screenshot, GIF, annotate, emoji, pause, stack and paste next. Each one is set in Settings → General → Other shortcuts, and can be cleared.
- Boards: drag an item from the list onto a board in the sidebar; the picker has a board filter (choose one board to work from); ⌘B files the selected items into a board.
- Boards: create, rename, recolour, delete, and remove items from a board. Deleting a board keeps its items in history.
- Capture and tools: a Recent captures list with Annotate, Favourite, Add to board and Delete; Pause and Resume switch the label straight away.
- Snippets: a New snippet button on the empty page; item actions no longer appear on the Snippets page.
- Failures are shown instead of silent: deletes, clears, pin, favourite and board actions report errors; a copy that cannot be saved is logged (never its content).
- Shell actions no longer hang when a command writes a lot of output; folder sync no longer drops another Mac's changes after a failed import.
- Privacy text corrected: the only network request is the daily update check.
- Internal: the history window is split into files for the sidebar, detail pane, snippets and About page.

## 1.0.0
First complete release, source only, private repository.
- Capture of text, links, rich text, HTML, images, GIFs and files; restored in their original form.
- Picker (default ⌘X, changeable): search, filters, cards and list, previews, multi-select, Touch ID or password lock with a 15-minute session.
- Auto-paste after choosing an item (needs the Accessibility permission).
- Main window with History, Library, Snippets, Settings (General, History, Privacy) and About.
- Stack, snippets with variables, boards, tags, favourites, text tools, smart actions, OCR search, annotation, area screenshots, GIF recording.
- Encryption of text, images and files; ignore rules; masked and expiring secrets.
- Export and import of history as JSON; one-command install; packaged zip with checksum.
- Known limits: not notarised; screen recording, Touch ID and Services were checked only in part on the author's Mac; English only.

## 0.2.0
- Menu-bar hub with every feature reachable (stack, capture, snippets, boards, pauses, ignore next copy, settings, help, quit).
- Picker: filters (type, pinned, favourites, time, app), previews, multi-select, thumbnails and colour swatches, ⌘D favourite, ⌘E extract text, Quick Look, placement under the menu-bar icon.
- History window: sections incl. Library and text found in images, list or cards view, tags, boards, text tools, smart actions, paste formats, annotation (pen, line, rectangle, arrow), Touch ID or password lock.
- Stack, snippets with variables, GIF recording with length and frame-rate settings, area screenshots.
- Privacy: optional encryption of text, images and files; regular-expression ignore rules; masked secrets; Quick Look copies deleted after use.
- Desktop app: standard menus, Dock icon (optional), Dock menu, window memory, Escape closes windows.
- Services entry "Save to WhatClip"; export and import of history as JSON.
- Shortcut recorder for the picker, with a message when the shortcut is taken.

## 0.1.0
- First version: history, picker, privacy rules, secret detection, settings, menu bar.
