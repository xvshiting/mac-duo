import Foundation

public enum FocusModel {
    /// HID feature report 1: report ID followed by a little-endian angle in degrees.
    public static func decode(report: [UInt8]) -> Double? {
        guard report.count >= 3, report[0] == 1 else { return nil }
        let value = Int(report[1]) | (Int(report[2]) << 8)
        guard (0...180).contains(value) else { return nil }
        return Double(value)
    }

    /// The distance between the moving display and a fixed focal plane is a chord.
    /// There is no blur at or beyond the calibrated opening angle.
    public static func blur(angle: Double, focusAngle: Double, maximum: Double) -> Double {
        guard angle.isFinite, focusAngle.isFinite, maximum.isFinite,
              focusAngle > 0, maximum > 0 else { return 0 }
        let deficit = max(0, min(focusAngle, focusAngle - angle))
        let distance = sin(deficit * .pi / 360) / sin(focusAngle * .pi / 360)
        return min(maximum, maximum * pow(max(0, distance), 0.85))
    }
}
