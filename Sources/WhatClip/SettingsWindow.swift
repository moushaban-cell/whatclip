import AppKit
import WhatClipCore

/// Settings: General, History and Privacy tabs. Lives inside the main window (sidebar ▸ Settings). Save applies immediately.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    /// The settings view, placed in the main window's detail pane.
    private(set) var rootView = NSView()
    private let monitor: PasteboardMonitor
    private let excluded = NSTextView()
    private let secretAction = NSPopUpButton()
    private let lifetime = NSPopUpButton()
    private let retention = NSPopUpButton()
    private let maxItems = NSTextField()
    private let appearancePop = NSPopUpButton()
    private let placementPop = NSPopUpButton()
    private let gifSecondsPop = NSPopUpButton()
    private let gifFPSPop = NSPopUpButton()
    private let shortcutLabel = NSTextField(labelWithString: "")
    private let shortcutButton = NSButton(title: "Change shortcut…", target: nil, action: nil)
    private var shortcutMonitor: Any?
    private let showInDock = NSButton(checkboxWithTitle: "Show WhatClip in the Dock (off: menu bar only)", target: nil, action: nil)
    private let clearOnQuit = NSButton(checkboxWithTitle: "Clear history when WhatClip quits (keeps pinned items)", target: nil, action: nil)
    private let fuzzy = NSButton(checkboxWithTitle: "Fuzzy search (letters in order, any gaps)", target: nil, action: nil)
    private let ignoredField = NSTextField()
    private let encrypt = NSButton(checkboxWithTitle: "Encrypt stored images and files (key kept in your Keychain)", target: nil, action: nil)
    private let touchID = NSButton(checkboxWithTitle: "Ask for Touch ID or my Mac password before opening history", target: nil, action: nil)
    private let autoPaste = NSButton(checkboxWithTitle: "Paste automatically after I choose an item (needs Accessibility)", target: nil, action: nil)
    private let loginItem = NSButton(checkboxWithTitle: "Start WhatClip when I log in", target: nil, action: nil)
    private let ocr = NSButton(checkboxWithTitle: "Read text in copied images on this Mac (searchable)", target: nil, action: nil)
    private let status = NSTextField(labelWithString: "")
    private let shortcutStatus = NSTextField(labelWithString: "")
    /// The hot-key registration status, in words (for example "Active" or "Used by another app").
    var hotKeyStatus = ""
    private let lifetimes: [(String, Double)] = [("10 seconds", 10), ("1 minute", 60), ("5 minutes", 300), ("1 hour", 3600)]

    init(monitor: PasteboardMonitor) {
        self.monitor = monitor
        super.init()
        build()
        load()
    }

    /// Reloads the controls from the current settings (called when the Settings section is opened).
    func show() { load() }

    /// A scrolling page: the controls stack from the top and grow with the window.
    private func page(_ views: [NSView]) -> NSScrollView {
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.drawsBackground = false; scroll.borderType = .noBorder
        let doc = NSView(); doc.translatesAutoresizingMaskIntoConstraints = false
        let stack = NSStackView(views: views)
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 22, bottom: 18, right: 22)
        stack.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: doc.topAnchor), stack.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: doc.bottomAnchor),
        ])
        scroll.documentView = doc
        // The page is at least as tall as the window's visible area, and the controls hug the top.
        doc.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
        doc.heightAnchor.constraint(greaterThanOrEqualTo: scroll.contentView.heightAnchor).isActive = true
        stack.setHuggingPriority(.required, for: .vertical)
        return scroll
    }

    private func build() {
        func label(_ t: String) -> NSTextField { let l = NSTextField(labelWithString: t); l.font = .systemFont(ofSize: 12, weight: .semibold); l.textColor = .secondaryLabelColor; return l }
        func hint(_ t: String) -> NSTextField { let l = NSTextField(wrappingLabelWithString: t); l.font = .systemFont(ofSize: 11); l.textColor = .secondaryLabelColor; l.preferredMaxLayoutWidth = 480; return l }
        func row(_ t: String, _ v: NSView) -> NSStackView { let r = NSStackView(views: [NSTextField(labelWithString: t), v]); r.spacing = 10; return r }
        excluded.isRichText = false; excluded.font = .monospacedSystemFont(ofSize: 12, weight: .regular); excluded.isAutomaticQuoteSubstitutionEnabled = false
        excluded.setAccessibilityLabel("Excluded apps, bundle identifiers")
        // Size the text to the box, so the list shows (a text view needs this to lay out inside a scroll view).
        excluded.isVerticallyResizable = true; excluded.isHorizontallyResizable = false; excluded.autoresizingMask = [.width]
        excluded.textContainer?.widthTracksTextView = true; excluded.textContainerInset = NSSize(width: 6, height: 6)
        excluded.backgroundColor = .textBackgroundColor; excluded.textColor = .labelColor
        let excludedScroll = NSScrollView(); excludedScroll.documentView = excluded; excludedScroll.hasVerticalScroller = true; excludedScroll.borderType = .bezelBorder
        excludedScroll.heightAnchor.constraint(equalToConstant: 96).isActive = true
        excludedScroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 380).isActive = true

        secretAction.addItems(withTitles: ["Remove after a while", "Don't keep it at all", "Keep it like any other copy"])
        lifetime.addItems(withTitles: lifetimes.map(\.0))
        retention.addItems(withTitles: Retention.allCases.map(\.title))
        maxItems.placeholderString = "500"; maxItems.alignment = .right
        maxItems.widthAnchor.constraint(equalToConstant: 80).isActive = true
        ignoredField.placeholderString = "^\\d{6}$"
        ignoredField.widthAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true

        // General: how WhatClip looks, opens and starts.
        let general = page([
            label("Picker shortcut"), NSStackView(views: [shortcutLabel, shortcutButton]),
            hint("Press Change, then the new key combination. It needs Command, Option or Control."),
            shortcutStatus,
            label("Look and behaviour"),
            row("Appearance", appearancePop), row("Open the picker", placementPop),
            autoPaste, showInDock, fuzzy, clearOnQuit, loginItem,
            label("Screen recording"),
            row("GIF length", gifSecondsPop), row("GIF frames per second", gifFPSPop),
        ])
        // History: what is kept, for how long, and what is never recorded.
        let history = page([
            label("Keep history"), row("Keep items for", retention), row("Maximum number of items", maxItems),
            label("Copied secrets (keys, tokens, card numbers)"), secretAction,
            row("Remove them after", lifetime),
            hint("Secrets are shown masked in the picker. They can be removed on a timer or never kept."),
            label("Apps that are never recorded"), excludedScroll,
            hint("One app bundle identifier per line, for example com.example.app. Password managers are already listed."),
            label("Never record text matching"), ignoredField,
            hint("Separate several patterns with spaces (a pattern cannot contain a space). Example for one-time codes: ^\\d{6}$"),
        ])
        // Privacy: encryption, locks and on-device reading of images.
        let privacy = page([
            label("Privacy and security"), encrypt, touchID, ocr,
            hint("Encryption keeps the key in your login Keychain. Turning it on does not change items you already saved."),
            hint("With the lock on, one unlock lasts 15 minutes across the picker and the history window. Lock history now in the menu locks it at once."),
        ])

        let tabs = NSTabView()
        tabs.tabViewType = .topTabsBezelBorder
        for (title, view) in [("General", general), ("History", history), ("Privacy", privacy)] {
            let item = NSTabViewItem(identifier: title); item.label = title
            let host = NSView(); view.translatesAutoresizingMaskIntoConstraints = false; host.addSubview(view)
            NSLayoutConstraint.activate([view.topAnchor.constraint(equalTo: host.topAnchor), view.bottomAnchor.constraint(equalTo: host.bottomAnchor),
                                         view.leadingAnchor.constraint(equalTo: host.leadingAnchor), view.trailingAnchor.constraint(equalTo: host.trailingAnchor)])
            item.view = host; tabs.addTabViewItem(item)
        }
        tabs.setContentHuggingPriority(.defaultLow, for: .vertical)
        // Testing aid: WHATCLIP_TAB=0|1|2 opens General, History or Privacy.
        if let t = ProcessInfo.processInfo.environment["WHATCLIP_TAB"], let i = Int(t) { tabs.selectTabViewItem(at: i) }

        // Save bar: always visible under the tabs.
        let save = NSButton(title: "Save", target: self, action: #selector(saveTapped)); save.keyEquivalent = "\r"; save.bezelStyle = .rounded
        let bar = NSStackView(views: [status, save]); bar.spacing = 12; bar.edgeInsets = NSEdgeInsets(top: 8, left: 22, bottom: 12, right: 22)
        status.textColor = .secondaryLabelColor
        let root = NSStackView(views: [tabs, bar]); root.orientation = .vertical; root.alignment = .leading; root.spacing = 0
        root.translatesAutoresizingMaskIntoConstraints = false
        rootView = root
        NSLayoutConstraint.activate([tabs.widthAnchor.constraint(equalTo: root.widthAnchor), bar.widthAnchor.constraint(equalTo: root.widthAnchor)])
    }

    /// Records the next key combination with Command, Option or Control, and saves it as the picker shortcut.
    @objc private func recordShortcut() {
        shortcutLabel.stringValue = "Press the new shortcut (Esc to cancel)…"
        if let m = shortcutMonitor { NSEvent.removeMonitor(m) }
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self else { return e }
            if e.keyCode == 53 { self.endRecording(); self.load(); return nil }            // Esc cancels
            let f = e.modifierFlags.intersection([.command, .option, .control, .shift])
            guard f.contains(.command) || f.contains(.option) || f.contains(.control) else { return nil }
            var carbon = 0
            if f.contains(.command) { carbon |= 256 }
            if f.contains(.shift) { carbon |= 512 }
            if f.contains(.option) { carbon |= 2048 }
            if f.contains(.control) { carbon |= 4096 }
            var s = self.monitor.settings
            s.hotKeyCode = Int(e.keyCode); s.hotKeyModifiers = carbon
            self.endRecording()
            do { try self.monitor.update(s); self.status.stringValue = "Shortcut saved." } catch { self.status.stringValue = "Could not save the shortcut." }
            self.load()
            return nil
        }
    }
    private func endRecording() { if let m = shortcutMonitor { NSEvent.removeMonitor(m) }; shortcutMonitor = nil }

    /// A readable name for a key code and Carbon modifier bits, for example "⌘⇧V".
    static func describe(code: Int, mods: Int) -> String {
        var s = ""
        if mods & 4096 != 0 { s += "⌃" }
        if mods & 2048 != 0 { s += "⌥" }
        if mods & 512 != 0 { s += "⇧" }
        if mods & 256 != 0 { s += "⌘" }
        let keys: [Int: String] = [0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
                                   16: "Y", 17: "T", 31: "O", 32: "U", 34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M", 29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9"]
        return s + (keys[code] ?? "key \(code)")
    }

    private func load() {
        let s = monitor.settings
        excluded.string = BundleIDList.format(s.excludedBundleIDs)
        secretAction.selectItem(at: [SecretAction.expire, .skip, .keep].firstIndex(of: s.secretAction) ?? 0)
        lifetime.selectItem(at: lifetimes.firstIndex { $0.1 == s.secretLifetimeSeconds } ?? 1)
        retention.selectItem(at: Retention.allCases.firstIndex(of: s.retention) ?? 0)
        maxItems.stringValue = String(s.maxItems)
        gifSecondsPop.removeAllItems(); gifSecondsPop.addItems(withTitles: ["3 seconds", "5 seconds", "10 seconds", "15 seconds"])
        gifSecondsPop.selectItem(at: [3, 5, 10, 15].firstIndex(of: s.gifSeconds) ?? 1)
        gifFPSPop.removeAllItems(); gifFPSPop.addItems(withTitles: ["5 (smallest)", "8", "12", "15 (smoothest)"])
        gifFPSPop.selectItem(at: [5, 8, 12, 15].firstIndex(of: s.gifFramesPerSecond) ?? 1)
        shortcutLabel.stringValue = "Show picker: " + Self.describe(code: s.hotKeyCode, mods: s.hotKeyModifiers)
        shortcutButton.target = self; shortcutButton.action = #selector(recordShortcut)
        shortcutStatus.stringValue = hotKeyStatus; shortcutStatus.font = .systemFont(ofSize: 11); shortcutStatus.textColor = .secondaryLabelColor
        appearancePop.removeAllItems(); appearancePop.addItems(withTitles: AppearanceChoice.allCases.map(\.title))
        appearancePop.selectItem(at: AppearanceChoice.allCases.firstIndex(of: s.appearance) ?? 0)
        placementPop.removeAllItems(); placementPop.addItems(withTitles: PopupPlacement.allCases.map(\.title))
        placementPop.selectItem(at: PopupPlacement.allCases.firstIndex(of: s.popupPlacement) ?? 0)
        showInDock.state = s.showInDock ? .on : .off
        autoPaste.state = s.autoPaste ? .on : .off
        clearOnQuit.state = s.clearOnQuit ? .on : .off; fuzzy.state = s.fuzzySearch ? .on : .off
        ignoredField.stringValue = s.ignoredPatterns.joined(separator: "  ")
        encrypt.state = s.encryptPayloads ? .on : .off; touchID.state = s.requireTouchID ? .on : .off
        ocr.state = s.recognizeText ? .on : .off; loginItem.state = s.launchAtLogin ? .on : .off
        status.stringValue = ""
    }

    @objc private func saveTapped() {
        endRecording()
        var s = monitor.settings
        s.excludedBundleIDs = BundleIDList.parse(excluded.string)
        s.secretAction = [SecretAction.expire, .skip, .keep][max(0, secretAction.indexOfSelectedItem)]
        s.secretLifetimeSeconds = lifetimes[max(0, lifetime.indexOfSelectedItem)].1
        s.retention = Retention.allCases[max(0, retention.indexOfSelectedItem)]
        s.appearance = AppearanceChoice.allCases[max(0, appearancePop.indexOfSelectedItem)]
        s.popupPlacement = PopupPlacement.allCases[max(0, placementPop.indexOfSelectedItem)]
        s.showInDock = showInDock.state == .on
        s.autoPaste = autoPaste.state == .on
        s.gifSeconds = [3, 5, 10, 15][max(0, gifSecondsPop.indexOfSelectedItem)]
        s.gifFramesPerSecond = [5, 8, 12, 15][max(0, gifFPSPop.indexOfSelectedItem)]
        s.clearOnQuit = clearOnQuit.state == .on; s.fuzzySearch = fuzzy.state == .on
        s.ignoredPatterns = ignoredField.stringValue.components(separatedBy: " ").filter { !$0.isEmpty }
        s.encryptPayloads = encrypt.state == .on; s.requireTouchID = touchID.state == .on
        s.recognizeText = ocr.state == .on; s.launchAtLogin = loginItem.state == .on
        let raw = maxItems.stringValue.trimmingCharacters(in: .whitespaces)
        if !raw.isEmpty {
            guard let n = Int(raw), (10...5_000).contains(n) else { status.stringValue = "Enter a whole number from 10 to 5000."; return }
            s.maxItems = n
        }
        do { try monitor.update(s); status.stringValue = "Saved." }
        catch { status.stringValue = "Could not save: \(error.localizedDescription)" }
    }
}
