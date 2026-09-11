import XCTest
@testable import MacDuo

final class CaptureAuthorizationTests: XCTestCase {
    func testRepeatedClicksAndRestartNeverRepeatTheSystemRequest() {
        let name = "MacDuo.AuthorizationTest.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var granted = false
        var requests = 0
        let authorization = CaptureAuthorization(defaults: defaults, preflight: { granted }, request: { requests += 1; return false })
        for _ in 0..<30 { authorization.requestOnce(); authorization.refresh() }
        XCTAssertEqual(requests, 1)
        XCTAssertFalse(authorization.granted)
        XCTAssertTrue(authorization.hasRequested)
        let restarted = CaptureAuthorization(defaults: defaults, preflight: { granted }, request: { requests += 1; return false })
        restarted.requestOnce()
        XCTAssertEqual(requests, 1)
        granted = true
        restarted.refresh()
        XCTAssertTrue(restarted.granted)
        restarted.requestOnce()
        XCTAssertEqual(requests, 1)
    }
    func testActualStreamSuccessOverridesAStalePreflightResult() {
        let state = CaptureAuthorization(preflight: { false }, request: { XCTFail("Should not request permission"); return false })
        state.refresh(streamReady: true)
        XCTAssertTrue(state.granted)
    }
}
