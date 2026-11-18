import AppKit
import WhatClipCore

/// The menu-bar hub: every feature is reachable from the status item (left or right click).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var status: NSStatusItem!
    var monitor: PasteboardMonitor!
    var store: ClipStore!
    var picker: PickerController!
    var settings: SettingsWindowController!
    var history: HistoryWindowController!
    var onboarding: OnboardingWindowController!
    let gif = GIFRecorder()
    var emoji: EmojiPanelController!
    var syncTimer: Timer?
    let hotKey = HotKey()
    var hotKeyOK = false
    var hotKeyStatus = Lang.t("ui.hk.notRegistered")
    let menu = NSMenu()
    /// The stack: copies collected in order while a stack is running (session only).
    var stack: [ClipItem] = []
    var stackOn = false
    var stackLastID: Int64 = 0

    func applicationDidFinishLaunching(_ n: Notification) {
        // Every file this app creates is private to the user from the start.
        umask(0o077)
        PickerController.cleanPreviews()
        let dir = ProcessInfo.processInfo.environment["WHATCLIP_DATA"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("WhatClip")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard let s = try? ClipStore(path: dir.appendingPathComponent("history.sqlite").path) else { NSApp.terminate(nil); return }
        store = s
        // The language comes from the same folder as the data. Arabic also sets the app's system layout to right to left.
        let language = SettingsStore(url: dir.appendingPathComponent("settings.json")).load().language
        Lang.current = language
        UserDefaults.standard.set(language == "en" ? nil : [language], forKey: "AppleLanguages")
        monitor = PasteboardMonitor(store: store, settingsStore: SettingsStore(url: dir.appendingPathComponent("settings.json")))
        monitor.applyPrivacyAndSystem(monitor.settings)
        monitor.start()
        picker = PickerController(store: store, monitor: monitor)
        settings = SettingsWindowController(monitor: monitor)
        history = HistoryWindowController(store: store, monitor: monitor)
        emoji = EmojiPanelController(copy: { [weak self] text in self?.monitor.restore(text) })
        history.settingsRoot = settings.rootView
        onboarding = OnboardingWindowController(monitor: monitor)
        monitor.onChange = { [weak self] in self?.copyHappened() }
        monitor.onSettingsChanged = { [weak self] _ in self?.applyAppearance(); self?.applyActivationPolicy(); self?.hotKeyChangedBySettings() }

        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "list.clipboard", accessibilityDescription: "WhatClip")
        status.button?.setAccessibilityLabel("WhatClip")
        menu.delegate = self; status.menu = menu

        hotKeyOK = applyHotKey()
        NSApp.servicesProvider = self
        NSApp.mainMenu = DesktopMenu.build(target: self, settingsAction: #selector(openSettings), aboutAction: #selector(showAbout),
                                           helpAction: #selector(openHelp), pickerAction: #selector(openPicker),
                                           historyAction: #selector(openHistory), pauseAction: #selector(pauseForever),
                                           exportAction: #selector(exportHistory), importAction: #selector(importHistory))
        applyAppearance()
        applyActivationPolicy()
        // Optional folder sync and the daily update check. Both are off or local unless you turn them on.
        runFolderSync()
        syncTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.runFolderSync() } }
        UpdateCheck.runIfDue(enabled: monitor.settings.checkForUpdates, current: (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0")
        if !monitor.settings.onboardingDone { onboarding.show() }
        // Testing aid: WHATCLIP_SHOW=picker, history or onboarding opens that window at launch.
        switch ProcessInfo.processInfo.environment["WHATCLIP_SHOW"] {
        case "picker":                       // opened after launch, when the menu-bar item has its real position
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.openPicker() }
        case "menu":
            // Testing aid: open the status menu after launch so it can be checked on screen.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self, let b = self.status.button else { return }
                NSApp.activate(ignoringOtherApps: true)
                self.menu.popUp(positioning: nil, at: NSPoint(x: 0, y: b.bounds.height), in: b)
            }
        case "history": history.show()
        case "cards": history.showCards()
        case "pickercards":
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.picker.showCards() }
        case "onboarding": onboarding.show()
        case "settings": history.show(section: .settings)
        case "emoji": emoji.show()
        default: break
        }
    }

    func runFolderSync() {
        guard let store, let monitor else { return }
        FolderSync.run(store: store, folder: monitor.settings.syncFolder)
    }

    /// Pastes every stack item at once, joined by a separator (one per line, comma, or space).
    func pasteStack(separator: Separator) {
        let texts = stack.map(\.text)
        guard !texts.isEmpty else { return }
        monitor.restore(Merge.join(texts, separator: separator))
        stack.removeAll(); stackOn = false
    }

    func applicationWillTerminate(_ n: Notification) {
        runFolderSync()
        PickerController.cleanPreviews()
        if monitor?.settings.clearOnQuit == true { try? store.clear(keepPinned: true) }
    }

    /// Registers the picker shortcut from the settings. False when another app already uses it.
    @discardableResult
    func applyHotKey() -> Bool {
        let st = monitor.settings
        let ok = hotKey.register(keyCode: UInt32(st.hotKeyCode), modifiers: UInt32(st.hotKeyModifiers)) { [weak self] in self?.openPicker() }
        hotKeyOK = ok
        hotKeyStatus = hotKey.lastStatus
        settings.hotKeyStatus = hotKeyStatus
        return ok
    }
    func hotKeyChangedBySettings() {
        if !applyHotKey() {
            let a = NSAlert(); a.messageText = Lang.t("ui.shortcutInUse")
            a.informativeText = Lang.t("ui.shortcutInUseInfo"); a.runModal()
        }
    }

    /// "Show in Dock" on (default): a normal desktop app with a Dock icon. Off: menu-bar only.
    func applyActivationPolicy() {
        NSApp.setActivationPolicy(monitor.settings.showInDock ? .regular : .accessory)
    }

    /// Closing a window hides it; the app keeps running in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Clicking the Dock icon with no window open brings up the history.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { history.show() }
        return true
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let m = NSMenu()
        for (title, action) in [(Lang.t("ui.m.openPicker"), #selector(openPicker)), (Lang.t("ui.m.openHistory"), #selector(openHistory)),
                                (Lang.t("ui.m.pauseCapturing"), #selector(pauseForever)), (Lang.t("ui.m.dock.settings"), #selector(openSettings))] {
            let it = NSMenuItem(title: title, action: action, keyEquivalent: ""); it.target = self; m.addItem(it)
        }
        m.addItem(.separator())
        let q = NSMenuItem(title: Lang.t("ui.m.quit"), action: #selector(quit), keyEquivalent: ""); q.target = self; m.addItem(q)
        return m
    }

    @objc func showAbout() { NSApp.orderFrontStandardAboutPanel(nil) }

    func applyAppearance() {
        switch monitor.settings.appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    // MARK: stack

    /// Called after every capture: while a stack runs, the new copy joins it.
    func copyHappened() {
        if stackOn, let newest = try? store.list(limit: 1).first, newest.id != stackLastID {
            stackLastID = newest.id; stack.append(newest)
        }
        picker.refreshIfVisible()
        history.refreshIfVisible()
    }

    // MARK: menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        add(Lang.t("menu.openPicker") + "   ⇧⌘X", #selector(openPicker))
        add(Lang.t("menu.openHistory"), #selector(openHistory))
        add(Lang.t("ui.m.emoji"), #selector(openEmoji))
        menu.addItem(.separator())

        let recent = (try? store.list(limit: 8)) ?? []
        if recent.isEmpty { disabled(Lang.t("ui.nothingYet")) }
        for i in recent { let m = NSMenuItem(title: PickerController.oneLine(i.listTitle), action: #selector(pasteRecent(_:)), keyEquivalent: ""); m.target = self; m.representedObject = i; m.image = NSImage(systemSymbolName: i.kind.symbol, accessibilityDescription: nil); menu.addItem(m) }
        menu.addItem(.separator())

        submenu(Lang.t("ui.menu.stack"), stackMenu())
        submenu(Lang.t("ui.menu.capture"), captureMenu())
        submenu(Lang.t("ui.snippets"), snippetsMenu())
        submenu(Lang.t("ui.boards"), boardsMenu())
        submenu(Lang.t("ui.menu.pause"), pauseMenu())
        add(monitor.policy.ignoreNextCopy ? Lang.t("ui.m.ignoring") : Lang.t("ui.m.ignoreNext"), #selector(ignoreNext))
        if monitor.settings.requireTouchID { add(Authentication.isUnlocked ? Lang.t("ui.lockNow") : Lang.t("ui.locked"), #selector(lockHistory)) }
        menu.addItem(.separator())
        add(Lang.t("ui.m.clearHistory"), #selector(clearHistory))
        menu.addItem(.separator())
        add(Lang.t("menu.settings"), #selector(openSettings))
        add(Lang.t("ui.m.setup"), #selector(openOnboarding))
        add(Lang.t("ui.m.help"), #selector(openHelp))
        add(Lang.t("menu.quit"), #selector(quit), key: "q")
    }

    private func stackMenu() -> NSMenu {
        let m = NSMenu()
        m.addItem(item(stackOn ? Lang.t("ui.m.stopStack") : Lang.t("ui.m.startStack"), #selector(toggleStack)))
        m.addItem(item(Lang.t("ui.m.pasteNext", ["n": "\(stack.count)"]), #selector(pasteNextStack), enabled: !stack.isEmpty))
        m.addItem(.separator())
        for sep in [Separator.newline, .comma, .space] {
            let it = item(Lang.t("ui.m.pasteAll", ["sep": Lang.t("sep." + sep.rawValue).lowercased()]), #selector(pasteAllStack(_:)), enabled: !stack.isEmpty)
            it.representedObject = sep.rawValue
            m.addItem(it)
        }
        m.addItem(item(Lang.t("ui.m.clearStack"), #selector(clearStack), enabled: !stack.isEmpty))
        return m
    }
    private func captureMenu() -> NSMenu {
        let m = NSMenu()
        m.addItem(item(Lang.t("ui.m.screenshot"), #selector(screenshot)))
        m.addItem(item(gif.isRecording ? Lang.t("ui.m.stopGif") : Lang.t("ui.m.gif"), #selector(recordGIF)))
        m.addItem(item(Lang.t("ui.m.annotate"), #selector(annotateLatest)))
        return m
    }
    private func snippetsMenu() -> NSMenu {
        let m = NSMenu()
        let snippets = (try? store.snippets()) ?? []
        for s in snippets.prefix(12) { let it = item(s.title, #selector(insertSnippet(_:))); it.representedObject = s.id; m.addItem(it) }
        if snippets.isEmpty { m.addItem(item(Lang.t("ui.noSnippets"), nil, enabled: false)) }
        m.addItem(.separator())
        m.addItem(item(Lang.t("ui.m.manageSnippets"), #selector(manageSnippets)))
        return m
    }
    private func boardsMenu() -> NSMenu {
        let m = NSMenu()
        let boards = (try? store.boards()) ?? []
        for b in boards { let it = item(b.name, #selector(openBoard(_:))); it.representedObject = b.id; m.addItem(it) }
        if boards.isEmpty { m.addItem(item(Lang.t("ui.noBoards"), nil, enabled: false)) }
        return m
    }
    private func pauseMenu() -> NSMenu {
        let m = NSMenu()
        if monitor.isPaused {
            m.addItem(item(Lang.t("ui.m.resume"), #selector(resumeCapture)))
        } else {
            m.addItem(item(Lang.t("ui.m.for5"), #selector(pause5)))
            m.addItem(item(Lang.t("ui.m.for1h"), #selector(pause60)))
            m.addItem(item(Lang.t("ui.m.untilOn"), #selector(pauseForever)))
        }
        return m
    }

    @discardableResult func add(_ t: String, _ a: Selector, key: String = "") -> NSMenuItem {
        let m = NSMenuItem(title: t, action: a, keyEquivalent: key); m.target = self; menu.addItem(m); return m
    }
    func item(_ t: String, _ a: Selector?, enabled: Bool = true) -> NSMenuItem {
        let m = NSMenuItem(title: t, action: a, keyEquivalent: ""); m.target = self; m.isEnabled = enabled && a != nil; return m
    }
    func submenu(_ title: String, _ sub: NSMenu) { let m = NSMenuItem(title: title, action: nil, keyEquivalent: ""); m.submenu = sub; menu.addItem(m) }
    func disabled(_ t: String) { let m = NSMenuItem(title: t, action: nil, keyEquivalent: ""); m.isEnabled = false; menu.addItem(m) }

    // MARK: actions

    @objc func openPicker() {
        let anchor = status.button.flatMap { b -> NSRect? in
            guard let w = b.window else { return nil }
            return w.convertToScreen(b.convert(b.bounds, to: nil))
        }
        picker.show(anchor: anchor)
    }
    @objc func openHistory() { history.show() }
    @objc func openEmoji() { emoji.show() }
    @objc func focusSearch() { history.show(); history.focusSearch() }
    @objc func openSettings() { history.show(section: .settings) }
    @objc func openOnboarding() { onboarding.show() }
    @objc func openHelp() { NSWorkspace.shared.open(URL(string: "https://github.com/moushaban-cell/whatclip")!) }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func pasteRecent(_ s: NSMenuItem) { if let i = s.representedObject as? ClipItem { monitor.restore(i) } }
    @objc func ignoreNext() { monitor.policy.ignoreNextCopy = true }
    @objc func lockHistory() { picker.close(); history.lockNow() }
    @objc func clearHistory() { try? store.clear() }
    @objc func pause5() { monitor.pause(for: 300) }
    @objc func pause60() { monitor.pause(for: 3600) }
    @objc func pauseForever() { monitor.pause(for: nil) }
    @objc func resumeCapture() { monitor.resume() }
    @objc func toggleStack() {
        stackOn.toggle()
        if stackOn { stack = []; stackLastID = (try? store.list(limit: 1).first?.id) ?? 0 }
    }
    @objc func pasteNextStack() {
        guard !stack.isEmpty else { return }
        monitor.restore(stack.removeFirst())
        if AXIsProcessTrusted() { DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { PickerController.sendPasteShortcut() } }
    }
    @objc func clearStack() { stack.removeAll(); stackOn = false }
    @objc func pasteAllStack(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let sep = Separator(rawValue: raw) else { return }
        pasteStack(separator: sep)
    }
    @objc func screenshot() { Screenshot.captureArea() }

    /// File ▸ Export History…: a JSON file of text, tags and favourites, saved privately.
    @objc func exportHistory() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "WhatClip-history.json"; panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Transfer.export(store)
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            let a = NSAlert(); a.messageText = Lang.t("ui.exported"); a.informativeText = Lang.t("ui.exportedInfo"); a.runModal()
        } catch { let a = NSAlert(error: error); a.runModal() }
    }
    /// File ▸ Import History…: adds the text items from a WhatClip export.
    @objc func importHistory() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let n = try Transfer.importData(Data(contentsOf: url), into: store)
            let a = NSAlert(); a.messageText = Lang.t("ui.imported", ["n": "\(n)"]); a.runModal()
        } catch {
            let a = NSAlert(); a.messageText = Lang.t("ui.notExport"); a.runModal()
        }
    }
    @objc func recordGIF() {
        if gif.isRecording { Task { await gif.stop() }; return }
        Task { @MainActor in
            let ok = await gif.start(seconds: Double(monitor.settings.gifSeconds), framesPerSecond: monitor.settings.gifFramesPerSecond) { [weak self] data, size in
                guard let self else { return }
                if let item = try? self.store.add(kind: .gif, label: "GIF \(size)", payload: data, payloadType: "com.compuserve.gif") { self.monitor.restore(item) }
            }
            if !ok { let a = NSAlert(); a.messageText = Lang.t("ui.gifPerm"); a.informativeText = Lang.t("ui.gifPermInfo"); a.runModal() }
        }
    }
    @objc func annotateLatest() {
        let latest = (try? store.list(limit: 200))?.first { $0.kind == .image }
        guard let i = latest, let d = store.payloadData(for: i), let a = AnnotateController(imageData: d, store: store, monitor: monitor) else { return }
        annotators.append(a); a.show()
    }
    var annotators: [AnnotateController] = []
    @objc func insertSnippet(_ s: NSMenuItem) {
        guard let id = s.representedObject as? Int64, let snip = (try? store.snippets())?.first(where: { $0.id == id }) else { return }
        history.show(); history.insertSnippetFromMenu(snip)
    }
    @objc func manageSnippets() { history.newSnippet(); history.show() }
    @objc func openBoard(_ s: NSMenuItem) {
        guard let id = s.representedObject as? Int64 else { return }
        history.show(section: .board(id))
    }
}

// MARK: Services ("Save to WhatClip" in the right-click menu of any app)

extension AppDelegate {
    @objc func saveToWhatClip(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        if let urls = pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            _ = try? store.add(kind: .file, text: urls.map(\.path).joined(separator: "\n"))
        } else if let text = pboard.string(forType: .string), !text.isEmpty {
            _ = try? store.add(text: text)
        } else {
            error.pointee = Lang.t("ui.nothingToSave") as NSString
        }
    }
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
