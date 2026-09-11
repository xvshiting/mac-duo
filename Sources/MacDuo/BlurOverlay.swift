import AppKit
import Darwin

/// WindowServer's live backdrop blur. Private symbols are optional and resolved at runtime.
/// No screenshots, screen-recording access, or desktop copies are involved.
final class BlurOverlay {
    private typealias Connection = @convention(c) () -> Int32
    private typealias SetBlur = @convention(c) (Int32, Int32, Int32) -> Int32
    private var connection: Connection?
    private var setBlur: SetBlur?
    private var library: UnsafeMutableRawPointer?
    private var window: NSWindow?
    private var lastRadius: Int32 = -1
    private(set) var error: String?
    var available: Bool { connection != nil && setBlur != nil && error == nil }

    init() {
        library = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
        if let library,
           let c = dlsym(library, "CGSMainConnectionID"),
           let b = dlsym(library, "CGSSetWindowBackgroundBlurRadius") {
            connection = unsafeBitCast(c, to: Connection.self)
            setBlur = unsafeBitCast(b, to: SetBlur.self)
        }
    }

    func rebuild() {
        hide(); window = nil; lastRadius = -1
        guard let screen = NSScreen.screens.first(where: {
            guard let number = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDisplayIsBuiltin(number.uint32Value) != 0
        }) else { return }
        let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // WindowServer only blurs non-transparent pixels. 0.001 quantizes to zero
        // on this compositor, silently disabling blur even when the API succeeds.
        // Keep the backing surface above an 8-bit alpha step (1/255).
        panel.backgroundColor = NSColor.white.withAlphaComponent(0.01)
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue - 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isExcludedFromWindowsMenu = true
        panel.setAccessibilityLabel("MacDuo 屏幕对焦效果")
        window = panel
    }

    @discardableResult
    func apply(radius: Double) -> Bool {
        guard radius > 0.15, available else { hide(); return available }
        if window == nil { rebuild() }
        guard let window, let connection, let setBlur else { return false }
        // Keep a non-zero radius until the focal point; the final subpixel blur fades out.
        let integer = Int32(max(1, radius.rounded()))
        if !window.isVisible { window.orderFrontRegardless() }
        window.alphaValue = min(1, radius)
        if integer != lastRadius {
            let result = setBlur(connection(), Int32(window.windowNumber), integer)
            guard result == 0 else {
                error = "当前系统无法启用桌面模糊（\(result)）"
                hide()
                return false
            }
            lastRadius = integer
        }
        return true
    }

    func hide() { window?.orderOut(nil) }
}
