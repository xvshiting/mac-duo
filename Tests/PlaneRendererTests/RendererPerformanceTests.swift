import XCTest
import Metal
import CoreImage
@testable import MacDuo

final class RendererPerformanceTests: XCTestCase {
    func testFullResolutionFrameBudget() throws {
        guard ProcessInfo.processInfo.environment["MACDUO_BENCHMARK"] == "1" else {
            throw XCTSkip("Opt-in full-resolution GPU benchmark")
        }
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let context = CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
        let bounds = CGRect(x: 0, y: 0, width: 3428, height: 2178)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 3428, height: 2178, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        let target = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        let pattern = CIImage.empty().applyingFilter("CICheckerboardGenerator", parameters: ["inputWidth": 12.0]).cropped(to: bounds)
        let foreground = pattern.cropped(to: bounds.insetBy(dx: 200, dy: 120))
            .composited(over: CIImage(color: .clear).cropped(to: bounds))
        var wall: [Double] = [], gpu: [Double] = []
        for index in 0..<50 {
            let started = CACurrentMediaTime()
            let command = try XCTUnwrap(queue.makeCommandBuffer())
            let image = PlaneRenderer.composite(source: foreground, desktop: pattern, size: bounds.size,
                                                angle: 96, focusAngle: 130, blur: 36)
            context.render(image, to: target, commandBuffer: command, bounds: bounds, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
            command.commit(); command.waitUntilCompleted()
            XCTAssertEqual(command.status, .completed)
            if index >= 8 {
                wall.append((CACurrentMediaTime() - started) * 1000)
                gpu.append((command.gpuEndTime - command.gpuStartTime) * 1000)
            }
        }
        wall.sort(); gpu.sort()
        let p95 = wall[Int(Double(wall.count) * 0.95)]
        print("RENDER_BENCHMARK 3428x2178 blur=36 wall_p50_ms=\(wall[wall.count/2]) wall_p95_ms=\(p95) gpu_p95_ms=\(gpu[Int(Double(gpu.count)*0.95)])")
        XCTAssertLessThan(p95, 16.7, "Rendering must fit a 60Hz frame budget")
    }
}
