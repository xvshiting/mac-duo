import XCTest
import CoreImage
import FocusCore
@testable import MacDuo

final class PlaneRendererTests: XCTestCase {
    let size = CGSize(width: 200, height: 120)
    let context = CIContext(options: [.useSoftwareRenderer: false])
    var bounds: CGRect { CGRect(origin: .zero, size: size) }

    func testWallpaperStaysFlatWhileWindowsChangeDepth() {
        // Left/right wallpaper colors expose any accidental perspective or dark fill.
        let blue = CIImage(color: CIColor(red: 0, green: 0, blue: 1)).cropped(to: bounds)
        let green = CIImage(color: CIColor(red: 0, green: 1, blue: 0)).cropped(to: CGRect(x: 100, y: 0, width: 100, height: 120))
        let wallpaper = green.composited(over: blue)
        let foreground = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: CGRect(x: 40, y: 20, width: 120, height: 80))
            .composited(over: CIImage(color: .clear).cropped(to: bounds))
        let image = PlaneRenderer.composite(source: foreground, desktop: wallpaper, size: size, angle: 85, focusAngle: 120, blur: 3)
        XCTAssertGreaterThan(sample(image, x: 5, y: 115)[2], 240)
        XCTAssertGreaterThan(sample(image, x: 195, y: 115)[1], 240)
        XCTAssertGreaterThan(sample(image, x: 5, y: 5)[2], 240)
        XCTAssertGreaterThan(sample(image, x: 195, y: 5)[1], 240)
        XCTAssertGreaterThan(sample(image, x: 100, y: 40)[0], 220, "Only the red application window belongs in the depth plane")
    }

    func sample(_ image: CIImage, x: Int, y: Int) -> [UInt8] {
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(image, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: x, y: y, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        return pixel
    }

    func testFoldingDoesNotStretchWindowContentVertically() {
        // Reproduce the reported 96° lid / 130° focus with squares at multiple heights.
        // Render actual pixels: corner bounds alone miss local homography stretch.
        for angle in [130.0, 120, 110, 96, 80, 60] {
            for y in [10, 45, 85] {
                let marker = CIImage(color: CIColor(red: 1, green: 0, blue: 1))
                    .cropped(to: CGRect(x: 90, y: y, width: 20, height: 20))
                    .composited(over: CIImage(color: .clear).cropped(to: bounds))
                let image = PlaneRenderer.composite(source: marker, size: size, angle: angle, focusAngle: 130, blur: 0)
                var pixels = [UInt8](repeating: 0, count: 200 * 120 * 4)
                context.render(image, toBitmap: &pixels, rowBytes: 200 * 4, bounds: bounds,
                               format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
                let rows = (0..<120).filter { row in
                    (0..<200).contains { x in
                        let i = (row * 200 + x) * 4
                        return pixels[i] > 200 && pixels[i + 2] > 200 && pixels[i + 1] < 30
                    }
                }
                XCTAssertFalse(rows.isEmpty)
                if let first = rows.first, let last = rows.last {
                    XCTAssertLessThanOrEqual(last - first + 1, 20,
                        "A 20px square stretched at lid \(angle)°, source y=\(y)")
                }
            }
        }
    }

    func testActualRenderedBottomEdgeDoesNotRetreatTowardCenter() {
        let source = CIImage(color: CIColor(red: 1, green: 0, blue: 1)).cropped(to: bounds)
        for angle in [130.0, 120, 96, 60] {
            let image = PlaneRenderer.composite(source: source, size: size, angle: angle, focusAngle: 130, blur: 0)
            for x in [2, 50, 100, 150, 197] {
                XCTAssertGreaterThan(sample(image, x: x, y: 0)[0], 230, "Bottom edge detached at \(angle)°")
            }
        }
    }

    func testDefaultTiltKeepsPlaneUprightAtReportedAngle() {
        let source = CIImage(color: CIColor(red: 1, green: 0, blue: 1)).cropped(to: bounds)
        let image = PlaneRenderer.composite(source: source, size: size, angle: 96, focusAngle: 130, blur: 0)
        XCTAssertGreaterThan(sample(image, x: 100, y: 108)[0], 230,
                             "The top edge should not fall below 90% of the screen height")
        XCTAssertGreaterThan(sample(image, x: 12, y: 100)[0], 230,
                             "Strong top-edge narrowing makes the plane appear to lean back")
    }

    func testFullStrengthRenderedLandmarkFollowsFixedWorldRay() {
        let sourceX = -0.2, sourceY = 0.7
        let marker = CIImage(color: CIColor(red: 1, green: 0, blue: 1))
            .cropped(to: CGRect(x: (sourceX + 0.5) * size.width - 4,
                                y: sourceY * size.height - 4, width: 8, height: 8))
            .composited(over: CIImage(color: .clear).cropped(to: bounds))
        let focus = 130.0 * Double.pi / 180
        for angle in [130.0, 120, 110, 96, 90] {
            let current = angle * Double.pi / 180
            // Independently intersect the fixed world ray with the current lid.
            let eyeDotNormal = 2.4 * sin(current) - 0.8 * cos(current)
            let pointDotNormal = sourceY * sin(current - focus)
            let t = eyeDotNormal / (eyeDotNormal - pointDotNormal)
            let worldForward = 2.4 + t * (sourceY * cos(focus) - 2.4)
            let worldUp = 0.8 + t * (sourceY * sin(focus) - 0.8)
            let pixelX = 0.5 + t * sourceX
            let pixelY = worldForward * cos(current) + worldUp * sin(current)
            let image = PlaneRenderer.composite(source: marker, size: size, angle: angle, focusAngle: 130, blur: 0, strength: 1)
            let color = sample(image, x: Int(pixelX * size.width), y: Int(pixelY * size.height))
            XCTAssertGreaterThan(color[0], 230, "Wrong direction at \(angle)°")
            XCTAssertGreaterThan(color[2], 230)
            XCTAssertLessThan(color[1], 20)
        }
    }

    func testFocusRestoresFullFrameAndNewContentReplacesOldContent() {
        let red = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: bounds)
        let blue = CIImage(color: CIColor(red: 0, green: 0, blue: 1)).cropped(to: bounds)
        let focused = PlaneRenderer.composite(source: red, size: size, angle: 120, focusAngle: 120, blur: 0)
        for (x, y) in [(1, 1), (198, 1), (1, 118), (198, 118)] {
            XCTAssertGreaterThan(sample(focused, x: x, y: y)[0], 240)
        }
        let nextFrame = PlaneRenderer.composite(source: blue, size: size, angle: 85, focusAngle: 120, blur: 0)
        XCTAssertGreaterThan(sample(nextFrame, x: 100, y: 40)[2], 240)
        XCTAssertLessThan(sample(nextFrame, x: 100, y: 40)[0], 10)
    }

    func testBlurGrowsFromHingeToTopOnBothWindowsAndWallpaper() {
        let size = CGSize(width: 256, height: 256)
        let bounds = CGRect(origin: .zero, size: size)
        var stripes = CIImage(color: .black).cropped(to: bounds)
        for x in stride(from: 0, to: 256, by: 16) {
            stripes = CIImage(color: .white).cropped(to: CGRect(x: x, y: 0, width: 8, height: 256)).composited(over: stripes)
        }
        let clear = CIImage(color: .clear).cropped(to: bounds)
        func contrast(_ image: CIImage, y: Int) -> Int {
            let values = (32..<224).map { Int(sample(image, x: $0, y: y)[0]) }
            return values.max()! - values.min()!
        }
        for wallpaperOnly in [false, true] {
            let foreground = wallpaperOnly ? clear : stripes
            let background = wallpaperOnly ? stripes : clear
            let light = PlaneRenderer.composite(source: foreground, desktop: background, size: size,
                                                angle: 110, focusAngle: 130, blur: 6, strength: 0)
            let heavy = PlaneRenderer.composite(source: foreground, desktop: background, size: size,
                                                angle: 80, focusAngle: 130, blur: 14, strength: 0)
            let bottom = contrast(heavy, y: 8), middle = contrast(heavy, y: 90), top = contrast(heavy, y: 220)
            XCTAssertGreaterThan(bottom, middle + 35, "Bottom should retain details; wallpaper=\(wallpaperOnly)")
            XCTAssertGreaterThan(middle, top + 10, "Blur should increase upward")
            XCTAssertGreaterThan(contrast(light, y: 90), middle + 15, "Closing should deepen blur")
            XCTAssertGreaterThan(bottom, 180)
            if wallpaperOnly, let path = ProcessInfo.processInfo.environment["MACDUO_RENDER_PREVIEW"] {
                // Synthetic QA only: original / light closing / deeper closing.
                let preview = heavy.transformed(by: CGAffineTransform(translationX: 512, y: 0))
                    .composited(over: light.transformed(by: CGAffineTransform(translationX: 256, y: 0)))
                    .composited(over: stripes)
                XCTAssertNoThrow(try context.writePNGRepresentation(of: preview, to: URL(fileURLWithPath: path),
                    format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB(), options: [:]))
            }
        }
    }
}
