import AppKit
import WhatClipCore

/// Optional sync through a folder the person chooses (for example iCloud Drive). No account and no server.
/// The file in that folder is a WhatClip export (text, tags, pins, favourites). Images and files stay on each Mac.
@MainActor
enum FolderSync {
    static let fileName = "WhatClip-history.json"

    /// Writes this Mac's history into the folder, then merges anything newer that another Mac wrote there.
    static func run(store: ClipStore, folder: String) {
        guard !folder.isEmpty else { return }
        let dir = URL(fileURLWithPath: folder, isDirectory: true)
        let file = dir.appendingPathComponent(fileName)
        if let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
           let modified = attrs[.modificationDate] as? Date,
           modified > (UserDefaults.standard.object(forKey: "whatclip.lastSyncRead") as? Date ?? .distantPast),
           let data = try? Data(contentsOf: file) {
            _ = try? Transfer.importData(data, into: store)
            UserDefaults.standard.set(Date(), forKey: "whatclip.lastSyncRead")
        }
        if let data = try? Transfer.export(store) {
            try? data.write(to: file, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        }
    }

    /// Asks for a folder with a standard dialog.
    static func chooseFolder() -> String? {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.canCreateDirectories = true; panel.prompt = "Use this folder"
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}

/// Checks GitHub once a day for a newer release. One request, no personal data; off in Settings if you prefer.
@MainActor
enum UpdateCheck {
    static let releasesURL = URL(string: "https://api.github.com/repos/moushaban-cell/whatclip/releases/latest")!

    static func runIfDue(enabled: Bool, current: String) {
        guard enabled else { return }
        let last = UserDefaults.standard.object(forKey: "whatclip.lastUpdateCheck") as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 86_400 else { return }
        UserDefaults.standard.set(Date(), forKey: "whatclip.lastUpdateCheck")
        var request = URLRequest(url: releasesURL, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { data, response, _ in
            guard (response as? HTTPURLResponse)?.statusCode == 200, let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else { return }
            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            guard isNewer(latest, than: current) else { return }
            DispatchQueue.main.async { announce(latest) }
        }.resume()
    }

    /// True when "a" is a higher version than "b", comparing numbers part by part (1.10.0 > 1.9.0).
    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    static func announce(_ version: String) {
        let alert = NSAlert()
        alert.messageText = "WhatClip \(version) is available"
        alert.informativeText = "You have an older version. The release notes and download are on the project page."
        alert.addButton(withTitle: "Open the release page"); alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn, let url = URL(string: "https://github.com/moushaban-cell/whatclip/releases/latest") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Runs one of the person's own actions on a text item. The command gets the text on standard input and its output becomes a new item.
enum ActionRunner {
    static func run(command: String, input: String) async -> Result<String, Error> {
        await withCheckedContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = ["-c", command]
            let inPipe = Pipe(), outPipe = Pipe()
            p.standardInput = inPipe; p.standardOutput = outPipe; p.standardError = outPipe
            p.terminationHandler = { _ in
                let out = String(decoding: outPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                cont.resume(returning: p.terminationStatus == 0 ? .success(out) : .failure(CocoaError(.executableRuntimeMismatch)))
            }
            do {
                try p.run()
                inPipe.fileHandleForWriting.write(Data(input.utf8))
                try? inPipe.fileHandleForWriting.close()
            } catch { cont.resume(returning: .failure(error)) }
        }
    }
}
