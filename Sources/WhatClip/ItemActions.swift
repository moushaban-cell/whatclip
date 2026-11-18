import AppKit
import WhatClipCore

/// Holds one action for a menu item (the menu keeps a strong reference through representedObject).
@MainActor
final class ItemAction: NSObject {
    let run: () -> Void
    init(_ run: @escaping () -> Void) { self.run = run }
    @objc func fire() { run() }
}

/// The actions on one item, shared by the picker and the history list: edit text, pin, favourite, delete.
@MainActor
enum ItemActions {
    static func menuItems(for item: ClipItem, store: ClipStore, changed: @escaping () -> Void) -> [NSMenuItem] {
        var out: [NSMenuItem] = []
        func add(_ title: String, _ act: @escaping () -> Void) {
            let a = ItemAction(act)
            let m = NSMenuItem(title: title, action: #selector(ItemAction.fire), keyEquivalent: "")
            m.target = a; m.representedObject = a
            out.append(m)
        }
        if item.kind == .text || item.kind == .url || item.kind == .richText {
            add(Lang.t("ui.editTextMore")) { editText(item, store: store, changed: changed) }
        }
        add(item.pinned ? Lang.t("ui.unpin") : Lang.t("ui.pin")) { try? store.setPinned(item.id, !item.pinned); changed() }
        add(item.favorite ? Lang.t("ui.unfav") : Lang.t("ui.fav")) { try? store.setFavorite(item.id, !item.favorite); changed() }
        add(Lang.t("ui.deleteMore")) { confirmDelete(item, store: store, changed: changed) }
        return out
    }

    /// Lang.t("ui.runAction") items for a text item: each of the person's own actions. The output becomes a new item.
    static func actionItems(for item: ClipItem, actions: [UserAction], store: ClipStore, changed: @escaping () -> Void) -> [NSMenuItem] {
        guard item.kind == .text || item.kind == .url || item.kind == .richText, !actions.isEmpty else { return [] }
        let parent = NSMenuItem(title: Lang.t("ui.runAction"), action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for act in actions {
            let a = ItemAction {
                Task { @MainActor in
                    switch await ActionRunner.run(command: act.command, input: item.text) {
                    case .success(let out):
                        let text = out.trimmingCharacters(in: .newlines)
                        if !text.isEmpty { _ = try? store.add(text: text, sourceBundleID: item.sourceBundleID); changed() }
                    case .failure:
                        let alert = NSAlert(); alert.messageText = Lang.t("ui.actionFailed", ["name": act.name])
                        alert.informativeText = Lang.t("ui.actionFailedInfo"); alert.runModal()
                    }
                }
            }
            let m = NSMenuItem(title: act.name, action: #selector(ItemAction.fire), keyEquivalent: "")
            m.target = a; m.representedObject = a
            sub.addItem(m)
        }
        parent.submenu = sub
        return [parent]
    }

    /// Edits the text of a text item in a sheet. A text that already exists in history is refused, with a message.
    static func editText(_ item: ClipItem, store: ClipStore, changed: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = Lang.t("ui.editText")
        alert.informativeText = Lang.t("ui.editTextInfo")
        alert.addButton(withTitle: Lang.t("ui.save")); alert.addButton(withTitle: Lang.t("ui.cancel"))
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 420, height: 160))
        scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 160))
        text.string = item.text; text.isRichText = false; text.font = .systemFont(ofSize: 13)
        text.isVerticallyResizable = true; text.isHorizontallyResizable = false; text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true; text.isEditable = true
        scroll.documentView = text
        alert.accessoryView = scroll
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let new = text.string
        guard !new.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do { try store.updateText(item.id, to: new); changed() }
        catch {
            let a = NSAlert(); a.messageText = Lang.t("ui.duplicate")
            a.informativeText = Lang.t("ui.nothingChanged"); a.runModal()
        }
    }

    /// Deletes one item after a confirmation. Pinned and favourite items are deleted too, when you confirm.
    static func confirmDelete(_ item: ClipItem, store: ClipStore, changed: @escaping () -> Void) {
        let a = NSAlert(); a.messageText = Lang.t("ui.deleteItemQ")
        a.informativeText = Lang.t("ui.deleteItemInfo")
        a.addButton(withTitle: Lang.t("ui.delete")); a.addButton(withTitle: Lang.t("ui.cancel"))
        a.buttons.first?.hasDestructiveAction = true
        guard a.runModal() == .alertFirstButtonReturn else { return }
        try? store.delete(item.id); changed()
    }
}
