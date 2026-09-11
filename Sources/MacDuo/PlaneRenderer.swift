import AppKit
import MetalKit
import CoreImage
import FocusCore

/// Blur the live windows, project the fixed focal plane onto the lid, and composite on the desktop.
final class PlaneRenderer: NSObject, MTKViewDelegate {
    let view: MTKView
    private let context: CIContext
    private let commands: MTLCommandQueue
    private let renderQueue = DispatchQueue(label: "app.macduo.render", qos: .userInteractive)
    private var inFlight = 0
    private(set) var skippedFrames = 0
    let mainThreadTimes = FrameMetrics()
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private var frame: CVPixelBuffer?
    private var desktop: CVPixelBuffer?
    var angle = 130.0
    var focusAngle = 130.0
    var blurRadius = 0.0
    var perspectiveStrength = FocusPlaneTransform.defaultStrength
    var didRender: (() -> Void)?
    var willRender: (() -> Void)?
    private(set) var renderedFrames = 0
    let submissionTimes = FrameMetrics()
    let gpuTimes = FrameMetrics()
    let frameIntervals = FrameMetrics()
    private var lastCompletion: CFTimeInterval?
    private var firstCompletion: CFTimeInterval?
    var measuredFPS: Double {
        guard let firstCompletion, let lastCompletion, lastCompletion > firstCompletion else { return 0 }
        return Double(renderedFrames - 1) / (lastCompletion - firstCompletion)
    }

    init?(frame rect: CGRect, maximumFPS: Int = 60) {
        guard let device = MTLCreateSystemDefaultDevice(), let commands = device.makeCommandQueue() else { return nil }
        self.commands = commands
        self.context = CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
        view = MTKView(frame: rect, device: device)
        super.init()
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = false
        // Reserve enough GPU time for capture and compositing to keep a steady cadence.
        view.preferredFramesPerSecond = min(60, max(30, maximumFPS))
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        view.clearColor = MTLClearColor(red: 0.015, green: 0.019, blue: 0.026, alpha: 1)
        view.delegate = self
        view.autoresizingMask = [.width, .height]
    }

    func receive(_ frame: CVPixelBuffer) { self.frame = frame }
    func receiveDesktop(_ frame: CVPixelBuffer) { desktop = frame }
    func clearFrame() { frame = nil; desktop = nil }
    var hasFrame: Bool { frame != nil && desktop != nil }
    func startRendering() {
        view.isPaused = false
        // Prime the hidden overlay once; its first completed frame makes it visible.
        if frame != nil { view.draw() }
    }
    func pauseRendering() { view.isPaused = true }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    /// Shared with the synthetic image regression test, independent of window state.
    static func composite(source: CIImage, desktop: CIImage? = nil, size: CGSize, angle: Double, focusAngle: Double, blur: Double, strength: Double = FocusPlaneTransform.defaultStrength) -> CIImage {
        let bounds = CGRect(origin: .zero, size: size)
        let normalized = source.transformed(by: CGAffineTransform(translationX: -source.extent.minX, y: -source.extent.minY))
        var texture = normalized.transformed(by: CGAffineTransform(scaleX: size.width / normalized.extent.width, y: size.height / normalized.extent.height))
        let plane = FocusPlaneTransform(angle: angle, focusAngle: focusAngle, strength: strength)
        func vector(_ p: PlanePoint) -> CIVector { CIVector(x: p.x * size.width, y: p.y * size.height) }
        texture = texture.applyingFilter("CIPerspectiveTransform", parameters: [
            "inputTopLeft": vector(plane.topLeft), "inputTopRight": vector(plane.topRight),
            "inputBottomLeft": vector(plane.bottomLeft), "inputBottomRight": vector(plane.bottomRight)
        ])
        var stage = CIImage(color: CIColor(red: 0.015, green: 0.019, blue: 0.026)).cropped(to: bounds)
        if let desktop {
            let origin = desktop.transformed(by: CGAffineTransform(translationX: -desktop.extent.minX, y: -desktop.extent.minY))
            stage = origin.transformed(by: CGAffineTransform(scaleX: size.width / origin.extent.width, y: size.height / origin.extent.height))

        }
        let combined = texture.composited(over: stage).cropped(to: bounds)
        guard blur > 0.05 else { return combined }
        // Apply focus after compositing so wallpaper and windows share one depth
        // gradient in physical screen coordinates: clear at hinge, strongest at top.
        let mask = CIFilter(name: "CILinearGradient", parameters: [
            "inputPoint0": CIVector(x: 0, y: 0),
            "inputPoint1": CIVector(x: 0, y: size.height),
            "inputColor0": CIColor.black, "inputColor1": CIColor.white
        ])!.outputImage!.cropped(to: bounds)
        return combined.clampedToExtent().applyingFilter("CIMaskedVariableBlur", parameters: [
            kCIInputRadiusKey: blur, "inputMask": mask
        ]).cropped(to: bounds)
    }

    func draw(in view: MTKView) {
        let submittedAt = CACurrentMediaTime()
        willRender?()
        // Keep only a bounded number of frames: never let work queue behind the lid.
        guard inFlight < 2 else { skippedFrames += 1; return }
        guard let frame, let desktop, view.drawableSize.width > 0,
              let drawable = view.currentDrawable else { return }
        let size = view.drawableSize
        let scale = size.height / max(1, view.bounds.height)
        let frameAngle = angle, frameFocus = focusAngle
        let frameBlur = blurRadius * scale, strength = perspectiveStrength
        inFlight += 1
        let preparationMS = (CACurrentMediaTime() - submittedAt) * 1000
        mainThreadTimes.record(preparationMS)
        // Hold both CVPixelBuffers until encoding finishes. Core Image work stays
        // off the main thread used by sensor delivery, capture callbacks and SwiftUI.
        renderQueue.async { [self] in
            autoreleasepool {
                guard let command = commands.makeCommandBuffer() else {
                    DispatchQueue.main.async { self.inFlight -= 1 }
                    return
                }
                let encodingStarted = CACurrentMediaTime()
                let result = Self.composite(source: CIImage(cvPixelBuffer: frame), desktop: CIImage(cvPixelBuffer: desktop),
                                            size: size, angle: frameAngle, focusAngle: frameFocus,
                                            blur: frameBlur, strength: strength)
                context.render(result, to: drawable.texture, commandBuffer: command,
                               bounds: CGRect(origin: .zero, size: size), colorSpace: colorSpace)
                command.present(drawable)
                command.addCompletedHandler { [weak self] buffer in
                    let completedAt = CACurrentMediaTime()
                    DispatchQueue.main.async {
                        guard let self else { return }
                        self.inFlight -= 1
                        guard buffer.status == .completed else { return }
                        if let last = self.lastCompletion { self.frameIntervals.record((completedAt - last) * 1000) }
                        if self.firstCompletion == nil { self.firstCompletion = completedAt }
                        self.lastCompletion = completedAt
                        self.gpuTimes.record((buffer.gpuEndTime - buffer.gpuStartTime) * 1000)
                        self.renderedFrames += 1
                        self.didRender?()
                    }
                }
                command.commit()
                let submissionMS = preparationMS + (CACurrentMediaTime() - encodingStarted) * 1000
                DispatchQueue.main.async { self.submissionTimes.record(submissionMS) }
            }
        }
    }
}
