import AppKit
import WhatClipCore

extension HistoryWindowController {
    /// The About page, in sections: the app, who built it, privacy, and the licence and links.
    func aboutPage() -> NSView {
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.2.0"
        func heading(_ s: String) -> NSTextField {
            let f = NSTextField(labelWithString: s); f.font = .systemFont(ofSize: 13, weight: .semibold); f.textColor = .secondaryLabelColor
            f.setContentHuggingPriority(.defaultLow, for: .horizontal); return f
        }
        func body(_ s: String, weight: NSFont.Weight = .regular) -> NSTextField {
            let f = NSTextField(wrappingLabelWithString: s); f.font = .systemFont(ofSize: 13, weight: weight); f.preferredMaxLayoutWidth = 520
            f.setContentHuggingPriority(.defaultLow, for: .horizontal); return f
        }
        func link(_ title: String, _ action: Selector) -> NSButton {
            let b = NSButton(title: title, target: AboutActions.shared, action: action); b.bezelStyle = .inline; return b
        }
        func section(_ views: [NSView]) -> NSStackView {
            let s = NSStackView(views: views); s.orientation = .vertical; s.alignment = .leading; s.spacing = 8
            s.userInterfaceLayoutDirection = Lang.isRightToLeft ? .rightToLeft : .leftToRight
            return s
        }
        func divider() -> NSBox { let b = NSBox(); b.boxType = .separator; return b }

        let icon = NSImageView(image: NSApp.applicationIconImage ?? NSImage())
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: 72).isActive = true; icon.heightAnchor.constraint(equalToConstant: 72).isActive = true
        let title = NSTextField(labelWithString: "WhatClip"); title.font = .systemFont(ofSize: 26, weight: .bold)
        let head = NSStackView(views: [icon, section([title, NSTextField(labelWithString: Lang.t("ui.aboutVersion", ["v": version])), body(Lang.t("ui.about.desc"))])])
        head.orientation = .horizontal; head.alignment = .top; head.spacing = 16

        let builder = section([heading(Lang.t("ui.about.builtBy")),
                               body("Moustafa Mohamed Shabaan", weight: .semibold),
                               body(Lang.t("ui.about.role")),
                               heading(Lang.t("ui.about.contact")),
                               link(AboutActions.email, #selector(AboutActions.sendEmail)),
                               link("github.com/moushaban-cell", #selector(AboutActions.openGitHub))])
        let privacy = section([heading(Lang.t("ui.about.privacyTitle")), body(Lang.t("ui.about.open"))])
        let links = section([heading(Lang.t("ui.about.linksTitle")), body(Lang.t("ui.about.licence")),
                             ])

        let sections: [NSView] = [head, divider(), builder, divider(), privacy, divider(), links]
        // The sections stacked from the top, aligned to the leading edge of the language (left, or right in Arabic).
        // Sections go to the top of the page; the page is at least as tall as the pane, so nothing is centred.
        let page = NSStackView()
        for v in [head, divider(), builder, divider(), privacy, divider(), links] { page.addView(v, in: .top) }
        page.orientation = .vertical; page.alignment = .leading; page.spacing = 18
        page.edgeInsets = NSEdgeInsets(top: 28, left: 28, bottom: 28, right: 28)
        page.userInterfaceLayoutDirection = Lang.isRightToLeft ? .rightToLeft : .leftToRight
        page.translatesAutoresizingMaskIntoConstraints = false
        if Lang.isRightToLeft { mirrorForRTL(page) }
        return page
    }
}

/// The links on the About page. The repository is public. Links go to the project page and the author's public profile.
@MainActor
final class AboutActions: NSObject {
    static let shared = AboutActions()
    static let email = "mou.shabaan@gmail.com"

    @objc func sendEmail() { NSWorkspace.shared.open(URL(string: "mailto:\(Self.email)")!) }
    @objc func openGitHub() { NSWorkspace.shared.open(URL(string: "https://github.com/moushaban-cell")!) }
}
