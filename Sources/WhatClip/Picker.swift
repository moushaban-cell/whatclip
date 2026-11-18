import AppKit
import QuickLookUI
import WhatClipCore

/// A panel that can take keyboard focus, and passes ⌘-key shortcuts to the picker before the text field sees them.
private final class KeyPanel: NSPanel {
    var onCommand: ((NSEvent) -> Bool)?
    override var canBecomeKey: Bool { true }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if onCommand?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }
}

/// The Windows-style picker: search, filters, previews, number shortcuts, pins, a paste queue and plain-text paste.
@MainActor
final class PickerController: NSObject, NSSearchFieldDelegate, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate, @preconcurrency QLPreviewPanelDataSource {
    enum Filter: Int, CaseIterable {
        case all, text, links, images, files, pinned, favorites
        @MainActor var title: String { [Lang.t("ui.all"), Lang.t("ui.text"), Lang.t("ui.links"), Lang.t("ui.images"), Lang.t("ui.files"), Lang.t("ui.pinned"), Lang.t("ui.favourites")][rawValue] }
        func keeps(_ i: ClipItem) -> Bool {
            switch self {
            case .all: true
            case .text: i.kind == .text || i.kind == .richText
            case .links: i.kind == .url
            case .images: i.kind == .image || i.kind == .gif
            case .files: i.kind == .file
            case .pinned: i.pinned
            case .favorites: i.favorite
            }
        }
    }

    private let panel: KeyPanel
    private let field = NSSearchField()
    private let filters = NSSegmentedControl(labels: Filter.allCases.map(\.title), trackingMode: .selectOne, target: nil, action: nil)
    private let table = NSTableView()
    private let preview = NSTextView()
    private let previewImage = NSImageView()
    private let status = NSTextField(labelWithString: "")
    private let datePop = NSPopUpButton()
    private let listScroll = NSScrollView()
    private let emptyHost = NSView()
    private var listPaneView = NSView()
    private let shelf = ShelfController()
    private let cardsButton = NSButton(title: Lang.t("ui.cards"), target: nil, action: nil)
    private var cardsOn = false
    private let appPop = NSPopUpButton()
    private let boardPop = NSPopUpButton()
    private var boardIDs: [Int64] = []
    private var appIDs: [String] = []
    private var items: [ClipItem] = []
    private var filter: Filter = .all
    private var queue: [ClipItem] = []
    private var locked = false
    private let store: ClipStore
    private let monitor: PasteboardMonitor
    private var previousApp: NSRunningApplication?

    init(store: ClipStore, monitor: PasteboardMonitor) {
        self.store = store; self.monitor = monitor
        panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 680, height: 440),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.minSize = NSSize(width: 520, height: 340)
        super.init()
        panel.titleVisibility = .hidden; panel.titlebarAppearsTransparent = true; panel.isFloatingPanel = true
        panel.level = .floating; panel.hidesOnDeactivate = true; panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.onCommand = { [weak self] e in self?.command(e) ?? false }

        field.placeholderString = Lang.t("ui.a11y.search"); field.delegate = self; field.font = .systemFont(ofSize: 15)
        field.setAccessibilityLabel(Lang.t("ui.a11y.search"))
        filters.target = self; filters.action = #selector(filterChanged); filters.selectedSegment = 0
        datePop.addItems(withTitles: [Lang.t("ui.date.any"), Lang.t("ui.date.hour"), Lang.t("ui.date.today"), Lang.t("ui.date.week")]); datePop.target = self; datePop.action = #selector(reloadFromControl)
        appPop.target = self; appPop.action = #selector(reloadFromControl); appPop.setAccessibilityLabel("Filter by app")
        boardPop.target = self; boardPop.action = #selector(reloadFromControl); boardPop.setAccessibilityLabel(Lang.t("ui.addToBoard"))
        datePop.setAccessibilityLabel(Lang.t("ui.a11y.date"))
        filters.segmentStyle = .texturedRounded

