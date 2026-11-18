import AppKit
import WhatClipCore

/// The full history window: sidebar (filters, boards, snippets), the list, a preview and actions on the selected item.
@MainActor
final class HistoryWindowController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSMenuDelegate {
    enum Section: Equatable { case header, all, library, pinned, text, links, images, files, textInImages, board(Int64), snippets, settings, about }

    private let window: NSWindow
    private let store: ClipStore
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
    private let viewMode = NSSegmentedControl(labels: ["List", "Cards"], trackingMode: .selectOne, target: nil, action: nil)
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
                let ok = await Authentication.unlock(reason: "Open your clipboard history")
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
        sidebar.setAccessibilityLabel("Sections")
        let sideScroll = NSScrollView(); sideScroll.documentView = sidebar; sideScroll.hasVerticalScroller = true; sideScroll.borderType = .noBorder

        search.placeholderString = "Search"; search.delegate = self
        list.headerView = nil; list.dataSource = self; list.delegate = self; list.rowHeight = Design.rowHeight
        list.allowsMultipleSelection = true; list.setAccessibilityLabel("Items")
        // Keyboard: Return or a double-click copies the selected item; arrows move through the list (built into the table).
        list.target = self; list.doubleAction = #selector(copyItem)
        let rowMenu = NSMenu(); rowMenu.delegate = self; list.menu = rowMenu
        list.addTableColumn(NSTableColumn(identifier: .init("item")))
        list.setAccessibilityLabel("Items")
        listScroll.documentView = list; listScroll.hasVerticalScroller = true; listScroll.borderType = .noBorder

        preview.isEditable = false; preview.font = .systemFont(ofSize: 14); preview.textContainerInset = NSSize(width: 14, height: 14)
        preview.isVerticallyResizable = true; preview.isHorizontallyResizable = false; preview.autoresizingMask = [.width]
        preview.textContainer?.widthTracksTextView = true; preview.textColor = .labelColor; preview.backgroundColor = .textBackgroundColor
        previewScroll.documentView = preview; previewScroll.hasVerticalScroller = true; previewScroll.borderType = .noBorder
        previewScroll.drawsBackground = true; previewScroll.backgroundColor = .textBackgroundColor
        previewImage.imageScaling = .scaleProportionallyUpOrDown; previewImage.isHidden = true
        actions.orientation = .horizontal; actions.spacing = 8

