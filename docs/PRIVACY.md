# Privacy

WhatClip keeps everything on your Mac.

- **Where data lives:** `~/Library/Application Support/WhatClip/` holds the history database, settings and image or file payloads. Folders are private to your user (mode 700); files are private too (mode 600).
- **Network:** WhatClip makes no network requests. There is no account, no telemetry and no crash reporting.
- **Passwords and secrets:** Copies from password managers and Keychain Access are never recorded. Apps that mark copies as concealed, transient or auto-generated are skipped. Copied secrets (API keys, tokens, private keys, card numbers that pass a checksum) are shown masked and are removed after a set time, or never kept.
- **Encryption (optional):** When turned on, images, files and the text of new items are encrypted with AES-GCM. The key is kept in your login Keychain. Items saved before encryption was turned on stay as they were. Search still works, because it runs on the decrypted rows in memory.
- **Text recognition:** Text in images is read on this Mac with Apple's Vision framework. Nothing leaves the Mac.
- **Quick Look:** Decrypted copies used for preview are written to a private temporary folder and deleted when the picker closes, at launch and at quit.
- **Export:** File ▸ Export History writes a JSON file with your text, tags, pins and favourites (no images or files). The file is private (mode 600), but it contains your copied text. Keep it safe.
- **Touch ID or password:** If you turn this on, the picker and the history window ask for Touch ID or your Mac password before they show anything.
- **Clear:** Clear history from the menu. Clear on quit removes everything except pinned items and the Library (favourites).
- **Limits:** The database is protected by file permissions. Text is encrypted only when encryption is on. Anyone with your unlocked user account can read the history.
