import AppKit
import WhatClipCore

/// One visual language for WhatClip: colours, sizes and the shared list row. Used by the picker and the history window.
@MainActor
enum Design {
    /// The brand teal. It is lighter in dark mode, so icons and links stay readable on a dark background.
    static let accent = NSColor(name: "WhatClipAccent") { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return dark ? NSColor(srgbRed: 0x5F / 255, green: 0xB8 / 255, blue: 0xC0 / 255, alpha: 1)
                    : NSColor(srgbRed: 0x14 / 255, green: 0x59 / 255, blue: 0x5F / 255, alpha: 1)
    }
    static let amber = NSColor(srgbRed: 0xF2 / 255, green: 0xB2 / 255, blue: 0x33 / 255, alpha: 1)
    static let rowHeight: CGFloat = 50
    /// Spacing scale (points). Use these, not ad hoc numbers.
    enum Space { static let xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 12, l: CGFloat = 16, xl: CGFloat = 24 }
    /// Corner radii: small for chips, medium for cards, large for panels.
    enum Radius { static let s: CGFloat = 6, m: CGFloat = 10, l: CGFloat = 14 }
    /// Selection tint: the brand teal at low strength, readable in light and dark.
    static var selection: NSColor { accent.withAlphaComponent(0.16) }

    /// A small SF Symbol used as a status mark in rows (pin, favourite, lock), tinted to match the text.
    static func mark(_ name: String, colour: NSColor = .secondaryLabelColor) -> NSImageView {
        let v = NSImageView(image: NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage())
        v.contentTintColor = colour; v.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([v.widthAnchor.constraint(equalToConstant: 11), v.heightAnchor.constraint(equalToConstant: 11)])
        return v
    }

