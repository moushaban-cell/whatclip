import AppKit
import WhatClipCore

/// Emoji and symbols (Windows Win+. style). Pick a category or search by Unicode name; a click copies the symbol.
/// Everything is built in: no network, no account.
@MainActor
final class EmojiPanelController: NSObject, NSSearchFieldDelegate {
    private let window: NSWindow
    private let search = NSSearchField()
    private let categories = NSSegmentedControl(labels: [Lang.t("ui.cat.smileys"), Lang.t("ui.cat.people"), Lang.t("ui.cat.nature"), Lang.t("ui.cat.food"), Lang.t("ui.cat.travel"), Lang.t("ui.cat.objects"), Lang.t("ui.cat.symbols")], trackingMode: .selectOne, target: nil, action: nil)
    private let grid = NSStackView()
    private let scroll = NSScrollView()
    private let copy: (String) -> Void

    /// The symbols, by category. Names come from Unicode, so search works in English.
    static let sets: [[String]] = [
        ["😀","😃","😄","😁","😆","😅","🤣","😂","🙂","🙃","😉","😊","😇","🥰","😍","🤩","😘","😗","😚","😙","😋","😛","😜","🤪","😝","🤑","🤗","🤭","🤫","🤔","🤐","🤨","😐","😑","😶","😏","😒","🙄","😬","🤥","😌","😔","😪","🤤","😴","😷","🤒","🤕","🤢","🤮","🤧","🥵","🥶","😵","🤯","🤠","🥳","😎","🤓","🧐","😕","😟","🙁","☹️","😮","😯","😲","😳","🥺","😦","😧","😨","😰","😥","😢","😭","😱","😖","😣","😞","😓","😩","😫","😤","😡","😠","🤬","😈","👿","💀","💩","🤡","👻","👽","🤖"],
        ["👋","🤚","🖐️","✋","🖖","👌","🤌","🤏","✌️","🤞","🤟","🤘","🤙","👈","👉","👆","👇","☝️","👍","👎","✊","👊","🤛","🤜","👏","🙌","👐","🤲","🤝","🙏","💪","🧠","👀","👁️","👅","👄","👶","🧒","👦","👧","🧑","👨","👩","🧓","👴","👵"],
        ["🌸","💮","🏵️","🌹","🥀","🌺","🌻","🌼","🌷","🌱","🌲","🌳","🌴","🌵","🌾","🌿","☘️","🍀","🍁","🍂","🍃","🌍","🌎","🌏","🌕","🌙","⭐","🌟","✨","⚡","☄️","🔥","🌈","☀️","⛅","☁️","❄️","💧","🌊"],
        ["🍏","🍎","🍐","🍊","🍋","🍌","🍉","🍇","🍓","🫐","🍈","🍒","🍑","🥭","🍍","🥥","🥝","🍅","🥑","🥦","🥕","🌽","🌶️","🥐","🍞","🥖","🧀","🍳","🥞","🍔","🍟","🍕","🌭","🥪","🌮","🌯","🍣","🍜","🍝","🍦","🍩","🍪","🎂","🍰","🍫","🍬","🍭","☕","🍵","🍺","🍷","🥂"],
        ["🚗","🚕","🚙","🚌","🚎","🏎️","🚓","🚑","🚒","🚲","🛴","✈️","🚀","🛸","🚁","⛵","🚤","🏠","🏡","🏢","🏥","🏦","🏨","🏪","🏫","🗼","🗽","⛪","🕌","🌋","🏔️","🗻","🏝️","🏜️","🌃","🌉","🎡","🎢"],
        ["⌚","📱","💻","⌨️","🖥️","🖨️","🖱️","💾","💿","📷","📸","📹","🎥","📞","☎️","📺","📻","🔋","🔌","💡","🔦","🕯️","📚","📖","✏️","🖊️","📝","📁","📂","📅","📆","📌","📍","📎","✂️","🔒","🔓","🔑","🗝️","🔨","🔧","⚙️","🧲","💰","💳","💎","📦","📮","🎁","🎈","🎉"],
        ["✅","❌","❎","✔️","➕","➖","➗","✖️","♾️","‼️","⁉️","❓","❔","❕","❗","〰️","©️","®️","™️","🔴","🟠","🟡","🟢","🔵","🟣","⚫","⚪","🔺","🔻","🔸","🔹","▪️","▫️","⬆️","⬇️","➡️","⬅️","↩️","↪️","🔁","🔂","🔄","⏩","⏪","🔊","🔇","🔔","🔕","💬","💭","🗯️","♻️","⚠️","🚫","💯","🆗","🆕","🆒"],
    ]

