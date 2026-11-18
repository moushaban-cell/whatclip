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

    let window: NSWindow
    let store: ClipStore
    let monitor: PasteboardMonitor
    let sidebar = NSTableView()
    let list = NSTableView()
    let search = NSSearchField()
    private let listScroll = NSScrollView()
    /// Shown over the empty Snippets list: starts a new snippet. It sits on the scroll view, so it stays put while the list scrolls.
    var annotators: [AnnotateController] = []
    let snippetsEmptyButton = NSButton(title: "", target: nil, action: nil)
    /// Settings (from the Settings module) and the About text: shown in the detail pane when their sidebar item is chosen.
    var settingsRoot: NSView?
    private let settingsHost = NSView()
    private let aboutScroll = NSScrollView()
    /// The Tools or About page and the document it sits in, laid out again whenever the pane is resized.
    private var aboutPageView: NSView?
    private var aboutDoc: NSView?
    private var aboutObserver: NSObjectProtocol?
    private var listPaneRef: NSView?
    private let viewMode = NSSegmentedControl(labels: [Lang.t("ui.list"), Lang.t("ui.cards")], trackingMode: .selectOne, target: nil, action: nil)
    private let shelf = ShelfController()
    let preview = NSTextView()
    private let previewScroll = NSScrollView()
    let previewImage = NSImageView()
    let actions = NSStackView()
    let snippetTitle = NSTextField()
    let snippetFolder = NSTextField()
    let snippetTags = NSTextField()
    let snippetBody = NSTextView()
    let snippetBox = NSStackView()
    var sections: [(String, Section)] = []
    var section: Section = .all
    var items: [ClipItem] = []
    var snippets: [Snippet] = []
    var selectedSnippet: Snippet?

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
        snippetsEmptyButton.bezelStyle = .rounded; snippetsEmptyButton.controlSize = .large
        snippetsEmptyButton.isHidden = true
        // Plain frame and autoresizing: the button keeps its size and stays centred as the list pane changes size.
        snippetsEmptyButton.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        listScroll.addSubview(snippetsEmptyButton)

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
    /// Brings the open window up to date with the data and the settings: the list, and the Tools page when it is open.
    func refreshIfVisible() {
        guard window.isVisible else { return }
        reloadSidebar(); reloadList()
        if section == .tools || section == .about { updateChrome() }
    }

    func button(_ title: String, _ action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action); b.bezelStyle = .rounded; return b
    }

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
            aboutPageView = page; aboutDoc = doc
            aboutScroll.contentView.postsFrameChangedNotifications = true
            if aboutObserver == nil {
                aboutObserver = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: aboutScroll.contentView, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.relayoutAboutPage() }
                }
            }
            relayoutAboutPage()
        }
        // Item actions apply to history items only; Snippets has its own editor.
        let plain = !isSettings && !isAbout && !isTools && section != .snippets
        previewScroll.isHidden = !plain
        previewImage.isHidden = true
        snippetBox.isHidden = true
        actions.isHidden = !plain
        window.contentView?.needsLayout = true   // a pane was shown or hidden: place the panes again
    }

    /// Lays out the Tools or About page for the pane's current width. Does nothing until the pane has a width.
    private func relayoutAboutPage() {
        guard let page = aboutPageView, let doc = aboutDoc, aboutScroll.contentView.bounds.width > 0 else { return }
        placePage(page, in: doc, scroll: aboutScroll)
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

    func reloadList() {
        updateChrome()
        // Settings and About own the whole detail pane: nothing else to load.
        if !locked && (section == .settings || section == .about || section == .tools) { return }
        if locked { items = []; list.reloadData(); showDetail(nil); preview.string = Lang.t("ui.lockedMain"); return }
        snippetsEmptyButton.isHidden = true   // only the Snippets branch shows it again
        if section == .snippets {
            snippets = (try? store.snippets(query: search.stringValue)) ?? []
            list.reloadData()
            // With no snippets yet, the list offers one button to start the first snippet.
            snippetsEmptyButton.title = Lang.t("ui.newSnippet")
            snippetsEmptyButton.target = self; snippetsEmptyButton.action = #selector(newSnippet)
            snippetsEmptyButton.isHidden = !snippets.isEmpty
            if snippets.isEmpty {
                let size = snippetsEmptyButton.intrinsicContentSize
                snippetsEmptyButton.frame = NSRect(x: max(0, (listScroll.bounds.width - size.width) / 2),
                                                   y: max(0, (listScroll.bounds.height - size.height) / 2),
                                                   width: size.width, height: size.height)
            }
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

    var selectedItem: ClipItem? { items.indices.contains(list.selectedRow) ? items[list.selectedRow] : nil }


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
    let search: NSView
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
