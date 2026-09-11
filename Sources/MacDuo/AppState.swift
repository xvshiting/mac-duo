import AppKit
import Combine
import FocusCore

final class AppState: ObservableObject {
    @Published var angle: Double?
    @Published var enabled: Bool { didSet { UserDefaults.standard.set(enabled, forKey: "enabled"); update() } }
    @Published var focusAngle: Double { didSet { UserDefaults.standard.set(focusAngle, forKey: "focusAngle"); update() } }
    @Published var maximumBlur: Double { didSet { UserDefaults.standard.set(maximumBlur, forKey: "maximumBlur"); update() } }
    @Published var perspectiveStrength: Double { didSet { UserDefaults.standard.set(perspectiveStrength, forKey: "perspectiveStrength"); update() } }
    @Published var isPreviewing = false
    @Published var currentBlur = 0.0
    @Published var error: String?
    @Published var settingsVisible = false
    @Published var needsCapturePermission = !CGPreflightScreenCaptureAccess()
    @Published var captureAuthorizationRequested = false
    @Published var perspectiveStatus = "正在准备立体画面"
    let overlay = BlurOverlay()
    let perspective = PerspectiveOverlay()
    let authorization = CaptureAuthorization()
    private let sensor = LidSensor()
    private var autoCalibrate: Bool
    private var lastReading = Date.distantPast
    private var watchdog: Timer?
    private var previewTimer: Timer?
    private var previewAngle: Double?
    var menuOpen = false { didSet { update() } }
    var asleep = false
    var didUpdate: (() -> Void)?

    init() {
        let defaults = UserDefaults.standard
        enabled = defaults.object(forKey: "enabled") as? Bool ?? true
        let savedFocus = defaults.double(forKey: "focusAngle")
        autoCalibrate = !(25...180).contains(savedFocus)
        focusAngle = autoCalibrate ? 130 : savedFocus
        let savedBlur = defaults.double(forKey: "maximumBlur")
        maximumBlur = (1...80).contains(savedBlur) ? savedBlur : 36
        let savedStrength = defaults.object(forKey: "perspectiveStrength") as? Double
        perspectiveStrength = savedStrength.flatMap { (0...1).contains($0) ? $0 : nil } ?? FocusPlaneTransform.defaultStrength
        perspective.didChange = { [weak self] in self?.update() }
        captureAuthorizationRequested = authorization.hasRequested
    }

    func start() {
        asleep = false
        sensor.start { [weak self] value in
            guard let self else { return }
            if let value {
                self.lastReading = Date()
                if self.autoCalibrate, value >= 25 {
                    self.autoCalibrate = false
                    self.focusAngle = value
                }
                if self.angle != value { self.angle = value }
            } else if Date().timeIntervalSince(self.lastReading) > 0.5 {
                self.angle = nil
            }
            self.update()
        }
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, Date().timeIntervalSince(self.lastReading) > 0.5 else { return }
            self.angle = nil
            self.update()
        }
    }

    func stop() {
        asleep = true
        stopPreview()
        sensor.stop(); watchdog?.invalidate(); watchdog = nil
        angle = nil; overlay.hide()
        perspective.setCaptureEnabled(false)
    }

    func calibrate() {
        guard let angle, angle >= 25 else { return }
        focusAngle = angle
        autoCalibrate = false
        stopPreview()
    }

    func update() {
        let source = previewAngle ?? angle
        let active = (enabled || isPreviewing) && !asleep
        perspective.setCaptureEnabled(active)
        needsCapturePermission = !perspective.hasPermission
        perspectiveStatus = needsCapturePermission ? (captureAuthorizationRequested ? "授权后请重新打开 MacDuo；当前暂用模糊" : "尚未获得本版本的屏幕录制权限") :
            perspective.error ?? (perspective.isReady ? "应用窗口立体 · 全画面渐变离焦" : active ? "正在准备立体画面" : "效果已暂停")
        let shouldShow = active && !menuOpen
        let radius = shouldShow && source != nil ? FocusModel.blur(angle: source!, focusAngle: focusAngle, maximum: maximumBlur) : 0
        if currentBlur != radius { currentBlur = radius }
        if shouldShow, let source, source < focusAngle - 0.1 {
            if perspective.apply(angle: source, focusAngle: focusAngle, radius: radius, strength: perspectiveStrength) {
                error = nil
                overlay.hide()
            } else {
                if !overlay.apply(radius: radius) { error = overlay.error }
            }
        } else {
            overlay.hide(); perspective.hide()
        }
        didUpdate?()
    }

    func authorizeCapture() {
        authorization.requestOnce()
        captureAuthorizationRequested = authorization.hasRequested
        refreshCapture()
    }

    func openCaptureSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") { NSWorkspace.shared.open(url) }
    }

    func reopenAfterAuthorization() {
        stop()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, failure in
            DispatchQueue.main.async {
                if let failure { self.error = "重新打开失败：\(failure.localizedDescription)"; self.start() }
                else { NSApp.terminate(nil) }
            }
        }
    }

    func refreshCapture() {
        authorization.refresh(streamReady: perspective.isReady)
        perspective.retry()
        update()
    }

    func preview() {
        stopPreview()
        isPreviewing = true
        let started = Date()
        previewTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            let elapsed = Date().timeIntervalSince(started)
            if elapsed >= 3.6 { self.stopPreview(); return }
            // Close gently, then open into the fixed focal plane.
            let t = elapsed / 3.6
            let folded = pow(sin(t * .pi), 2)
            self.previewAngle = self.focusAngle * (1 - 0.8 * folded)
            self.update()
        }
    }

    func stopPreview() {
        previewTimer?.invalidate(); previewTimer = nil
        previewAngle = nil; isPreviewing = false
        update()
    }

    func emergencyClear() { enabled = false; stopPreview(); overlay.hide() }
}
