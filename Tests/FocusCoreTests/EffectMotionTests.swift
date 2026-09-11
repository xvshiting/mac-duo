import XCTest
@testable import FocusCore

final class EffectMotionTests: XCTestCase {
    func testQuantizedInputHasIntermediateFramesAndSettlesQuickly() {
        var motion = EffectMotion(angle: 96, blur: 8)
        motion.advance(angle: 97, blur: 9, elapsed: 1.0 / 120)
        XCTAssertGreaterThan(motion.angle, 96)
        XCTAssertLessThan(motion.angle, 96.6)
        for _ in 0..<7 { motion.advance(angle: 97, blur: 9, elapsed: 1.0 / 120) }
        XCTAssertEqual(motion.angle, 97, accuracy: 0.03)
        XCTAssertLessThanOrEqual(motion.angle, 97)
    }

    func testRefreshRateDoesNotChangeMotionOrOvershootOnReversal() {
        var slow = EffectMotion(angle: 96, blur: 8), fast = slow
        for _ in 0..<6 { slow.advance(angle: 100, blur: 0, elapsed: 1.0 / 60) }
        for _ in 0..<12 { fast.advance(angle: 100, blur: 0, elapsed: 1.0 / 120) }
        XCTAssertEqual(slow.angle, fast.angle, accuracy: 1e-9)
        XCTAssertEqual(slow.blur, fast.blur, accuracy: 1e-9)
        for _ in 0..<30 {
            fast.advance(angle: 90, blur: 12, elapsed: 1.0 / 120)
            XCTAssertGreaterThanOrEqual(fast.angle, 90)
            XCTAssertLessThanOrEqual(fast.blur, 12)
        }
        XCTAssertEqual(fast.angle, 90, accuracy: 0.001)
    }
}
