import AppKit
import WhatClipCore

/// A small rounded label: a status such as "On", or a count.
@MainActor
final class StatusPill: NSView {
    init(_ text: String, active: Bool) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 9
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = active ? Design.accent : .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        layer?.backgroundColor = (active ? Design.accent.withAlphaComponent(0.14) : NSColor.quaternaryLabelColor).cgColor
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
        ])
        setAccessibilityElement(true)
        setAccessibilityLabel(text)
    }
    required init?(coder: NSCoder) { nil }
}

/// One feature on the Capture and tools page: a real button with its icon, name, a line of help, and an optional state.
/// Click, Space and Return all run the action through the responder chain, exactly as the menu item does.
@MainActor
func toolButton(symbol: String, title: String, detail: String, state: String?, active: Bool, action: Selector) -> NSButton {
    let b = NSButton(title: "", target: nil, action: action)
    b.bezelStyle = .regularSquare
    b.imagePosition = .imageLeading
    b.alignment = .left
    b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
        .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 18, weight: .medium))
    b.contentTintColor = Design.accent
    let line = NSMutableAttributedString(string: title, attributes: [
        .font: NSFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: NSColor.labelColor])
    if let state {
        line.append(NSAttributedString(string: "   " + state, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: active ? Design.accent : NSColor.secondaryLabelColor]))
    }
    line.append(NSAttributedString(string: "\n" + detail, attributes: [
        .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor]))
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .natural; paragraph.lineSpacing = 3; paragraph.paragraphSpacing = 2
    line.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: line.length))
    b.attributedTitle = line
    b.setAccessibilityLabel(title)
    b.setAccessibilityHelp(detail)
    b.heightAnchor.constraint(greaterThanOrEqualToConstant: 64).isActive = true
    return b
}

