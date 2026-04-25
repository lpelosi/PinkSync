import Foundation
import UIKit

enum APIClient {
    static var baseURL = Secrets.baseURL
    static let apiKey = Secrets.apiKey

    struct StartingGoaliePayload: Encodable {
        let playerId: String
        let playerName: String
        let playerNumber: Int
    }

    struct GamePayload: Encodable {
        let gameId: String
        let date: String
        let opponent: String
        let location: String
        let goalsFor: Int
        let goalsAgainst: Int
        let result: String
        let startingGoalie: StartingGoaliePayload?
        let playerStats: [PlayerStatPayload]
        let goalieStats: [GoalieStatPayload]
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

        let url = URL(string: "\(baseURL)/api/game-stats")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")

        let dateFormatter = ISO8601DateFormatter()

        let playerPayloads = game.playerStats.compactMap { stat -> PlayerStatPayload? in
            guard let player = stat.player else { return nil }
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
                penaltyMinutes: stat.penaltyMinutes
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

        // Derive goalie result from the game result (single source of truth).
        let gameResult = game.result
        let goaliePayloads = deduped.map { stat, player in
            let rounds = stat.shootoutRounds
                .sorted { $0.roundNumber < $1.roundNumber }
                .map { ShootoutRoundPayload(roundNumber: $0.roundNumber, isGoal: $0.isGoal) }
            return GoalieStatPayload(
                playerId: player.playerId,
                playerName: player.name,
                playerNumber: player.number,
                shotsAgainst: stat.shotsAgainst,
                goalsAgainst: stat.goalsAgainst,
                result: gameResult,
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

        let payload = GamePayload(
            gameId: game.gameId,
            date: dateFormatter.string(from: game.date),
            opponent: game.opponent,
            location: game.location,
            goalsFor: game.goalsFor,
            goalsAgainst: game.goalsAgainst,
            result: game.result,
            startingGoalie: startingGoaliePayload,
            playerStats: playerPayloads,
            goalieStats: goaliePayloads
        )

        request.httpBody = try JSONEncoder().encode(payload)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
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
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")

        let payload = TeamLogoPayload(
            teamName: teamName,
            logoBase64: compressed.base64EncodedString()
        )

        do {
            request.httpBody = try JSONEncoder().encode(payload)
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                print("Team logo upload failed: HTTP \(http.statusCode)")
            }
        } catch {
            print("Team logo upload error: \(error.localizedDescription)")
        }
    }

    /// Delete a game from the server by its stable gameId.
    static func deleteGameFromServer(gameId: String) async throws {
        guard !gameId.isEmpty else { return }
        guard let url = URL(string: "\(baseURL)/api/game/\(gameId)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    // MARK: - Roster Sync

    struct RosterPlayerResponse: Decodable {
        let playerId: String
        let name: String
        let number: Int
        let position: String
        let isGoalie: Bool
        let isActive: Bool
        let photo: String?
    }

    struct RosterPlayerPayload: Encodable {
        let playerId: String
        let name: String
        let number: Int
        let position: String
        let isGoalie: Bool
        let isActive: Bool
        let photo: String?
    }

    /// Fetch the full roster from the server.
    static func fetchRoster() async throws -> [RosterPlayerResponse] {
        guard let url = URL(string: "\(baseURL)/api/roster") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode([RosterPlayerResponse].self, from: data)
    }

    /// Push the full roster to the server (replaces server roster).
    static func pushRoster(players: [Player]) async throws {
        guard let url = URL(string: "\(baseURL)/api/roster") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")

        let payload = players.map { player in
            RosterPlayerPayload(
                playerId: player.playerId,
                name: player.name,
                number: player.number,
                position: player.position,
                isGoalie: player.isGoalie,
                isActive: player.isActive,
                photo: player.photoPath
            )
        }

        request.httpBody = try JSONEncoder().encode(payload)
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
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
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")

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
    }

    struct AddScheduleResponse: Decodable {
        let success: Bool
        let entry: ScheduleEntry?
    }

    static func fetchSchedule() async throws -> [ScheduleEntry] {
        guard let url = URL(string: "\(baseURL)/api/schedule") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode([ScheduleEntry].self, from: data)
    }

    static func addScheduleEntry(date: String, opponent: String, location: String, time: String) async throws -> ScheduleEntry {
        guard let url = URL(string: "\(baseURL)/api/schedule") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")

        let payload = ScheduleEntryPayload(date: date, opponent: opponent, location: location, time: time)
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let result = try JSONDecoder().decode(AddScheduleResponse.self, from: data)
        guard let entry = result.entry else { throw URLError(.cannotParseResponse) }
        return entry
    }

    static func deleteScheduleEntry(id: String) async throws {
        guard let url = URL(string: "\(baseURL)/api/schedule/\(id)") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")

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

    /// Fetch all games from the server.
    static func fetchGames() async throws -> [GameResponse] {
        guard let url = URL(string: "\(baseURL)/api/games") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode([GameResponse].self, from: data)
    }
}
