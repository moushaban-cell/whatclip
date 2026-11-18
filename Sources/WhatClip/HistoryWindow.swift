import AppKit
import WhatClipCore

/// The full history window: sidebar (filters, boards, snippets), the list, a preview and actions on the selected item.
/// A view whose origin is its top-left corner, so scroll content starts at the top.
@MainActor
final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
final class HistoryWindowController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSMenuDelegate {
    enum Section: Equatable { case header, all, library, pinned, text, links, images, files, textInImages, board(Int64), addBoard, snippets, settings, about, tools }

    private let window: NSWindow
    let store: ClipStore
    private let monitor: PasteboardMonitor
    private let sidebar = NSTableView()
    private let list = NSTableView()
    private let search = NSSearchField()
    private let listScroll = NSScrollView()
    /// Settings (from the Settings module) and the About text: shown in the detail pane when their sidebar item is chosen.
    var settingsRoot: NSView?
    private let settingsHost = NSView()
    private let aboutScroll = NSScrollView()
    private var listPaneRef: NSView?
    private let viewMode = NSSegmentedControl(labels: [Lang.t("ui.list"), Lang.t("ui.cards")], trackingMode: .selectOne, target: nil, action: nil)
    private let shelf = ShelfController()
    private let preview = NSTextView()
    private let previewScroll = NSScrollView()
    private let previewImage = NSImageView()
    private let actions = NSStackView()
    private let snippetTitle = NSTextField()
    private let snippetFolder = NSTextField()
    private let snippetTags = NSTextField()
    private let snippetBody = NSTextView()
    private let snippetBox = NSStackView()
    private var sections: [(String, Section)] = []
    private var section: Section = .all
    private var items: [ClipItem] = []
    private var snippets: [Snippet] = []
    private var selectedSnippet: Snippet?

