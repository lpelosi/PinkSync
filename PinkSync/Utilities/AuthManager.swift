import AuthenticationServices
import Foundation
import os

private let logger = Logger(subsystem: "PinkSync", category: "Auth")

@Observable
final class AuthManager {

    private(set) var currentUser: AuthUser?
    private(set) var isLoading = true

    var isAuthenticated: Bool { currentUser != nil }

    // MARK: - Role Convenience Checks

    var canEditRoster: Bool {
        guard let role = currentUser?.role else { return false }
        return role == .rosterManager || role == .admin
    }

    var canUploadPhotos: Bool {
        guard let role = currentUser?.role else { return false }
        return role == .photographer || role == .admin
    }

    var canManageSchedule: Bool {
        guard let role = currentUser?.role else { return false }
        return role == .scheduleManager || role == .admin
    }

    var canManageGames: Bool {
        currentUser?.role == .admin
    }

    var canManageUsers: Bool {
        currentUser?.role == .admin
    }

    // MARK: - Initialization

    init() {
        Task { await restoreSession() }
    }

    // MARK: - Login

    func login(email: String, password: String) async throws {
        let response = try await APIClient.login(email: email, password: password)
        try saveTokens(access: response.accessToken, refresh: response.refreshToken)
        currentUser = response.user
    }

    // MARK: - Registration

    func register(email: String, displayName: String, password: String) async throws {
        let response = try await APIClient.register(email: email, displayName: displayName, password: password)
        currentUser = response.user
        try saveTokens(access: response.accessToken, refresh: response.refreshToken)
    }

    // MARK: - Sign in with Apple

    func handleAppleSignIn(result: Result<ASAuthorization, Error>) async throws {
        let authorization = try result.get()
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let identityToken = String(data: tokenData, encoding: .utf8) else {
            throw AuthError.appleSignInFailed
        }

        let response = try await APIClient.appleSignIn(
            identityToken: identityToken,
            fullName: credential.fullName,
            email: credential.email
        )
        currentUser = response.user
        try saveTokens(access: response.accessToken, refresh: response.refreshToken)
    }

    // MARK: - Token Refresh

    private var refreshTask: Task<String, Error>?

    // Returns a usable access token. Only a refresh the server explicitly
    // rejects (401) ends the session; a network blip, timeout, or 5xx keeps
    // the user signed in and hands back the current token so the request can
    // fail on its own terms (SyncManager queues and retries anyway).
    func refreshTokenIfNeeded() async throws -> String {
        if let existing = refreshTask {
            return try await existing.value
        }

        guard let accessData = KeychainHelper.load(key: "accessToken"),
              let accessToken = String(data: accessData, encoding: .utf8) else {
            throw AuthError.notAuthenticated
        }

        if !Self.isTokenExpiringSoon(accessToken) {
            return accessToken
        }

        let task = Task<String, Error> {
            defer { refreshTask = nil }
            do {
                return try await refreshAccessToken()
            } catch AuthError.sessionExpired {
                throw AuthError.sessionExpired
            } catch {
                logger.warning("Token refresh failed transiently, reusing current token: \(error.localizedDescription)")
                return accessToken
            }
        }
        refreshTask = task
        return try await task.value
    }

    @discardableResult
    private func refreshAccessToken() async throws -> String {
        guard let refreshData = KeychainHelper.load(key: "refreshToken"),
              let refreshToken = String(data: refreshData, encoding: .utf8) else {
            throw AuthError.notAuthenticated
        }

        do {
            let response = try await APIClient.refreshToken(refreshToken: refreshToken)
            currentUser = response.user
            try saveTokens(access: response.accessToken, refresh: response.refreshToken)
            return response.accessToken
        } catch APIClient.AuthAPIError.refreshRejected {
            logger.error("Refresh token rejected by server, signing out")
            logout()
            throw AuthError.sessionExpired
        }
    }

    // MARK: - Account Deletion

    func deleteAccount() async {
        try? await APIClient.deleteAccount()
        KeychainHelper.delete(key: "accessToken")
        KeychainHelper.delete(key: "refreshToken")
        KeychainHelper.delete(key: "currentUser")
        currentUser = nil
    }

    // MARK: - Logout

    func logout() {
        if let refreshData = KeychainHelper.load(key: "refreshToken"),
           let refreshToken = String(data: refreshData, encoding: .utf8) {
            Task { try? await APIClient.logout(refreshToken: refreshToken) }
        }
        KeychainHelper.delete(key: "accessToken")
        KeychainHelper.delete(key: "refreshToken")
        KeychainHelper.delete(key: "currentUser")
        currentUser = nil
    }

    // MARK: - Session Restore

    private func restoreSession() async {
        defer { isLoading = false }

        guard let userData = KeychainHelper.load(key: "currentUser"),
              let user = try? JSONDecoder().decode(AuthUser.self, from: userData),
              KeychainHelper.load(key: "refreshToken") != nil else {
            return
        }

        // Trust the stored session immediately; a refresh only signs the user
        // out if the server says the token is no longer valid.
        currentUser = user

        do {
            try await refreshAccessToken()
        } catch AuthError.sessionExpired {
            logger.info("Stored session rejected by server, requiring login")
        } catch {
            logger.info("Session restore refresh skipped (offline?), staying signed in")
        }
    }

    // MARK: - Helpers

    private func saveTokens(access: String, refresh: String) throws {
        try KeychainHelper.save(key: "accessToken", data: Data(access.utf8))
        try KeychainHelper.save(key: "refreshToken", data: Data(refresh.utf8))
        if let user = currentUser {
            let userData = try JSONEncoder().encode(user)
            try KeychainHelper.save(key: "currentUser", data: userData)
        }
    }

    // JWT segments are base64url (`-` and `_`, no padding), which
    // `Data(base64Encoded:)` rejects. Decoding failure used to be treated as
    // "expired", which made the app refresh on every request.
    static func isTokenExpiringSoon(_ token: String, now: Date = Date()) -> Bool {
        let parts = token.split(separator: ".")
        guard parts.count == 3,
              let payloadData = decodeBase64URL(String(parts[1])),
              let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              let exp = json["exp"] as? TimeInterval else {
            return true
        }
        return Date(timeIntervalSince1970: exp).timeIntervalSince(now) < 60
    }

    static func decodeBase64URL(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder != 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64)
    }

    // MARK: - Errors

    enum AuthError: LocalizedError {
        case notAuthenticated
        case sessionExpired
        case appleSignInFailed

        var errorDescription: String? {
            switch self {
            case .notAuthenticated: return "Not signed in."
            case .sessionExpired: return "Session expired. Please sign in again."
            case .appleSignInFailed: return "Sign in with Apple failed. Please try again."
            }
        }
    }
}
