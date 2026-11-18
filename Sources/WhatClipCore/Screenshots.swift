import Foundation

/// Recognises the files the Mac's own screenshot tool saves ("Screenshot 2026-11-18 at 10.00.00.png").
public enum ScreenshotFiles {
    public static func isScreenshot(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        guard ["png", "jpg", "jpeg", "tif", "tiff"].contains(ext) else { return false }
        return name.hasPrefix("Screenshot ") || name.hasPrefix("Screen Shot ")
    }
}