    init(store: ClipStore, monitor: PasteboardMonitor) {
        self.store = store; self.monitor = monitor
        window = CloseWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 620), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        super.init()
        window.title = "WhatClip"; window.isReleasedWhenClosed = false; window.minSize = NSSize(width: 800, height: 480)
        window.collectionBehavior.insert(.fullScreenPrimary)
        if !window.setFrameUsingName("WhatClipHistory") { window.center() }
        window.setFrameAutosaveName("WhatClipHistory")
        build()
        reloadSidebar()
    }

    /// True while the history is hidden behind Touch ID or the Mac password (when the setting is on).
    private var locked = false

    func show() {
        locked = monitor.settings.requireTouchID
        reloadSidebar(); reloadList()
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        if locked {
            list.reloadData()
            Task { @MainActor in
                let ok = await Authentication.unlock(reason: Lang.t("ui.reasonOpen"))
                self.locked = !ok
                self.reloadList()
            }
        }
    }

    /// Opens the window on a given sidebar section (boards and snippets from the menu bar).
    func show(section target: Section) {
        section = target; selectedSnippet = nil
        show()
    }

    private func build() {
        sidebar.headerView = nil; sidebar.dataSource = self; sidebar.delegate = self; sidebar.rowHeight = 26
        sidebar.addTableColumn(NSTableColumn(identifier: .init("side")))
        sidebar.setAccessibilityLabel(Lang.t("ui.a11y.sections"))
        let sideScroll = NSScrollView(); sideScroll.documentView = sidebar; sideScroll.hasVerticalScroller = true; sideScroll.borderType = .noBorder

        search.placeholderString = Lang.t("ui.search"); search.delegate = self
        list.headerView = nil; list.dataSource = self; list.delegate = self; list.rowHeight = Design.rowHeight
        list.allowsMultipleSelection = true; list.setAccessibilityLabel(Lang.t("ui.a11y.items"))
        // Keyboard: Return or a double-click copies the selected item; arrows move through the list (built into the table).
        list.target = self; list.doubleAction = #selector(copyItem)
        let rowMenu = NSMenu(); rowMenu.delegate = self; list.menu = rowMenu
        list.addTableColumn(NSTableColumn(identifier: .init("item")))
        list.setAccessibilityLabel(Lang.t("ui.a11y.items"))
        listScroll.documentView = list; listScroll.hasVerticalScroller = true; listScroll.borderType = .noBorder

        preview.isEditable = false; preview.font = .systemFont(ofSize: 14); preview.textContainerInset = NSSize(width: 14, height: 14)
        preview.isVerticallyResizable = true; preview.isHorizontallyResizable = false; preview.autoresizingMask = [.width]
        preview.textContainer?.widthTracksTextView = true; preview.textColor = .labelColor; preview.backgroundColor = .textBackgroundColor
        previewScroll.documentView = preview; previewScroll.hasVerticalScroller = true; previewScroll.borderType = .noBorder
        previewScroll.drawsBackground = true; previewScroll.backgroundColor = .textBackgroundColor
        previewImage.imageScaling = .scaleProportionallyUpOrDown; previewImage.isHidden = true
        actions.orientation = .horizontal; actions.spacing = 8

        // Snippet editor (shown in place of the preview in the Snippets section)
        snippetTitle.placeholderString = Lang.t("ui.title"); snippetFolder.placeholderString = Lang.t("ui.folderOpt"); snippetTags.placeholderString = Lang.t("ui.tagsPh")
        snippetBody.font = .monospacedSystemFont(ofSize: 12, weight: .regular); snippetBody.isRichText = false; snippetBody.isAutomaticQuoteSubstitutionEnabled = false
        let bodyScroll = NSScrollView(); bodyScroll.documentView = snippetBody; bodyScroll.hasVerticalScroller = true; bodyScroll.borderType = .bezelBorder
        bodyScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        let hint = NSTextField(wrappingLabelWithString: Lang.t("ui.snippetHint"))
        hint.font = .systemFont(ofSize: 11); hint.textColor = .secondaryLabelColor
        let buttons = NSStackView(views: [
            button("Save snippet", #selector(saveSnippet)), button("Insert…", #selector(insertSnippet)), button(Lang.t("ui.delete"), #selector(deleteSnippet)),
        ])
        buttons.spacing = 8
        snippetBox.orientation = .vertical; snippetBox.alignment = .leading; snippetBox.spacing = 8
        snippetBox.setViews([snippetTitle, snippetFolder, snippetTags, bodyScroll, hint, buttons], in: .leading)
        snippetBox.isHidden = true

        settingsHost.translatesAutoresizingMaskIntoConstraints = false; settingsHost.isHidden = true
        settingsHost.setContentHuggingPriority(.defaultLow, for: .vertical)
        settingsHost.heightAnchor.constraint(greaterThanOrEqualToConstant: 460).isActive = true
        aboutScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 460).isActive = true
        aboutScroll.hasVerticalScroller = true; aboutScroll.borderType = .noBorder; aboutScroll.isHidden = true
        // The detail pane is a plain container: the item preview stack and the full-pane Settings/About views are pinned to its edges,
        // so Settings fills the pane instead of being centred in it.
        let detailStack = NSStackView(views: [previewScroll, previewImage, snippetBox, actions])
        detailStack.orientation = .vertical; detailStack.alignment = .width; detailStack.spacing = 10
        detailStack.translatesAutoresizingMaskIntoConstraints = false
        let detail = NSView()
        detail.addSubview(detailStack)
        detail.addSubview(settingsHost)
        detail.addSubview(aboutScroll)
        for v in [detailStack, settingsHost, aboutScroll] { v.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            detailStack.topAnchor.constraint(equalTo: detail.topAnchor, constant: 12),
            detailStack.leadingAnchor.constraint(equalTo: detail.leadingAnchor, constant: 12),
            detailStack.trailingAnchor.constraint(equalTo: detail.trailingAnchor, constant: -12),
            detailStack.bottomAnchor.constraint(equalTo: detail.bottomAnchor, constant: -12),
        ])
        for v in [settingsHost, aboutScroll] {
            NSLayoutConstraint.activate([
                v.topAnchor.constraint(equalTo: detail.topAnchor), v.bottomAnchor.constraint(equalTo: detail.bottomAnchor),
                v.leadingAnchor.constraint(equalTo: detail.leadingAnchor), v.trailingAnchor.constraint(equalTo: detail.trailingAnchor),
            ])
        }
        previewImage.heightAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true
        detail.widthAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true

        // Three resizable panes: sections, items, details. A split view keeps each pane at its own size.
        sideScroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
        viewMode.selectedSegment = 0; viewMode.target = self; viewMode.action = #selector(viewModeChanged)
        viewMode.setAccessibilityLabel(Lang.t("ui.a11y.viewMode"))
        shelf.scroll.isHidden = true
        shelf.menuForItem = { [weak self] i in self?.contextMenu(forItem: i) }
        shelf.onSelect = { [weak self] index in
            guard let self else { return }
            self.list.selectRowIndexes([index], byExtendingSelection: false)
        }
        // The toolbar (search and List/Cards) stays at the top; the items take the rest of the pane.
        let listArea = NSStackView(views: [listScroll, shelf.scroll]); listArea.orientation = .vertical; listArea.distribution = .fillEqually
        // The list pane places this area by frame; without this its scroll view never gets a size and the rows never draw.
        listArea.translatesAutoresizingMaskIntoConstraints = true
        listArea.setHuggingPriority(.defaultLow, for: .vertical)
        let listPane = ListPaneView(search: search, mode: viewMode, body: listArea)
        listPaneRef = listPane
        listPane.widthAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true
        // Three panes placed by hand: sections (fixed width), items (fixed width), details (takes the rest).
        // A plain layout keeps each pane exactly where it belongs, including when Settings replaces the list.
        let panes = PaneLayout(panes: [sideScroll, listPane, detail], widths: [220, 300, nil])
        window.contentView = panes
        panes.userInterfaceLayoutDirection = Lang.isRightToLeft ? .rightToLeft : .leftToRight

    }

    /// Opens the window with the cards view selected.
    func showCards() { viewMode.selectedSegment = 1; viewModeChanged(); show() }

    @objc private func viewModeChanged() {
        let cards = viewMode.selectedSegment == 1
        listScroll.isHidden = cards; shelf.scroll.isHidden = !cards
        if cards { shelf.reload(items, store: store); syncShelfSelection() }
    }
    private func syncShelfSelection() {
        shelf.select(Set(list.selectedRowIndexes))
    }

    /// The window refreshes itself when a copy arrives while it is open.
    var isVisible: Bool { window.isVisible }
    func refreshIfVisible() { if window.isVisible { reloadSidebar(); reloadList() } }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action); b.bezelStyle = .rounded; return b
    }

    // MARK: sidebar

    /// The sidebar in groups: History (what was copied), Library (saved things), Boards, Tools, App.
    /// Headers are shown but cannot be selected. "New board" is always the last row of Boards.
    func reloadSidebar() {
        var s: [(String, Section)] = [(Lang.t("ui.history"), .header), (Lang.t("ui.allItems"), .all), (Lang.t("ui.pinned"), .pinned), (Lang.t("ui.text"), .text), (Lang.t("ui.links"), .links),
                                      (Lang.t("ui.imagesGifs"), .images), (Lang.t("ui.files"), .files), (Lang.t("ui.textInImages"), .textInImages),
                                      (Lang.t("ui.library"), .header), (Lang.t("ui.favourites"), .library), (Lang.t("ui.snippets"), .snippets)]
        let boards = (try? store.boards()) ?? []
        s.append((Lang.t("ui.boards"), .header))
        for b in boards { s.append((b.name, .board(b.id))) }
        s.append(("+ " + Lang.t("ui.newBoard"), .addBoard))
        s.append((Lang.t("ui.tools"), .header))
        s.append((Lang.t("ui.tools.page"), .tools))
        s.append((Lang.t("ui.app"), .header))
        s.append((Lang.t("ui.settings"), .settings))
        s.append((Lang.t("ui.about"), .about))
        sections = s
        sidebar.reloadData()
        if let row = sections.firstIndex(where: { $0.1 == section }) { sidebar.selectRowIndexes([row], byExtendingSelection: false) }
    }

    /// Locks the window now (menu: Lock history now). It asks again the next time it is opened.
    func lockNow() { Authentication.lockNow(); locked = true; reloadList() }

    /// Shows the settings or About pane for their sections, and the list and preview for every other section.
    func updateChrome() {
        // While locked, Settings and About are hidden too: the lock covers the whole app, not only the list.
        let isSettings = section == .settings && !locked, isAbout = section == .about && !locked, isTools = section == .tools && !locked
        listPaneRef?.isHidden = isSettings || isAbout || isTools || locked
        (listPaneRef as? ListPaneView)?.guide.stringValue = sectionGuide()
        settingsHost.isHidden = !isSettings
        aboutScroll.isHidden = !(isAbout || isTools)
        if isSettings, let root = settingsRoot, root.superview !== settingsHost {
            settingsHost.subviews.forEach { $0.removeFromSuperview() }
            root.translatesAutoresizingMaskIntoConstraints = false
            settingsHost.addSubview(root)
            NSLayoutConstraint.activate([root.topAnchor.constraint(equalTo: settingsHost.topAnchor), root.bottomAnchor.constraint(equalTo: settingsHost.bottomAnchor),
                                         root.leadingAnchor.constraint(equalTo: settingsHost.leadingAnchor), root.trailingAnchor.constraint(equalTo: settingsHost.trailingAnchor)])
        }
        if isAbout || isTools {
            let page = isTools ? toolsPage() : aboutPage()
            // A top-down document laid out by frame: the page starts at its top, and grows to fit its content.
            let doc = FlippedDocumentView()
            page.translatesAutoresizingMaskIntoConstraints = true
            page.autoresizingMask = [.width]
            doc.addSubview(page)
            aboutScroll.documentView = doc
            placePage(page, in: doc, scroll: aboutScroll)
        }
        let plain = !isSettings && !isAbout && !isTools
        previewScroll.isHidden = !plain
        previewImage.isHidden = true
        snippetBox.isHidden = true
        actions.isHidden = !plain
        window.contentView?.needsLayout = true   // a pane was shown or hidden: place the panes again
    }

    /// Sizes the page to its content (at least the visible height) and starts the scroll at the top.
    private func placePage(_ page: NSView, in doc: NSView, scroll: NSScrollView) {
        let w = scroll.contentView.bounds.width
        // Set the width first, so wrapped text is measured at the width it will be shown at.
        page.setFrameSize(NSSize(width: w, height: 1))
        page.layoutSubtreeIfNeeded()
        let h = max(page.fittingSize.height, scroll.contentView.bounds.height)
        doc.frame = NSRect(x: 0, y: 0, width: w, height: h)
        page.frame = doc.bounds
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 0))
        scroll.reflectScrolledClipView(scroll.contentView)
    }
    /// The About page, in sections: the app, who built it, privacy, and the licence and links.
    private func aboutPage() -> NSView {
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

    func reloadList() {
        updateChrome()
        // Settings and About own the whole detail pane: nothing else to load.
        if !locked && (section == .settings || section == .about || section == .tools) { return }
        if locked { items = []; list.reloadData(); showDetail(nil); preview.string = Lang.t("ui.lockedMain"); return }
        if section == .snippets {
            snippets = (try? store.snippets(query: search.stringValue)) ?? []
            list.reloadData()
            snippetBox.isHidden = selectedSnippet == nil; previewScroll.isHidden = selectedSnippet != nil
            if selectedSnippet == nil { preview.string = Lang.t("ui.chooseSnippet") }
            return
        }
        switch section {
        case .all: items = (try? store.list(query: search.stringValue, limit: 1000)) ?? []
        case .pinned: items = ((try? store.list(query: search.stringValue, limit: 1000)) ?? []).filter(\.pinned)
        case .text: items = ((try? store.list(query: search.stringValue, limit: 1000)) ?? []).filter { $0.kind == .text || $0.kind == .richText }
        case .links: items = ((try? store.list(query: search.stringValue, limit: 1000)) ?? []).filter { $0.kind == .url }
        case .images: items = ((try? store.list(query: search.stringValue, limit: 1000)) ?? []).filter { $0.kind == .image || $0.kind == .gif }
        case .files: items = ((try? store.list(query: search.stringValue, limit: 1000)) ?? []).filter { $0.kind == .file }
        case .board(let id): items = ((try? store.items(onBoard: id)) ?? []).filter { search.stringValue.isEmpty || $0.text.localizedCaseInsensitiveContains(search.stringValue) }
        case .library: items = (try? store.list(query: search.stringValue, limit: 1000, filter: .init(favoritesOnly: true))) ?? []
        case .textInImages: items = (try? store.list(query: search.stringValue, limit: 1000, filter: .init(hasText: true))) ?? []
        case .snippets, .header, .addBoard, .settings, .about, .tools: break
        }
        list.reloadData()
        if viewMode.selectedSegment == 1 { shelf.reload(items, store: store) }
        snippetBox.isHidden = true; previewScroll.isHidden = false
        if !items.isEmpty { list.selectRowIndexes([0], byExtendingSelection: false) } else { showDetail(nil) }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView == sidebar { return sections.count }
        return section == .snippets ? snippets.count : items.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView == sidebar {
            let (title, sec) = sections[row]
            if sec == .header {
                let h = NSTextField(labelWithString: title)
                h.font = .systemFont(ofSize: 11, weight: .semibold); h.textColor = .secondaryLabelColor
                h.lineBreakMode = .byTruncatingTail
                h.alignment = Lang.isRightToLeft ? .right : .left
                // Sit the heading on the bottom of its row, so it belongs to the group below it.
                let holder = NSView(); h.translatesAutoresizingMaskIntoConstraints = false
                holder.addSubview(h)
                NSLayoutConstraint.activate([
                    h.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: 2),
                    h.trailingAnchor.constraint(lessThanOrEqualTo: holder.trailingAnchor),
                    h.bottomAnchor.constraint(equalTo: holder.bottomAnchor, constant: -4),
                ])
                return holder
            }
            let l = NSTextField(labelWithString: "")
            let out = NSMutableAttributedString()
            if case .board(let id) = sec, let b = (try? store.boards())?.first(where: { $0.id == id }) {
                out.append(NSAttributedString(string: "● ", attributes: [.foregroundColor: Self.colour(b.colorName), .font: NSFont.systemFont(ofSize: 13)]))
            }
            let isAdd = sec == .addBoard
            out.append(NSAttributedString(string: title, attributes: [
                .font: NSFont.systemFont(ofSize: 13), .foregroundColor: isAdd ? NSColor.secondaryLabelColor : NSColor.labelColor]))
            // Arabic: the item text starts from the right, like the rest of the window.
            let paragraph = NSMutableParagraphStyle(); paragraph.alignment = Lang.isRightToLeft ? .right : .left
            out.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: out.length))
            l.alignment = Lang.isRightToLeft ? .right : .left
            l.attributedStringValue = out
            l.lineBreakMode = .byTruncatingTail
            return l
        }
        if section == .snippets {
            let s = snippets[row]
            let t = NSTextField(labelWithString: (s.favorite ? "★ " : "") + s.title + (s.folder.isEmpty ? "" : "  · " + s.folder))
            t.lineBreakMode = .byTruncatingTail; return t
        }
        return Design.row(for: items[row], store: store)
    }

    /// The right-click menu for a card or row at an index in the current list.
    func contextMenu(forItem index: Int) -> NSMenu? {
        guard section != .settings, section != .about, section != .tools, section != .snippets, items.indices.contains(index) else { return nil }
        let menu = NSMenu()
        for m in ItemActions.menuItems(for: items[index], store: store, changed: { [weak self] in self?.reloadList() }) { menu.addItem(m) }
        for m in ItemActions.actionItems(for: items[index], actions: UserAction.parse(monitor.settings.actionsText), store: store, changed: { [weak self] in self?.reloadList() }) { menu.addItem(m) }
        return menu
    }

    /// Right-click on a list row: edit, pin, favourite or delete that item.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard section != .settings, section != .about, section != .tools, section != .snippets, items.indices.contains(list.clickedRow) else { return }
        let item = items[list.clickedRow]
        for m in ItemActions.menuItems(for: item, store: store, changed: { [weak self] in self?.reloadList() }) { menu.addItem(m) }
    }

    /// Headers in the sidebar are labels, not destinations.
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        tableView == sidebar ? sections[row].1 != .header : true
    }
    /// Sidebar rows are taller than the list rows; headers are short.
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard tableView == sidebar else { return Design.rowHeight }
        // Group headers get air above them, except the first one at the top of the sidebar.
        if sections[row].1 == .header { return row == 0 ? 24 : 34 }
        return 26
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        if (notification.object as? NSTableView) == sidebar {
            guard sidebar.selectedRow >= 0 else { return }
            // The "+ New board" row opens the dialog and keeps the section that was open.
            if sections[sidebar.selectedRow].1 == .addBoard { newBoard(); reloadSidebar(); return }
            section = sections[sidebar.selectedRow].1
            selectedSnippet = nil; reloadList(); return
        }
        if section == .snippets {
            guard list.selectedRow >= 0, snippets.indices.contains(list.selectedRow) else { return }
            selectedSnippet = snippets[list.selectedRow]
            snippetTitle.stringValue = selectedSnippet!.title; snippetFolder.stringValue = selectedSnippet!.folder; snippetTags.stringValue = selectedSnippet!.tags
            snippetBody.string = selectedSnippet!.body
            snippetBox.isHidden = false; previewScroll.isHidden = true
            return
        }
        if viewMode.selectedSegment == 1 { syncShelfSelection() }
        showDetail(selectedItem)
    }

    func controlTextDidChange(_ obj: Notification) { reloadList() }

    private var selectedItem: ClipItem? { items.indices.contains(list.selectedRow) ? items[list.selectedRow] : nil }

    // MARK: detail

    private func showDetail(_ i: ClipItem?) {
        actions.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if case .board = section {
            actions.addArrangedSubview(button("Edit board…", #selector(editBoard)))
            let delBoard = button(Lang.t("ui.board.delete"), #selector(deleteBoardTapped)); delBoard.contentTintColor = .systemRed
            actions.addArrangedSubview(delBoard)
        }
        guard let i else { preview.string = Lang.t("ui.nothingHere"); previewImage.isHidden = true; preview.isHidden = false; return }
        if i.kind == .image || i.kind == .gif, let d = store.payloadData(for: i), let img = NSImage(data: d) {
            previewImage.image = img; previewImage.isHidden = false; preview.isHidden = true
        } else {
            previewImage.isHidden = true; preview.isHidden = false
            var body = i.secretKinds.isEmpty ? i.listTitle : Lang.t("ui.hiddenSecretLine", ["kinds": i.secretKinds.map(\.rawValue).joined(separator: ", ")])
            let ocr = store.ocrText(for: i.id)
            if !ocr.isEmpty { body += "\n\n— Text in this image —\n" + ocr }
            preview.string = String(body.prefix(20_000))
        }
        // Primary actions stay visible; everything else lives in one More menu, so the row never overflows.
        actions.addArrangedSubview(button(Lang.t("ui.copy"), #selector(copyItem)))
        actions.addArrangedSubview(button(i.pinned ? Lang.t("ui.unpin") : Lang.t("ui.pin"), #selector(togglePin)))
        actions.addArrangedSubview(button(i.favorite ? Lang.t("ui.unfavourite") : Lang.t("ui.favourite"), #selector(toggleFavorite)))
        // Saving to a board is one visible step: the board list opens right here, and the item is added on click.
        actions.addArrangedSubview(menuButton(Lang.t("ui.addToBoard"), boardMenu()))
        if case .board = section { actions.addArrangedSubview(button(Lang.t("ui.board.removeItem"), #selector(removeFromBoardTapped))) }
        actions.addArrangedSubview(menuButton(Lang.t("ui.more"), moreMenu(i)))
        let n = list.selectedRowIndexes.count
        let del = button(n > 1 ? Lang.t("ui.deleteNItems", ["n": "\(n)"]) : Lang.t("ui.delete"), #selector(deleteItem))
        del.contentTintColor = .systemRed
        actions.addArrangedSubview(del)
    }

    func menuButton(_ title: String, _ menu: NSMenu) -> NSButton {
        let b = NSButton(title: title, target: nil, action: nil); b.bezelStyle = .rounded
        b.menu = menu; b.target = self; b.action = #selector(showMenu(_:)); return b
    }
    @objc private func showMenu(_ sender: NSButton) {
        guard let m = sender.menu else { return }
        m.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
    }
    func boardMenu() -> NSMenu {
        let m = NSMenu()
        for b in (try? store.boards()) ?? [] {
            let it = NSMenuItem(title: b.name, action: #selector(addToBoard(_:)), keyEquivalent: ""); it.target = self; it.representedObject = b.id; m.addItem(it)
        }
        m.addItem(.separator())
        let new = NSMenuItem(title: "New board…", action: #selector(newBoard), keyEquivalent: ""); new.target = self; m.addItem(new)
        return m
    }
    private func toolsMenu() -> NSMenu {
        let m = NSMenu()
        for t in TextTool.allCases {
            let it = NSMenuItem(title: Lang.t("tt." + t.rawValue), action: #selector(runTool(_:)), keyEquivalent: ""); it.target = self; it.representedObject = t.rawValue; m.addItem(it)
        }
        return m
    }
    private func smartMenu(_ found: [(kind: SmartKind, value: String)]) -> NSMenu {
        let m = NSMenu()
        for f in found {
            let it = NSMenuItem(title: "Copy \(f.kind.rawValue): \(f.value)", action: #selector(copyValue(_:)), keyEquivalent: ""); it.target = self; it.representedObject = f.value; m.addItem(it)
        }
        return m
    }

    /// Everything that is not a primary action, grouped the way people look for it.
    private func moreMenu(_ i: ClipItem) -> NSMenu {
        let m = NSMenu()
        func entry(_ t: String, _ a: Selector, _ obj: Any? = nil) { let it = NSMenuItem(title: t, action: a, keyEquivalent: ""); it.target = self; it.representedObject = obj; m.addItem(it) }
        func sub(_ t: String, _ menu: NSMenu) { let it = NSMenuItem(title: t, action: nil, keyEquivalent: ""); it.submenu = menu; m.addItem(it) }
        entry("Tags…", #selector(editTags))
        sub(Lang.t("ui.addToBoard"), boardMenu())
        if i.kind == .text || i.kind == .richText || i.kind == .url {
            sub(Lang.t("ui.textTools"), toolsMenu())
            sub(Lang.t("ui.pasteAs"), pasteFormatMenu())
            let smart = SmartRecognizer.find(in: i.text)
            if !smart.isEmpty { sub(Lang.t("ui.smartActions"), smartMenu(smart)) }
        }
        if i.kind == .image, store.payloadData(for: i) != nil {
            entry("Annotate…", #selector(annotateItem))
            if !store.ocrText(for: i.id).isEmpty { entry("Extract text", #selector(extractTextItem)) }
        }
        return m
    }

    private func pasteFormatMenu() -> NSMenu {
        let m = NSMenu()
        for f in PasteFormat.allCases {
            let it = NSMenuItem(title: Lang.t("pf." + f.rawValue), action: #selector(pasteAs(_:)), keyEquivalent: ""); it.target = self; it.representedObject = f.rawValue; m.addItem(it)
        }
        return m
    }
    @objc private func pasteAs(_ s: NSMenuItem) {
        guard let i = selectedItem, let raw = s.representedObject as? String, let f = PasteFormat(rawValue: raw) else { return }
        monitor.restore(f.apply(i.text))
    }
    @objc private func extractTextItem() {
        guard let i = selectedItem else { return }
        let text = store.ocrText(for: i.id)
        guard !text.isEmpty else { return }
        _ = try? store.add(text: text, sourceBundleID: i.sourceBundleID); reloadList()
    }

    @objc private func annotateItem() {
        guard let i = selectedItem else { return }
        annotate(i)
    }
    /// Opens the annotate window for an image. Says so when the image cannot be opened, instead of doing nothing.
    func annotate(_ i: ClipItem) {
        guard let d = store.payloadData(for: i), let a = AnnotateController(imageData: d, store: store, monitor: monitor) else {
            let alert = NSAlert(); alert.messageText = Lang.t("ui.annotate.none"); alert.runModal(); return
        }
        annotators.append(a); a.show()
    }
    var annotators: [AnnotateController] = []

    @objc private func removeFromBoardTapped() {
        guard case .board(let id) = section, let i = selectedItem else { return }
        try? store.removeFromBoard(item: i.id, board: id); reloadList()
    }
    @objc private func deleteBoardTapped() {
        guard case .board(let id) = section else { return }
        let alert = NSAlert(); alert.messageText = Lang.t("ui.board.delete"); alert.informativeText = Lang.t("ui.board.deleteInfo")
        alert.addButton(withTitle: Lang.t("ui.delete")); alert.addButton(withTitle: Lang.t("ui.cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        try? store.deleteBoard(id); section = .all; reloadSidebar(); reloadList()
    }

    @objc private func copyItem() { guard let i = selectedItem else { return }; monitor.restore(i) }

    /// ⌘F from the menu: move the cursor to the search field.
    @objc func focusSearch() { window.makeKeyAndOrderFront(nil); window.makeFirstResponder(search) }
    @objc private func togglePin() { guard let i = selectedItem else { return }; try? store.setPinned(i.id, !i.pinned); reloadList() }
    @objc private func deleteItem() {
        // Batch delete: every selected row goes, after one confirmation when more than one is selected.
        let picked = list.selectedRowIndexes.compactMap { items[safe: $0]?.id }
        guard !picked.isEmpty else { return }
        if picked.count > 1 {
            let a = NSAlert(); a.messageText = Lang.t("ui.deleteN", ["n": "\(picked.count)"]); a.informativeText = Lang.t("ui.deleteNInfo")
            a.addButton(withTitle: Lang.t("ui.delete")); a.addButton(withTitle: Lang.t("ui.cancel"))
            guard a.runModal() == .alertFirstButtonReturn else { return }
        }
        try? store.delete(picked); reloadList()
    }
    @objc private func editTags() {
        guard let i = selectedItem else { return }
        let alert = NSAlert(); alert.messageText = Lang.t("ui.tags"); alert.informativeText = Lang.t("ui.tagsInfo")
        alert.addButton(withTitle: Lang.t("ui.save")); alert.addButton(withTitle: Lang.t("ui.cancel"))
        let f = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24)); f.stringValue = store.tags(for: i.id).joined(separator: ", ")
        alert.accessoryView = f
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        try? store.setTags(i.id, f.stringValue.split(separator: ",").map(String.init)); reloadList()
    }
    @objc private func toggleFavorite() { guard let i = selectedItem else { return }; try? store.setFavorite(i.id, !i.favorite); reloadList() }
    @objc private func addToBoard(_ s: NSMenuItem) { guard let i = selectedItem, let b = s.representedObject as? Int64 else { return }; try? store.addToBoard(item: i.id, board: b); reloadSidebar() }
    static func colour(_ name: String) -> NSColor {
        switch name {
        case "green": return .systemGreen
        case "amber": return .systemOrange
        case "red": return .systemRed
        case "purple": return .systemPurple
        case "gray": return .systemGray
        default: return .systemBlue
        }
    }

    /// Name and colour of a board, in one dialog. Used for new boards and for editing.
    private func boardDialog(title: String, name: String, colour: String) -> (String, BoardColor)? {
        let alert = NSAlert(); alert.messageText = title; alert.addButton(withTitle: Lang.t("ui.save")); alert.addButton(withTitle: Lang.t("ui.cancel"))
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
        let f = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24)); f.placeholderString = Lang.t("ui.boardName"); f.stringValue = name
        let pop = NSPopUpButton(); pop.addItems(withTitles: BoardColor.allCases.map { Lang.t("bc." + $0.rawValue) })
        pop.selectItem(at: BoardColor.allCases.firstIndex { $0.rawValue == colour } ?? 0)
        stack.addArrangedSubview(f); stack.addArrangedSubview(pop)
        stack.frame = NSRect(x: 0, y: 0, width: 260, height: 60)
        alert.accessoryView = stack
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let clean = f.stringValue.trimmingCharacters(in: .whitespaces)
        return clean.isEmpty ? nil : (clean, BoardColor.allCases[pop.indexOfSelectedItem])
    }

    @objc private func newBoard() {
        guard let (name, colour) = boardDialog(title: Lang.t("ui.newBoard"), name: "", colour: "blue") else { return }
        _ = try? store.addBoard(name: name, color: colour.rawValue); reloadSidebar()
    }
    /// Renames and recolours the board in view.
    @objc func editBoard() {
        guard case .board(let id) = section, let b = (try? store.boards())?.first(where: { $0.id == id }),
              let (name, colour) = boardDialog(title: Lang.t("ui.editBoard"), name: b.name, colour: b.colorName) else { return }
        try? store.updateBoard(id, name: name, color: colour); reloadSidebar()
    }
    @objc private func runTool(_ s: NSMenuItem) {
        guard let i = selectedItem, let raw = s.representedObject as? String, let tool = TextTool(rawValue: raw), let out = tool.apply(i.text) else { return }
        // A transformed text is a new item, so the original stays in history.
        _ = try? store.add(text: out, sourceBundleID: i.sourceBundleID); reloadList()
    }
    @objc private func copyValue(_ s: NSMenuItem) { if let v = s.representedObject as? String { monitor.restore(v) } }

    // MARK: snippets

    @objc func newSnippet() {
        section = .snippets; selectedSnippet = nil
        if let s = try? store.addSnippet(title: Lang.t("ui.newSnippet"), body: "") { selectedSnippet = s }
        reloadList(); reloadSidebar()
        if let row = snippets.firstIndex(where: { $0.id == selectedSnippet?.id }) { list.selectRowIndexes([row], byExtendingSelection: false) }
    }
    @objc private func saveSnippet() {
        guard var s = selectedSnippet else { return }
        s.title = snippetTitle.stringValue.isEmpty ? Lang.t("ui.untitled") : snippetTitle.stringValue
        s.folder = snippetFolder.stringValue; s.body = snippetBody.string; s.tags = snippetTags.stringValue
        try? store.updateSnippet(s); selectedSnippet = s; reloadList()
    }
    @objc private func deleteSnippet() {
        guard let s = selectedSnippet else { return }
        try? store.deleteSnippet(s.id); selectedSnippet = nil; reloadList()
    }
    /// Used by the menu bar: fill in and copy a snippet without opening the editor.
    func insertSnippetFromMenu(_ snip: Snippet) {
        selectedSnippet = snip; snippetBody.string = snip.body
        insertSnippet()
    }

    @objc private func insertSnippet() {
        guard let s = selectedSnippet else { return }
        let names = Template.variables(in: snippetBody.string)
        var values: [String: String] = [:]
        if !names.isEmpty {
            let alert = NSAlert(); alert.messageText = Lang.t("ui.fillIn", ["title": s.title]); alert.addButton(withTitle: Lang.t("ui.copy")); alert.addButton(withTitle: Lang.t("ui.cancel"))
            let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 6
            var fields: [(String, NSTextField)] = []
            for n in names {
                let f = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24)); f.placeholderString = n
                fields.append((n, f)); stack.addArrangedSubview(NSTextField(labelWithString: n)); stack.addArrangedSubview(f)
            }
            stack.frame = NSRect(x: 0, y: 0, width: 300, height: CGFloat(names.count) * 52)
            alert.accessoryView = stack
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            for (n, f) in fields { values[n] = f.stringValue }
        }
        monitor.restore(Template.render(snippetBody.string, values: values))
    }
}


/// Lays out a row of panes: fixed widths for the first ones, the last pane takes whatever is left. Hidden panes take no room.
final class PaneLayout: NSView {
    private let panes: [NSView]
    private let widths: [CGFloat?]
    private let divider: CGFloat = 1
    private var dividers: [NSView] = []

    init(panes: [NSView], widths: [CGFloat?]) {
        self.panes = panes; self.widths = widths
        super.init(frame: .zero)
        for p in panes { addSubview(p) }
    }
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    /// Panes run from the leading edge: left to right normally, right to left in Arabic (the list follows the language).
    override func layout() {
        super.layout()
        let rtl = userInterfaceLayoutDirection == .rightToLeft
        let visible = panes.enumerated().filter { !$0.element.isHidden }
        let fixed = visible.dropLast().map { widths[$0.offset] ?? 0 }
        let gaps = CGFloat(max(0, visible.count - 1)) * divider
        let remainder = max(0, bounds.width - fixed.reduce(0, +) - gaps)
        let sizes = fixed + [remainder]
        var edge: CGFloat = rtl ? bounds.width : 0      // leading edge of the next pane
        for (k, item) in visible.enumerated() {
            let w = sizes[k]
            let x = rtl ? edge - w : edge
            item.element.frame = NSRect(x: x, y: 0, width: w, height: bounds.height)
            edge = rtl ? x - divider : x + w + divider
            if k < visible.count - 1 {
                let dx = rtl ? x - divider : x + w
                divider(at: k).frame = NSRect(x: dx, y: 0, width: divider, height: bounds.height)
            }
        }
        for (k, d) in dividers.enumerated() where k >= max(0, visible.count - 1) { d.isHidden = true }
    }

    private func divider(at index: Int) -> NSView {
        if index < dividers.count { dividers[index].isHidden = false; return dividers[index] }
        let d = NSView(); d.wantsLayer = true; d.layer?.backgroundColor = NSColor.separatorColor.cgColor
        addSubview(d); dividers.append(d)
        return d
    }
}

/// A vertical stack whose first view is at the top, whatever the window's coordinate system.
final class TopDownStack: NSStackView {
    override var isFlipped: Bool { true }
}

/// The item-list pane: the search field and the List/Cards control along the top, the items below.
/// Placed by hand so the toolbar mirrors in Arabic: the control on the left, the search field filling the rest.
final class ListPaneView: NSView {
    private let search: NSView
    private let mode: NSView
    private let body: NSView
    /// One line that says what the section is for, under the search bar.
    let guide = NSTextField(wrappingLabelWithString: "")
    init(search: NSView, mode: NSView, body: NSView) {
        self.search = search; self.mode = mode; self.body = body
        super.init(frame: .zero)
        guide.font = .systemFont(ofSize: 12); guide.textColor = .secondaryLabelColor
        guide.alignment = Lang.isRightToLeft ? .right : .left
        guide.maximumNumberOfLines = 2; guide.preferredMaxLayoutWidth = 0
        addSubview(search); addSubview(mode); addSubview(guide); addSubview(body)
    }
    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }
    override func layout() {
        super.layout()
        let rowHeight: CGFloat = 30, margin: CGFloat = 8, gap: CGFloat = 6
        let rtl = Lang.isRightToLeft
        let modeWidth = max(mode.intrinsicContentSize.width, 60)
        let searchWidth = max(0, bounds.width - 2 * margin - modeWidth - gap)
        let modeX = rtl ? margin : bounds.width - margin - modeWidth
        let searchX = rtl ? margin + modeWidth + gap : margin
        mode.frame = NSRect(x: modeX, y: 10, width: modeWidth, height: rowHeight)
        search.frame = NSRect(x: searchX, y: 10, width: searchWidth, height: rowHeight)
        guide.frame = NSRect(x: margin, y: 44, width: max(0, bounds.width - 2 * margin), height: 30)
        body.frame = NSRect(x: 0, y: 80, width: bounds.width, height: max(0, bounds.height - 80))
    }
}

/// The links on the About page. The repository is private, so only public places are linked.
@MainActor
final class AboutActions: NSObject {
    static let shared = AboutActions()
    static let email = "mou.shabaan@gmail.com"

    @objc func sendEmail() { NSWorkspace.shared.open(URL(string: "mailto:\(Self.email)")!) }
    @objc func openGitHub() { NSWorkspace.shared.open(URL(string: "https://github.com/moushaban-cell")!) }
}


/// A view whose origin is at the top-left, so content in a scroll view starts at the top.
final class TopAlignedView: NSView {
    override var isFlipped: Bool { true }
}

/// Arabic: every view in the subtree lays out right to left, and text is right aligned.
@MainActor
func mirrorForRTL(_ view: NSView) {
    view.userInterfaceLayoutDirection = .rightToLeft
    if let field = view as? NSTextField { field.alignment = .right }
    for sub in view.subviews { mirrorForRTL(sub) }
}


extension HistoryWindowController {
    /// What the current sidebar section is for, in the person's language.
    func sectionGuide() -> String {
        switch section {
        case .all: return Lang.t("ui.help.all")
        case .pinned: return Lang.t("ui.help.pinned")
        case .text: return Lang.t("ui.help.text")
        case .links: return Lang.t("ui.help.links")
        case .images: return Lang.t("ui.help.images")
        case .files: return Lang.t("ui.help.files")
        case .textInImages: return Lang.t("ui.help.textInImages")
        case .library: return Lang.t("ui.help.favourites")
        case .board: return Lang.t("ui.help.board")
        case .snippets: return Lang.t("ui.help.snippets")
        default: return ""
        }
    }
}
