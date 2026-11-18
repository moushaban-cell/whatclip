import AppKit

/// A short message near the top of the screen that says what just happened (for example, "Collecting copies is on").
/// It does not take focus, does not block clicks, and disappears by itself.
@MainActor
enum Hud {
    private static var panel: NSPanel?
    private static var generation = 0

    static func show(_ text: String, seconds: Double = 2.2) {
        generation += 1
        let token = generation
        let old = panel
        old?.orderOut(nil)

        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = .white
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 3
        label.preferredMaxLayoutWidth = 480

        let size = label.intrinsicContentSize
        let width = min(max(size.width + 40, 220), 520)
        let height = size.height + 28
        let box = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.82).cgColor
        box.layer?.cornerRadius = 12
        label.frame = NSRect(x: 20, y: 14, width: width - 40, height: size.height)
        box.addSubview(label)

        let p = NSPanel(contentRect: box.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .floating
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = box
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let f = screen.visibleFrame
            p.setFrameOrigin(NSPoint(x: f.midX - width / 2, y: f.maxY - height - 60))
        }
        p.orderFrontRegardless()
        panel = p

        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            // Only the newest message closes itself; an older timer must not hide a newer message.
            MainActor.assumeIsolated { if token == generation { panel?.orderOut(nil); panel = nil } }
        }
    }
}
