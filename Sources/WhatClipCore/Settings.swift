import Foundation

public enum Retention: String, Sendable, Codable, CaseIterable {
    case day, week, month, quarter, forever
    public var maxAgeDays: Int? {
        switch self { case .day: 1; case .week: 7; case .month: 30; case .quarter: 90; case .forever: nil }
    }
    public var title: String {
        switch self { case .day: "One day"; case .week: "One week"; case .month: "One month"; case .quarter: "Three months"; case .forever: "Keep until I clear it" }
    }
}

/// What the person chose in Settings. Decoding is tolerant: a bad or missing field falls back to its default, never an error.
public enum AppearanceChoice: String, Sendable, Codable, CaseIterable {
    case system, light, dark
    public var title: String { switch self { case .system: "System"; case .light: "Light"; case .dark: "Dark" } }
}

/// Where the picker opens.
public enum PopupPlacement: String, Sendable, Codable, CaseIterable {
    case menuIcon, cursor, screenCenter
    public var title: String {
        switch self { case .menuIcon: "Under the menu-bar icon"; case .cursor: "At the mouse pointer"; case .screenCenter: "In the middle of the screen" }
    }
}

public struct WhatClipSettings: Sendable, Codable, Equatable {
    public var excludedBundleIDs: [String]
    public var secretAction: SecretAction
    public var secretLifetimeSeconds: Double
    public var retention: Retention
    public var maxItems: Int
    public var encryptPayloads: Bool
    public var requireTouchID: Bool
    public var launchAtLogin: Bool
    public var recognizeText: Bool
    public var appearance: AppearanceChoice
    public var popupPlacement: PopupPlacement
    public var clearOnQuit: Bool
    public var fuzzySearch: Bool
    public var ignoredPatterns: [String]
    public var onboardingDone: Bool
    public var showInDock: Bool
    public var gifSeconds: Int
    public var gifFramesPerSecond: Int
    /// The picker shortcut: a virtual key code and Carbon modifier bits (command 256, shift 512, option 2048, control 4096).
    public var hotKeyCode: Int
    public var hotKeyModifiers: Int
    /// After choosing an item, paste it into the app you were using (needs the Accessibility permission).
    public var autoPaste: Bool
    /// Interface language code (for example "en", "es", "ar"). English is the default.
    public var language: String
    /// User actions, one per line in the form "Name | command" (see UserAction).
    public var actionsText: String
    /// Optional sync: a folder you choose (for example in iCloud Drive). Empty means off.
    public var syncFolder: String
    /// Check GitHub once a day for a newer version. Sends no personal data.
    public var checkForUpdates: Bool
    /// Add screenshots taken with the Mac's own screenshot tool (saved as files) to the history.
    public var watchScreenshots: Bool

    public static let supportedLanguages = ["en", "zh-Hans", "hi", "es", "fr", "ar", "bn", "pt", "ru", "ja", "de"]

    public static let `default` = WhatClipSettings(
        excludedBundleIDs: BundleIDList.defaultExcluded, secretAction: .expire,
        secretLifetimeSeconds: 60, retention: .quarter, maxItems: 500,
        encryptPayloads: false, requireTouchID: false, launchAtLogin: false, recognizeText: true,
        appearance: .system, popupPlacement: .menuIcon, clearOnQuit: false, fuzzySearch: true, ignoredPatterns: [], onboardingDone: false, showInDock: true, gifSeconds: 5, gifFramesPerSecond: 8, hotKeyCode: 7, hotKeyModifiers: 256, autoPaste: true, language: "en", actionsText: "", syncFolder: "", checkForUpdates: true)

    public init(excludedBundleIDs: [String], secretAction: SecretAction, secretLifetimeSeconds: Double, retention: Retention, maxItems: Int,
                encryptPayloads: Bool = false, requireTouchID: Bool = false, launchAtLogin: Bool = false, recognizeText: Bool = true,
                appearance: AppearanceChoice = .system, popupPlacement: PopupPlacement = .menuIcon, clearOnQuit: Bool = false,
                fuzzySearch: Bool = true, ignoredPatterns: [String] = [], onboardingDone: Bool = false, showInDock: Bool = true,
                gifSeconds: Int = 5, gifFramesPerSecond: Int = 8, hotKeyCode: Int = 7, hotKeyModifiers: Int = 256, autoPaste: Bool = true, language: String = "en",
                actionsText: String = "", syncFolder: String = "", checkForUpdates: Bool = true, watchScreenshots: Bool = true) {
        self.actionsText = actionsText; self.syncFolder = syncFolder; self.checkForUpdates = checkForUpdates; self.watchScreenshots = watchScreenshots
        self.language = language; self.autoPaste = autoPaste; self.gifSeconds = gifSeconds; self.gifFramesPerSecond = gifFramesPerSecond; self.hotKeyCode = hotKeyCode; self.hotKeyModifiers = hotKeyModifiers
        self.showInDock = showInDock
        self.appearance = appearance; self.popupPlacement = popupPlacement; self.clearOnQuit = clearOnQuit
        self.fuzzySearch = fuzzySearch; self.ignoredPatterns = ignoredPatterns; self.onboardingDone = onboardingDone
        self.excludedBundleIDs = excludedBundleIDs
        self.secretAction = secretAction
        self.secretLifetimeSeconds = secretLifetimeSeconds
        self.retention = retention
        self.maxItems = maxItems
        self.encryptPayloads = encryptPayloads
        self.requireTouchID = requireTouchID
        self.launchAtLogin = launchAtLogin
        self.recognizeText = recognizeText
        clamped()
    }

