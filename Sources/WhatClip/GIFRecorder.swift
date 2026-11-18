import AppKit
@preconcurrency import ScreenCaptureKit
import ImageIO
import CoreMedia
import VideoToolbox
import UniformTypeIdentifiers
import WhatClipCore

/// Records the main display for a few seconds and saves an animated GIF to the history and the clipboard.
/// Needs the Screen Recording permission (macOS asks the first time). Not verified on this Mac yet: see docs/QA_MATRIX.md.
@MainActor
final class GIFRecorder: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private var destination: CGImageDestination?
    private var data = NSMutableData()
    private var frames = 0
    private var size = ""
    private var fps: Int32 = 8
    private var onDone: ((Data, String) -> Void)?

    var isRecording: Bool { stream != nil }

    /// Starts recording; `onDone` gets the GIF bytes and a size label when it stops.
    func start(seconds: Double = 5, framesPerSecond: Int = 8, onDone: @escaping (Data, String) -> Void) async -> Bool {
        guard !isRecording else { return false }
        fps = Int32(framesPerSecond)
        if !CGPreflightScreenCaptureAccess() { _ = CGRequestScreenCaptureAccess(); return false }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else { return false }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            let scale = min(1.0, 960.0 / Double(display.width))
            config.width = Int(Double(display.width) * scale); config.height = Int(Double(display.height) * scale)
            config.minimumFrameInterval = CMTime(value: 1, timescale: fps)
            config.queueDepth = 5
            config.showsCursor = true
            size = "\(config.width) × \(config.height)"
            let s = SCStream(filter: filter, configuration: config, delegate: self)
            try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: DispatchQueue(label: "gif.frames"))
            guard let dest = CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, 0, nil) else { return false }
            let fileProps = [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFLoopCount as String: 0]] as CFDictionary
            CGImageDestinationSetProperties(dest, fileProps)
            destination = dest; frames = 0; self.onDone = onDone
            try await s.startCapture()
            stream = s
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in Task { @MainActor in await self?.stop() } }
            return true
        } catch {
            destination = nil
            return false
        }
    }

    func stop() async {
        guard let s = stream else { return }
        stream = nil
        try? await s.stopCapture()
        guard let dest = destination else { return }
        destination = nil
        if frames > 0 && CGImageDestinationFinalize(dest) {
            onDone?(data as Data, size)
        }
        data.length = 0
    }

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        var image: CGImage?
        VTCreateCGImageFromCVPixelBuffer(pixels, options: nil, imageOut: &image)
        guard let cg = image else { return }
        Task { @MainActor in
            guard let dest = self.destination else { return }
            let frame = [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFDelayTime as String: 1.0 / Double(self.fps)]] as CFDictionary
            CGImageDestinationAddImage(dest, cg, frame)
            self.frames += 1
        }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in self.stream = nil }
    }
}