extension HistoryWindowController {
    /// Capture and tools: every feature that otherwise lives only in the menu bar, as tiles in the window.
    /// Each tile sends its action down the responder chain, the same action the menu item uses.
    func toolsPage() -> NSView {
        let app = NSApp.delegate as? AppDelegate
        let recording = !(app?.monitor.isPaused ?? false)
        let stacking = app?.stackOn ?? false
        let waiting = app?.stack.count ?? 0
        let needsLock = app?.monitor.settings.requireTouchID ?? false

        func tile(_ symbol: String, _ title: String, _ detail: String, _ action: Selector,
                  state: String? = nil, active: Bool = false) -> NSButton {
            toolButton(symbol: symbol, title: title, detail: detail, state: state, active: active, action: action)
        }
        // One column of tiles at a fixed width, aligned to the leading edge of the language (left, or right in Arabic).
        let column: CGFloat = 560
        func section(_ title: String, _ tiles: [NSButton]) -> NSStackView {
            for tile in tiles {
                tile.translatesAutoresizingMaskIntoConstraints = false
                tile.widthAnchor.constraint(equalToConstant: column).isActive = true
            }
            let list = NSStackView(views: tiles)
            list.orientation = .vertical; list.alignment = .leading; list.spacing = 10
            let heading = NSTextField(labelWithString: title)
            heading.font = .systemFont(ofSize: 13, weight: .semibold); heading.textColor = .secondaryLabelColor
            let block = NSStackView(views: [heading, list])
            block.orientation = .vertical; block.alignment = .leading; block.spacing = 10
            return block
        }

        // Header: the title, a line of help, and the state of the main switches.
        let title = NSTextField(labelWithString: Lang.t("ui.tools.page"))
        title.font = .systemFont(ofSize: 24, weight: .bold)
        let hint = NSTextField(wrappingLabelWithString: Lang.t("ui.tools.hint"))
        hint.font = .systemFont(ofSize: 13); hint.textColor = .secondaryLabelColor; hint.preferredMaxLayoutWidth = 560
        let status = NSStackView(views: [
            StatusPill("\(Lang.t("ui.tools.recording")): \(recording ? Lang.t("ui.tools.on") : Lang.t("ui.tools.off"))", active: recording),
            StatusPill("\(Lang.t("ui.menu.stack")): \(stacking ? Lang.t("ui.tools.waiting", ["n": "\(waiting)"]) : Lang.t("ui.tools.off"))", active: stacking),
        ])
        status.orientation = .horizontal; status.spacing = 8
        let header = NSStackView(views: [title, hint, status])
        header.orientation = .vertical; header.alignment = .leading; header.spacing = 8

        let capture = section(Lang.t("ui.tools.sec.capture"), [
            tile("camera.viewfinder", Lang.t("ui.m.screenshot"), Lang.t("ui.tools.d.shot"), #selector(AppDelegate.screenshot)),
            tile("record.circle", Lang.t("ui.m.gif"), Lang.t("ui.tools.d.gif"), #selector(AppDelegate.recordGIF)),
            tile("pencil.tip.crop.circle", Lang.t("ui.m.annotate"), Lang.t("ui.tools.d.annotate"), #selector(AppDelegate.annotateLatest)),
            tile("face.smiling", Lang.t("ui.m.emoji"), Lang.t("ui.tools.d.emoji"), #selector(AppDelegate.openEmoji)),
        ])
        let clipboard = section(Lang.t("ui.tools.sec.clipboard"), [
            recording
                ? tile("pause.circle", Lang.t("ui.m.pauseCapturing"), Lang.t("ui.tools.d.pause"), #selector(AppDelegate.pauseForever),
                       state: Lang.t("ui.tools.on"), active: true)
                : tile("play.circle", Lang.t("ui.m.resume"), Lang.t("ui.tools.d.pause"), #selector(AppDelegate.resumeCapture),
                       state: Lang.t("ui.tools.off"), active: false),
            tile("nosign", Lang.t("ui.m.ignoreNext"), Lang.t("ui.tools.d.ignore"), #selector(AppDelegate.ignoreNext)),
            tile("square.stack.3d.up", stacking ? Lang.t("ui.m.stopStack") : Lang.t("ui.m.startStack"), Lang.t("ui.tools.d.stack"), #selector(AppDelegate.toggleStack),
                 state: stacking ? Lang.t("ui.tools.on") : Lang.t("ui.tools.off"), active: stacking),
            tile("tray", Lang.t("ui.m.clearStack"), Lang.t("ui.tools.d.clearStack"), #selector(AppDelegate.clearStack)),
            tile("trash", Lang.t("ui.m.clearHistory"), Lang.t("ui.tools.d.clear"), #selector(AppDelegate.clearHistory)),
        ])
        let data = section(Lang.t("ui.tools.sec.data"), [
            tile("square.and.arrow.up", Lang.t("ui.tools.export"), Lang.t("ui.tools.d.export"), #selector(AppDelegate.exportHistory)),
            tile("square.and.arrow.down", Lang.t("ui.tools.import"), Lang.t("ui.tools.d.import"), #selector(AppDelegate.importHistory)),
        ])
        var setupTiles = [
            tile("checkmark.shield", Lang.t("ui.m.setup"), Lang.t("ui.tools.d.setup"), #selector(AppDelegate.openOnboarding)),
            tile("questionmark.circle", Lang.t("ui.m.help"), Lang.t("ui.tools.d.help"), #selector(AppDelegate.openHelp)),
        ]
        if needsLock { setupTiles.append(tile("lock", Lang.t("ui.lockNow"), Lang.t("ui.tools.d.lock"), #selector(AppDelegate.lockHistory))) }
        let setup = section(Lang.t("ui.tools.sec.setup"), setupTiles)

        let page = NSStackView(views: [header, capture, clipboard, data, setup])
        page.orientation = .vertical; page.alignment = .leading; page.spacing = 26
        page.edgeInsets = NSEdgeInsets(top: 28, left: 28, bottom: 28, right: 28)
        page.userInterfaceLayoutDirection = Lang.isRightToLeft ? .rightToLeft : .leftToRight
        page.translatesAutoresizingMaskIntoConstraints = false
        if Lang.isRightToLeft { mirrorForRTL(page) }
        return page
    }
}
