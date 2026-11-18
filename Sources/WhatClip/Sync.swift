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
           modified > (UserDefaults.standard.object(forKey: "whatclip.lastSyncRead") as? Date ?? .distantPast) {
            // Only a successful import counts as read. If the file cannot be read or imported, leave it alone:
            // overwriting it would drop the other Mac's changes.
            guard let data = try? Data(contentsOf: file), (try? Transfer.importData(data, into: store)) != nil else { return }
            UserDefaults.standard.set(modified, forKey: "whatclip.lastSyncRead")
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
        alert.messageText = Lang.t("ui.update.available", ["v": version])
        alert.informativeText = Lang.t("ui.update.info")
        alert.addButton(withTitle: Lang.t("ui.update.now")); alert.addButton(withTitle: Lang.t("ui.update.later")); alert.addButton(withTitle: Lang.t("ui.update.page"))
        switch alert.runModal() {
        case .alertFirstButtonReturn: confirmAndInstall(version)
        case .alertThirdButtonReturn:
            if let url = URL(string: "https://github.com/moushaban-cell/whatclip/releases/latest") { NSWorkspace.shared.open(url) }
        default: break
        }
    }

    /// Asks once more, then writes the installer script to a private folder and opens it in Terminal, so every step is visible.
    static func confirmAndInstall(_ version: String) {
        guard let script = UpdateScript.make(version: version) else { return }
        let confirm = NSAlert()
        confirm.messageText = Lang.t("ui.update.confirm", ["v": version])
        confirm.informativeText = Lang.t("ui.update.confirmInfo")
        confirm.addButton(withTitle: Lang.t("ui.update.now")); confirm.addButton(withTitle: Lang.t("ui.update.later"))
        guard confirm.runModal() == .alertFirstButtonReturn else { return }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("WhatClipUpdate-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let file = dir.appendingPathComponent("install-whatclip-\(version).command")
            try script.write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
            NSWorkspace.shared.open(file)
        } catch {
            reportFailure(error)
        }
    }
}

/// Runs one of the person's own actions on a text item. The command gets the text on standard input and its output becomes a new item.
enum ActionRunner {
    /// Holds output read on a background thread. Only that thread writes it, and the caller reads it after the read has finished.
    private final class OutputBox: @unchecked Sendable { var data = Data() }

    static func run(command: String, input: String) async -> Result<String, Error> {
        await withCheckedContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = ["-c", command]
            let inPipe = Pipe(), outPipe = Pipe()
            p.standardInput = inPipe; p.standardOutput = outPipe; p.standardError = outPipe
            // Read the output while the command runs. Reading only after it exits would block a command whose output
            // fills the pipe, and the command would never exit.
            let output = OutputBox()
            let readDone = DispatchGroup()
            readDone.enter()
            DispatchQueue.global().async {
                output.data = outPipe.fileHandleForReading.readDataToEndOfFile()
                readDone.leave()
            }
            p.terminationHandler = { proc in
                readDone.notify(queue: .global()) {
                    let out = String(decoding: output.data, as: UTF8.self)
                    cont.resume(returning: proc.terminationStatus == 0 ? .success(out) : .failure(CocoaError(.executableRuntimeMismatch)))
                }
            }
            do {
                try p.run()
                // Write the input off the calling thread, so a command that does not read it cannot block the app.
                let bytes = Array(input.utf8)
                let writer = inPipe.fileHandleForWriting
                DispatchQueue.global().async {
                    _ = bytes.withUnsafeBytes { Darwin.write(writer.fileDescriptor, $0.baseAddress, $0.count) }
                    try? writer.close()
                }
            } catch {
                readDone.wait()
                cont.resume(returning: .failure(error))
            }
        }
    }
}
