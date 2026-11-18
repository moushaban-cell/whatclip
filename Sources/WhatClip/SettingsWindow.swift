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
    private let languagePop = NSPopUpButton()
    private let placementPop = NSPopUpButton()
    private let gifSecondsPop = NSPopUpButton()
    private let gifFPSPop = NSPopUpButton()
    private let shortcutLabel = NSTextField(labelWithString: "")
    private let shortcutButton = NSButton(title: Lang.t("ui.changeShortcut"), target: nil, action: nil)
    private var shortcutMonitor: Any?
    private let showInDock = NSButton(checkboxWithTitle: Lang.t("ui.set.dock"), target: nil, action: nil)
    private let clearOnQuit = NSButton(checkboxWithTitle: Lang.t("ui.set.clearQuit"), target: nil, action: nil)
    private let fuzzy = NSButton(checkboxWithTitle: Lang.t("ui.set.fuzzy"), target: nil, action: nil)
    private let ignoredField = NSTextField()
    private let encrypt = NSButton(checkboxWithTitle: Lang.t("ui.set.encrypt"), target: nil, action: nil)
    private let touchID = NSButton(checkboxWithTitle: Lang.t("ui.set.touch"), target: nil, action: nil)
    private let autoPaste = NSButton(checkboxWithTitle: Lang.t("ui.set.autoPaste"), target: nil, action: nil)
    private let actionsView = NSTextView()
    private let actionsScroll = NSScrollView()
    private let syncField = NSTextField()
    private let chooseSync = NSButton(title: Lang.t("ui.chooseFolder"), target: nil, action: nil)
    private let updates = NSButton(checkboxWithTitle: Lang.t("ui.set.updates"), target: nil, action: nil)
    private let loginItem = NSButton(checkboxWithTitle: Lang.t("ui.set.login"), target: nil, action: nil)
    private let ocr = NSButton(checkboxWithTitle: Lang.t("ui.set.ocr"), target: nil, action: nil)
    private let status = NSTextField(labelWithString: "")
    private let shortcutStatus = NSTextField(labelWithString: "")
    /// The hot-key registration status, in words (for example Lang.t("ui.active") or Lang.t("ui.usedByOther")).
    var hotKeyStatus = ""
    private let lifetimes: [(String, Double)] = [(Lang.t("ui.dur.10s"), 10), (Lang.t("ui.dur.1m"), 60), (Lang.t("ui.dur.5m"), 300), (Lang.t("ui.dur.1h"), 3600)]

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
        excluded.setAccessibilityLabel(Lang.t("ui.a11y.excluded"))
        actionsView.isVerticallyResizable = true; actionsView.isHorizontallyResizable = false; actionsView.autoresizingMask = [.width]
        actionsView.textContainer?.widthTracksTextView = true; actionsView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        actionsView.isAutomaticQuoteSubstitutionEnabled = false; actionsView.textColor = .labelColor; actionsView.backgroundColor = .textBackgroundColor
        actionsScroll.documentView = actionsView; actionsScroll.hasVerticalScroller = true; actionsScroll.borderType = .bezelBorder
        actionsScroll.heightAnchor.constraint(equalToConstant: 80).isActive = true
        actionsScroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 380).isActive = true
        syncField.placeholderString = Lang.t("ui.noFolder"); syncField.isEditable = false
        syncField.widthAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true
        chooseSync.target = self; chooseSync.action = #selector(pickSyncFolder)
        // Size the text to the box, so the list shows (a text view needs this to lay out inside a scroll view).
        excluded.isVerticallyResizable = true; excluded.isHorizontallyResizable = false; excluded.autoresizingMask = [.width]
        excluded.textContainer?.widthTracksTextView = true; excluded.textContainerInset = NSSize(width: 6, height: 6)
        excluded.backgroundColor = .textBackgroundColor; excluded.textColor = .labelColor
        let excludedScroll = NSScrollView(); excludedScroll.documentView = excluded; excludedScroll.hasVerticalScroller = true; excludedScroll.borderType = .bezelBorder
        excludedScroll.heightAnchor.constraint(equalToConstant: 96).isActive = true
        excludedScroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 380).isActive = true

        secretAction.addItems(withTitles: [Lang.t("ui.secret.remove"), Lang.t("ui.secret.never"), Lang.t("ui.secret.keep")])
        lifetime.addItems(withTitles: lifetimes.map(\.0))
        retention.addItems(withTitles: Retention.allCases.map { Lang.t("ret." + $0.rawValue) })
        maxItems.placeholderString = "500"; maxItems.alignment = .right
        maxItems.widthAnchor.constraint(equalToConstant: 80).isActive = true
        ignoredField.placeholderString = "^\\d{6}$"
        ignoredField.widthAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true

        // General: how WhatClip looks, opens and starts.
        let general = page([
            label(Lang.t("ui.set.pickerShortcut")), NSStackView(views: [shortcutLabel, shortcutButton]),
            hint(Lang.t("ui.set.pressChange")),
            shortcutStatus,
            label(Lang.t("ui.set.lookBehaviour")),
            row(Lang.t("ui.set.appearance"), appearancePop), row(Lang.t("ui.set.openPicker"), placementPop),
            row(Lang.t("ui.set.language"), languagePop), hint(Lang.t("ui.set.languageHint")),
            autoPaste, showInDock, fuzzy, clearOnQuit, loginItem, updates,
            label(Lang.t("ui.set.actionsLabel")), actionsScroll,
            hint(Lang.t("ui.set.actionsHint")),
            label(Lang.t("ui.set.syncLabel")), NSStackView(views: [syncField, chooseSync]),
            hint(Lang.t("ui.set.syncHint")),
            label(Lang.t("ui.set.screenRec")),
            row(Lang.t("ui.set.gifLength"), gifSecondsPop), row(Lang.t("ui.set.gifFps"), gifFPSPop),
        ])
        // History: what is kept, for how long, and what is never recorded.
        let history = page([
            label(Lang.t("ui.set.keepHistory")), row(Lang.t("ui.set.keepFor"), retention), row(Lang.t("ui.set.maxItems"), maxItems),
            label(Lang.t("ui.set.secrets")), secretAction,
            row(Lang.t("ui.set.removeAfter"), lifetime),
            hint(Lang.t("ui.set.secretsHint")),
            label(Lang.t("ui.set.excludedApps")), excludedScroll,
            hint(Lang.t("ui.set.excludedHint")),
            label(Lang.t("ui.set.ignored")), ignoredField,
            hint(Lang.t("ui.set.ignoredHint")),
        ])
        // Privacy: encryption, locks and on-device reading of images.
        let privacy = page([
            label(Lang.t("ui.set.privacy")), encrypt, touchID, ocr,
            hint(Lang.t("ui.set.encryptHint")),
            hint(Lang.t("ui.set.lockHint")),
        ])

        let tabs = NSTabView()
        tabs.tabViewType = .topTabsBezelBorder
        for (title, view) in [(Lang.t("ui.tab.general"), general), (Lang.t("ui.history"), history), (Lang.t("ui.tab.privacy"), privacy)] {
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
        let save = NSButton(title: Lang.t("ui.save"), target: self, action: #selector(saveTapped)); save.keyEquivalent = "\r"; save.bezelStyle = .rounded
        let bar = NSStackView(views: [status, save]); bar.spacing = 12; bar.edgeInsets = NSEdgeInsets(top: 8, left: 22, bottom: 12, right: 22)
        status.textColor = .secondaryLabelColor
        let root = NSStackView(views: [tabs, bar]); root.orientation = .vertical; root.alignment = .leading; root.spacing = 0
        root.translatesAutoresizingMaskIntoConstraints = false
        rootView = root
        NSLayoutConstraint.activate([tabs.widthAnchor.constraint(equalTo: root.widthAnchor), bar.widthAnchor.constraint(equalTo: root.widthAnchor)])
    }

    /// Picks the sync folder with a standard dialog.
    @objc private func pickSyncFolder() {
        if let path = FolderSync.chooseFolder() { syncField.stringValue = path }
    }

    /// Records the next key combination with Command, Option or Control, and saves it as the picker shortcut.
    @objc private func recordShortcut() {
        shortcutLabel.stringValue = Lang.t("ui.set.pressNew")
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
            do { try self.monitor.update(s); self.status.stringValue = Lang.t("ui.set.shortcutSaved") } catch { self.status.stringValue = Lang.t("ui.set.shortcutFail") }
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
        return s + (keys[code] ?? Lang.t("ui.keyFallback", ["code": "\(code)"]))
    }

    private func load() {
        let s = monitor.settings
        excluded.string = BundleIDList.format(s.excludedBundleIDs)
        secretAction.selectItem(at: [SecretAction.expire, .skip, .keep].firstIndex(of: s.secretAction) ?? 0)
        lifetime.selectItem(at: lifetimes.firstIndex { $0.1 == s.secretLifetimeSeconds } ?? 1)
        retention.selectItem(at: Retention.allCases.firstIndex(of: s.retention) ?? 0)
        maxItems.stringValue = String(s.maxItems)
        gifSecondsPop.removeAllItems(); gifSecondsPop.addItems(withTitles: [Lang.t("ui.dur.3s"), Lang.t("ui.dur.5s"), Lang.t("ui.dur.10s"), Lang.t("ui.dur.15s")])
        gifSecondsPop.selectItem(at: [3, 5, 10, 15].firstIndex(of: s.gifSeconds) ?? 1)
        gifFPSPop.removeAllItems(); gifFPSPop.addItems(withTitles: [Lang.t("ui.gif.smallest"), "8", "12", Lang.t("ui.gif.smoothest")])
        gifFPSPop.selectItem(at: [5, 8, 12, 15].firstIndex(of: s.gifFramesPerSecond) ?? 1)
        shortcutLabel.stringValue = Lang.t("ui.set.showPicker") + Self.describe(code: s.hotKeyCode, mods: s.hotKeyModifiers)
        shortcutButton.target = self; shortcutButton.action = #selector(recordShortcut)
        shortcutStatus.stringValue = hotKeyStatus; shortcutStatus.font = .systemFont(ofSize: 11); shortcutStatus.textColor = .secondaryLabelColor
        languagePop.removeAllItems(); languagePop.addItems(withTitles: Lang.names.map(\.name))
        languagePop.selectItem(at: Lang.names.firstIndex { $0.code == s.language } ?? 0)
        appearancePop.removeAllItems(); appearancePop.addItems(withTitles: AppearanceChoice.allCases.map { Lang.t("app." + $0.rawValue) })
        appearancePop.selectItem(at: AppearanceChoice.allCases.firstIndex(of: s.appearance) ?? 0)
        placementPop.removeAllItems(); placementPop.addItems(withTitles: PopupPlacement.allCases.map { Lang.t("place." + $0.rawValue) })
        placementPop.selectItem(at: PopupPlacement.allCases.firstIndex(of: s.popupPlacement) ?? 0)
        showInDock.state = s.showInDock ? .on : .off
        actionsView.string = s.actionsText
        syncField.stringValue = s.syncFolder
        updates.state = s.checkForUpdates ? .on : .off
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
        s.language = Lang.names[max(0, languagePop.indexOfSelectedItem)].code
        s.popupPlacement = PopupPlacement.allCases[max(0, placementPop.indexOfSelectedItem)]
        s.showInDock = showInDock.state == .on
        s.actionsText = actionsView.string
        s.syncFolder = syncField.stringValue
        s.checkForUpdates = updates.state == .on
        s.autoPaste = autoPaste.state == .on
        s.gifSeconds = [3, 5, 10, 15][max(0, gifSecondsPop.indexOfSelectedItem)]
        s.gifFramesPerSecond = [5, 8, 12, 15][max(0, gifFPSPop.indexOfSelectedItem)]
        s.clearOnQuit = clearOnQuit.state == .on; s.fuzzySearch = fuzzy.state == .on
        s.ignoredPatterns = ignoredField.stringValue.components(separatedBy: " ").filter { !$0.isEmpty }
        s.encryptPayloads = encrypt.state == .on; s.requireTouchID = touchID.state == .on
        s.recognizeText = ocr.state == .on; s.launchAtLogin = loginItem.state == .on
        let raw = maxItems.stringValue.trimmingCharacters(in: .whitespaces)
        if !raw.isEmpty {
            guard let n = Int(raw), (10...5_000).contains(n) else { status.stringValue = Lang.t("ui.set.badNumber"); return }
            s.maxItems = n
        }
        do { try monitor.update(s); status.stringValue = Lang.t("ui.set.saved") }
        catch { status.stringValue = Lang.t("ui.set.couldNotSave", ["error": error.localizedDescription]) }
    }
}
