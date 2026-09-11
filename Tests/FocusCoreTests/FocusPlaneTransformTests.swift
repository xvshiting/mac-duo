import XCTest
@testable import FocusCore

final class FocusPlaneTransformTests: XCTestCase {
    func testFullStrengthKeepsCalibratedImageStationaryFromBaseFrameEye() {
        let focus = 130.0 * Double.pi / 180
        // Independent world-space ray check: base x points toward the user, z up.
        for angle in [130.0, 125, 120, 110, 100, 96, 90] {
            let current = angle * Double.pi / 180
            let plane = FocusPlaneTransform(angle: angle, focusAngle: 130, strength: 1)
            let width = plane.topRight.x - plane.topLeft.x
            let k = 1 / width - 1
            let vertical = plane.topLeft.y * (1 + k)
            for sourceY in [0.0, 0.2, 0.5, 0.8, 1] {
                for sourceX in [-0.4, 0.0, 0.4] {
                    let u = sourceX / (1 + k * sourceY)
                    let v = vertical * sourceY / (1 + k * sourceY)
                    let actual = [u, v * cos(current), v * sin(current)]
                    let target = [sourceX, sourceY * cos(focus), sourceY * sin(focus)]
                    let eye = [0.0, 2.4, 0.8]
                    let rayA = zip(actual, eye).map { $0 - $1 }
                    let rayB = zip(target, eye).map { $0 - $1 }
                    let cross = [rayA[1]*rayB[2] - rayA[2]*rayB[1],
                                 rayA[2]*rayB[0] - rayA[0]*rayB[2],
                                 rayA[0]*rayB[1] - rayA[1]*rayB[0]]
                    for error in cross { XCTAssertEqual(error, 0, accuracy: 1e-9, "World drift at \(angle)°") }
                }
            }
        }
    }

    func testHingeFixedAndNoStretchOrFlipAcrossSettings() {
        for focus in stride(from: 25.0, through: 180, by: 5) {
            for angle in stride(from: 0.0, through: 180, by: 1) {
                let plane = FocusPlaneTransform(angle: angle, focusAngle: focus)
                XCTAssertEqual(plane.bottomLeft, PlanePoint(x: 0, y: 0))
                XCTAssertEqual(plane.bottomRight, PlanePoint(x: 1, y: 0))
                let width = plane.topRight.x - plane.topLeft.x
                XCTAssertGreaterThan(width, 0)
                XCTAssertLessThanOrEqual(width, 1)
                XCTAssertGreaterThan(plane.topLeft.y, 0)
                // For this homography the maximum vertical derivative is at y=0.
                XCTAssertLessThanOrEqual(plane.topLeft.y / width, 1 + 1e-12)
            }
        }
    }

    func testUprightAdjustmentHasStableHingeAndMonotonicStrength() {
        var lastWidth = 1.0, lastHeight = 1.0
        for strength in stride(from: 0.0, through: 1, by: 0.05) {
            let plane = FocusPlaneTransform(angle: 96, focusAngle: 130, strength: strength)
            let width = plane.topRight.x - plane.topLeft.x
            XCTAssertLessThanOrEqual(width, lastWidth)
            XCTAssertLessThanOrEqual(plane.topLeft.y, lastHeight)
            XCTAssertLessThanOrEqual(plane.topLeft.y / width, 1 + 1e-12)
            XCTAssertEqual(plane.bottomLeft, PlanePoint(x: 0, y: 0))
            XCTAssertEqual(plane.bottomRight, PlanePoint(x: 1, y: 0))
            lastWidth = width; lastHeight = plane.topLeft.y
        }
        let upright = FocusPlaneTransform(angle: 96, focusAngle: 130, strength: 0)
        XCTAssertEqual(upright.topLeft, PlanePoint(x: 0, y: 1))
        XCTAssertEqual(upright.topRight, PlanePoint(x: 1, y: 1))
        XCTAssertGreaterThan(FocusPlaneTransform(angle: 96, focusAngle: 130).topLeft.y, 0.92)
    }

    func testFocusAndInvalidValuesRestoreOriginalImage() {
        for (angle, focus) in [(130.0, 130.0), (180, 130), (.nan, 130),
                                (.infinity, 130), (96, .nan), (96, .infinity), (0, 0)] {
            let plane = FocusPlaneTransform(angle: angle, focusAngle: focus)
            XCTAssertEqual(plane.topLeft, PlanePoint(x: 0, y: 1))
            XCTAssertEqual(plane.topRight, PlanePoint(x: 1, y: 1))
        }
    }
}
