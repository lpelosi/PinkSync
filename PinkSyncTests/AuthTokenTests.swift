import XCTest
@testable import PinkSync

/// JWTs are base64url. The old decoder used plain base64 and treated any
/// decode failure as "expired", so the app refreshed on every request, got
/// rate-limited, and signed the scorekeeper out mid-game.
final class AuthTokenTests: XCTestCase {

    private func makeJWT(exp: TimeInterval) -> String {
        // Payload deliberately contains bytes that base64url-encode to `-` / `_`.
        let payload: [String: Any] = [
            "userId": "~~~~~~~~~~~~????????>>>>>>>>",
            "role": "admin",
            "exp": exp
        ]
        let json = try! JSONSerialization.data(withJSONObject: payload)
        let encoded = json.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "eyJhbGciOiJIUzI1NiJ9.\(encoded).sig"
    }

    func testBase64URLPayloadDecodes() {
        let token = makeJWT(exp: 4_102_444_800) // 2100-01-01
        let payload = String(token.split(separator: ".")[1])
        XCTAssertTrue(payload.contains("-") || payload.contains("_"), "fixture must exercise base64url chars")
        XCTAssertNotNil(AuthManager.decodeBase64URL(payload))
    }

    func testFarFutureTokenIsNotExpiringSoon() {
        let now = Date()
        let token = makeJWT(exp: now.timeIntervalSince1970 + 3600)
        XCTAssertFalse(AuthManager.isTokenExpiringSoon(token, now: now))
    }

    func testTokenInsideOneMinuteIsExpiringSoon() {
        let now = Date()
        let token = makeJWT(exp: now.timeIntervalSince1970 + 30)
        XCTAssertTrue(AuthManager.isTokenExpiringSoon(token, now: now))
    }

    func testMalformedTokenCountsAsExpiring() {
        XCTAssertTrue(AuthManager.isTokenExpiringSoon("not.a.jwt"))
        XCTAssertTrue(AuthManager.isTokenExpiringSoon(""))
    }
}
