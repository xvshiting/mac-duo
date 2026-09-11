import AppKit
import ScreenCaptureKit

// Compositor integration test: capture only the rectangle covered by our opaque
// synthetic fixture. No images are stored. Requires existing screen-capture access.
final class StripeView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill(); bounds.fill()
        NSColor.black.setFill()
        for x in stride(from: 0, to: Int(bounds.width), by: 64) {
            NSRect(x: CGFloat(x), y: 0, width: 32, height: bounds.height).fill()
        }
    }
}

func contrast(_ image: CGImage) -> Double {
    let width = image.width, height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let space = CGColorSpaceCreateDeviceRGB()
    pixels.withUnsafeMutableBytes { buffer in
        let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    // Sample the center, well clear of crop edges where blur has no backdrop.
    var values = [Double]()
    for x in (width / 4)..<(3 * width / 4) {
        values.append(Double(pixels[((height / 2) * width + x) * 4]))
    }
    let mean = values.reduce(0, +) / Double(values.count)
    return sqrt(values.map { pow($0 - mean, 2) }.reduce(0, +) / Double(values.count))
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let overlay = BlurOverlay()
let screen = NSScreen.screens.first {
    let id = ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! NSNumber).uint32Value
    return CGDisplayIsBuiltin(id) != 0
}!
let rect = NSRect(x: screen.frame.minX + 60, y: screen.frame.minY + 100, width: 400, height: 300)
let fixture = NSWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
fixture.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue - 2)
fixture.contentView = StripeView(frame: NSRect(origin: .zero, size: rect.size))
fixture.isReleasedWhenClosed = false
fixture.orderFrontRegardless()

Task { @MainActor in
    do {
        guard CGPreflightScreenCaptureAccess() else { throw NSError(domain: "Grant screen recording to the test runner before running", code: 1) }
        try await Task.sleep(for: .milliseconds(200))
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! NSNumber).uint32Value
        let display = content.displays.first { $0.displayID == displayID }!
        // Capture the actual compositor: application-filtered capture substitutes
        // the backdrop and can falsely report a flat image instead of real blur.
        // sourceRect below stays entirely inside the opaque synthetic fixture.
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = 400; config.height = 300
        config.sourceRect = CGRect(x: rect.minX - screen.frame.minX,
                                   y: screen.frame.maxY - rect.maxY,
                                   width: rect.width, height: rect.height)
        config.showsCursor = false
        config.captureResolution = .best
        let sharp = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        _ = overlay.apply(radius: 2)
        try await Task.sleep(for: .milliseconds(200))
        let gentle = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        let accepted = overlay.apply(radius: 36)
        try await Task.sleep(for: .milliseconds(300))
        let blurred = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        overlay.hide()
        try await Task.sleep(for: .milliseconds(200))
        let restored = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        _ = overlay.apply(radius: 36)
        try await Task.sleep(for: .milliseconds(200))
        let repeated = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        overlay.hide()
        let a = contrast(sharp), g = contrast(gentle), b = contrast(blurred), c = contrast(restored), d = contrast(repeated)
        print(String(format: "API accepted=%@ | sharp=%.2f | gentle=%.2f | blurred=%.2f | restored=%.2f | repeated=%.2f", String(accepted), a, g, b, c, d))
        let passed = accepted && a > 80 && g < a && g > b && b < a * 0.6 && abs(c - a) < 5 && d < a * 0.6
        print(passed ? "PASS: backdrop actually blurs and returns to sharp" : "FAIL: backdrop has no visible blur or does not restore")
        fixture.orderOut(nil)
        exit(passed ? 0 : 1)
    } catch {
        overlay.hide(); fixture.orderOut(nil)
        print("ERROR: \(error)")
        exit(2)
    }
}
app.run()
