import Foundation
import SwiftData
import UIKit
import os

private let logger = Logger(subsystem: "PinkSync", category: "APIClient")

enum APIClient {
    static var baseURL = Secrets.baseURL
    static var authManager: AuthManager?

    // MARK: - Authorized Request Builder

    private static func authorizedRequest(url: URL, method: String = "GET") async throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let manager = authManager {
            let token = try await manager.refreshTokenIfNeeded()
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if method != "GET" && method != "HEAD" {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    // MARK: - Auth API

    struct LoginResponse: Decodable {
        let success: Bool
        let accessToken: String
        let refreshToken: String
        let user: AuthUser
    }

    struct RefreshResponse: Decodable {
        let success: Bool
        let accessToken: String
        let refreshToken: String
        let user: AuthUser
    }

    static func login(email: String, password: String) async throws -> LoginResponse {
        guard let url = URL(string: "\(baseURL)/api/auth/login") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = ["email": email, "password": password]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if http.statusCode == 401 {
            let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let message = body?["message"] as? String ?? "Invalid email or password"
            throw AuthAPIError.invalidCredentials(message)
        }
        guard (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(LoginResponse.self, from: data)
    }

    static func refreshToken(refreshToken: String) async throws -> RefreshResponse {
        guard let url = URL(string: "\(baseURL)/api/auth/refresh") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = ["refreshToken": refreshToken]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        // 401 means the server no longer honours this refresh token (revoked,
        // expired, or the account is gone). Anything else is transient.
        if http.statusCode == 401 {
            throw AuthAPIError.refreshRejected
        }
        guard (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(RefreshResponse.self, from: data)
    }

    static func logout(refreshToken: String) async throws {
        guard let url = URL(string: "\(baseURL)/api/auth/logout") else { return }
        var request = try await authorizedRequest(url: url, method: "POST")
        let payload = ["refreshToken": refreshToken]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        _ = try? await URLSession.shared.data(for: request)
    }

    static func deleteAccount() async throws {
        guard let url = URL(string: "\(baseURL)/api/auth/delete-account") else {
            throw URLError(.badURL)
        }
        let request = try await authorizedRequest(url: url, method: "DELETE")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if !(200...299).contains(http.statusCode) {
            let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let message = body?["message"] as? String ?? "Account deletion failed"
            throw AuthAPIError.registrationFailed(message)
        }
    }

    static func register(email: String, displayName: String, password: String) async throws -> LoginResponse {
        guard let url = URL(string: "\(baseURL)/api/auth/register") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: String] = ["email": email, "displayName": displayName, "password": password]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if !(200...299).contains(http.statusCode) {
            let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let message = body?["message"] as? String ?? "Registration failed"
            throw AuthAPIError.registrationFailed(message)
        }
        return try JSONDecoder().decode(LoginResponse.self, from: data)
    }

    static func appleSignIn(identityToken: String, fullName: PersonNameComponents?, email: String?) async throws -> LoginResponse {
        guard let url = URL(string: "\(baseURL)/api/auth/apple") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var payload: [String: Any] = ["identityToken": identityToken]
        if let email { payload["email"] = email }
        if let givenName = fullName?.givenName, let familyName = fullName?.familyName {
            payload["fullName"] = ["givenName": givenName, "familyName": familyName]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if !(200...299).contains(http.statusCode) {
            let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let message = body?["message"] as? String ?? "Apple sign-in failed"
            throw AuthAPIError.registrationFailed(message)
        }
        return try JSONDecoder().decode(LoginResponse.self, from: data)
    }

    enum AuthAPIError: LocalizedError {
        case invalidCredentials(String)
        case registrationFailed(String)
        case refreshRejected
        var errorDescription: String? {
            switch self {
            case .invalidCredentials(let message): return message
            case .registrationFailed(let message): return message
            case .refreshRejected: return "Session expired. Please sign in again."
            }
        }
    }

    // MARK: - User Management API

    struct UserResponse: Decodable, Identifiable, Hashable {
        let userId: String
        let email: String
        let displayName: String
        let role: UserRole
        let isActive: Bool
        let createdAt: String?

        var id: String { userId }
    }

    struct UsersListResponse: Decodable {
        let success: Bool
        let users: [UserResponse]
    }

    struct CreateUserResponse: Decodable {
        let success: Bool
        let user: UserResponse
    }

    static func fetchUsers() async throws -> [UserResponse] {
        guard let url = URL(string: "\(baseURL)/api/users") else {
            throw URLError(.badURL)
        }
        let request = try await authorizedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let result = try JSONDecoder().decode(UsersListResponse.self, from: data)
        return result.users
    }

    static func createUser(email: String, displayName: String, password: String, role: UserRole) async throws -> UserResponse {
        guard let url = URL(string: "\(baseURL)/api/users") else {
            throw URLError(.badURL)
        }
        var request = try await authorizedRequest(url: url, method: "POST")
        let payload: [String: String] = [
            "email": email,
            "displayName": displayName,
            "password": password,
            "role": role.rawValue
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let result = try JSONDecoder().decode(CreateUserResponse.self, from: data)
        return result.user
    }

    static func updateUser(userId: String, displayName: String? = nil, role: UserRole? = nil, isActive: Bool? = nil, password: String? = nil) async throws {
        guard let url = URL(string: "\(baseURL)/api/users/\(userId)") else {
            throw URLError(.badURL)
        }
        var request = try await authorizedRequest(url: url, method: "PUT")
        var payload: [String: Any] = [:]
        if let displayName { payload["displayName"] = displayName }
        if let role { payload["role"] = role.rawValue }
        if let isActive { payload["isActive"] = isActive }
        if let password { payload["password"] = password }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    static func deleteUser(userId: String) async throws {
        guard let url = URL(string: "\(baseURL)/api/users/\(userId)") else {
            throw URLError(.badURL)
        }
        let request = try await authorizedRequest(url: url, method: "DELETE")
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    struct MergeResponse: Decodable {
        let success: Bool
        let message: String
        let user: UserResponse
    }

    static func mergeUsers(primaryUserId: String, duplicateUserId: String) async throws -> MergeResponse {
        guard let url = URL(string: "\(baseURL)/api/users/merge") else {
            throw URLError(.badURL)
        }
        var request = try await authorizedRequest(url: url, method: "POST")
        let payload: [String: String] = [
            "primaryUserId": primaryUserId,
            "duplicateUserId": duplicateUserId
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if !(200...299).contains(http.statusCode) {
            let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let message = body?["message"] as? String ?? "Merge failed"
            throw AuthAPIError.registrationFailed(message)
        }
        return try JSONDecoder().decode(MergeResponse.self, from: data)
    }

    struct StartingGoaliePayload: Encodable {
        let playerId: String
        let playerName: String
        let playerNumber: Int
    }

    struct GamePayload: Encodable {
        let gameId: String
        let scheduleId: String?
        /// Left out for a league game rather than sent as null. The server
        /// reads a missing field as "work it out from the bout", and an
        /// explicit null as "not a tournament game" — which would untag a game
        /// this device simply has not heard the tournament of yet.
        let tournamentId: String?
        let date: String
        let opponent: String
        let location: String
        let goalsFor: Int
        let goalsAgainst: Int
        let result: String
        let startingGoalie: StartingGoaliePayload?
        let playerStats: [PlayerStatPayload]
        let goalieStats: [GoalieStatPayload]
        let events: [EventPayload]
    }

    struct EventPayload: Encodable {
        let type: String
        let period: Int
        let clockTime: String
        let playerId: String?
        let playerName: String
        let playerNumber: Int
        let assist1Id: String?
        let assist1Name: String?
        let assist1Number: Int?
        let assist2Id: String?
        let assist2Name: String?
        let assist2Number: Int?
        let penaltyMinutes: Int?
        let penaltyType: String?
        let opponentNumber: String?
        let isPowerPlay: Bool?
        let isShortHanded: Bool?
        let onIcePlayerIds: String?
    }

    struct ShiftPayload: Encodable {
        let period: Int
        let duration: Int
        let startClockTime: String
        let endClockTime: String
    }

    struct PlayerStatPayload: Encodable {
        let playerId: String
        let playerName: String
        let playerNumber: Int
        let position: String
        let shots: Int
        let goals: Int
        let assists: Int
        let hits: Int
        let blocks: Int
        let penaltyMinutes: Int
        let powerPlayGoals: Int
        let shortHandedGoals: Int
        let powerPlayAssists: Int
        let shortHandedAssists: Int
        let gameWinningGoals: Int
        let faceoffWins: Int
        let faceoffLosses: Int
        let timeOnIce: Int?
        let plusMinus: Int?
        let shifts: [ShiftPayload]?
    }

    struct GoalieStatPayload: Encodable {
        let playerId: String
        let playerName: String
        let playerNumber: Int
        let shotsAgainst: Int
        let goalsAgainst: Int
        let result: String
        let shootoutRounds: [ShootoutRoundPayload]
    }

    struct ShootoutRoundPayload: Encodable {
        let roundNumber: Int
        let isGoal: Bool
    }

    /// Errors surfaced to the user before submission.
    enum ValidationError: LocalizedError {
        case missingResult
        case missingOpponent
        case negativeScore
        case goalieGAExceedsSA(name: String)

        var errorDescription: String? {
            switch self {
            case .missingResult: return "Set a game result before sending."
            case .missingOpponent: return "Opponent name is missing."
            case .negativeScore: return "Score cannot be negative."
            case .goalieGAExceedsSA(let name):
                return "\(name) has more goals against than shots against."
            }
        }
    }

    static func sendGameStats(game: Game) async throws {
        // ── Validation ──────────────────────────────────────────────
        if game.opponent.trimmingCharacters(in: .whitespaces).isEmpty {
            throw ValidationError.missingOpponent
        }
        let validResults: Set<String> = ["W", "L", "OTL", "SOW", "SOL"]
        if !validResults.contains(game.result) {
            throw ValidationError.missingResult
        }
        if game.goalsFor < 0 || game.goalsAgainst < 0 {
            throw ValidationError.negativeScore
        }

        guard let url = URL(string: "\(baseURL)/api/game-stats") else {
            throw URLError(.badURL)
        }
        var request = try await authorizedRequest(url: url, method: "POST")

        let playerPayloads = game.playerStats.compactMap { stat -> PlayerStatPayload? in
            guard let player = stat.player else { return nil }
            let shiftPayloads: [ShiftPayload]? = stat.shifts.isEmpty ? nil : stat.shifts
                .sorted { a, b in
                    if a.period != b.period { return a.period < b.period }
                    return a.startClockTime > b.startClockTime
                }
                .map { ShiftPayload(period: $0.period, duration: $0.duration, startClockTime: $0.startClockTime, endClockTime: $0.endClockTime) }
            return PlayerStatPayload(
                playerId: player.playerId,
                playerName: player.name,
                playerNumber: player.number,
                position: player.position,
                shots: stat.shots,
                goals: stat.goals,
                assists: stat.assists,
                hits: stat.hits,
                blocks: stat.blocks,
                penaltyMinutes: stat.penaltyMinutes,
                powerPlayGoals: stat.powerPlayGoals,
                shortHandedGoals: stat.shortHandedGoals,
                powerPlayAssists: stat.powerPlayAssists,
                shortHandedAssists: stat.shortHandedAssists,
                gameWinningGoals: stat.gameWinningGoals,
                faceoffWins: stat.faceoffWins,
                faceoffLosses: stat.faceoffLosses,
                timeOnIce: stat.timeOnIce > 0 ? stat.timeOnIce : nil,
                plusMinus: stat.plusMinus != 0 ? stat.plusMinus : nil,
                shifts: shiftPayloads
            )
        }

        // Deduplicate goalie stats by (playerName, playerNumber).
        // If the same goalie appears more than once, keep only the entry
        // with the highest shotsAgainst (the most complete record).
        var seenGoalies = Set<String>()
        let deduped = game.goalieStats
            .compactMap { stat -> (GameGoalieStats, Player)? in
                guard let player = stat.player else { return nil }
                return (stat, player)
            }
            .sorted { $0.0.shotsAgainst > $1.0.shotsAgainst }
            .filter { seenGoalies.insert("\($0.1.name)_\($0.1.number)").inserted }

        // Validate goalie SA >= GA
        for (stat, player) in deduped {
            if stat.goalsAgainst > stat.shotsAgainst {
                throw ValidationError.goalieGAExceedsSA(name: player.name)
            }
        }

        // The game result is the source of truth for the decision letter, so a
        // result corrected on the game screen after the fact still reaches the
        // goalie line. With more than one goalie, only the goalie of record
        // (the line the live scorer gave a result to) gets the decision; the
        // relief goalie is sent with no decision, the way hockey records it.
        let gameResult = game.result
        let holders = decisionHolders(lines: deduped, startingGoalie: game.startingGoalie)
        let goaliePayloads = deduped.map { stat, player in
            let rounds = stat.shootoutRounds
                .sorted { $0.roundNumber < $1.roundNumber }
                .map { ShootoutRoundPayload(roundNumber: $0.roundNumber, isGoal: $0.isGoal) }
            let getsDecision = holders.contains(player.persistentModelID)
            return GoalieStatPayload(
                playerId: player.playerId,
                playerName: player.name,
                playerNumber: player.number,
                shotsAgainst: stat.shotsAgainst,
                goalsAgainst: stat.goalsAgainst,
                result: getsDecision ? gameResult : "",
                shootoutRounds: rounds
            )
        }

        var startingGoaliePayload: StartingGoaliePayload?
        if let goalie = game.startingGoalie {
            startingGoaliePayload = StartingGoaliePayload(
                playerId: goalie.playerId,
                playerName: goalie.name,
                playerNumber: goalie.number
            )
        }

        let eventPayloads = game.events.map { event in
            EventPayload(
                type: event.type,
                period: event.period,
                clockTime: event.clockTime,
                playerId: event.playerId.isEmpty ? nil : event.playerId,
                playerName: event.playerName,
                playerNumber: event.playerNumber,
                assist1Id: event.assist1Id.isEmpty ? nil : event.assist1Id,
                assist1Name: event.assist1Name.isEmpty ? nil : event.assist1Name,
                assist1Number: event.assist1Number == 0 ? nil : event.assist1Number,
                assist2Id: event.assist2Id.isEmpty ? nil : event.assist2Id,
                assist2Name: event.assist2Name.isEmpty ? nil : event.assist2Name,
                assist2Number: event.assist2Number == 0 ? nil : event.assist2Number,
                penaltyMinutes: event.penaltyMinutes == 0 ? nil : event.penaltyMinutes,
                penaltyType: event.penaltyType.isEmpty ? nil : event.penaltyType,
                opponentNumber: event.opponentNumber.isEmpty ? nil : event.opponentNumber,
                isPowerPlay: event.isPowerPlay ? true : nil,
                isShortHanded: event.isShortHanded ? true : nil,
                onIcePlayerIds: event.onIcePlayerIds.isEmpty ? nil : event.onIcePlayerIds
            )
        }

        let payload = GamePayload(
            gameId: game.gameId,
            scheduleId: game.scheduleId.isEmpty ? nil : game.scheduleId,
            tournamentId: game.tournamentId.isEmpty ? nil : game.tournamentId,
            date: Season.apiTimestamp(for: game.date),
            opponent: game.opponent,
            location: game.location,
            goalsFor: game.goalsFor,
            goalsAgainst: game.goalsAgainst,
            result: game.result,
            startingGoalie: startingGoaliePayload,
            playerStats: playerPayloads,
            goalieStats: goaliePayloads,
            events: eventPayloads
        )

        request.httpBody = try JSONEncoder().encode(payload)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    /// Which goalie lines carry the game's decision when sent.
    ///
    /// One goalie: always them. Otherwise the lines live scoring gave a result
    /// to (the goalie of record). If none has one — a hand-entered or
    /// reopened game — the starting goalie, else whoever faced the most shots.
    /// Never every goalie, which would double-count the team record.
    static func decisionHolders(lines: [(GameGoalieStats, Player)], startingGoalie: Player?) -> Set<PersistentIdentifier> {
        if lines.count <= 1 { return Set(lines.map { $0.1.persistentModelID }) }
        let decided = lines.filter { !$0.0.result.isEmpty }.map { $0.1.persistentModelID }
        if !decided.isEmpty { return Set(decided) }
        if let starter = startingGoalie, lines.contains(where: { $0.1.persistentModelID == starter.persistentModelID }) {
            return [starter.persistentModelID]
        }
        return Set([lines.max { $0.0.shotsAgainst < $1.0.shotsAgainst }?.1.persistentModelID].compactMap { $0 })
    }

    struct TeamLogoPayload: Encodable {
        let teamName: String
        let logoBase64: String
    }

    /// Resize and compress an image to fit within maxSize x maxSize at the given JPEG quality.
    private static func compressLogo(_ data: Data, maxSize: CGFloat = 640, quality: CGFloat = 0.7) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let size = image.size
        let scale = min(maxSize / size.width, maxSize / size.height, 1.0)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: quality)
    }

    /// Upload a team logo to the server. Compresses to 640×640 JPEG quality 70% first.
    /// Fails silently — logo upload is best-effort.
    static func sendTeamLogo(teamName: String, logoData: Data) async {
        guard let compressed = compressLogo(logoData) else { return }
        guard let url = URL(string: "\(baseURL)/api/team-logo") else { return }

        do {
            var request = try await authorizedRequest(url: url, method: "POST")
            let payload = TeamLogoPayload(
                teamName: teamName,
                logoBase64: compressed.base64EncodedString()
            )
            request.httpBody = try JSONEncoder().encode(payload)
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                logger.warning("Team logo upload failed: HTTP \(http.statusCode)")
            }
        } catch {
            logger.error("Team logo upload error: \(error.localizedDescription)")
        }
    }

    /// Delete a game from the server by its stable gameId.
    static func deleteGameFromServer(gameId: String) async throws {
        guard !gameId.isEmpty else { return }
        guard let url = URL(string: "\(baseURL)/api/game/\(gameId)") else { return }
        let request = try await authorizedRequest(url: url, method: "DELETE")

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    // MARK: - Seasons

    /// The `?season=` value for the season-scoped read endpoints
    /// (`/api/roster`, `/api/games`, `/api/schedule`).
    enum SeasonQuery {
        /// No parameter: the server's current season.
        case current
        /// Every season.
        case all
        case id(String)

        var queryItem: URLQueryItem? {
            switch self {
            case .current: nil
            case .all: URLQueryItem(name: "season", value: Season.allId)
            case .id(let id): URLQueryItem(name: "season", value: id)
            }
        }
    }

    private static func url(path: String, season: SeasonQuery = .current) throws -> URL {
        guard var components = URLComponents(string: "\(baseURL)\(path)") else {
            throw URLError(.badURL)
        }
        if let item = season.queryItem {
            components.queryItems = [item]
        }
        guard let url = components.url else { throw URLError(.badURL) }
        return url
    }

    /// The server's `{ success: false, message }` body as an error, so a 400
    /// such as "Unknown season id" reaches the screen instead of a generic
    /// "bad server response".
    private static func serverError(_ data: Data, status: Int, fallback: String) -> Error {
        let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let message = body?["message"] as? String ?? fallback
        return NSError(domain: "PinkSyncAPI", code: status, userInfo: [NSLocalizedDescriptionKey: message])
    }

    /// Fetch the season list, oldest first, with `isCurrent` resolved.
    static func fetchSeasons() async throws -> [Season] {
        let request = try await authorizedRequest(url: try url(path: "/api/seasons"))
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode([Season].self, from: data)
    }

    struct SaveSeasonsResponse: Decodable {
        let success: Bool
        let seasons: [Season]
    }

    /// Replace the season list (admin). Returns the list as the server now has it.
    static func saveSeasons(_ seasons: [Season]) async throws -> [Season] {
        var request = try await authorizedRequest(url: try url(path: "/api/seasons"), method: "PUT")
        request.httpBody = try JSONEncoder().encode(seasons)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw serverError(data, status: status, fallback: "Could not save seasons")
        }
        return try JSONDecoder().decode(SaveSeasonsResponse.self, from: data).seasons
    }

    // MARK: - Live Score

    struct LiveScorePayload: Encodable {
        let gameId: String
        let opponent: String
        let date: String
        let goalsFor: Int
        let goalsAgainst: Int
        let shotsFor: Int
        let shotsAgainst: Int
        let period: String
        let clock: String
        let clockRunning: Bool
        /// Lets the banner name the tournament. Left out for a league game.
        let tournamentId: String?
        /// The latest play worth announcing. Left out when there is none, which
        /// also takes down one that was undone.
        var lastPlay: LivePlay? = nil
    }

    /// One play, for the website's lower third.
    struct LivePlay: Encodable, Equatable {
        struct Assist: Encodable, Equatable {
            let name: String
            let number: Int?
        }

        /// Unique per play, so the website shows each one once.
        let id: String
        /// "goal", "shot", "save", "block", "hit" or "penalty".
        let type: String
        let playerId: String
        let playerName: String
        /// Nil for a substitute with no number.
        let playerNumber: Int?
        let assists: [Assist]
        /// "PP", "SH" or empty.
        let strength: String
        /// The kind of penalty, e.g. "Minor".
        let note: String
    }

    /// Push the scoreboard for the website's live banner.
    static func pushLiveScore(_ payload: LiveScorePayload) async throws {
        var request = try await authorizedRequest(url: try url(path: "/api/live"), method: "PUT")
        request.httpBody = try JSONEncoder().encode(payload)
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    /// Take the live banner down, but only if it is still showing this game.
    /// With no game, whatever is showing comes down.
    static func clearLiveScore(gameId: String? = nil) async throws {
        guard var components = URLComponents(string: "\(baseURL)/api/live") else { throw URLError(.badURL) }
        if let gameId, !gameId.isEmpty {
            components.queryItems = [URLQueryItem(name: "gameId", value: gameId)]
        }
        guard let url = components.url else { throw URLError(.badURL) }
        let request = try await authorizedRequest(url: url, method: "DELETE")
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    /// A game that is deleted or reset must not stay live on the website.
    /// Best effort: the banner expires by itself if this never gets through.
    static func takeDownLiveScore(for gameId: String) {
        guard !gameId.isEmpty else { return }
        Task { try? await clearLiveScore(gameId: gameId) }
    }

    // MARK: - Tournaments

    /// Fetch the tournament list, oldest first.
    static func fetchTournaments() async throws -> [Tournament] {
        let request = try await authorizedRequest(url: try url(path: "/api/tournaments"))
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode([Tournament].self, from: data)
    }

    struct SaveTournamentsResponse: Decodable {
        let success: Bool
        let tournaments: [Tournament]
    }

    /// Replace the tournament list (admin). Returns the list as the server now
    /// has it.
    static func saveTournaments(_ tournaments: [Tournament]) async throws -> [Tournament] {
        var request = try await authorizedRequest(url: try url(path: "/api/tournaments"), method: "PUT")
        request.httpBody = try JSONEncoder().encode(tournaments)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw serverError(data, status: status, fallback: "Could not save tournaments")
        }
        return try JSONDecoder().decode(SaveTournamentsResponse.self, from: data).tournaments
    }

    /// Move a game already on the server into a tournament, or back to league
    /// play with an empty id. Sending the game again cannot do the second:
    /// see `GamePayload.tournamentId`.
    static func setGameTournament(gameId: String, tournamentId: String) async throws {
        guard let encoded = gameId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw URLError(.badURL)
        }
        var request = try await authorizedRequest(url: try url(path: "/api/game/\(encoded)/tournament"), method: "PUT")
        // An explicit null is what takes a game out of its tournament.
        var body: [String: Any] = ["tournamentId": NSNull()]
        if !tournamentId.isEmpty {
            body["tournamentId"] = tournamentId
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw serverError(data, status: status, fallback: "Could not change the tournament")
        }
    }

    /// Fetch the all-time franchise record book.
    static func fetchRecords() async throws -> FranchiseRecords {
        let request = try await authorizedRequest(url: try url(path: "/api/records"))
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(FranchiseRecords.self, from: data)
    }

    // MARK: - Roster Sync

    struct RosterPlayerResponse: Decodable {
        let playerId: String
        let name: String
        let number: Int
        let position: String
        let isGoalie: Bool?
        let isActive: Bool
        let isSubstitute: Bool?
        let photo: String?
        /// Season ids the player was on the team for. Nil means every season.
        let seasons: [String]?

        var playsGoalie: Bool { isGoalie ?? (position == "Goalie") }
    }

    /// Fetch the roster. Defaults to the current season, matching the server;
    /// pass `.all` for everyone who has ever played.
    static func fetchRoster(season: SeasonQuery = .current) async throws -> [RosterPlayerResponse] {
        let request = try await authorizedRequest(url: try url(path: "/api/roster", season: season))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode([RosterPlayerResponse].self, from: data)
    }

    /// Save one player's roster entry on the server.
    ///
    /// Reads the roster exactly as stored (`/api/roster/raw`), merges this
    /// player in and writes the whole list back. Fields the app does not own
    /// survive that way: every other player's season membership, stored photo
    /// paths and `jerseyDisplay`. Pushing the app's own copy of the roster used
    /// to drop every player's `seasons` and pin cache-busted photo URLs into
    /// the stored roster.
    ///
    /// A `seasonIds` of nil leaves the server's membership for this player as
    /// it is; an empty array explicitly removes them from every season.
    static func savePlayer(_ player: Player) async throws {
        let rawRequest = try await authorizedRequest(url: try url(path: "/api/roster/raw"))
        let (rawData, rawResponse) = try await URLSession.shared.data(for: rawRequest)
        guard let rawHttp = rawResponse as? HTTPURLResponse,
              (200...299).contains(rawHttp.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard var roster = try JSONSerialization.jsonObject(with: rawData) as? [[String: Any]] else {
            throw URLError(.cannotParseResponse)
        }

        let index = roster.firstIndex { $0["playerId"] as? String == player.playerId }
        var entry = index.map { roster[$0] } ?? ["playerId": player.playerId]
        entry["name"] = player.name
        entry["number"] = player.number
        entry["position"] = player.position
        entry["isGoalie"] = player.isGoalie
        entry["isActive"] = player.isActive
        entry["isSubstitute"] = player.isSubstitute
        if let seasonIds = player.seasonIds {
            entry["seasons"] = seasonIds
        }
        // A brand-new player's photo upload happens before their roster entry
        // exists, so the photo endpoint had nothing to attach it to. Carry the
        // stored path over (without the cache-busting query) in that one case.
        if entry["photo"] == nil, let photoPath = player.photoPath {
            entry["photo"] = photoPath.split(separator: "?", maxSplits: 1).first.map(String.init)
        }

        if let index {
            roster[index] = entry
        } else {
            roster.append(entry)
        }

        var request = try await authorizedRequest(url: try url(path: "/api/roster"), method: "PUT")
        request.httpBody = try JSONSerialization.data(withJSONObject: roster)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw serverError(data, status: status, fallback: "Roster save failed")
        }
    }

    struct PlayerPhotoResponse: Decodable {
        let success: Bool
        let photoPath: String?
    }

    /// Upload a player photo. Compresses to 640×640 JPEG. Returns the server photo path.
    static func sendPlayerPhoto(playerId: String, photoData: Data) async throws -> String {
        guard let compressed = compressLogo(photoData) else {
            throw URLError(.cannotDecodeContentData)
        }
        guard let url = URL(string: "\(baseURL)/api/player-photo") else {
            throw URLError(.badURL)
        }
        var request = try await authorizedRequest(url: url, method: "POST")

        let payload: [String: String] = [
            "playerId": playerId,
            "photoBase64": compressed.base64EncodedString()
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(PlayerPhotoResponse.self, from: data)
        return decoded.photoPath ?? ""
    }

    // MARK: - Schedule

    struct ScheduleEntry: Decodable, Identifiable {
        let id: String
        let date: String
        let opponent: String
        let location: String
        let time: String
        /// Nil on entries that predate the field; only an explicit `false` is
        /// an away game.
        let isHome: Bool?
        /// Set on tournament bouts. A game started from one inherits it.
        let tournamentId: String?

        /// "vs Opponent" at home, "@ Opponent" on the road.
        var matchupTitle: String {
            isHome == false ? "@ \(opponent)" : "vs \(opponent)"
        }

        var displayDate: String {
            let parts = date.split(separator: "-")
            guard parts.count == 3,
                  let month = Int(parts[1]),
                  let day = Int(parts[2]) else { return date }
            let months = ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
            return "\(months[month]) \(day)"
        }
    }

    struct ScheduleEntryPayload: Encodable {
        let date: String
        let opponent: String
        let location: String
        let time: String
        let isHome: Bool?
        let tournamentId: String?
    }

    struct AddScheduleResponse: Decodable {
        let success: Bool
        let entry: ScheduleEntry?
    }

    /// Fetch scheduled bouts. Defaults to the current season, matching the server.
    static func fetchSchedule(season: SeasonQuery = .current) async throws -> [ScheduleEntry] {
        let request = try await authorizedRequest(url: try url(path: "/api/schedule", season: season))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode([ScheduleEntry].self, from: data)
    }

    static func addScheduleEntry(date: String, opponent: String, location: String, time: String, isHome: Bool? = nil, tournamentId: String? = nil) async throws -> ScheduleEntry {
        var request = try await authorizedRequest(url: try url(path: "/api/schedule"), method: "POST")

        let payload = ScheduleEntryPayload(date: date, opponent: opponent, location: location, time: time, isHome: isHome, tournamentId: tournamentId)
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw serverError(data, status: status, fallback: "Could not add bout")
        }
        let result = try JSONDecoder().decode(AddScheduleResponse.self, from: data)
        guard let entry = result.entry else { throw URLError(.cannotParseResponse) }
        return entry
    }

    static func deleteScheduleEntry(id: String) async throws {
        guard let url = URL(string: "\(baseURL)/api/schedule/\(id)") else {
            throw URLError(.badURL)
        }
        let request = try await authorizedRequest(url: url, method: "DELETE")

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    // MARK: - Game Sync

    struct GameStartingGoalieResponse: Decodable {
        let playerId: String?
        let playerName: String
        let playerNumber: Int
    }

    struct ShiftResponse: Decodable {
        let period: Int
        let duration: Int
        let startClockTime: String?
        let endClockTime: String?
    }

    struct GamePlayerStatResponse: Decodable {
        let playerId: String?
        let playerName: String
        let playerNumber: Int
        let position: String?
        let shots: Int?
        let goals: Int?
        let assists: Int?
        let hits: Int?
        let blocks: Int?
        let penaltyMinutes: Int?
        let powerPlayGoals: Int?
        let shortHandedGoals: Int?
        let powerPlayAssists: Int?
        let shortHandedAssists: Int?
        let gameWinningGoals: Int?
        let faceoffWins: Int?
        let faceoffLosses: Int?
        let timeOnIce: Int?
        let plusMinus: Int?
        let shifts: [ShiftResponse]?
    }

    struct ShootoutRoundResponse: Decodable {
        let roundNumber: Int
        let isGoal: Bool
    }

    struct GameGoalieStatResponse: Decodable {
        let playerId: String?
        let playerName: String
        let playerNumber: Int
        let shotsAgainst: Int
        let goalsAgainst: Int
        let result: String
        let shootoutRounds: [ShootoutRoundResponse]?
    }

    struct GameResponse: Decodable {
        let gameId: String?
        let scheduleId: String?
        let tournamentId: String?
        let date: String
        let opponent: String
        let location: String?
        let goalsFor: Int
        let goalsAgainst: Int
        let result: String
        let startingGoalie: GameStartingGoalieResponse?
        let playerStats: [GamePlayerStatResponse]?
        let goalieStats: [GameGoalieStatResponse]?
    }

    /// Fetch games from the server. The server defaults to the current season,
    /// so a sync that reconciles the whole local store must ask for `.all`.
    /// Regular-season, playoff and tournament games all come back;
    /// `/api/games` never filters by type unless asked.
    static func fetchGames(season: SeasonQuery = .current) async throws -> [GameResponse] {
        let request = try await authorizedRequest(url: try url(path: "/api/games", season: season))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode([GameResponse].self, from: data)
    }

    // MARK: - MVP Voting

    struct MvpVotePlayer: Decodable, Hashable {
        let playerId: String?
        let playerName: String?
        let playerNumber: Int?
    }

    struct MvpVoteStanding: Decodable, Identifiable {
        let playerId: String?
        let playerName: String?
        let playerNumber: Int?
        let votes: Int
        let standing: Int?
        let isWinner: Bool?
        var id: String { playerId ?? "\(playerName ?? "")-\(playerNumber ?? 0)" }
    }

    struct MvpVoteBallot: Decodable {
        let browserId: String?
        let votedForPlayerId: String?
        let voteCastAt: String?
    }

    struct MvpVoteFinalMvp: Decodable {
        let playerId: String?
        let playerName: String?
        let playerNumber: Int?
        let votes: Int?
    }

    /// Public MVP vote summary. Standings + finalMvp only populated after close.
    struct MvpVoteSummary: Decodable {
        let gameId: String?
        let status: String
        let totalEligibleCount: Int?
        let totalBallotCount: Int
        let votedCount: Int
        let finalMvp: MvpVoteFinalMvp?
        let standings: [MvpVoteStanding]?
    }

    /// Admin MVP vote summary — includes individual ballots for live tallying.
    struct MvpVoteAdminSummary: Decodable {
        let gameId: String?
        let status: String
        let totalEligibleCount: Int?
        let totalBallotCount: Int
        let votedCount: Int
        let finalMvp: MvpVoteFinalMvp?
        let ballots: [MvpVoteBallot]?
        let lineup: [MvpVotePlayer]?
    }

    private struct MvpVoteSummaryEnvelope: Decodable {
        let success: Bool
        let summary: MvpVoteSummary?
    }

    private struct MvpVoteAdminSummaryEnvelope: Decodable {
        let success: Bool
        let summary: MvpVoteAdminSummary?
    }

    /// Fetch the public MVP vote status for a game (visible to anyone).
    static func fetchMvpVoteStatus(gameId: String) async throws -> MvpVoteSummary? {
        guard let url = URL(string: "\(baseURL)/api/games/\(gameId)/mvp-vote-status") else {
            throw URLError(.badURL)
        }
        let request = try await authorizedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(MvpVoteSummaryEnvelope.self, from: data).summary
    }

    /// Fetch the admin MVP vote summary (includes individual ballots for live tallying).
    static func fetchMvpVoteAdminSummary(gameId: String) async throws -> MvpVoteAdminSummary? {
        guard let url = URL(string: "\(baseURL)/api/games/\(gameId)/mvp-vote") else {
            throw URLError(.badURL)
        }
        let request = try await authorizedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(MvpVoteAdminSummaryEnvelope.self, from: data).summary
    }

    /// Close the MVP vote for a game (admin only). Returns the post-close public summary.
    @discardableResult
    static func closeMvpVote(gameId: String) async throws -> MvpVoteSummary? {
        guard let url = URL(string: "\(baseURL)/api/games/\(gameId)/mvp-vote-close") else {
            throw URLError(.badURL)
        }
        let request = try await authorizedRequest(url: url, method: "POST")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(MvpVoteSummaryEnvelope.self, from: data).summary
    }

    /// Open (or reopen) MVP voting for a game (admin only). Duration in minutes.
    @discardableResult
    static func openMvpVote(gameId: String, durationMinutes: Int = 30) async throws -> MvpVoteSummary? {
        guard let url = URL(string: "\(baseURL)/api/games/\(gameId)/mvp-vote-open") else {
            throw URLError(.badURL)
        }
        var request = try await authorizedRequest(url: url, method: "POST")
        let payload: [String: Any] = ["durationMinutes": durationMinutes]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if !(200...299).contains(http.statusCode) {
            let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let message = body?["message"] as? String ?? "Failed to open MVP voting"
            throw NSError(domain: "MvpVote", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
        }
        return try JSONDecoder().decode(MvpVoteSummaryEnvelope.self, from: data).summary
    }
}
