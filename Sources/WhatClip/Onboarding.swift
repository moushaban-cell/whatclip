import AppKit
import WhatClipCore

/// First-run tour: four short steps, then the optional permissions. Nothing is requested silently.
@MainActor
final class OnboardingWindowController: NSObject {
    private let window: NSWindow
    private let monitor: PasteboardMonitor
    private let pageHost = NSView()
    private let back = NSButton(title: Lang.t("tour.back"), target: nil, action: nil)
    private let next = NSButton(title: Lang.t("tour.next"), target: nil, action: nil)
    private let dots = NSStackView()
    private var step = 0
    private var pages: [NSView] = []

    init(monitor: PasteboardMonitor) {
        self.monitor = monitor
        window = CloseWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 470),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init()
        window.title = Lang.t("tour.window"); window.isReleasedWhenClosed = false; window.center()
        window.minSize = NSSize(width: 520, height: 420)
        // Testing aid: WHATCLIP_TOUR_PAGE=n opens the tour at page n the first time it is shown.
        startPage = Int(ProcessInfo.processInfo.environment["WHATCLIP_TOUR_PAGE"] ?? "") ?? 0
        build()
    }
    private var startPage = 0

    /// Shows the tour from its first page, unless it is already on screen (then it stays where it is).
    func show() {
        if !window.isVisible { show(startPage) }
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }

    /// One tour page: a symbol, a heading and a line of help.
    private func tourPage(symbol: String, title: String, body: String) -> NSView {
        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: title) ?? NSImage())
        icon.contentTintColor = Design.accent
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 46, weight: .regular)
        let head = NSTextField(labelWithString: title); head.font = .systemFont(ofSize: 22, weight: .semibold)
        let text = NSTextField(wrappingLabelWithString: body); text.font = .systemFont(ofSize: 14); text.textColor = .secondaryLabelColor
        text.alignment = .center; text.preferredMaxLayoutWidth = 420
        head.alignment = .center
        let stack = NSStackView(views: [icon, head, text]); stack.orientation = .vertical; stack.alignment = .centerX; stack.spacing = 14
        return stack
    }

    private let languagePop = NSPopUpButton()

    /// First page: the language. English is selected by default; the choice is saved and applied the next time WhatClip starts.
    private func languagePage() -> NSView {
        let icon = NSImageView(image: NSImage(systemSymbolName: "globe", accessibilityDescription: "Language") ?? NSImage())
        icon.contentTintColor = Design.accent; icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 46, weight: .regular)
        let head = NSTextField(labelWithString: Lang.t("tour.language.title")); head.font = .systemFont(ofSize: 22, weight: .semibold)
        let body = NSTextField(wrappingLabelWithString: Lang.t("tour.language.body"))
        body.font = .systemFont(ofSize: 14); body.textColor = .secondaryLabelColor; body.alignment = .center; body.preferredMaxLayoutWidth = 420
        languagePop.removeAllItems(); languagePop.addItems(withTitles: Lang.names.map(\.name))
        let current = monitor.settings.language
        languagePop.selectItem(at: Lang.names.firstIndex { $0.code == current } ?? 0)
        languagePop.target = self; languagePop.action = #selector(languageChosen)
        let stack = NSStackView(views: [icon, head, body, languagePop])
        stack.orientation = .vertical; stack.alignment = .centerX; stack.spacing = 14
        return stack
    }

    /// The tour changes language at once: its pages, buttons and title are built again in the chosen language.
    @objc private func languageChosen() {
        var s = monitor.settings
        s.language = Lang.names[max(0, languagePop.indexOfSelectedItem)].code
        try? monitor.update(s)
        Lang.current = s.language
        let at = step
        build()
        show(at)
    }

    private let shortcutLabel = NSTextField(labelWithString: "")
    private let recorder = ShortcutRecorder()

    /// Choose the picker shortcut during the first launch. Default ⇧⌘X; change it any time in Settings too.
    private func shortcutPage() -> NSView {
        let icon = NSImageView(image: NSImage(systemSymbolName: "command", accessibilityDescription: "Shortcut") ?? NSImage())
        icon.contentTintColor = Design.accent; icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 46, weight: .regular)
        let head = NSTextField(labelWithString: Lang.t("tour.shortcut.title")); head.font = .systemFont(ofSize: 22, weight: .semibold)
        let body = NSTextField(wrappingLabelWithString: Lang.t("tour.shortcut.body"))
        body.font = .systemFont(ofSize: 14); body.textColor = .secondaryLabelColor; body.alignment = .center; body.preferredMaxLayoutWidth = 420
        shortcutLabel.font = .monospacedSystemFont(ofSize: 20, weight: .medium); shortcutLabel.alignment = .center
        refreshShortcutLabel()
        let change = NSButton(title: Lang.t("tour.shortcut.change"), target: self, action: #selector(changeShortcut)); change.bezelStyle = .rounded
        let stack = NSStackView(views: [icon, head, body, shortcutLabel, change])
        stack.orientation = .vertical; stack.alignment = .centerX; stack.spacing = 14
        return stack
    }

    private func refreshShortcutLabel() {
        let s = monitor.settings
        shortcutLabel.stringValue = ShortcutRecorder.describe(code: s.hotKeyCode, mods: s.hotKeyModifiers)
    }

    /// Records the next combination and saves it; the app re-registers the hot key from the settings change.
    @objc private func changeShortcut() {
        shortcutLabel.stringValue = Lang.t("ui.set.pressNew")
        recorder.start(onRecord: { [weak self] code, mods in
            guard let self else { return }
            var s = self.monitor.settings
            s.hotKeyCode = code; s.hotKeyModifiers = mods
            try? self.monitor.update(s)
            self.refreshShortcutLabel()
        }, onCancel: { [weak self] in self?.refreshShortcutLabel() })
    }

    private var packChecks: [String: NSButton] = [:]
    private var packStatus: [String: NSTextField] = [:]

    /// The last page: every permission in one pack. Each has its status and a checkbox; "Set up WhatClip" asks for the ticked ones together.
    private func permissionsPage() -> NSView {
        let icon = NSImageView(image: NSImage(systemSymbolName: "checkmark.shield", accessibilityDescription: "Permissions") ?? NSImage())
        icon.contentTintColor = Design.accent; icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 40, weight: .regular)
        let head = NSTextField(labelWithString: Lang.t("tour.permissions.title")); head.font = .systemFont(ofSize: 22, weight: .semibold)
        let intro = NSTextField(wrappingLabelWithString: Lang.t("tour.permissions.intro"))
        intro.font = .systemFont(ofSize: 13); intro.textColor = .secondaryLabelColor; intro.preferredMaxLayoutWidth = 440
        var rows: [NSView] = [icon, head, intro]
        let items: [(String, String, String)] = [
            ("accessibility", Lang.t("perm.accessibility.title"), Lang.t("perm.accessibility.body")),
            ("screen", Lang.t("perm.screen.title"), Lang.t("perm.screen.body")),
            ("touch", Lang.t("perm.touch.title"), Lang.t("perm.touch.body")),
            ("login", Lang.t("perm.login.title"), Lang.t("perm.login.body")),
        ]
        for (key, title, why) in items {
            let check = NSButton(checkboxWithTitle: title, target: nil, action: nil)
            check.state = key == "accessibility" ? .on : .off
            let status = NSTextField(labelWithString: statusText(for: key))
            status.font = .systemFont(ofSize: 11); status.textColor = .tertiaryLabelColor
            let w = NSTextField(wrappingLabelWithString: why); w.font = .systemFont(ofSize: 12); w.textColor = .secondaryLabelColor; w.preferredMaxLayoutWidth = 420
            let row = NSStackView(views: [check, status, w]); row.orientation = .vertical; row.alignment = .leading; row.spacing = 2
            packChecks[key] = check; packStatus[key] = status
            rows.append(row)
        }
        let setUp = NSButton(title: Lang.t("tour.permissions.setup"), target: self, action: #selector(setUpPack)); setUp.bezelStyle = .rounded
        rows.append(setUp)
        let stack = NSStackView(views: rows); stack.orientation = .vertical; stack.alignment = .centerX; stack.spacing = 12
        return stack
    }

    /// The live state of one permission, in words.
    private func statusText(for key: String) -> String {
        switch key {
        case "accessibility": return AutoPaste.isTrusted ? Lang.t("status.on") : Lang.t("status.off")
        case "screen": return CGPreflightScreenCaptureAccess() ? Lang.t("status.on") : Lang.t("status.off")
        case "touch": return monitor.settings.requireTouchID ? Lang.t("status.on") : Lang.t("status.off")
        case "login": return monitor.settings.launchAtLogin ? Lang.t("status.on") : Lang.t("status.off")
        default: return ""
        }
    }

    /// Asks for everything ticked, in one go. macOS shows its own prompts for Accessibility and Screen Recording.
    @objc private func setUpPack() {
        var s = monitor.settings
        if packChecks["touch"]?.state == .on { s.requireTouchID = true }
        if packChecks["login"]?.state == .on { s.launchAtLogin = true }
        if packChecks["accessibility"]?.state == .on, !AutoPaste.isTrusted { AutoPaste.requestTrust() }
        if packChecks["screen"]?.state == .on, !CGPreflightScreenCaptureAccess() { _ = CGRequestScreenCaptureAccess() }
        s.autoPaste = packChecks["accessibility"]?.state == .on
        s.onboardingDone = true
        try? monitor.update(s)
        for (key, field) in packStatus { field.stringValue = statusText(for: key) }
        window.close()
    }

    private func build() {
        window.title = Lang.t("tour.window")
        back.title = Lang.t("tour.back")
        pages = [
            languagePage(),
            tourPage(symbol: "doc.on.clipboard", title: Lang.t("tour.copy.title"),
                     body: Lang.t("tour.copy.body")),
            shortcutPage(),
            tourPage(symbol: "menubar.rectangle", title: Lang.t("tour.menu.title"),
                     body: Lang.t("tour.menu.body")),
            tourPage(symbol: "folder", title: Lang.t("tour.organise.title"),
                     body: Lang.t("tour.organise.body")),
            permissionsPage(),
        ]
        pageHost.translatesAutoresizingMaskIntoConstraints = false
        back.target = self; back.action = #selector(goBack)
        next.target = self; next.action = #selector(goNext); next.bezelStyle = .rounded
        back.bezelStyle = .rounded
        dots.orientation = .horizontal; dots.spacing = 6
        let rtl: NSUserInterfaceLayoutDirection = Lang.isRightToLeft ? .rightToLeft : .leftToRight
        let footer = NSStackView(views: [back, dots, next]); footer.spacing = 12; footer.alignment = .centerY
        footer.userInterfaceLayoutDirection = rtl; dots.userInterfaceLayoutDirection = rtl; pageHost.userInterfaceLayoutDirection = rtl
        footer.edgeInsets = NSEdgeInsets(top: 0, left: 24, bottom: 18, right: 24)
        let root = NSStackView(views: [pageHost, footer]); root.orientation = .vertical; root.spacing = 0
        root.translatesAutoresizingMaskIntoConstraints = false
        // Arabic: mirror the whole tour (buttons, dots, text) right to left.
        root.userInterfaceLayoutDirection = rtl
        window.contentView = root
        NSLayoutConstraint.activate([pageHost.widthAnchor.constraint(equalTo: root.widthAnchor), footer.widthAnchor.constraint(equalTo: root.widthAnchor)])
        for p in pages { p.translatesAutoresizingMaskIntoConstraints = false }
    }

    private func show(_ index: Int) {
        step = max(0, min(index, pages.count - 1))
        pageHost.subviews.forEach { $0.removeFromSuperview() }
        let page = pages[step]
        pageHost.addSubview(page)
        NSLayoutConstraint.activate([page.centerXAnchor.constraint(equalTo: pageHost.centerXAnchor), page.centerYAnchor.constraint(equalTo: pageHost.centerYAnchor),
                                     page.leadingAnchor.constraint(greaterThanOrEqualTo: pageHost.leadingAnchor, constant: 24),
                                     page.trailingAnchor.constraint(lessThanOrEqualTo: pageHost.trailingAnchor, constant: -24)])
        back.isEnabled = step > 0
        next.title = step == pages.count - 1 ? Lang.t("tour.start") : Lang.t("tour.next")
        dots.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for i in pages.indices {
            let d = NSView(); d.wantsLayer = true; d.layer?.cornerRadius = 4
            d.layer?.backgroundColor = (i == step ? Design.accent : NSColor.tertiaryLabelColor).cgColor
            d.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([d.widthAnchor.constraint(equalToConstant: 8), d.heightAnchor.constraint(equalToConstant: 8)])
            dots.addArrangedSubview(d)
        }
    }

    @objc private func goBack() { show(step - 1) }
    @objc private func goNext() {
        if step == pages.count - 1 { done() } else { show(step + 1) }
    }

    @objc private func openAccessibility() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    @objc private func openScreenRecording() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }
    private func done() {
        var s = monitor.settings; s.onboardingDone = true
        try? monitor.update(s)
        window.close()
    }
}
