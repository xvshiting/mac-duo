import XCTest
@testable import FocusCore

final class FocusModelTests: XCTestCase {
    func testSensorReportValidation() {
        XCTAssertEqual(FocusModel.decode(report: [1, 132, 0]), 132)
        XCTAssertEqual(FocusModel.decode(report: [1, 0, 0]), 0)
        XCTAssertEqual(FocusModel.decode(report: [1, 180, 0]), 180)
        XCTAssertNil(FocusModel.decode(report: [1, 132]))
        XCTAssertNil(FocusModel.decode(report: [2, 132, 0]))
        XCTAssertNil(FocusModel.decode(report: [1, 0, 1]))
    }
    func testFixedFocalPlaneAndMonotonicOpening() {
        for focus in [25.0, 90, 132, 180] {
            var previous = 36.0
            for angle in stride(from: 0.0, through: focus, by: 0.25) {
                let blur = FocusModel.blur(angle: angle, focusAngle: focus, maximum: 36)
                XCTAssertLessThanOrEqual(blur, previous + 1e-10)
                if angle < focus { XCTAssertGreaterThan(blur, 0) }
                previous = blur
            }
            XCTAssertEqual(FocusModel.blur(angle: 0, focusAngle: focus, maximum: 36), 36, accuracy: 1e-10)
            XCTAssertEqual(FocusModel.blur(angle: focus, focusAngle: focus, maximum: 36), 0)
            XCTAssertEqual(FocusModel.blur(angle: focus + 10, focusAngle: focus, maximum: 36), 0)
        }
    }
    func testInvalidValuesFailClear() {
        XCTAssertEqual(FocusModel.blur(angle: .nan, focusAngle: 132, maximum: 36), 0)
        XCTAssertEqual(FocusModel.blur(angle: 60, focusAngle: 0, maximum: 36), 0)
        XCTAssertEqual(FocusModel.blur(angle: 60, focusAngle: 132, maximum: -.infinity), 0)
    }
}
