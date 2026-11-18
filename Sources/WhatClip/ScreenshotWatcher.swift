import Foundation
import WhatClipCore

/// Watches the folder the Mac saves screenshots to. A screenshot taken after WhatClip starts is handed on once it is finished.
/// Files that were already there when WhatClip started are never read.
@MainActor
final class ScreenshotWatcher {
    private let isEnabled: () -> Bool
    private let onNew: (URL) -> Void
    private var seen: Set<String> = []
    private var timer: Timer?
    private let startedAt = Date()

    init(isEnabled: @escaping () -> Bool, onNew: @escaping (URL) -> Void) {
        self.isEnabled = isEnabled; self.onNew = onNew
    }

    /// The folder from the Mac's screenshot settings, or the Desktop when none is set.
    static var folder: URL {
        if let saved = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location"), !saved.isEmpty {
            return URL(fileURLWithPath: (saved as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
    }

    func start() {
        seen = Set(names())
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.check() } }
        RunLoop.main.add(t, forMode: .common); timer = t
    }

    private func names() -> [String] {
        readOrDefault("contentsOfDirectory", []) { try FileManager.default.contentsOfDirectory(atPath: Self.folder.path) }
    }

    private func check() {
        for name in names() where !seen.contains(name) {
            guard ScreenshotFiles.isScreenshot(name) else { seen.insert(name); continue }
            let url = Self.folder.appendingPathComponent(name)
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let created = attrs[.creationDate] as? Date, created >= startedAt.addingTimeInterval(-2) else {
                seen.insert(name); continue
            }
            // Wait until the file has stopped changing, so the whole image is read.
            let modified = attrs[.modificationDate] as? Date ?? .distantPast
            guard Date().timeIntervalSince(modified) > 0.6 else { continue }
            seen.insert(name)
            if isEnabled() { onNew(url) }
        }
    }
}