        let col = NSTableColumn(identifier: .init("row")); col.resizingMask = .autoresizingMask; table.addTableColumn(col)
        table.headerView = nil; table.dataSource = self; table.delegate = self; table.rowHeight = Design.rowHeight
        let rowMenu = NSMenu(); rowMenu.delegate = self; table.menu = rowMenu
        table.target = self; table.doubleAction = #selector(doubleClicked); table.allowsMultipleSelection = true; table.setAccessibilityLabel(Lang.t("ui.a11y.clipItems"))
        listScroll.documentView = table; listScroll.hasVerticalScroller = true; listScroll.borderType = .noBorder
        shelf.scroll.isHidden = true
        shelf.menuForItem = { [weak self] i in self?.contextMenu(forItem: i) }
        shelf.scroll.widthAnchor.constraint(equalToConstant: 360).isActive = true
        shelf.onSelect = { [weak self] i in self?.table.selectRowIndexes([i], byExtendingSelection: false); self?.updatePreview() }
        shelf.onActivate = { [weak self] i in self?.table.selectRowIndexes([i], byExtendingSelection: false); self?.choose(plain: false) }
        // Remember where the person moved the picker; it opens there next time. Moves the app makes itself are not remembered.
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if self?.placing == false { self?.rememberPosition() } }
        }
        cardsButton.setButtonType(.toggle); cardsButton.bezelStyle = .rounded; cardsButton.target = self; cardsButton.action = #selector(toggleCards)
        cardsButton.setAccessibilityLabel(Lang.t("ui.a11y.showCards"))

        preview.isEditable = false; preview.font = .systemFont(ofSize: 13); preview.textContainerInset = NSSize(width: 10, height: 10)
        preview.isVerticallyResizable = true; preview.isHorizontallyResizable = false; preview.autoresizingMask = [.width]
        preview.textContainer?.widthTracksTextView = true; preview.textColor = .labelColor; preview.backgroundColor = .textBackgroundColor
        let previewScroll = NSScrollView(); previewScroll.documentView = preview; previewScroll.hasVerticalScroller = true; previewScroll.borderType = .noBorder
        previewScroll.drawsBackground = true; previewScroll.backgroundColor = .textBackgroundColor
        previewImage.imageScaling = .scaleProportionallyUpOrDown; previewImage.isHidden = true
        let previewBox = NSStackView(views: [previewScroll, previewImage]); previewBox.orientation = .vertical
        previewScroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 280).isActive = true

        status.font = .systemFont(ofSize: 11); status.textColor = .secondaryLabelColor
        let hint = NSTextField(labelWithString: "↩ \(Lang.t("ui.hint.paste"))  ·  ⇧↩ \(Lang.t("ui.hint.plain"))  ·  ⌘1–9 \(Lang.t("ui.hint.pick"))  ·  ⌘D \(Lang.t("ui.hint.favourite"))  ·  ⌘B \(Lang.t("ui.hint.board"))  ·  ⌘⌫ \(Lang.t("ui.hint.delete"))  ·  \(Lang.t("ui.hint.more"))")
        hint.font = .systemFont(ofSize: 10); hint.textColor = .tertiaryLabelColor

        // The list and the empty state share one pane, so the empty state sits where the list would be.
        listPaneView = NSView()
        let listPane = listPaneView
        listScroll.translatesAutoresizingMaskIntoConstraints = false; emptyHost.translatesAutoresizingMaskIntoConstraints = false
        listPane.addSubview(listScroll); listPane.addSubview(emptyHost)
        NSLayoutConstraint.activate([
            listScroll.leadingAnchor.constraint(equalTo: listPane.leadingAnchor), listScroll.trailingAnchor.constraint(equalTo: listPane.trailingAnchor),
            listScroll.topAnchor.constraint(equalTo: listPane.topAnchor), listScroll.bottomAnchor.constraint(equalTo: listPane.bottomAnchor),
            emptyHost.leadingAnchor.constraint(equalTo: listPane.leadingAnchor), emptyHost.trailingAnchor.constraint(equalTo: listPane.trailingAnchor),
            emptyHost.topAnchor.constraint(equalTo: listPane.topAnchor), emptyHost.bottomAnchor.constraint(equalTo: listPane.bottomAnchor),
        ])
        listPane.widthAnchor.constraint(equalToConstant: 360).isActive = true
        emptyHost.isHidden = true
        let body = NSStackView(views: [listPane, shelf.scroll, previewBox]); body.distribution = .fill; body.spacing = 1
        let filterRow = NSStackView(views: [filters, datePop, appPop, boardPop, cardsButton]); filterRow.spacing = 8
        let stack = NSStackView(views: [field, filterRow, body, NSStackView(views: [status, hint])])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
        // Top inset clears the traffic-light buttons (close, minimise, zoom) that sit over the top edge.
        stack.edgeInsets = NSEdgeInsets(top: 34, left: 14, bottom: 12, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = stack
        stack.userInterfaceLayoutDirection = Lang.isRightToLeft ? .rightToLeft : .leftToRight
        if Lang.isRightToLeft { mirrorForRTL(stack) }
        field.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -24).isActive = true
        body.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -24).isActive = true
        // The body grows with the window (340 is the starting height, not a fixed one).
        let bodyHeight = body.heightAnchor.constraint(greaterThanOrEqualToConstant: 340)
        bodyHeight.priority = .defaultHigh; bodyHeight.isActive = true
        body.setContentHuggingPriority(.defaultLow, for: .vertical)
        body.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    }

    var isVisible: Bool { panel.isVisible }
    /// Called when the clipboard changes: the open picker shows the new item at once.
    func refreshIfVisible() { if panel.isVisible { reload() } }
    func toggle() { isVisible ? close() : show() }

    /// `anchor` is the status item's frame on screen, used for the "menu icon" placement.
    func show(anchor: NSRect? = nil, filter start: Filter = .all) {
        lastOpened = Date()
        previousApp = NSWorkspace.shared.frontmostApplication
        field.stringValue = ""; filter = start; filters.selectedSegment = start.rawValue
        // The picker (⌘X) never asks for Touch ID: quick paste must stay one step. The lock guards the main app (history, Settings).
        locked = false
        place(anchor: anchor)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(field)
        reload()
        if locked {
            Task { @MainActor in
                let ok = await Authentication.unlock(reason: Lang.t("ui.reasonOpen"))
                self.locked = !ok
                self.reload()
            }
        }
    }
    func close() { panel.orderOut(nil); Self.cleanPreviews() }
    /// True while the picker is on screen.
    var isOpen: Bool { panel.isVisible }
    /// True for a moment after the picker was asked to open. Activating the app then must not open the main window.
    var openedRecently: Bool { Date().timeIntervalSince(lastOpened) < 2 }
    private var lastOpened = Date.distantPast

    /// Puts the picker where the person chose: under the menu icon, at the pointer, or in the middle of the screen.
    private func place(anchor: NSRect?) {
        let size = panel.frame.size
        var origin: NSPoint
        if let remembered = UserDefaults.standard.string(forKey: Self.positionKey).map(NSPointFromString), remembered != .zero {
            origin = remembered
        } else {
        switch monitor.settings.popupPlacement {
        case .menuIcon:
            if let a = anchor { origin = NSPoint(x: a.midX - size.width / 2, y: a.minY - size.height - 4) }
            else { origin = NSPoint(x: NSScreen.main?.frame.midX ?? 400 - size.width / 2, y: NSScreen.main?.frame.midY ?? 400) }
        case .cursor:
            let m = NSEvent.mouseLocation
            origin = NSPoint(x: m.x - size.width / 2, y: m.y - size.height)
        case .screenCenter:
            let f = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
            origin = NSPoint(x: f.midX - size.width / 2, y: f.midY - size.height / 2)
        }
        }
        // Keep the panel on the visible screen.
        if let f = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
            origin.x = min(max(origin.x, f.minX + 8), f.maxX - size.width - 8)
            origin.y = min(max(origin.y, f.minY + 8), f.maxY - size.height - 8)
        }
        placing = true; panel.setFrameOrigin(origin); placing = false
    }

    private static let positionKey = "picker.origin"
    private var placing = false
    private func rememberPosition() { UserDefaults.standard.set(NSStringFromPoint(panel.frame.origin), forKey: Self.positionKey) }

    @objc private func filterChanged() { filter = Filter(rawValue: filters.selectedSegment) ?? .all; reload() }
    @objc private func reloadFromControl() { reload() }

    /// Switches the picker between the list and the visual shelf of cards. Selection is shared.
    @objc private func toggleCards() {
        cardsOn = cardsButton.state == .on
        // Cards replace the whole list pane, so the list's column does not stay empty.
        listPaneView.isHidden = cardsOn; shelf.scroll.isHidden = !cardsOn
        if cardsOn { emptyHost.isHidden = true }
        if cardsOn { shelf.reload(items, store: store); shelf.select(Set(table.selectedRowIndexes)) }
    }

    /// Date and app filters, read from the popups.
    private func storeFilter() -> ClipStore.Filter {
        var f = ClipStore.Filter()
        let now = Date()
        switch datePop.indexOfSelectedItem {
        case 1: f.since = now.addingTimeInterval(-3600)
        case 2: f.since = Calendar.current.startOfDay(for: now)
        case 3: f.since = now.addingTimeInterval(-7 * 86_400)
        default: break
        }
        if appPop.indexOfSelectedItem > 0, appIDs.indices.contains(appPop.indexOfSelectedItem - 1) { f.source = appIDs[appPop.indexOfSelectedItem - 1] }
        return f
    }

    /// The board list, kept in step with the boards that exist. The chosen board stays chosen when the list changes.
    private func refreshBoardPopup() {
        let current = boardPop.indexOfSelectedItem > 0 ? boardIDs[safe: boardPop.indexOfSelectedItem - 1] : nil
        let boards = (try? store.boards()) ?? []
        boardPop.removeAllItems()
        boardPop.addItem(withTitle: Lang.t("ui.anyBoard"))
        boardIDs = boards.map(\.id)
        for b in boards { boardPop.addItem(withTitle: b.name) }
        if let current, let i = boardIDs.firstIndex(of: current) { boardPop.selectItem(at: i + 1) }
    }
    /// ⌘B: files the selected items into a board, from the picker, without opening the History window.
    private func addSelectedToBoard() {
        let picked = table.selectedRowIndexes.compactMap { items[safe: $0] }
        guard !picked.isEmpty else { return }
        let boards = (try? store.boards()) ?? []
        guard !boards.isEmpty else {
            let alert = NSAlert(); alert.messageText = Lang.t("ui.board.noneYet"); alert.runModal(); return
        }
        let menu = NSMenu()
        for b in boards {
            menu.addItem(closureMenuItem(b.name) { [weak self] in
                for i in picked { try? self?.store.addToBoard(item: i.id, board: b.id) }
                self?.reload()
            })
        }
        menu.popUp(positioning: nil, at: NSPoint(x: table.bounds.midX, y: table.bounds.midY), in: table)
    }

    private func refreshAppPopup() {
        let current = appPop.indexOfSelectedItem > 0 ? appIDs[safe: appPop.indexOfSelectedItem - 1] : nil
        appIDs = (try? store.sourceApps()) ?? []
        appPop.removeAllItems()
        appPop.addItem(withTitle: Lang.t("ui.anyApp"))
        for id in appIDs { appPop.addItem(withTitle: Design.appName(id) ?? id) }
        if let current, let i = appIDs.firstIndex(of: current) { appPop.selectItem(at: i + 1) }
    }

    func reload() {
        if locked { items = []; table.reloadData(); preview.string = Lang.t("ui.lockedPicker"); previewImage.isHidden = true; return }
        var found = (try? store.list(query: monitor.settings.fuzzySearch ? "" : field.stringValue, limit: 500, filter: storeFilter())) ?? []
        if monitor.settings.fuzzySearch, !field.stringValue.isEmpty { found = found.filter { FuzzyMatch.matches(field.stringValue, in: $0.text) } }
        refreshAppPopup()
        refreshBoardPopup()
        // A chosen board shows only its items; the search text still applies to them.
        if boardPop.indexOfSelectedItem > 0, boardIDs.indices.contains(boardPop.indexOfSelectedItem - 1) {
            let onBoard = (try? store.items(onBoard: boardIDs[boardPop.indexOfSelectedItem - 1])) ?? []
            let q = field.stringValue
            found = q.isEmpty ? onBoard : onBoard.filter { $0.text.localizedCaseInsensitiveContains(q) }
        }
        items = found.filter(filter.keeps)
        if cardsOn { shelf.reload(items, store: store) }
        table.reloadData()
        if !items.isEmpty { table.selectRowIndexes([0], byExtendingSelection: false) }
        updateEmptyState()
        updatePreview()
        status.stringValue = (items.count == 1 ? Lang.t("ui.items.one") : Lang.t("ui.items.many", ["n": "\(items.count)"])) + (queue.isEmpty ? "" : " " + Lang.t("ui.stackCount", ["n": "\(queue.count)"]))
    }

    func controlTextDidChange(_ obj: Notification) { reload() }

    /// Shown in place of the list when there is nothing to show.
    private func updateEmptyState() {
        emptyHost.subviews.forEach { $0.removeFromSuperview() }
        guard items.isEmpty else { emptyHost.isHidden = true; return }
        let text = !field.stringValue.isEmpty ? Lang.t("ui.noMatch", ["q": field.stringValue])
            : (filter == .all ? Lang.t("ui.nothingYet") : Lang.t("ui.nothingIn", ["kind": filter.title.lowercased()]))
        let detail = field.stringValue.isEmpty ? Lang.t("ui.copyHint") : Lang.t("ui.tryShorter")
        let view = Design.emptyState(symbol: "doc.on.clipboard", title: text, detail: detail)
        view.translatesAutoresizingMaskIntoConstraints = false
        emptyHost.addSubview(view)
        NSLayoutConstraint.activate([view.centerXAnchor.constraint(equalTo: emptyHost.centerXAnchor), view.centerYAnchor.constraint(equalTo: emptyHost.centerYAnchor)])
        emptyHost.isHidden = false
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        switch sel {
        case #selector(NSResponder.moveDown(_:)): move(1); return true
        case #selector(NSResponder.moveUp(_:)): move(-1); return true
        case #selector(NSResponder.insertNewline(_:)):
            let e = NSApp.currentEvent
            if e?.modifierFlags.contains(.option) == true { addToQueue(); return true }
            choose(plain: e?.modifierFlags.contains(.shift) == true); return true
        case #selector(NSResponder.cancelOperation(_:)): close(); return true
        default: return false
        }
    }

    /// ⌘1–9 choose a visible item, ⌘P pin/unpin, ⌘⌫ delete. Returns true when handled.
    private func command(_ e: NSEvent) -> Bool {
        guard e.modifierFlags.contains(.command), let ch = e.charactersIgnoringModifiers else { return false }
        if let n = Int(ch), (1...9).contains(n) {
            guard items.indices.contains(n - 1) else { return true }
            table.selectRowIndexes([n - 1], byExtendingSelection: false); choose(plain: false); return true
        }
        if ch == "p" { togglePin(); return true }
        if ch == "y" { quickLook(); return true }
        if ch == "e" { extractText(); return true }
        if ch == "d" { toggleFavorite(); return true }
        if ch == "b" { addSelectedToBoard(); return true }
        if e.keyCode == 51 { deleteSelected(); return true }     // ⌘⌫
        return false
    }

    private func move(_ d: Int) {
        guard !items.isEmpty else { return }
        let r = max(0, min(items.count - 1, table.selectedRow + d))
        table.selectRowIndexes([r], byExtendingSelection: false); table.scrollRowToVisible(r)
    }

    private var selected: ClipItem? { items.indices.contains(table.selectedRow) ? items[table.selectedRow] : nil }
    /// The newest selection is the one previewed and acted on; multi-select is for deleting.

    @objc private func doubleClicked() { choose(plain: false) }

    func choose(plain: Bool) {
        guard let item = selected else { return }
        if plain, item.kind != .file, item.kind != .image, item.kind != .gif { monitor.restore(item.text) } else { monitor.restore(item) }
        close()
        // Auto-paste: the item is on the clipboard now; paste it into the app the person was using.
        // Without the Accessibility permission, WhatClip asks macOS for it, and the item stays on the clipboard for ⌘V.
        if monitor.settings.autoPaste {
            if AutoPaste.isTrusted { AutoPaste.paste(into: previousApp) } else { AutoPaste.askOnce() }
        }
    }

    private func addToQueue() {
        guard let item = selected else { return }
        queue.append(item); status.stringValue = Lang.t("ui.addedQueue", ["n": "\(queue.count)"])
    }
    /// Puts the next queued item on the clipboard and pastes it (when Accessibility allows). Used from the menu.
    func pasteNextFromQueue() -> Bool {
        guard !queue.isEmpty else { return false }
        let next = queue.removeFirst()
        monitor.restore(next)
        if AXIsProcessTrusted() { DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { Self.sendPaste() } }
        return true
    }
    func clearQueue() { queue.removeAll() }
    var queueCount: Int { queue.count }

    /// ⌘Y: Quick Look at the selected item. Items are written decrypted to a private temporary folder for the preview.
    private var previewURLs: [URL] = []
    private func quickLook() {
        guard let i = selected, let url = previewFile(for: i) else { return }
        previewURLs = [url]
        let panel = QLPreviewPanel.shared()
        panel?.dataSource = self
        panel?.makeKeyAndOrderFront(nil)
        panel?.reloadData()
    }
    private func previewFile(for i: ClipItem) -> URL? {
        if i.kind == .file, let first = i.text.split(separator: "\n").first { return URL(fileURLWithPath: String(first)) }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("whatclip-preview", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let ext: String
        let bytes: Data
        if let data = monitor.store.payloadData(for: i) {
            bytes = data
            // The file type follows the payload, so Quick Look opens it with the right viewer.
            let byType = ["public.png": "png", "public.jpeg": "jpg", "public.tiff": "tiff", "public.rtf": "rtf", "public.html": "html", "com.compuserve.gif": "gif"]
            ext = i.kind == .gif ? "gif" : (byType[i.payloadType ?? ""] ?? "bin")
        } else {
            bytes = Data(i.text.utf8); ext = "txt"
        }
        let url = dir.appendingPathComponent(UUID().uuidString + "." + ext)
        guard (try? bytes.write(to: url, options: .atomic)) != nil else { return nil }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { previewURLs.count }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! { previewURLs[index] as NSURL }

    /// ⌘E: text read from a copied image becomes a new text item.
    private func extractText() {
        guard let i = selected, i.kind == .image || i.kind == .gif else { return }
        let text = store.ocrText(for: i.id)
        guard !text.isEmpty else { status.stringValue = Lang.t("ui.noTextImage"); return }
        do { _ = try store.add(text: text, sourceBundleID: i.sourceBundleID) } catch { reportFailure(error) }
        reload()
    }

    /// Opens the picker on a given section (used by the menu-bar submenus).
    /// Opens with the cards shelf already on (launch option for testing).
    func showCards() { cardsButton.state = .on; toggleCards(); show() }

    func showSection(_ f: Filter) {
        show(filter: f)
    }

    private func toggleFavorite() {
        guard let item = selected else { return }
        do { try store.setFavorite(item.id, !item.favorite) } catch { reportFailure(error) }
        reload()
    }

    /// Removes the decrypted preview copies. Called when the picker closes and at launch and quit.
    static func cleanPreviews() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("whatclip-preview", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
    }

    private func togglePin() {
        guard let item = selected else { return }
        do { try store.setPinned(item.id, !item.pinned) } catch { reportFailure(error) }
        reload()
    }
    /// Deletes every selected item (multi-select with Shift or Command clicks).
    private func deleteSelected() {
        let ids = table.selectedRowIndexes.compactMap { items[safe: $0]?.id }
        guard !ids.isEmpty else { return }
        do { try store.delete(ids) } catch { reportFailure(error) }
        reload()
    }

    static func sendPasteShortcut() { sendPaste() }

    private static func sendPaste() {
        // Only into another app: never into WhatClip itself.
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        AutoPaste.postCommandV()
    }

    // MARK: table

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        Design.row(for: items[row], index: row, store: store)
    }

    func tableViewSelectionDidChange(_ notification: Notification) { updatePreview() }

    /// The person's actions, from Settings.
    func currentActions() -> [UserAction] { UserAction.parse(monitor.settings.actionsText) }

    /// The right-click menu for one item, the same as a list row.
    func contextMenu(forItem index: Int) -> NSMenu? {
        guard items.indices.contains(index) else { return nil }
        let menu = NSMenu()
        for m in ItemActions.menuItems(for: items[index], store: store, changed: { [weak self] in self?.reload() }) { menu.addItem(m) }
        for m in ItemActions.actionItems(for: items[index], actions: currentActions(), store: store, changed: { [weak self] in self?.reload() }) { menu.addItem(m) }
        return menu
    }

    /// Right-click on a row: edit, pin, favourite or delete that item.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let row = table.clickedRow as Int?, items.indices.contains(row) else { return }
        let item = items[row]
        for m in ItemActions.menuItems(for: item, store: store, changed: { [weak self] in self?.reload() }) { menu.addItem(m) }
    }

    private func updatePreview() {
        guard let i = selected else { preview.string = ""; previewImage.isHidden = true; return }
        if i.kind == .image || i.kind == .gif, let data = monitor.store.payloadData(for: i), let img = NSImage(data: data) {
            previewImage.image = img; previewImage.isHidden = false; preview.isHidden = true
            return
        }
        previewImage.isHidden = true; preview.isHidden = false
        preview.string = i.secretKinds.isEmpty ? String(i.listTitle.prefix(4000)) : Lang.t("ui.hiddenSecret", ["kinds": i.secretKinds.map(\.rawValue).joined(separator: ", ")]) + "\n" + Lang.t("ui.hiddenSecretMasked")
    }

    static func oneLine(_ s: String) -> String {
        let t = s.split(whereSeparator: \.isNewline).first.map(String.init) ?? s
        return t.count > 90 ? String(t.prefix(90)) + "…" : t
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
