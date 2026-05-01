import Foundation
import SwiftData

@Model
final class Player {
    /// Stable identifier used for matching across iOS app, server, and website.
    /// Default "" allows lightweight migration for existing players.
    var playerId: String = ""

    var name: String
    var number: Int
    var position: String
    var isGoalie: Bool
    var isActive: Bool

    /// Server URL path for the player photo (e.g., "/img/players/uuid.jpg").
    /// Optional with nil default for lightweight SwiftData migration.
    var photoPath: String? = nil

    /// Full URL for the player photo, constructed from the server base URL.
    var photoURL: URL? {
        guard let photoPath else { return nil }
        return URL(string: Secrets.baseURL + photoPath)
    }

    var team: Team?

    @Relationship(deleteRule: .cascade, inverse: \GamePlayerStats.player)
    var gameStats: [GamePlayerStats] = []

    @Relationship(deleteRule: .cascade, inverse: \GameGoalieStats.player)
    var goalieGameStats: [GameGoalieStats] = []

    @Relationship(deleteRule: .nullify, inverse: \Game.startingGoalie)
    var gamesAsStartingGoalie: [Game] = []

    init(name: String, number: Int, position: String, isGoalie: Bool, isActive: Bool = true) {
        self.name = name
        self.number = number
        self.position = position
        self.isGoalie = isGoalie
        self.isActive = isActive
    }

    // MARK: - Display

    var displayNumber: String {
        number > 0 ? "#\(number)" : "--"
    }

    // MARK: - Skater Aggregates

    var gamesPlayed: Int { gameStats.count + goalieGameStats.count }
    var totalShots: Int { gameStats.reduce(0) { $0 + $1.shots } }
    var totalGoals: Int { gameStats.reduce(0) { $0 + $1.goals } }
    var totalAssists: Int { gameStats.reduce(0) { $0 + $1.assists } }
    var totalPoints: Int { totalGoals + totalAssists }
    var totalHits: Int { gameStats.reduce(0) { $0 + $1.hits } }
    var totalBlocks: Int { gameStats.reduce(0) { $0 + $1.blocks } }
    var totalPenaltyMinutes: Int { gameStats.reduce(0) { $0 + $1.penaltyMinutes } }
    var totalPowerPlayGoals: Int { gameStats.reduce(0) { $0 + $1.powerPlayGoals } }
    var totalFaceoffWins: Int { gameStats.reduce(0) { $0 + $1.faceoffWins } }
    var totalFaceoffLosses: Int { gameStats.reduce(0) { $0 + $1.faceoffLosses } }
    var faceoffPercentage: Double {
        let total = totalFaceoffWins + totalFaceoffLosses
        guard total > 0 else { return 0 }
        return Double(totalFaceoffWins) / Double(total) * 100
    }

    // MARK: - Goalie Aggregates

    var totalShotsAgainst: Int { goalieGameStats.reduce(0) { $0 + $1.shotsAgainst } }
    var totalGoalsAgainst: Int { goalieGameStats.reduce(0) { $0 + $1.goalsAgainst } }

    var goalsAgainstAverage: Double {
        let games = goalieGameStats.count
        guard games > 0 else { return 0.0 }
        return Double(totalGoalsAgainst) / Double(games)
    }

    var savePercentage: Double {
        guard totalShotsAgainst > 0 else { return 0.0 }
        return Double(totalShotsAgainst - totalGoalsAgainst) / Double(totalShotsAgainst)
    }

    var wins: Int {
        goalieGameStats.filter {
            $0.result == GameResult.win.rawValue || $0.result == GameResult.shootoutWin.rawValue
        }.count
    }

    var losses: Int {
        goalieGameStats.filter {
            $0.result == GameResult.loss.rawValue || $0.result == GameResult.shootoutLoss.rawValue
        }.count
    }

    var overtimeLosses: Int {
        goalieGameStats.filter { $0.result == GameResult.overtimeLoss.rawValue }.count
    }
}