        // Snippet editor (shown in place of the preview in the Snippets section)
        snippetTitle.placeholderString = "Title"; snippetFolder.placeholderString = "Folder (optional)"; snippetTags.placeholderString = "Tags, separated by commas"
        snippetBody.font = .monospacedSystemFont(ofSize: 12, weight: .regular); snippetBody.isRichText = false; snippetBody.isAutomaticQuoteSubstitutionEnabled = false
        let bodyScroll = NSScrollView(); bodyScroll.documentView = snippetBody; bodyScroll.hasVerticalScroller = true; bodyScroll.borderType = .bezelBorder
        bodyScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        let hint = NSTextField(wrappingLabelWithString: "Use {{name}} for values to fill in when you insert this snippet.")
        hint.font = .systemFont(ofSize: 11); hint.textColor = .secondaryLabelColor
        let buttons = NSStackView(views: [
            button("Save snippet", #selector(saveSnippet)), button("Insert…", #selector(insertSnippet)), button("Delete", #selector(deleteSnippet)),
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
        viewMode.setAccessibilityLabel("Show as list or cards")
        shelf.scroll.isHidden = true
        shelf.menuForItem = { [weak self] i in self?.contextMenu(forItem: i) }
        shelf.onSelect = { [weak self] index in
            guard let self else { return }
            self.list.selectRowIndexes([index], byExtendingSelection: false)
        }
        let listArea = NSStackView(views: [listScroll, shelf.scroll]); listArea.orientation = .vertical; listArea.distribution = .fillEqually
        let listPane = NSStackView(views: [NSStackView(views: [search, viewMode]), listArea]); listPane.orientation = .vertical; listPane.spacing = 6
        listPaneRef = listPane
        listPane.edgeInsets = NSEdgeInsets(top: 10, left: 8, bottom: 8, right: 8)
        listPane.widthAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true
        // Three panes placed by hand: sections (fixed width), items (fixed width), details (takes the rest).
        // A plain layout keeps each pane exactly where it belongs, including when Settings replaces the list.
        let panes = PaneLayout(panes: [sideScroll, listPane, detail], widths: [220, 300, nil])
        window.contentView = panes

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

    /// The sidebar in groups: History, Library, Boards, Tools. Headers are shown but cannot be selected.
    func reloadSidebar() {
        var s: [(String, Section)] = [("History", .header), ("All items", .all), ("Pinned", .pinned), ("Text", .text), ("Links", .links),
                                      ("Images and GIFs", .images), ("Files", .files), ("Text found in images", .textInImages),
                                      ("Library", .header), ("Favourites", .library)]
        let boards = (try? store.boards()) ?? []
        s.append(("Boards", .header))
        for b in boards { s.append((b.name, .board(b.id))) }
        if boards.isEmpty { s.append(("No boards yet", .header)) }
        s.append(("Tools", .header))
        s.append(("Snippets", .snippets))
        s.append(("App", .header))
        s.append(("Settings", .settings))
        s.append(("About WhatClip", .about))
        sections = s
        sidebar.reloadData()
        if let row = sections.firstIndex(where: { $0.1 == section }) { sidebar.selectRowIndexes([row], byExtendingSelection: false) }
    }

    /// Locks the window now (menu: Lock history now). It asks again the next time it is opened.
    func lockNow() { Authentication.lockNow(); locked = true; reloadList() }

    /// Shows the settings or About pane for their sections, and the list and preview for every other section.
    private func updateChrome() {
        // While locked, Settings and About are hidden too: the lock covers the whole app, not only the list.
        let isSettings = section == .settings && !locked, isAbout = section == .about && !locked
        listPaneRef?.isHidden = isSettings || isAbout || locked
        settingsHost.isHidden = !isSettings
        aboutScroll.isHidden = !isAbout
        if isSettings, let root = settingsRoot, root.superview !== settingsHost {
            settingsHost.subviews.forEach { $0.removeFromSuperview() }
            root.translatesAutoresizingMaskIntoConstraints = false
            settingsHost.addSubview(root)
            NSLayoutConstraint.activate([root.topAnchor.constraint(equalTo: settingsHost.topAnchor), root.bottomAnchor.constraint(equalTo: settingsHost.bottomAnchor),
                                         root.leadingAnchor.constraint(equalTo: settingsHost.leadingAnchor), root.trailingAnchor.constraint(equalTo: settingsHost.trailingAnchor)])
        }
        if isAbout { aboutScroll.documentView = aboutText() }
        let plain = !isSettings && !isAbout
        previewScroll.isHidden = !plain
        previewImage.isHidden = true
        snippetBox.isHidden = true
        actions.isHidden = !plain
        window.contentView?.needsLayout = true   // a pane was shown or hidden: place the panes again
    }

    /// The About text: version from the app bundle, what the app does, and where the licence and notices are.
    private func aboutText() -> NSTextView {
        let v = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.2.0"
        let t = NSTextView(); t.isEditable = false; t.drawsBackground = false; t.textContainerInset = NSSize(width: 22, height: 22)
        t.isVerticallyResizable = true; t.isHorizontallyResizable = false; t.autoresizingMask = [.width]
        t.textContainer?.widthTracksTextView = true; t.minSize = NSSize(width: 0, height: 0); t.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        t.string = ["WhatClip \(v)", "", "A clipboard history for macOS. Everything stays on this Mac: no account, no network, no telemetry.", "", "Open the picker with the shortcut in Settings (⇧⌘V by default). Copies from password managers are never recorded.", "", "Licence: MIT. Source and notices: README.md, THIRD_PARTY_NOTICES.md and LICENSE in the project repository."].joined(separator: "\n")
        t.font = .systemFont(ofSize: 14); t.textColor = .labelColor
        return t
    }

    func reloadList() {
        updateChrome()
        // Settings and About own the whole detail pane: nothing else to load.
        if !locked && (section == .settings || section == .about) { return }
        if locked { items = []; list.reloadData(); showDetail(nil); preview.string = "Locked. Unlock with Touch ID or your Mac password to see your history and settings."; return }
        if section == .snippets {
            snippets = (try? store.snippets(query: search.stringValue)) ?? []
            list.reloadData()
            snippetBox.isHidden = selectedSnippet == nil; previewScroll.isHidden = selectedSnippet != nil
            if selectedSnippet == nil { preview.string = "Choose a snippet, or create one with the New snippet button." }
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
        case .snippets, .header, .settings, .about: break
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
                return h
            }
            let l = NSTextField(labelWithString: "")
            let out = NSMutableAttributedString()
            if case .board(let id) = sec, let b = (try? store.boards())?.first(where: { $0.id == id }) {
                out.append(NSAttributedString(string: "● ", attributes: [.foregroundColor: Self.colour(b.colorName), .font: NSFont.systemFont(ofSize: 13)]))
            }
            out.append(NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 13)]))
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
        guard section != .settings, section != .about, section != .snippets, items.indices.contains(index) else { return nil }
        let menu = NSMenu()
        for m in ItemActions.menuItems(for: items[index], store: store, changed: { [weak self] in self?.reloadList() }) { menu.addItem(m) }
        return menu
    }

