import Testing
import Foundation
@testable import WhatClipCore

@Suite struct SettingsTests {
    func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("wc-set-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    @Test func roundTripAndPrivateFile() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = SettingsStore(url: dir.appendingPathComponent("settings.json"))
        var s = WhatClipSettings.default; s.retention = .week; s.secretAction = .skip; s.excludedBundleIDs = ["org.example.vault"]
        try store.save(s)
        #expect(store.load() == s)
        let perms = try FileManager.default.attributesOfItem(atPath: store.url.path)[.posixPermissions] as? Int
        #expect(perms == 0o600)
    }
    @Test func garbageFallsBackToDefaults() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("settings.json")
        try Data("not json at all".utf8).write(to: url)
        #expect(SettingsStore(url: url).load() == .default)
        try Data(#"{"retention":"sometimes","maxItems":"lots","secretAction":"keep"}"#.utf8).write(to: url)
        let s = SettingsStore(url: url).load()
        #expect(s.retention == .quarter && s.maxItems == 500 && s.secretAction == .keep)
    }
    @Test func clampsAndDropsBadIDs() {
        var s = WhatClipSettings.default
        s.secretLifetimeSeconds = 1; s.maxItems = 1_000_000; s.excludedBundleIDs = ["ok.app", "bad id!", "ok.app"]
        s.clamped()
        #expect(s.secretLifetimeSeconds == 10 && s.maxItems == 5_000)
        #expect(s.excludedBundleIDs == ["ok.app"])
        s.secretLifetimeSeconds = .nan; s.clamped(); #expect(s.secretLifetimeSeconds == 60)
    }
    @Test func appliesToPolicy() {
        var s = WhatClipSettings.default; s.secretAction = .skip; s.secretLifetimeSeconds = 120; s.excludedBundleIDs = ["x.y"]
        var p = PrivacyPolicy(); s.apply(to: &p)
        #expect(p.secretAction == .skip && p.secretLifetime == 120 && p.excludedBundleIDs == ["x.y"])
    }
    @Test func retentionMapping() {
        #expect(Retention.day.maxAgeDays == 1 && Retention.quarter.maxAgeDays == 90)
        #expect(Retention.forever.maxAgeDays == nil)
        #expect(Retention.allCases.allSatisfy { !$0.title.isEmpty })
    }
    @Test func defaultsCoverPasswordManagers() {
        #expect(BundleIDList.defaultExcluded.contains("com.1password.1password"))
        #expect(BundleIDList.defaultExcluded.allSatisfy { BundleIDList.parse($0) == [$0] })
    }
}

@Suite struct StorePermissionTests {
    @Test func databaseFilesAreRestricted() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("wc-perm-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("h.sqlite").path
        let s = try ClipStore(path: path)
        try s.add(text: "x")
        ClipStore.restrict(path)
        for p in [path, path + "-wal", path + "-shm"] where FileManager.default.fileExists(atPath: p) {
            let mode = try FileManager.default.attributesOfItem(atPath: p)[.posixPermissions] as? Int
            #expect(mode == 0o600, "\(p)")
        }
    }
}

@Suite struct NewSettingsTests {
    @Test func newFlagsDefaultAndSurviveRoundTrip() throws {
        let data = try JSONEncoder().encode(WhatClipSettings.default)
        var s = try JSONDecoder().decode(WhatClipSettings.self, from: data)
        #expect(s.encryptPayloads == false && s.requireTouchID == false && s.launchAtLogin == false && s.recognizeText == true)
        s.encryptPayloads = true; s.requireTouchID = true
        let again = try JSONDecoder().decode(WhatClipSettings.self, from: JSONEncoder().encode(s))
        #expect(again.encryptPayloads && again.requireTouchID)
    }
}

@Suite struct BehaviourSettingsTests {
    @Test func newBehaviourSettingsRoundTrip() throws {
        var s = WhatClipSettings.default
        s.appearance = .dark; s.popupPlacement = .cursor; s.clearOnQuit = true; s.ignoredPatterns = ["^x$"]; s.onboardingDone = true
        let back = try JSONDecoder().decode(WhatClipSettings.self, from: JSONEncoder().encode(s))
        #expect(back.appearance == .dark && back.popupPlacement == .cursor && back.clearOnQuit && back.ignoredPatterns == ["^x$"] && back.onboardingDone)
        let bad = try JSONDecoder().decode(WhatClipSettings.self, from: Data(#"{"appearance":"neon","popupPlacement":5}"#.utf8))
        #expect(bad.appearance == .system && bad.popupPlacement == .menuIcon)
    }
}

@Suite struct Settings3Tests {
    @Test func gifAndShortcutSettings() throws {
        var s = WhatClipSettings.default
        s.gifSeconds = 99; s.gifFramesPerSecond = 3; s.hotKeyModifiers = 0
        s.clamped()
        #expect(s.gifSeconds == 15 && s.gifFramesPerSecond == 8 && s.hotKeyModifiers == 256)
        let back = try JSONDecoder().decode(WhatClipSettings.self, from: JSONEncoder().encode(s))
        #expect(back == s)
    }
}

@Suite struct AutoPasteSettingTests {
    @Test func autoPasteDefaultsOnAndSurvivesBadData() throws {
        #expect(WhatClipSettings.default.autoPaste == true)
        let off = try JSONDecoder().decode(WhatClipSettings.self, from: Data(#"{"autoPaste":false}"#.utf8))
        #expect(off.autoPaste == false)
        let bad = try JSONDecoder().decode(WhatClipSettings.self, from: Data(#"{"autoPaste":"maybe"}"#.utf8))
        #expect(bad.autoPaste == true)
    }
}

@Suite struct NewSettings4Tests {
    @Test func actionsSyncAndUpdateDefaults() throws {
        #expect(WhatClipSettings.default.checkForUpdates == true && WhatClipSettings.default.syncFolder == "")
        let back = try JSONDecoder().decode(WhatClipSettings.self, from: JSONEncoder().encode(WhatClipSettings.default))
        #expect(back == WhatClipSettings.default)
        let bad = try JSONDecoder().decode(WhatClipSettings.self, from: Data(#"{"checkForUpdates":"yes","language":"klingon"}"#.utf8))
        #expect(bad.checkForUpdates == true && bad.language == "en")
    }

    @Test func actionShortcutsRoundTripAndOlderFilesHaveNone() throws {
        var s = WhatClipSettings.default
        s.actionShortcuts = ["screenshot": ActionShortcut(keyCode: 1, modifiers: 256)]
        let back = try JSONDecoder().decode(WhatClipSettings.self, from: JSONEncoder().encode(s))
        #expect(back.actionShortcuts == s.actionShortcuts)
        let older = try JSONDecoder().decode(WhatClipSettings.self, from: Data("{}".utf8))
        #expect(older.actionShortcuts.isEmpty)
    }

    @Test func pickerStyleRoundTripsAndDefaultsToFull() throws {
        var s = WhatClipSettings.default
        s.pickerStyle = .compact
        let back = try JSONDecoder().decode(WhatClipSettings.self, from: JSONEncoder().encode(s))
        #expect(back.pickerStyle == .compact)
        let older = try JSONDecoder().decode(WhatClipSettings.self, from: Data("{}".utf8))
        #expect(older.pickerStyle == .full)
    }
}
