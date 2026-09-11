import Foundation

/// Bounded measurements used by --check-perspective; contains no captured pixels.
final class FrameMetrics {
    private var values: [Double] = []
    func record(_ milliseconds: Double) {
        guard milliseconds.isFinite, milliseconds >= 0 else { return }
        values.append(milliseconds)
        if values.count > 360 { values.removeFirst() }
    }
    var p95: Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
    }
    var maximum: Double { values.max() ?? 0 }
}
