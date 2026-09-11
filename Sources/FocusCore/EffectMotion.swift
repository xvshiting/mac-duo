import Foundation

/// Short, time-based interpolation between quantized 30Hz hinge readings.
/// The angle settles within about 55ms, with no prediction or overshoot.
public struct EffectMotion {
    public private(set) var angle: Double
    public private(set) var blur: Double

    public init(angle: Double, blur: Double) { self.angle = angle; self.blur = blur }

    public mutating func advance(angle targetAngle: Double, blur targetBlur: Double, elapsed: Double) {
        guard elapsed.isFinite, elapsed > 0 else { return }
        func approach(_ value: Double, _ target: Double, timeConstant: Double) -> Double {
            guard target.isFinite else { return value }
            let next = value + (target - value) * (1 - exp(-elapsed / timeConstant))
            return abs(next - target) < 0.001 ? target : next
        }
        angle = approach(angle, targetAngle, timeConstant: 0.018)
        blur = approach(blur, targetBlur, timeConstant: 0.030)
    }
}
