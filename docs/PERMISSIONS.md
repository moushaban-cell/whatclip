# Permissions and system changes

WhatClip works with no permission. Each item below is optional, and each is only used when you turn on the feature that needs it.

| Permission or change | Needed for | Without it | How to remove it |
|---|---|---|---|
| None | history, picker, menus, search, filters, export and import, snippets, text tools | works | - |
| Accessibility | pressing ⌘V for you after you choose an item | the item is on the clipboard; press ⌘V yourself | System Settings → Privacy & Security → Accessibility |
| Screen Recording | screenshots (system tool) and GIF recording | screenshots and GIFs do not work | System Settings → Privacy & Security → Screen Recording |
| Touch ID or Mac password | unlock the picker and history (setting) | no lock | turn off in Settings |
| Keychain item `app.whatclip.WhatClip` | the encryption key (setting) | no encryption | turn off encryption; delete the item in Keychain Access |
| Login item | start at login (setting) | does not start at login | turn off in Settings |
| Services entry "Save to WhatClip" | sending text or files from any app's right-click menu | no entry | delete the app |
| Dock icon | desktop behaviour (setting "Show in Dock") | menu bar only | turn off in Settings |

## Notes
- The app is signed with a local self-signed certificate, not with an Apple developer account. macOS therefore shows an unidentified developer warning on other Macs. Trusting the certificate on your Mac (once) keeps the Accessibility and Screen Recording permissions across rebuilds.
- Nothing outside WhatClip's own folder is changed, except the optional items above.
