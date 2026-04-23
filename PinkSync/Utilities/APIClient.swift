import Foundation

enum APIClient {
    static var baseURL = Secrets.baseURL
    static let apiKey = Secrets.apiKey

    struct StartingGoaliePayload: Encodable {
        let playerName: String
        let playerNumber: Int
    }

    struct GamePayload: Encodable {
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

    static func sendGameStats(game: Game) async throws {
        let url = URL(string: "\(baseURL)/api/game-stats")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")

        let dateFormatter = ISO8601DateFormatter()

        let playerPayloads = game.playerStats.compactMap { stat -> PlayerStatPayload? in
            guard let player = stat.player else { return nil }
            return PlayerStatPayload(
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

        let goaliePayloads = game.goalieStats.compactMap { stat -> GoalieStatPayload? in
            guard let player = stat.player else { return nil }
            let rounds = stat.shootoutRounds
                .sorted { $0.roundNumber < $1.roundNumber }
                .map { ShootoutRoundPayload(roundNumber: $0.roundNumber, isGoal: $0.isGoal) }
            return GoalieStatPayload(
                playerName: player.name,
                playerNumber: player.number,
                shotsAgainst: stat.shotsAgainst,
                goalsAgainst: stat.goalsAgainst,
                result: stat.result,
                shootoutRounds: rounds
            )
        }

        var startingGoaliePayload: StartingGoaliePayload?
        if let goalie = game.startingGoalie {
            startingGoaliePayload = StartingGoaliePayload(
                playerName: goalie.name,
                playerNumber: goalie.number
            )
        }

        let payload = GamePayload(
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

    /// Upload a team logo to the server. Fails silently — logo upload is best-effort.
    static func sendTeamLogo(teamName: String, logoData: Data) async {
        guard let url = URL(string: "\(baseURL)/api/team-logo") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")

        let payload = TeamLogoPayload(
            teamName: teamName,
            logoBase64: logoData.base64EncodedString()
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
}
