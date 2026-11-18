import AppKit
import WhatClipCore

/// Draws shapes over an image: freehand pen, rectangle and arrow, with undo and clear. Saved as a new image in history.
@MainActor
final class AnnotateController: NSObject {
    enum Tool: Int { case pen, line, rectangle, arrow }
    struct Shape { var tool: Tool; var points: [NSPoint] }

    private let window: NSWindow
    private let canvas: CanvasView
    private let store: ClipStore
    private let monitor: PasteboardMonitor
    private let tool = NSSegmentedControl(labels: ["Pen", "Line", "Rectangle", "Arrow"], trackingMode: .selectOne, target: nil, action: nil)

    init?(imageData: Data, store: ClipStore, monitor: PasteboardMonitor) {
        guard let image = NSImage(data: imageData) else { return nil }
        self.store = store; self.monitor = monitor
        let size = image.size
        let scale = min(1, 900 / max(size.width, 1))
        let w = size.width * scale, h = size.height * scale
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: max(w, 420), height: h + 60), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        canvas = CanvasView(image: image, shown: NSSize(width: w, height: h))
        super.init()
        window.title = "Annotate screenshot"; window.isReleasedWhenClosed = false; window.center()
        tool.selectedSegment = 0; tool.target = self; tool.action = #selector(toolChanged)
        canvas.tool = .pen
        let undo = NSButton(title: "Undo", target: self, action: #selector(undoTapped)); undo.keyEquivalent = "z"; undo.keyEquivalentModifierMask = [.command]
        let clear = NSButton(title: "Clear", target: self, action: #selector(clearTapped))
        let save = NSButton(title: "Save as new item", target: self, action: #selector(saveTapped)); save.keyEquivalent = "\r"
        let bar = NSStackView(views: [tool, undo, clear, save]); bar.spacing = 10; bar.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        let root = NSStackView(views: [bar, canvas]); root.orientation = .vertical; root.alignment = .leading
        window.contentView = root
    }

    func show() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }

    @objc private func toolChanged() { canvas.tool = Tool(rawValue: tool.selectedSegment) ?? .pen }
    @objc private func undoTapped() { canvas.undo() }
    @objc private func clearTapped() { canvas.clear() }

    @objc private func saveTapped() {
        guard let png = canvas.renderPNG() else { return }
        if let item = try? store.add(kind: .image, label: "Annotated image", payload: png, payloadType: "public.png") {
            monitor.restore(item)
        }
        window.close()
    }
}

/// Shows the image and collects shapes from mouse drags.
@MainActor
final class CanvasView: NSView {
    var tool: AnnotateController.Tool = .pen
    private let image: NSImage
    private var shapes: [AnnotateController.Shape] = []
    private var current: AnnotateController.Shape?

    init(image: NSImage, shown: NSSize) {
        self.image = image
        super.init(frame: NSRect(origin: .zero, size: shown))
        widthAnchor.constraint(equalToConstant: shown.width).isActive = true
        heightAnchor.constraint(equalToConstant: shown.height).isActive = true
    }
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        image.draw(in: bounds)
        for s in shapes + (current.map { [$0] } ?? []) { stroke(s) }
    }

    private func stroke(_ s: AnnotateController.Shape) {
        NSColor.systemRed.setStroke(); NSColor.systemRed.setFill()
        guard let first = s.points.first, let last = s.points.last else { return }
        switch s.tool {
        case .pen:
            let p = NSBezierPath(); p.lineWidth = 3; p.lineJoinStyle = .round
            p.move(to: first); s.points.dropFirst().forEach { p.line(to: $0) }; p.stroke()
        case .line:
            let p = NSBezierPath(); p.lineWidth = 3; p.lineCapStyle = .round; p.move(to: first); p.line(to: last); p.stroke()
        case .rectangle:
            let p = NSBezierPath(rect: NSRect(x: min(first.x, last.x), y: min(first.y, last.y), width: abs(last.x - first.x), height: abs(last.y - first.y)))
            p.lineWidth = 3; p.stroke()
        case .arrow:
            let p = NSBezierPath(); p.lineWidth = 3; p.move(to: first); p.line(to: last); p.stroke()
            let angle = atan2(last.y - first.y, last.x - first.x)
            let head = NSBezierPath()
            head.move(to: last)
            head.line(to: NSPoint(x: last.x - 14 * cos(angle - .pi / 6), y: last.y - 14 * sin(angle - .pi / 6)))
            head.line(to: NSPoint(x: last.x - 14 * cos(angle + .pi / 6), y: last.y - 14 * sin(angle + .pi / 6)))
            head.close(); head.fill()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        current = AnnotateController.Shape(tool: tool, points: [p])
    }
    override func mouseDragged(with event: NSEvent) {
        guard var c = current else { return }
        let p = convert(event.locationInWindow, from: nil)
        if c.tool == .pen { c.points.append(p) } else { c.points = [c.points[0], p] }
        current = c; needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        if let c = current, c.points.count > 1 || c.tool == .pen { shapes.append(c) }
        current = nil; needsDisplay = true
    }

    func undo() { if !shapes.isEmpty { shapes.removeLast(); needsDisplay = true } }
    func clear() { shapes.removeAll(); needsDisplay = true }

    /// The image with the shapes drawn on it, at the image's own pixel size, as PNG.
    func renderPNG() -> Data? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(image.size.width), pixelsHigh: Int(image.size.height),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        let scaleX = image.size.width / max(bounds.width, 1), scaleY = image.size.height / max(bounds.height, 1)
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ctx
        image.draw(in: NSRect(origin: .zero, size: image.size))
        let t = NSAffineTransform(); t.scaleX(by: scaleX, yBy: scaleY); t.concat()
        // Shapes are stored in view coordinates (flipped); draw them in the flipped space of the view.
        let flip = NSAffineTransform(); flip.translateX(by: 0, yBy: bounds.height); flip.scaleX(by: 1, yBy: -1); flip.concat()
        for s in shapes { stroke(s) }
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}
