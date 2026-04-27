import AuthenticationServices
import Foundation
import LocalAuthentication
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

    // MARK: - Biometric Quick-Unlock

    var biometricEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "biometricLoginEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "biometricLoginEnabled") }
    }

    func authenticateWithBiometric() async throws {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            throw AuthError.biometricUnavailable
        }
        let success = try await context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: "Sign in to PinkSync"
        )
        guard success else { throw AuthError.biometricFailed }
        try await refreshAccessToken()
    }

    // MARK: - Token Refresh

    private var refreshTask: Task<String, Error>?

    func refreshTokenIfNeeded() async throws -> String {
        if let existing = refreshTask {
            return try await existing.value
        }

        guard let accessData = KeychainHelper.load(key: "accessToken"),
              let accessToken = String(data: accessData, encoding: .utf8) else {
            throw AuthError.notAuthenticated
        }

        if !isTokenExpiringSoon(accessToken) {
            return accessToken
        }

        let task = Task<String, Error> {
            defer { refreshTask = nil }
            let newToken = try await refreshAccessToken()
            return newToken
        }
        refreshTask = task
        return try await task.value
    }

    @discardableResult
    private func refreshAccessToken() async throws -> String {
        guard let refreshData = KeychainHelper.load(key: "refreshToken"),
              let refreshToken = String(data: refreshData, encoding: .utf8) else {
            logout()
            throw AuthError.notAuthenticated
        }

        do {
            let response = try await APIClient.refreshToken(refreshToken: refreshToken)
            try saveTokens(access: response.accessToken, refresh: response.refreshToken)
            currentUser = response.user
            return response.accessToken
        } catch {
            logger.error("Token refresh failed: \(error.localizedDescription)")
            logout()
            throw AuthError.sessionExpired
        }
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

        currentUser = user

        do {
            try await refreshAccessToken()
        } catch {
            logger.info("Session restore failed, requiring login")
            currentUser = nil
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

    private func isTokenExpiringSoon(_ token: String) -> Bool {
        let parts = token.split(separator: ".")
        guard parts.count == 3,
              let payloadData = Data(base64Encoded: padBase64(String(parts[1]))),
              let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              let exp = json["exp"] as? TimeInterval else {
            return true
        }
        return Date(timeIntervalSince1970: exp).timeIntervalSinceNow < 60
    }

    private func padBase64(_ string: String) -> String {
        let remainder = string.count % 4
        if remainder == 0 { return string }
        return string + String(repeating: "=", count: 4 - remainder)
    }

    // MARK: - Errors

    enum AuthError: LocalizedError {
        case notAuthenticated
        case sessionExpired
        case biometricUnavailable
        case biometricFailed
        case appleSignInFailed

        var errorDescription: String? {
            switch self {
            case .notAuthenticated: return "Not signed in."
            case .sessionExpired: return "Session expired. Please sign in again."
            case .biometricUnavailable: return "Biometric authentication is not available."
            case .biometricFailed: return "Biometric authentication failed."
            case .appleSignInFailed: return "Sign in with Apple failed. Please try again."
            }
        }
    }
}
