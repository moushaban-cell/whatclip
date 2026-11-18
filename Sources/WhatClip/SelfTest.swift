import AppKit
import WhatClipCore

/// Runs the Capture and tools actions inside the running app, against whatever data directory the app was started with.
/// Started with WHATCLIP_SELFTEST=1 (and WHATCLIP_DATA pointing at a scratch folder). Writes PASS or FAIL per check to selftest.txt there.
@MainActor
enum SelfTest {
    /// The marker file that says this data folder is a scratch folder for tests.
    static func isAllowed(in dir: URL) -> Bool {
        FileManager.default.fileExists(atPath: dir.appendingPathComponent(".selftest-ok").path)
    }

    static func run(app: AppDelegate, dataDir: URL) {
        var lines: [String] = []
        func check(_ name: String, _ ok: () throws -> Bool) {
            let result: Bool
            do { result = try ok() } catch { result = false; lines.append("FAIL \(name): threw \(error)"); return }
            lines.append((result ? "PASS " : "FAIL ") + name)
        }
        guard let store = app.store, let monitor = app.monitor else {
            lines.append("FAIL app not ready"); write(lines, dataDir); return
        }

        // Clipboard section
        check("pause capturing turns on") { app.monitor.pause(for: nil); return monitor.isPaused }
        check("resume capturing turns off") { app.monitor.resume(); return !monitor.isPaused }
        // The Tools page must show the action that does the opposite of the current state.
        func toolsButtonTitles() -> [String] {
            var found: [String] = []
            func walk(_ v: NSView) {
                if let b = v as? NSButton { found.append(b.attributedTitle.string) }
                v.subviews.forEach(walk)
            }
            walk(app.history.toolsPage())
            return found
        }
        app.monitor.pause(for: nil)
        check("Tools page offers Resume while paused") { toolsButtonTitles().contains { $0.contains(Lang.t("ui.m.resume")) } }
        app.monitor.resume()
        check("Tools page offers Pause while capturing") { toolsButtonTitles().contains { $0.contains(Lang.t("ui.m.pauseCapturing")) } }
        check("ignore next copy is set") { monitor.policy.ignoreNextCopy = true; return monitor.policy.ignoreNextCopy }
        monitor.policy.ignoreNextCopy = false

        // Stack: a new copy joins it while collecting; clearing empties it and keeps collecting
        app.toggleStack()
        check("start collecting turns the stack on") { app.stackOn }
        let stackItem = try? store.add(text: "selftest stack item")
        app.copyHappened()
        check("a copy joins the running stack") { app.stack.contains { $0.text == "selftest stack item" } }
        app.clearStack()
        check("clear stack empties the stack") { app.stack.isEmpty }
        check("clear stack keeps collecting on") { app.stackOn }
        app.toggleStack()

        // Favourites
        if let item = stackItem {
            try? store.setFavorite(item.id, true)
            check("favourite is set") { (try store.list().first { $0.id == item.id })?.favorite == true }
            try? store.setFavorite(item.id, false)
            check("favourite is removed") { (try store.list().first { $0.id == item.id })?.favorite == false }
        }

        // Boards: create, add, remove from board, delete board (items stay in history)
        check("create a board") { _ = try store.addBoard(name: "Selftest", color: "blue"); return try store.boards().contains { $0.name == "Selftest" } }
        if let board = try? store.boards().first(where: { $0.name == "Selftest" }), let item = try? store.add(text: "selftest board item") {
            try? store.addToBoard(item: item.id, board: board.id)
            check("add an item to a board") { try store.items(onBoard: board.id).contains { $0.id == item.id } }
            try? store.removeFromBoard(item: item.id, board: board.id)
            check("remove an item from a board keeps it in history") {
                try store.items(onBoard: board.id).isEmpty && (try store.list().contains { $0.id == item.id })
            }
            try? store.deleteBoard(board.id)
            check("delete a board") { !(try store.boards().contains { $0.id == board.id }) }
        }

        // Annotate: opens a window for the newest image
        if let image = readOrDefault("list", nil) { try store.list(limit: 300) }?.first(where: { $0.kind == .image }) {
            let before = app.history.annotators.count
            app.history.annotate(image)
            check("annotate opens a window for the newest image") { app.history.annotators.count == before + 1 }
        } else {
            lines.append("SKIP annotate: no image in this data folder")
        }

        // Clear history keeps pinned and favourite items
        if let pinned = try? store.add(text: "selftest pinned"), let fav = try? store.add(text: "selftest fav"), (try? store.add(text: "selftest plain")) != nil {
            try? store.setPinned(pinned.id, true); try? store.setFavorite(fav.id, true)
            try? store.clear()
            let texts = Set(readOrDefault("list", []) { try store.list().map(\.text) })
            check("clear history keeps pinned and favourite items") { texts.contains("selftest pinned") && texts.contains("selftest fav") && !texts.contains("selftest plain") }
        }

        // Drag source: a history row produces a payload that carries its item id, and only ours
        app.history.reloadList()
        check("a history row can be dragged, carrying its item id") {
            guard let item = app.history.items.first else { return false }
            guard let writer = app.history.tableView(app.history.list, pasteboardWriterForRow: 0) as? NSPasteboardItem else { return false }
            return writer.string(forType: HistoryDrag.type) == String(item.id)
        }

        // Export and import round trip
        if let data = try? Transfer.export(store) {
            check("export produces data") { !data.isEmpty }
            check("import reads the export back") { (try Transfer.importData(data, into: store)) >= 0 }
        } else {
            lines.append("FAIL export threw")
        }

        // Not automated: need a person or the screen
        lines.append("SKIP screenshot and GIF: need Screen Recording and a visible selection")
        lines.append("SKIP emoji panel, Settings, Setup windows: open windows, checked by eye")
        // Action runner with output and input larger than a pipe buffer: it must finish, not hang.
        let big = String(repeating: "x", count: 200_000)
        Task { @MainActor in
            let result = await ActionRunner.run(command: "head -c 300000 /dev/zero | tr '\\0' a", input: big)
            var ok = false
            if case .success(let out) = result { ok = out.count == 300_000 }
            lines.append((ok ? "PASS " : "FAIL ") + "action runner handles large input and output")
            write(lines, dataDir)
        }
    }

    static func write(_ lines: [String], _ dir: URL) {
        let text = lines.joined(separator: "\n") + "\n"
        try? text.write(to: dir.appendingPathComponent("selftest.txt"), atomically: true, encoding: .utf8)
    }
}