    enum CodingKeys: String, CodingKey {
        case excludedBundleIDs, secretAction, secretLifetimeSeconds, retention, maxItems, encryptPayloads, requireTouchID, launchAtLogin, recognizeText
        case appearance, popupPlacement, clearOnQuit, fuzzySearch, ignoredPatterns, onboardingDone, showInDock, gifSeconds, gifFramesPerSecond, hotKeyCode, hotKeyModifiers, autoPaste, language, actionsText, syncFolder, checkForUpdates, watchScreenshots
    }

    /// Tolerant: a missing or wrong field takes its default instead of failing the whole file.
    public init(from decoder: Decoder) throws {
        let c = try? decoder.container(keyedBy: CodingKeys.self)
        let d = WhatClipSettings.default
        self.init(
            excludedBundleIDs: (try? c?.decode([String].self, forKey: .excludedBundleIDs)).flatMap { $0 } ?? d.excludedBundleIDs,
            secretAction: (try? c?.decode(SecretAction.self, forKey: .secretAction)) ?? d.secretAction,
            secretLifetimeSeconds: (try? c?.decode(Double.self, forKey: .secretLifetimeSeconds)) ?? d.secretLifetimeSeconds,
            retention: (try? c?.decode(Retention.self, forKey: .retention)) ?? d.retention,
            maxItems: (try? c?.decode(Int.self, forKey: .maxItems)) ?? d.maxItems,
            encryptPayloads: (try? c?.decode(Bool.self, forKey: .encryptPayloads)) ?? d.encryptPayloads,
            requireTouchID: (try? c?.decode(Bool.self, forKey: .requireTouchID)) ?? d.requireTouchID,
            launchAtLogin: (try? c?.decode(Bool.self, forKey: .launchAtLogin)) ?? d.launchAtLogin,
            recognizeText: (try? c?.decode(Bool.self, forKey: .recognizeText)) ?? d.recognizeText,
            appearance: (try? c?.decode(AppearanceChoice.self, forKey: .appearance)) ?? d.appearance,
            popupPlacement: (try? c?.decode(PopupPlacement.self, forKey: .popupPlacement)) ?? d.popupPlacement,
            clearOnQuit: (try? c?.decode(Bool.self, forKey: .clearOnQuit)) ?? d.clearOnQuit,
            fuzzySearch: (try? c?.decode(Bool.self, forKey: .fuzzySearch)) ?? d.fuzzySearch,
            ignoredPatterns: (try? c?.decode([String].self, forKey: .ignoredPatterns)) ?? d.ignoredPatterns,
            onboardingDone: (try? c?.decode(Bool.self, forKey: .onboardingDone)) ?? d.onboardingDone,
            showInDock: (try? c?.decode(Bool.self, forKey: .showInDock)) ?? d.showInDock,
            gifSeconds: (try? c?.decode(Int.self, forKey: .gifSeconds)) ?? d.gifSeconds,
            gifFramesPerSecond: (try? c?.decode(Int.self, forKey: .gifFramesPerSecond)) ?? d.gifFramesPerSecond,
            hotKeyCode: (try? c?.decode(Int.self, forKey: .hotKeyCode)) ?? d.hotKeyCode,
            hotKeyModifiers: (try? c?.decode(Int.self, forKey: .hotKeyModifiers)) ?? d.hotKeyModifiers,
            autoPaste: (try? c?.decode(Bool.self, forKey: .autoPaste)) ?? d.autoPaste,
            language: (try? c?.decode(String.self, forKey: .language)) ?? d.language,
            actionsText: (try? c?.decode(String.self, forKey: .actionsText)) ?? d.actionsText,
            syncFolder: (try? c?.decode(String.self, forKey: .syncFolder)) ?? d.syncFolder,
            checkForUpdates: (try? c?.decode(Bool.self, forKey: .checkForUpdates)) ?? d.checkForUpdates,
            watchScreenshots: (try? c?.decode(Bool.self, forKey: .watchScreenshots)) ?? d.watchScreenshots)
    }

    /// Keeps numbers in sensible ranges and drops invalid bundle identifiers.
    public mutating func clamped() {
        secretLifetimeSeconds = min(max(secretLifetimeSeconds.isFinite ? secretLifetimeSeconds : 60, 10), 86_400)
        if !Self.supportedLanguages.contains(language) { language = "en" }
        gifSeconds = min(max(gifSeconds, 2), 15)
        gifFramesPerSecond = [5, 8, 12, 15].contains(gifFramesPerSecond) ? gifFramesPerSecond : 8
        if hotKeyModifiers & 0x0F00 == 0 { hotKeyModifiers = 256 }   // a shortcut needs command or control or option
        maxItems = min(max(maxItems, 10), 5_000)
        excludedBundleIDs = Array(Set(excludedBundleIDs.filter { BundleIDList.parse($0) == [$0] })).sorted()
    }

    /// Applies these settings to the privacy policy used for capture.
    public func apply(to policy: inout PrivacyPolicy) {
        policy.excludedBundleIDs = Set(excludedBundleIDs)
        policy.secretAction = secretAction
        policy.secretLifetime = secretLifetimeSeconds
    }
}

extension BundleIDList {
    /// Password managers and the keychain: never recorded by default.
    public static let defaultExcluded = [
        "com.1password.1password", "com.1password.1password7", "com.bitwarden.desktop", "org.keepassxc.keepassxc",
        "com.apple.keychainaccess", "com.apple.Passwords",
    ]
}

/// Settings saved as JSON in the data folder, private to the user (mode 0600).
public struct SettingsStore: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }

    public func load() -> WhatClipSettings {
        guard let data = try? Data(contentsOf: url) else { return .default }
        guard var v = try? JSONDecoder().decode(WhatClipSettings.self, from: data) else { return .default }
        v.clamped(); return v
    }

    public func save(_ s: WhatClipSettings) throws {
        var v = s; v.clamped()
        let data = try JSONEncoder().encode(v)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
