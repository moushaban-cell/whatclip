import AppKit
import WhatClipCore

@MainActor
extension HistoryWindowController {

    @objc func newSnippet() {
        section = .snippets; selectedSnippet = nil
        if let s = try? store.addSnippet(title: Lang.t("ui.newSnippet"), body: "") { selectedSnippet = s }
        reloadList(); reloadSidebar()
        if let row = snippets.firstIndex(where: { $0.id == selectedSnippet?.id }) { list.selectRowIndexes([row], byExtendingSelection: false) }
    }
    @objc func saveSnippet() {
        guard var s = selectedSnippet else { return }
        s.title = snippetTitle.stringValue.isEmpty ? Lang.t("ui.untitled") : snippetTitle.stringValue
        s.folder = snippetFolder.stringValue; s.body = snippetBody.string; s.tags = snippetTags.stringValue
        try? store.updateSnippet(s); selectedSnippet = s; reloadList()
    }
    @objc func deleteSnippet() {
        guard let s = selectedSnippet else { return }
        do { try store.deleteSnippet(s.id) } catch { reportFailure(error) }
        selectedSnippet = nil; reloadList()
    }
    /// Used by the menu bar: fill in and copy a snippet without opening the editor.
    func insertSnippetFromMenu(_ snip: Snippet) {
        selectedSnippet = snip; snippetBody.string = snip.body
        insertSnippet()
    }

    @objc func insertSnippet() {
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