    /// Right-click on a list row: edit, pin, favourite or delete that item.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard section != .settings, section != .about, section != .snippets, items.indices.contains(list.clickedRow) else { return }
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
        return sections[row].1 == .header ? 26 : 24
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        if (notification.object as? NSTableView) == sidebar {
            guard sidebar.selectedRow >= 0 else { return }
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
        if case .board = section { actions.addArrangedSubview(button("Edit board…", #selector(editBoard))) }
        guard let i else { preview.string = "Nothing here yet."; previewImage.isHidden = true; preview.isHidden = false; return }
        if i.kind == .image || i.kind == .gif, let d = store.payloadData(for: i), let img = NSImage(data: d) {
            previewImage.image = img; previewImage.isHidden = false; preview.isHidden = true
        } else {
            previewImage.isHidden = true; preview.isHidden = false
            var body = i.secretKinds.isEmpty ? i.listTitle : "Hidden secret: \(i.secretKinds.map(\.rawValue).joined(separator: ", "))"
            let ocr = store.ocrText(for: i.id)
            if !ocr.isEmpty { body += "\n\n— Text in this image —\n" + ocr }
            preview.string = String(body.prefix(20_000))
        }
        // Primary actions stay visible; everything else lives in one More menu, so the row never overflows.
        actions.addArrangedSubview(button("Copy", #selector(copyItem)))
        actions.addArrangedSubview(button(i.pinned ? "Unpin" : "Pin", #selector(togglePin)))
        actions.addArrangedSubview(button(i.favorite ? "Unfavourite" : "Favourite", #selector(toggleFavorite)))
        actions.addArrangedSubview(menuButton("More", moreMenu(i)))
        let n = list.selectedRowIndexes.count
        let del = button(n > 1 ? "Delete \(n) items" : "Delete", #selector(deleteItem))
        del.contentTintColor = .systemRed
        actions.addArrangedSubview(del)
    }

    private func menuButton(_ title: String, _ menu: NSMenu) -> NSButton {
        let b = NSButton(title: title, target: nil, action: nil); b.bezelStyle = .rounded
        b.menu = menu; b.target = self; b.action = #selector(showMenu(_:)); return b
    }
    @objc private func showMenu(_ sender: NSButton) {
        guard let m = sender.menu else { return }
        m.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
    }
    private func boardMenu() -> NSMenu {
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
            let it = NSMenuItem(title: t.title, action: #selector(runTool(_:)), keyEquivalent: ""); it.target = self; it.representedObject = t.rawValue; m.addItem(it)
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
        sub("Add to board", boardMenu())
        if i.kind == .text || i.kind == .richText || i.kind == .url {
            sub("Text tools", toolsMenu())
            sub("Paste as…", pasteFormatMenu())
            let smart = SmartRecognizer.find(in: i.text)
            if !smart.isEmpty { sub("Smart actions", smartMenu(smart)) }
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
            let it = NSMenuItem(title: f.title, action: #selector(pasteAs(_:)), keyEquivalent: ""); it.target = self; it.representedObject = f.rawValue; m.addItem(it)
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
        guard let i = selectedItem, let d = store.payloadData(for: i), let a = AnnotateController(imageData: d, store: store, monitor: monitor) else { return }
        annotators.append(a); a.show()
    }
    private var annotators: [AnnotateController] = []

    @objc private func copyItem() { guard let i = selectedItem else { return }; monitor.restore(i) }

    /// ⌘F from the menu: move the cursor to the search field.
    @objc func focusSearch() { window.makeKeyAndOrderFront(nil); window.makeFirstResponder(search) }
    @objc private func togglePin() { guard let i = selectedItem else { return }; try? store.setPinned(i.id, !i.pinned); reloadList() }
    @objc private func deleteItem() {
        // Batch delete: every selected row goes, after one confirmation when more than one is selected.
        let picked = list.selectedRowIndexes.compactMap { items[safe: $0]?.id }
        guard !picked.isEmpty else { return }
        if picked.count > 1 {
            let a = NSAlert(); a.messageText = "Delete \(picked.count) items?"; a.informativeText = "Pinned items are deleted too. This cannot be undone."
            a.addButton(withTitle: "Delete"); a.addButton(withTitle: "Cancel")
            guard a.runModal() == .alertFirstButtonReturn else { return }
        }
        try? store.delete(picked); reloadList()
    }
    @objc private func editTags() {
        guard let i = selectedItem else { return }
        let alert = NSAlert(); alert.messageText = "Tags"; alert.informativeText = "Separate tags with commas, for example work, invoice."
        alert.addButton(withTitle: "Save"); alert.addButton(withTitle: "Cancel")
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
        let alert = NSAlert(); alert.messageText = title; alert.addButton(withTitle: "Save"); alert.addButton(withTitle: "Cancel")
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
        let f = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24)); f.placeholderString = "Board name"; f.stringValue = name
        let pop = NSPopUpButton(); pop.addItems(withTitles: BoardColor.allCases.map(\.title))
        pop.selectItem(at: BoardColor.allCases.firstIndex { $0.rawValue == colour } ?? 0)
        stack.addArrangedSubview(f); stack.addArrangedSubview(pop)
        stack.frame = NSRect(x: 0, y: 0, width: 260, height: 60)
        alert.accessoryView = stack
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let clean = f.stringValue.trimmingCharacters(in: .whitespaces)
        return clean.isEmpty ? nil : (clean, BoardColor.allCases[pop.indexOfSelectedItem])
    }

    @objc private func newBoard() {
        guard let (name, colour) = boardDialog(title: "New board", name: "", colour: "blue") else { return }
        _ = try? store.addBoard(name: name, color: colour.rawValue); reloadSidebar()
    }
    /// Renames and recolours the board in view.
    @objc func editBoard() {
        guard case .board(let id) = section, let b = (try? store.boards())?.first(where: { $0.id == id }),
              let (name, colour) = boardDialog(title: "Edit board", name: b.name, colour: b.colorName) else { return }
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
        if let s = try? store.addSnippet(title: "New snippet", body: "") { selectedSnippet = s }
        reloadList(); reloadSidebar()
        if let row = snippets.firstIndex(where: { $0.id == selectedSnippet?.id }) { list.selectRowIndexes([row], byExtendingSelection: false) }
    }
    @objc private func saveSnippet() {
        guard var s = selectedSnippet else { return }
        s.title = snippetTitle.stringValue.isEmpty ? "Untitled" : snippetTitle.stringValue
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
            let alert = NSAlert(); alert.messageText = "Fill in \(s.title)"; alert.addButton(withTitle: "Copy"); alert.addButton(withTitle: "Cancel")
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

    init(panes: [NSView], widths: [CGFloat?]) {
        self.panes = panes; self.widths = widths
        super.init(frame: .zero)
        for p in panes { addSubview(p) }
    }
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let visible = panes.filter { !$0.isHidden }
        var x: CGFloat = 0
        for (i, pane) in panes.enumerated() {
            if pane.isHidden { continue }
            let isLast = pane === visible.last
            let w: CGFloat = isLast ? max(0, bounds.width - x) : (widths[i] ?? 0)
            pane.frame = NSRect(x: x, y: 0, width: w, height: bounds.height)
            x += w + divider
            if !isLast { addDividerIfNeeded(after: pane, at: x - divider) }
        }
    }

    private var dividers: [NSView] = []
    private func addDividerIfNeeded(after pane: NSView, at x: CGFloat) {
        let d: NSView
        if let existing = dividers.first(where: { $0.superview === self && $0.identifier?.rawValue == "\(panes.firstIndex(of: pane) ?? 0)" }) {
            d = existing
        } else {
            d = NSView(); d.wantsLayer = true; d.layer?.backgroundColor = NSColor.separatorColor.cgColor
            d.identifier = NSUserInterfaceItemIdentifier("\(panes.firstIndex(of: pane) ?? 0)")
            addSubview(d); dividers.append(d)
        }
        d.frame = NSRect(x: x, y: 0, width: divider, height: bounds.height)
    }
}