    /// An empty state: one symbol, a short heading and a line of help. Replaces blank panes.
    static func emptyState(symbol: String, title: String, detail: String) -> NSView {
        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = accent; icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 30, weight: .regular)
        let head = NSTextField(labelWithString: title); head.font = .systemFont(ofSize: 15, weight: .semibold); head.alignment = .center
        let body = NSTextField(wrappingLabelWithString: detail); body.font = .systemFont(ofSize: 12); body.textColor = .secondaryLabelColor
        body.alignment = .center; body.preferredMaxLayoutWidth = 260
        let stack = NSStackView(views: [icon, head, body]); stack.orientation = .vertical; stack.alignment = .centerX; stack.spacing = Space.s
        return stack
    }
    static var relative: RelativeDateTimeFormatter {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .short; return f
    }

    /// A coloured square with the kind's symbol, so every item type is recognisable at a glance.
    static func kindBadge(_ kind: ClipKind) -> NSView {
        let box = NSView(); box.wantsLayer = true
        box.layer?.backgroundColor = accent.withAlphaComponent(0.12).cgColor
        box.layer?.cornerRadius = 8
        let icon = NSImageView(image: NSImage(systemSymbolName: kind.symbol, accessibilityDescription: kind.symbol) ?? NSImage())
        icon.contentTintColor = accent; icon.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(icon)
        NSLayoutConstraint.activate([
            box.widthAnchor.constraint(equalToConstant: 30), box.heightAnchor.constraint(equalToConstant: 30),
            icon.centerXAnchor.constraint(equalTo: box.centerXAnchor), icon.centerYAnchor.constraint(equalTo: box.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16), icon.heightAnchor.constraint(equalToConstant: 16),
        ])
        return box
    }

    /// The leading visual: a thumbnail for images, a swatch for colours, otherwise the kind badge.
    static func badge(for item: ClipItem, store: ClipStore?) -> NSView {
        if let thumb = thumbnail(item, store: store) {
            let iv = NSImageView(image: thumb); iv.wantsLayer = true; iv.layer?.cornerRadius = 6; iv.layer?.masksToBounds = true
            iv.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([iv.widthAnchor.constraint(equalToConstant: 30), iv.heightAnchor.constraint(equalToConstant: 30)])
            return iv
        }
        if item.kind == .text, let c = hexColour(item.text) {
            let sw = NSView(); sw.wantsLayer = true; sw.layer?.backgroundColor = c.cgColor; sw.layer?.cornerRadius = 8
            sw.layer?.borderWidth = 1; sw.layer?.borderColor = NSColor.separatorColor.cgColor
            sw.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([sw.widthAnchor.constraint(equalToConstant: 30), sw.heightAnchor.constraint(equalToConstant: 30)])
            return sw
        }
        return kindBadge(item.kind)
    }

    /// Name of the app an item came from, looked up on this Mac. Falls back to the bundle identifier.
    static func appName(_ bundleID: String?) -> String? {
        guard let id = bundleID else { return nil }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id),
           let name = Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleName") as? String { return name }
        return id
    }

    /// The row used in every list: badge, title (pinned and secret marks included), and a grey line with app and time.
    /// A small preview of an image or GIF, read from the private payload file.
    static func thumbnail(_ item: ClipItem, store: ClipStore?) -> NSImage? {
        guard let store, item.kind == .image || item.kind == .gif, let data = store.payloadData(for: item), let img = NSImage(data: data) else { return nil }
        let size = NSSize(width: 30, height: 30)
        let out = NSImage(size: size)
        out.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        let r = img.size.width > 0 && img.size.height > 0 ? min(size.width / img.size.width, size.height / img.size.height) : 1
        let w = img.size.width * r, h = img.size.height * r
        img.draw(in: NSRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h))
        out.unlockFocus()
        return out
    }

    /// A colour for text that is a single CSS hex colour (#rgb or #rrggbb), so the row can show a swatch.
    static func hexColour(_ text: String) -> NSColor? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("#"), t.count == 7 || t.count == 4, let v = UInt32(t.dropFirst(), radix: 16) else { return nil }
        let full: UInt32 = t.count == 4 ? {
            let d = Array(t.dropFirst())
            return UInt32(String([d[0], d[0], d[1], d[1], d[2], d[2]]), radix: 16) ?? 0
        }() : v
        return NSColor(srgbRed: CGFloat((full >> 16) & 0xFF) / 255, green: CGFloat((full >> 8) & 0xFF) / 255, blue: CGFloat(full & 0xFF) / 255, alpha: 1)
    }

    static func row(for item: ClipItem, index: Int? = nil, store: ClipStore? = nil) -> NSView {
        let shown = item.secretKinds.isEmpty ? PickerController.oneLine(item.listTitle) : SecretMask.preview(item.text, maxLength: 40)
        let title = NSTextField(labelWithString: shown)
        title.font = .systemFont(ofSize: 13, weight: .medium); title.lineBreakMode = .byTruncatingTail
        title.setAccessibilityLabel(item.secretKinds.isEmpty ? item.listTitle : "Hidden secret")
        var sub = abs(item.lastUsedAt.timeIntervalSinceNow) < 60 ? "just now" : relative.localizedString(for: item.lastUsedAt, relativeTo: Date())
        if let app = appName(item.sourceBundleID) { sub = app + " · " + sub }
        let subtitle = NSTextField(labelWithString: sub)
        subtitle.font = .systemFont(ofSize: 11); subtitle.textColor = .secondaryLabelColor; subtitle.lineBreakMode = .byTruncatingTail
        // Status marks as symbols, after the title. Never emoji.
        let marks = NSStackView(views: [])
        if item.pinned { marks.addArrangedSubview(mark("pin.fill", colour: amber)) }
        if item.favorite { marks.addArrangedSubview(mark("star.fill", colour: amber)) }
        if !item.secretKinds.isEmpty { marks.addArrangedSubview(mark("lock.fill")) }
        marks.spacing = Space.xs
        let titleRow = NSStackView(views: [title, marks]); titleRow.spacing = Space.xs; titleRow.alignment = .centerY
        let text = NSStackView(views: [titleRow, subtitle]); text.orientation = .vertical; text.alignment = .leading; text.spacing = 2
        var views: [NSView] = [badge(for: item, store: store), text]
        if let index, index < 9 {
            let n = NSTextField(labelWithString: "⌘\(index + 1)"); n.font = .systemFont(ofSize: 10); n.textColor = .tertiaryLabelColor
            views.append(n)
        }
        let row = NSStackView(views: views); row.spacing = 10; row.alignment = .centerY
        row.edgeInsets = NSEdgeInsets(top: Space.xs, left: Space.s, bottom: Space.xs, right: Space.s)
        return row
    }
}

/// A copy that could not be saved. Logs the error only, never the copied content, and does not interrupt the person's copying.
func logCaptureFailure(_ error: Error) {
    NSLog("WhatClip: a copy could not be saved: %@", String(describing: error))
}

/// Shows a plain failure message after an action could not finish. Used where a delete or clear would otherwise fail silently.
@MainActor
func reportFailure(_ error: Error) {
    let alert = NSAlert()
    alert.messageText = Lang.t("ui.errorGeneric")
    alert.informativeText = error.localizedDescription
    alert.runModal()
}
