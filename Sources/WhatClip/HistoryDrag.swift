import AppKit
import WhatClipCore

/// Drag an item from the history list onto a board in the sidebar to file it there. The item stays in history.
enum HistoryDrag {
    /// Our own pasteboard type, so a drop only ever carries a history item id, never arbitrary text.
    static let type = NSPasteboard.PasteboardType("app.whatclip.history-item")
}

@MainActor
extension HistoryWindowController {
    /// The list supplies the dragged item's id. Only list rows can be dragged.
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard tableView == list, items.indices.contains(row) else { return nil }
        let pb = NSPasteboardItem()
        pb.setString(String(items[row].id), forType: HistoryDrag.type)
        return pb
    }

    /// A board row accepts the drop; other sidebar rows do not.
    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int,
                   proposedDropOperation op: NSTableView.DropOperation) -> NSDragOperation {
        guard tableView == sidebar, info.draggingPasteboard.types?.contains(HistoryDrag.type) == true else { return [] }
        guard sections.indices.contains(row), case .board = sections[row].1 else { return [] }
        tableView.setDropRow(row, dropOperation: .on)
        return .copy
    }

    /// Files the dragged item on the board it was dropped on.
    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int,
                   dropOperation op: NSTableView.DropOperation) -> Bool {
        guard tableView == sidebar, sections.indices.contains(row), case .board(let boardID) = sections[row].1,
              let text = info.draggingPasteboard.string(forType: HistoryDrag.type), let itemID = Int64(text) else { return false }
        do { try store.addToBoard(item: itemID, board: boardID) } catch { reportFailure(error); return false }
        reloadList()
        return true
    }
}
