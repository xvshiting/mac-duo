import AppKit
import ScreenCaptureKit
import CoreMedia
import MetalKit
import FocusCore

/// Main-queue state, separate transparent application and flat desktop streams.
final class PerspectiveOverlay: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private var stream: SCStream?
    private var desktopStream: SCStream?
    private var display: SCDisplay?
    private var starting = false
    private var generation = 0
    private var desiredCapture = false
    private var panel: NSPanel?
    private var renderer: PlaneRenderer?
    private var wantedEffect = false
    private var isAnimating = false
    private var refreshTimer: Timer?
    private var refreshing = false
    private var layerIDs = [CGWindowID]()
    private let transparentBackground = CGColor(red: 0, green: 0, blue: 0, alpha: 0)
    private var targetAngle = 130.0
    private var targetFocus = 130.0
    private var targetBlur = 0.0
    private var targetStrength = FocusPlaneTransform.defaultStrength
    private var motion: EffectMotion?
    private var lastRenderTime: CFTimeInterval?
    var inspectTransparency = false
    private var inspectedTransparency = false
    private(set) var error: String?
    private(set) var hasPermission = CGPreflightScreenCaptureAccess()
    private(set) var foregroundWindowCount = 0
    private(set) var desktopWindowCount = 0
    private(set) var foregroundHasTransparency = false
    var didChange: (() -> Void)?
    var isReady: Bool { renderer?.hasFrame == true && stream != nil && desktopStream != nil }
    var frameCount: Int { renderer?.renderedFrames ?? 0 }
    private let captureReadbackTimes = FrameMetrics()
    var performanceReport: [String: Double] {
        ["renderFPS": renderer?.measuredFPS ?? 0,
         "frameIntervalP95MS": renderer?.frameIntervals.p95 ?? 0,
         "frameIntervalMaxMS": renderer?.frameIntervals.maximum ?? 0,
         "submissionP95MS": renderer?.submissionTimes.p95 ?? 0,
         "mainThreadP95MS": renderer?.mainThreadTimes.p95 ?? 0,
         "skippedFrames": Double(renderer?.skippedFrames ?? 0),
         "gpuP95MS": renderer?.gpuTimes.p95 ?? 0,
         "captureReadbackP95MS": captureReadbackTimes.p95]
    }

    func refreshPermission() {
        // Cache this check; polling TCC for every hinge sample is unnecessary.
        hasPermission = isReady || CGPreflightScreenCaptureAccess()
    }

    func setCaptureEnabled(_ enabled: Bool) {
        desiredCapture = enabled
        if enabled && hasPermission && stream == nil && !starting && error == nil { startCapture() }
        else if !enabled { stopCapture() }
    }

    func retry() {
        error = nil
        refreshPermission()
        if desiredCapture { setCaptureEnabled(true) }
    }

    private func split(_ content: SCShareableContent, display: SCDisplay) -> (apps: [SCWindow], desktop: [SCWindow]) {
        let flatApps: Set<String> = ["com.apple.dock", "com.apple.controlcenter", "com.apple.systemuiserver", "com.apple.wallpaper.agent", "com.apple.WindowManager"]
        let candidates = content.windows.filter {
            guard let owner = $0.owningApplication, owner.processID != getpid(),
                  owner.bundleIdentifier != "local.macduo.app", $0.frame.intersects(display.frame), $0.isOnScreen else { return false }
            return true
        }
        func isDesktop(_ window: SCWindow) -> Bool {
            window.windowLayer < 0 || flatApps.contains(window.owningApplication?.bundleIdentifier ?? "")
        }
        return (candidates.filter { !isDesktop($0) }, candidates.filter { isDesktop($0) })
    }

    private func configuration(screen: NSScreen, fps: Int32) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.width = Int(screen.frame.width * min(2, screen.backingScaleFactor))
        config.height = Int(screen.frame.height * min(2, screen.backingScaleFactor))
        config.minimumFrameInterval = CMTime(value: 1, timescale: fps)
        config.queueDepth = 3
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.capturesAudio = false
        config.backgroundColor = transparentBackground
        config.colorSpaceName = CGColorSpace.sRGB
        return config
    }

    private func startCapture() {
        starting = true
        inspectedTransparency = false
        foregroundHasTransparency = false
        generation += 1
        let token = generation
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                guard let screen = NSScreen.screens.first(where: {
                    guard let id = ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { return false }
                    return CGDisplayIsBuiltin(id) != 0
                }) else { throw NSError(domain: "未找到内置显示屏", code: 1) }
                self.buildPanel(screen: screen)
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                guard self.generation == token, self.desiredCapture else { return }
                guard let display = content.displays.first(where: { CGDisplayIsBuiltin($0.displayID) != 0 }), self.renderer != nil else {
                    throw NSError(domain: "无法准备内置显示屏", code: 2)
                }
                self.display = display
                let layers = self.split(content, display: display)
                guard !layers.desktop.isEmpty else { throw NSError(domain: "未找到可用桌面背景，已保持原桌面", code: 3) }
                let foreground = SCStream(filter: SCContentFilter(display: display, including: layers.apps), configuration: self.configuration(screen: screen, fps: 60), delegate: self)
                let background = SCStream(filter: SCContentFilter(display: display, including: layers.desktop), configuration: self.configuration(screen: screen, fps: 30), delegate: self)
                try foreground.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
                try background.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
                self.stream = foreground; self.desktopStream = background
                try await background.startCapture()
                guard self.generation == token else { try? await background.stopCapture(); return }
                try await foreground.startCapture()
                guard self.generation == token, self.desiredCapture else {
                    try? await foreground.stopCapture(); try? await background.stopCapture(); return
                }
                self.foregroundWindowCount = layers.apps.count; self.desktopWindowCount = layers.desktop.count
                self.layerIDs = layers.apps.map(\.windowID) + [0] + layers.desktop.map(\.windowID)
                self.starting = false; self.hasPermission = true
                self.refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in self?.refreshLayers() }
                self.didChange?()
            } catch {
                guard self.generation == token else { return }
                self.error = "立体效果未启动：\(error.localizedDescription)"
                self.stopCapture()
                self.didChange?()
            }
        }
    }

    private func refreshLayers() {
        guard !refreshing, let display, stream != nil else { return }
        refreshing = true
        let token = generation
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if self.generation == token { self.refreshing = false } }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard self.generation == token, let stream = self.stream, let desktopStream = self.desktopStream else { return }
                let layers = self.split(content, display: display)
                let ids = layers.apps.map(\.windowID) + [0] + layers.desktop.map(\.windowID)
                guard ids != self.layerIDs, !layers.desktop.isEmpty else { return }
                try await desktopStream.updateContentFilter(SCContentFilter(display: display, including: layers.desktop))
                try await stream.updateContentFilter(SCContentFilter(display: display, including: layers.apps))
                guard self.generation == token else { return }
                self.layerIDs = ids
                self.foregroundWindowCount = layers.apps.count; self.desktopWindowCount = layers.desktop.count
            } catch {
                guard self.generation == token else { return }
                self.error = "窗口画面读取中断，请重试"
                self.stopCapture(); self.didChange?()
            }
        }
    }

    private func buildPanel(screen: NSScreen) {
        panel?.orderOut(nil)
        let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.backgroundColor = .black
        panel.isOpaque = true
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue - 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        renderer = PlaneRenderer(frame: CGRect(origin: .zero, size: screen.frame.size), maximumFPS: screen.maximumFramesPerSecond)
        renderer?.willRender = { [weak self] in self?.prepareFrame() }
        panel.contentView = renderer?.view
        renderer?.didRender = { [weak self] in
            guard let self, self.wantedEffect, self.desiredCapture else { return }
            if self.panel?.isVisible != true { self.panel?.orderFrontRegardless() }
        }
        self.panel = panel
    }

    func apply(angle: Double, focusAngle: Double, radius: Double, strength: Double = FocusPlaneTransform.defaultStrength) -> Bool {
        targetAngle = angle; targetFocus = focusAngle; targetBlur = radius; targetStrength = strength
        wantedEffect = angle < focusAngle - 0.1
        guard wantedEffect, isReady else { hide(); return false }
        if !isAnimating {
            motion = EffectMotion(angle: angle, blur: radius)
            lastRenderTime = nil
            isAnimating = true
            renderer?.startRendering()
        }
        return true
    }

    private func prepareFrame() {
        guard wantedEffect, let renderer, renderer.hasFrame else { return }
        let now = CACurrentMediaTime()
        let elapsed = lastRenderTime.map { now - $0 } ?? 1.0 / 60
        lastRenderTime = now
        motion?.advance(angle: targetAngle, blur: targetBlur, elapsed: elapsed)
        renderer.angle = motion?.angle ?? targetAngle
        renderer.focusAngle = targetFocus
        renderer.blurRadius = motion?.blur ?? targetBlur
        renderer.perspectiveStrength = targetStrength
    }

    func hide() {
        wantedEffect = false
        isAnimating = false
        motion = nil; lastRenderTime = nil
        renderer?.pauseRendering()
        panel?.orderOut(nil)
    }

    func rebuild() {
        let resume = desiredCapture
        stopCapture()
        if resume { setCaptureEnabled(true) }
    }

    private func stopCapture() {
        guard starting || stream != nil || panel != nil else { return }
        generation += 1
        starting = false; refreshing = false
        hide()
        refreshTimer?.invalidate(); refreshTimer = nil
        let previous = stream, desktop = desktopStream
        stream = nil; desktopStream = nil
        renderer?.clearFrame(); renderer = nil
        panel = nil; display = nil
        Task { try? await previous?.stopCapture(); try? await desktop?.stopCapture() }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard stream === self.stream || stream === desktopStream, type == .screen, sampleBuffer.isValid else { return }
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: rawStatus) else { return }
        if status == .idle { return }
        guard status == .complete else {
            if status == .blank || status == .suspended || status == .stopped {
                panel?.orderOut(nil); renderer?.clearFrame()
            }
            return
        }
        guard let frame = sampleBuffer.imageBuffer else { return }
        let wasReady = isReady
        if stream === desktopStream { renderer?.receiveDesktop(frame) }
        else {
            renderer?.receive(frame)
            if inspectTransparency && !inspectedTransparency {
                inspectedTransparency = true
                let readbackStart = CACurrentMediaTime()
                CVPixelBufferLockBaseAddress(frame, .readOnly)
                if let bytes = CVPixelBufferGetBaseAddress(frame)?.assumingMemoryBound(to: UInt8.self) {
                    let stride = CVPixelBufferGetBytesPerRow(frame)
                    for y in Swift.stride(from: 0, to: CVPixelBufferGetHeight(frame), by: 40) {
                        for x in Swift.stride(from: 0, to: CVPixelBufferGetWidth(frame), by: 40) {
                            if bytes[y * stride + x * 4 + 3] < 20 { foregroundHasTransparency = true; break }
                        }
                        if foregroundHasTransparency { break }
                    }
                }
                CVPixelBufferUnlockBaseAddress(frame, .readOnly)
                captureReadbackTimes.record((CACurrentMediaTime() - readbackStart) * 1000)
            }
        }
        if !wasReady && isReady { didChange?() }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self, stream === self.stream || stream === self.desktopStream else { return }
            self.error = "画面读取已停止：\(error.localizedDescription)"
            self.stopCapture(); self.didChange?()
        }
    }
}
