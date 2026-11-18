import AppKit
import WhatClipCore

/// First-run tour: four short steps, then the optional permissions. Nothing is requested silently.
@MainActor
final class OnboardingWindowController: NSObject {
    private let window: NSWindow
    private let monitor: PasteboardMonitor
    private let pageHost = NSView()
    private let back = NSButton(title: "Back", target: nil, action: nil)
    private let next = NSButton(title: "Next", target: nil, action: nil)
    private let dots = NSStackView()
    private var step = 0
    private var pages: [NSView] = []

    init(monitor: PasteboardMonitor) {
        self.monitor = monitor
        window = CloseWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 470),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init()
        window.title = "Welcome to WhatClip"; window.isReleasedWhenClosed = false; window.center()
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

    private let shortcutLabel = NSTextField(labelWithString: "")
    private let recorder = ShortcutRecorder()

    /// Choose the picker shortcut during the first launch. Default ⇧⌘X; change it any time in Settings too.
    private func shortcutPage() -> NSView {
        let icon = NSImageView(image: NSImage(systemSymbolName: "command", accessibilityDescription: "Shortcut") ?? NSImage())
        icon.contentTintColor = Design.accent; icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 46, weight: .regular)
        let head = NSTextField(labelWithString: "Choose your picker shortcut"); head.font = .systemFont(ofSize: 22, weight: .semibold)
        let body = NSTextField(wrappingLabelWithString: "This opens the picker from any app. Pick a combination no other app uses. You can change it later in Settings.")
        body.font = .systemFont(ofSize: 14); body.textColor = .secondaryLabelColor; body.alignment = .center; body.preferredMaxLayoutWidth = 420
        shortcutLabel.font = .monospacedSystemFont(ofSize: 20, weight: .medium); shortcutLabel.alignment = .center
        refreshShortcutLabel()
        let change = NSButton(title: "Change shortcut…", target: self, action: #selector(changeShortcut)); change.bezelStyle = .rounded
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
        shortcutLabel.stringValue = "Press the new shortcut…"
        recorder.start(onRecord: { [weak self] code, mods in
            guard let self else { return }
            var s = self.monitor.settings
            s.hotKeyCode = code; s.hotKeyModifiers = mods
            try? self.monitor.update(s)
            self.refreshShortcutLabel()
        }, onCancel: { [weak self] in self?.refreshShortcutLabel() })
    }

    /// The last page: the two optional permissions, each with a button that opens the right System Settings pane.
    private func permissionsPage() -> NSView {
        func row(_ head: String, _ why: String, _ action: Selector) -> NSStackView {
            let h = NSTextField(labelWithString: head); h.font = .systemFont(ofSize: 13, weight: .semibold)
            let w = NSTextField(wrappingLabelWithString: why); w.font = .systemFont(ofSize: 12); w.textColor = .secondaryLabelColor; w.preferredMaxLayoutWidth = 440
            let b = NSButton(title: "Open System Settings", target: self, action: action); b.bezelStyle = .rounded
            let r = NSStackView(views: [h, w, b]); r.orientation = .vertical; r.alignment = .leading; r.spacing = 4
            return r
        }
        let icon = NSImageView(image: NSImage(systemSymbolName: "lock.shield", accessibilityDescription: "Permissions") ?? NSImage())
        icon.contentTintColor = Design.accent; icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 40, weight: .regular)
        let head = NSTextField(labelWithString: "Two optional permissions"); head.font = .systemFont(ofSize: 22, weight: .semibold)
        let intro = NSTextField(wrappingLabelWithString: "WhatClip works without either. Turn them on only for the features you want.")
        intro.font = .systemFont(ofSize: 13); intro.textColor = .secondaryLabelColor; intro.preferredMaxLayoutWidth = 440
        let stack = NSStackView(views: [icon, head, intro,
            row("Accessibility", "Lets WhatClip press ⌘V for you after you choose an item. Without it, press ⌘V yourself.", #selector(openAccessibility)),
            row("Screen Recording", "Needed only for screenshots and GIF recording.", #selector(openScreenRecording))])
        stack.orientation = .vertical; stack.alignment = .centerX; stack.spacing = 14
        return stack
    }

    private func build() {
        pages = [
            tourPage(symbol: "doc.on.clipboard", title: "Everything you copy is kept",
                     body: "Text, links, images, GIFs and files. Copies from password managers are never recorded, and nothing leaves this Mac."),
            shortcutPage(),
            tourPage(symbol: "menubar.rectangle", title: "Everything is in the menu bar",
                     body: "Stack copies, take screenshots, pause capturing, open snippets and boards, or change settings from the menu. Settings are always under WhatClip ▸ Settings… (⌘,)."),
            tourPage(symbol: "folder", title: "Pin, favourite and organise",
                     body: "Pin what you always need, favourite items for the Library, add tags, and group items into boards. Export a copy any time from File ▸ Export History."),
            permissionsPage(),
        ]
        pageHost.translatesAutoresizingMaskIntoConstraints = false
        back.target = self; back.action = #selector(goBack)
        next.target = self; next.action = #selector(goNext); next.bezelStyle = .rounded
        back.bezelStyle = .rounded
        dots.orientation = .horizontal; dots.spacing = 6
        let footer = NSStackView(views: [back, dots, next]); footer.spacing = 12; footer.alignment = .centerY
        footer.edgeInsets = NSEdgeInsets(top: 0, left: 24, bottom: 18, right: 24)
        let root = NSStackView(views: [pageHost, footer]); root.orientation = .vertical; root.spacing = 0
        root.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = root
        NSLayoutConstraint.activate([pageHost.widthAnchor.constraint(equalTo: root.widthAnchor), footer.widthAnchor.constraint(equalTo: root.widthAnchor)])
        for p in pages { p.translatesAutoresizingMaskIntoConstraints = false }
    }

    private func show(_ index: Int) {
        step = max(0, min(index, pages.count - 1)); FileHandle.standardError.write(Data("DEBUG step=\(step) requested=\(index)\n".utf8))
        pageHost.subviews.forEach { $0.removeFromSuperview() }
        let page = pages[step]
        pageHost.addSubview(page)
        NSLayoutConstraint.activate([page.centerXAnchor.constraint(equalTo: pageHost.centerXAnchor), page.centerYAnchor.constraint(equalTo: pageHost.centerYAnchor),
                                     page.leadingAnchor.constraint(greaterThanOrEqualTo: pageHost.leadingAnchor, constant: 24),
                                     page.trailingAnchor.constraint(lessThanOrEqualTo: pageHost.trailingAnchor, constant: -24)])
        back.isEnabled = step > 0
        next.title = step == pages.count - 1 ? "Start using WhatClip" : "Next"
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
        FileHandle.standardError.write(Data("DEBUG goNext \(Thread.callStackSymbols.prefix(8).joined(separator: " | "))\n".utf8))
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
