import AppKit
import WhatClipCore

@MainActor
extension HistoryWindowController {
    func showDetail(_ i: ClipItem?) {
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
    @objc func showMenu(_ sender: NSButton) {
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
    func toolsMenu() -> NSMenu {
        let m = NSMenu()
        for t in TextTool.allCases {
            let it = NSMenuItem(title: Lang.t("tt." + t.rawValue), action: #selector(runTool(_:)), keyEquivalent: ""); it.target = self; it.representedObject = t.rawValue; m.addItem(it)
        }
        return m
    }
    func smartMenu(_ found: [(kind: SmartKind, value: String)]) -> NSMenu {
        let m = NSMenu()
        for f in found {
            let it = NSMenuItem(title: "Copy \(f.kind.rawValue): \(f.value)", action: #selector(copyValue(_:)), keyEquivalent: ""); it.target = self; it.representedObject = f.value; m.addItem(it)
        }
        return m
    }

    /// Everything that is not a primary action, grouped the way people look for it.
    func moreMenu(_ i: ClipItem) -> NSMenu {
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

    func pasteFormatMenu() -> NSMenu {
        let m = NSMenu()
        for f in PasteFormat.allCases {
            let it = NSMenuItem(title: Lang.t("pf." + f.rawValue), action: #selector(pasteAs(_:)), keyEquivalent: ""); it.target = self; it.representedObject = f.rawValue; m.addItem(it)
        }
        return m
    }
    @objc func pasteAs(_ s: NSMenuItem) {
        guard let i = selectedItem, let raw = s.representedObject as? String, let f = PasteFormat(rawValue: raw) else { return }
        monitor.restore(f.apply(i.text))
    }
    @objc func extractTextItem() {
        guard let i = selectedItem else { return }
        let text = store.ocrText(for: i.id)
        guard !text.isEmpty else { return }
        _ = try? store.add(text: text, sourceBundleID: i.sourceBundleID); reloadList()
    }

    @objc func annotateItem() {
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

    @objc func removeFromBoardTapped() {
        guard case .board(let id) = section, let i = selectedItem else { return }
        try? store.removeFromBoard(item: i.id, board: id); reloadList()
    }
    @objc func deleteBoardTapped() {
        guard case .board(let id) = section else { return }
        let alert = NSAlert(); alert.messageText = Lang.t("ui.board.delete"); alert.informativeText = Lang.t("ui.board.deleteInfo")
        alert.addButton(withTitle: Lang.t("ui.delete")); alert.addButton(withTitle: Lang.t("ui.cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do { try store.deleteBoard(id) } catch { reportFailure(error) }
        section = .all; reloadSidebar(); reloadList()
    }

    @objc func copyItem() { guard let i = selectedItem else { return }; monitor.restore(i) }

    /// ⌘F from the menu: move the cursor to the search field.
    @objc func focusSearch() { window.makeKeyAndOrderFront(nil); window.makeFirstResponder(search) }
    @objc func togglePin() { guard let i = selectedItem else { return }; try? store.setPinned(i.id, !i.pinned); reloadList() }
    @objc func deleteItem() {
        // Batch delete: every selected row goes, after one confirmation when more than one is selected.
        let picked = list.selectedRowIndexes.compactMap { items[safe: $0]?.id }
        guard !picked.isEmpty else { return }
        if picked.count > 1 {
            let a = NSAlert(); a.messageText = Lang.t("ui.deleteN", ["n": "\(picked.count)"]); a.informativeText = Lang.t("ui.deleteNInfo")
            a.addButton(withTitle: Lang.t("ui.delete")); a.addButton(withTitle: Lang.t("ui.cancel"))
            guard a.runModal() == .alertFirstButtonReturn else { return }
        }
        do { try store.delete(picked) } catch { reportFailure(error) }
        reloadList()
    }
    @objc func editTags() {
        guard let i = selectedItem else { return }
        let alert = NSAlert(); alert.messageText = Lang.t("ui.tags"); alert.informativeText = Lang.t("ui.tagsInfo")
        alert.addButton(withTitle: Lang.t("ui.save")); alert.addButton(withTitle: Lang.t("ui.cancel"))
        let f = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24)); f.stringValue = store.tags(for: i.id).joined(separator: ", ")
        alert.accessoryView = f
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        try? store.setTags(i.id, f.stringValue.split(separator: ",").map(String.init)); reloadList()
    }
    @objc func toggleFavorite() { guard let i = selectedItem else { return }; try? store.setFavorite(i.id, !i.favorite); reloadList() }
    @objc func addToBoard(_ s: NSMenuItem) { guard let i = selectedItem, let b = s.representedObject as? Int64 else { return }; try? store.addToBoard(item: i.id, board: b); reloadSidebar() }
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
    func boardDialog(title: String, name: String, colour: String) -> (String, BoardColor)? {
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

    @objc func newBoard() {
        guard let (name, colour) = boardDialog(title: Lang.t("ui.newBoard"), name: "", colour: "blue") else { return }
        _ = try? store.addBoard(name: name, color: colour.rawValue); reloadSidebar()
    }
    /// Renames and recolours the board in view.
    @objc func editBoard() {
        guard case .board(let id) = section, let b = (try? store.boards())?.first(where: { $0.id == id }),
              let (name, colour) = boardDialog(title: Lang.t("ui.editBoard"), name: b.name, colour: b.colorName) else { return }
        try? store.updateBoard(id, name: name, color: colour); reloadSidebar()
    }
    @objc func runTool(_ s: NSMenuItem) {
        guard let i = selectedItem, let raw = s.representedObject as? String, let tool = TextTool(rawValue: raw), let out = tool.apply(i.text) else { return }
        // A transformed text is a new item, so the original stays in history.
        _ = try? store.add(text: out, sourceBundleID: i.sourceBundleID); reloadList()
    }
    @objc func copyValue(_ s: NSMenuItem) { if let v = s.representedObject as? String { monitor.restore(v) } }
}
