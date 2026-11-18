import Testing
@testable import WhatClipCore

@Suite struct ScreenshotTests {
    @Test func recognisesMacScreenshotFiles() {
        #expect(ScreenshotFiles.isScreenshot("Screenshot 2026-11-18 at 10.00.00.png"))
        #expect(ScreenshotFiles.isScreenshot("Screen Shot 2019-01-02 at 9.00.00.png"))
        #expect(!ScreenshotFiles.isScreenshot("notes.png"))
        #expect(!ScreenshotFiles.isScreenshot("Screenshot 2026.txt"))
    }
}
