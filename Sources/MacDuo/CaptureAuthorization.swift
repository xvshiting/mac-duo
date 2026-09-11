import CoreGraphics
import Foundation

/// Permission requests are explicit, one-shot actions. Returning from System Settings
/// refreshes state; it never asks the OS for consent again automatically.
final class CaptureAuthorization {
    private let defaults: UserDefaults
    private let preflight: () -> Bool
    private let request: () -> Bool
    private(set) var granted: Bool
    var hasRequested: Bool { defaults.bool(forKey: "captureAuthorizationRequested") }

    init(defaults: UserDefaults = .standard,
         preflight: @escaping () -> Bool = CGPreflightScreenCaptureAccess,
         request: @escaping () -> Bool = CGRequestScreenCaptureAccess) {
        self.defaults = defaults; self.preflight = preflight; self.request = request
        granted = preflight()
    }
    func refresh(streamReady: Bool = false) { granted = streamReady || preflight() }
    func requestOnce() {
        refresh()
        guard !granted, !hasRequested else { return }
        defaults.set(true, forKey: "captureAuthorizationRequested")
        granted = request()
    }
}