    init(copy: @escaping (String) -> Void) {
        self.copy = copy
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init()
        window.title = Lang.t("ui.emojiTitle"); window.isReleasedWhenClosed = false; window.center()
        window.minSize = NSSize(width: 380, height: 300)
        search.placeholderString = Lang.t("ui.emojiSearch"); search.delegate = self
        categories.selectedSegment = 0; categories.target = self; categories.action = #selector(categoryChanged)
        grid.orientation = .vertical; grid.alignment = .leading; grid.spacing = 6
        // The grid sits at the top of the scroll view and fills its width; the page grows with the symbols.
        let doc = NSView(); doc.translatesAutoresizingMaskIntoConstraints = false
        grid.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: doc.topAnchor, constant: 12), grid.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: 12),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: doc.trailingAnchor, constant: -12), grid.bottomAnchor.constraint(lessThanOrEqualTo: doc.bottomAnchor, constant: -12),
        ])
        scroll.documentView = doc; scroll.hasVerticalScroller = true; scroll.borderType = .noBorder; scroll.drawsBackground = false
        doc.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
        doc.heightAnchor.constraint(greaterThanOrEqualTo: scroll.contentView.heightAnchor).isActive = true
        let top = NSStackView(views: [search, categories]); top.orientation = .vertical; top.alignment = .leading; top.spacing = 8
        top.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 0, right: 12)
        let root = NSStackView(views: [top, scroll]); root.orientation = .vertical; root.alignment = .leading; root.spacing = 8
        root.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = root
        root.userInterfaceLayoutDirection = Lang.isRightToLeft ? .rightToLeft : .leftToRight
        if Lang.isRightToLeft { mirrorForRTL(root) }
        NSLayoutConstraint.activate([search.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -24),
                                     scroll.widthAnchor.constraint(equalTo: root.widthAnchor)])
        show(category: 0)
    }

    func show() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); search.becomeFirstResponder() }

    @objc private func categoryChanged() { search.stringValue = ""; show(category: categories.selectedSegment) }

    func controlTextDidChange(_ obj: Notification) {
        let q = search.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { show(category: categories.selectedSegment); return }
        // Search every set; match on the Unicode name of the first scalar (for example "grinning face").
        let all = Self.sets.flatMap { $0 }
        let hits = all.filter { symbol in
            guard let scalar = symbol.unicodeScalars.first else { return false }
            return (scalar.properties.name ?? "").lowercased().contains(q)
        }
        fill(hits.isEmpty ? all.filter { _ in false } : hits)
    }

    private func show(category: Int) { fill(Self.sets[max(0, min(category, Self.sets.count - 1))]) }

    /// Lays the symbols out in rows of 12, each a button; a click copies the symbol and closes the panel.
    private func fill(_ symbols: [String]) {
        grid.arrangedSubviews.forEach { $0.removeFromSuperview() }
        var row: NSStackView?
        for (i, sym) in symbols.enumerated() {
            if i % 12 == 0 { let r = NSStackView(); r.orientation = .horizontal; r.spacing = 6; grid.addArrangedSubview(r); row = r }
            let b = NSButton(title: sym, target: self, action: #selector(pick(_:)))
            b.font = .systemFont(ofSize: 24); b.bezelStyle = .texturedRounded
            b.setAccessibilityLabel(Self.name(of: sym))
            b.toolTip = Self.name(of: sym)
            row?.addArrangedSubview(b)
        }
        if symbols.isEmpty { grid.addArrangedSubview(NSTextField(labelWithString: Lang.t("ui.noMatches"))) }
    }

    @objc private func pick(_ sender: NSButton) {
        copy(sender.title)
        window.orderOut(nil)
    }

    static func name(of symbol: String) -> String {
        symbol.unicodeScalars.first.flatMap { $0.properties.name } ?? "symbol"
    }
}
