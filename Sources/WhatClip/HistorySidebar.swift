import AppKit
import WhatClipCore

@MainActor
extension HistoryWindowController {
    /// The sidebar in groups: History (what was copied), Library (saved things), Boards, Tools, App.
    /// Headers are shown but cannot be selected. "New board" is always the last row of Boards.
    func reloadSidebar() {
        var s: [(String, Section)] = [(Lang.t("ui.history"), .header), (Lang.t("ui.allItems"), .all), (Lang.t("ui.pinned"), .pinned), (Lang.t("ui.text"), .text), (Lang.t("ui.links"), .links),
                                      (Lang.t("ui.imagesGifs"), .images), (Lang.t("ui.files"), .files), (Lang.t("ui.textInImages"), .textInImages),
                                      (Lang.t("ui.library"), .header), (Lang.t("ui.favourites"), .library), (Lang.t("ui.snippets"), .snippets)]
        let boards = readOrDefault("boards", []) { try store.boards() }
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
}
