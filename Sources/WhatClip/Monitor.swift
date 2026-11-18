import AppKit
import WhatClipCore

/// Watches the system pasteboard by its change count (cheap) and records eligible text. Never logs clipboard contents.
@MainActor
final class PasteboardMonitor {
    private let pb = NSPasteboard.general
    private var last: Int
    private var timer: Timer?
    private var ownChange = -1
    let store: ClipStore
    private(set) var settings: WhatClipSettings
    let settingsStore: SettingsStore
    var policy = PrivacyPolicy()
    var onChange: (() -> Void)?
    /// Capture is paused until this moment (distantFuture means until resumed). Nil when capturing.
    private(set) var pausedUntil: Date?

    var isPaused: Bool { if let p = pausedUntil { return p > Date() }; return false }
    /// Pause capture for a time, or until resumed when seconds is nil.
    func pause(for seconds: TimeInterval?) { pausedUntil = seconds.map { Date().addingTimeInterval($0) } ?? .distantFuture }
    func resume() { pausedUntil = nil }

    init(store: ClipStore, settingsStore: SettingsStore) {
        self.store = store; self.settingsStore = settingsStore
        settings = settingsStore.load()
        last = pb.changeCount
        settings.apply(to: &policy)
    }

    /// Settings take effect immediately: the next copy and the next cleanup use them.
    var onSettingsChanged: ((WhatClipSettings) -> Void)?

    func update(_ new: WhatClipSettings) throws {
        var s = new; s.clamped()
        try settingsStore.save(s)
        settings = s
        s.apply(to: &policy)
        applyPrivacyAndSystem(s)
        onSettingsChanged?(s)
        _ = try? store.enforceRetention(maxItems: s.maxItems, maxAgeDays: s.retention.maxAgeDays)
        onChange?()
    }

    /// Encryption, login item and text recognition follow the settings at once.
    func applyPrivacyAndSystem(_ s: WhatClipSettings) {
        policy.ignoredPatterns = IgnorePatterns(s.ignoredPatterns)
        if s.encryptPayloads && store.cipher == nil, let key = KeyStore.loadOrCreateKey() { store.cipher = PayloadCipher(key: key) }
        store.encryptNew = s.encryptPayloads && store.cipher != nil
        _ = LoginItem.set(s.launchAtLogin)
    }

    func start() {
        let t = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.poll() } }
        RunLoop.main.add(t, forMode: .common); timer = t
    }

    /// Put an item back on the clipboard in its original form, without recording it again.
    func restore(_ item: ClipItem) {
        pb.clearContents()
        if item.kind == .file {
            let urls = item.text.split(separator: "\n").map { URL(fileURLWithPath: String($0)) as NSURL }
            pb.writeObjects(urls)
        } else if let type = item.payloadType, let data = store.payloadData(for: item) {
            pb.setData(data, forType: NSPasteboard.PasteboardType(type))
            if item.kind == .richText { pb.setString(item.text, forType: .string) }
        } else {
            pb.setString(item.text, forType: .string)
        }
        ownChange = pb.changeCount; last = ownChange
    }
    func restore(_ text: String) {
        pb.clearContents(); pb.setString(text, forType: .string)
        ownChange = pb.changeCount; last = ownChange
    }


    private var lastCleanup = Date.distantPast

    private func poll() {
        // Expired secrets are hidden at once but only deleted here: sweep once a minute even when nothing is copied.
        if Date().timeIntervalSince(lastCleanup) > 60 {
            lastCleanup = Date()
            _ = try? store.enforceRetention(maxItems: settings.maxItems, maxAgeDays: settings.retention.maxAgeDays)
        }
        let n = pb.changeCount
        guard n != last else { return }
        last = n
        if n == ownChange { return }
        if isPaused { return }     // copies made while paused are never recorded
        let types = (pb.types ?? []).map(\.rawValue)
        let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if let captured = capture(types: types) {
            switch policy.decide(text: captured.policyText, types: types, sourceBundleID: app) {
            case .capture: store(captured, app: app, expiresIn: nil, secrets: [])
            case .captureExpiring(let sec, let kinds): store(captured, app: app, expiresIn: sec, secrets: kinds)
            case .skip(let why): if why == .ignoreNext { policy.ignoreNextCopy = false }
            }
        }
        _ = try? store.enforceRetention(maxItems: settings.maxItems, maxAgeDays: settings.retention.maxAgeDays)
        onChange?()
    }

    /// What is on the pasteboard, in order of richness: files, GIF, image, rich text, plain text.
    struct Captured {
        var kind: ClipKind
        var text: String           // what the list shows, and what secrets are checked against (text only)
        var policyText: String     // text used for privacy checks
        var payload: Data?
        var payloadType: String?
    }

    private func capture(types: [String]) -> Captured? {
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            let paths = urls.map(\.path).joined(separator: "\n")
            return Captured(kind: .file, text: paths, policyText: paths, payload: nil, payloadType: nil)
        }
        if types.contains("com.compuserve.gif"), let d = pb.data(forType: NSPasteboard.PasteboardType("com.compuserve.gif")) {
            return Captured(kind: .gif, text: "GIF \(Self.size(d))", policyText: "gif", payload: d, payloadType: "com.compuserve.gif")
        }
        for t in ["public.png", "public.tiff", "public.jpeg"] where types.contains(t) {
            if let d = pb.data(forType: NSPasteboard.PasteboardType(t)) {
                return Captured(kind: .image, text: "Image \(Self.size(d))", policyText: "image", payload: d, payloadType: t)
            }
        }
        if types.contains("public.html"), let d = pb.data(forType: NSPasteboard.PasteboardType("public.html")), let plain = pb.string(forType: .string) {
            return Captured(kind: .richText, text: plain, policyText: plain, payload: d, payloadType: "public.html")
        }
        if types.contains("public.rtf"), let d = pb.data(forType: NSPasteboard.PasteboardType("public.rtf")), let plain = pb.string(forType: .string) {
            return Captured(kind: .richText, text: plain, policyText: plain, payload: d, payloadType: "public.rtf")
        }
        guard let text = pb.string(forType: .string) else { return nil }
        return Captured(kind: classifyKind(text), text: text, policyText: text, payload: nil, payloadType: nil)
    }

    private func classifyKind(_ text: String) -> ClipKind { WhatClipCore.classify(text) }

    private func store(_ c: Captured, app: String?, expiresIn: TimeInterval?, secrets: [SecretKind]) {
        if let payload = c.payload, let type = c.payloadType {
            // Save first; read the text of an image in the background. Recognition can take seconds the first time.
            guard let item = try? store.add(kind: c.kind, label: c.text, payload: payload, payloadType: type, sourceBundleID: app) else { return }
            if c.kind == .image && settings.recognizeText {
                let db = store
                Task.detached(priority: .utility) {
                    let text = TextRecognizer.recognize(imageData: payload)
                    try? db.setOCR(item.id, text)
                    await MainActor.run { [weak self] in self?.onChange?() }
                }
            }
        } else if c.kind == .file {
            _ = try? store.add(kind: .file, text: c.text, sourceBundleID: app)
        } else {
            _ = try? store.add(text: c.text, sourceBundleID: app, expiresIn: expiresIn, secretKinds: secrets)
        }
    }

    /// Pixel size of an image or GIF, for the list label. Empty when it cannot be read.
    static func size(_ data: Data) -> String {
        guard let rep = NSBitmapImageRep(data: data) ?? NSImage(data: data).flatMap({ $0.representations.first }) as? NSBitmapImageRep else { return "" }
        return "\(rep.pixelsWide) × \(rep.pixelsHigh)"
    }
}
