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

    /// True for substitute players who borrow other players' jerseys.
    /// Subs don't have a permanent number — `number` should be ignored and `—` shown instead.
    /// Default false allows lightweight SwiftData migration for existing players.
    var isSubstitute: Bool = false

    /// Server URL path for the player photo (e.g., "/img/players/uuid.jpg").
    /// Optional with nil default for lightweight SwiftData migration.
    var photoPath: String? = nil

    /// Season ids this player was on the team for, mirroring the server's
    /// `seasons` field. Nil means no membership has been set on the server,
    /// which the server treats as "every season".
    /// Optional with nil default for lightweight SwiftData migration.
    var seasonIds: [String]? = nil

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

    // MARK: - Seasons

    /// Whether this player was on the roster for a season. Matches the
    /// server's `playerInSeason`: no membership set means every season.
    func isMember(of seasonId: String) -> Bool {
        guard let seasonIds else { return true }
        return seasonIds.contains(seasonId)
    }

    // MARK: - Display

    var displayNumber: String {
        if isSubstitute { return "—" }
        if number < 0 { return "—" }
        if number == 0 { return "#00" }
        return "#\(number)"
    }

    /// Number-only string for compact UI (no `#`). Substitutes render as `—`.
    var jerseyText: String {
        if isSubstitute { return "—" }
        if number < 0 { return "—" }
        if number == 0 { return "00" }
        return "\(number)"
    }

    var lastName: String {
        name.components(separatedBy: " ").last ?? name
    }

    // MARK: - Aggregates

    /// Every game this player has a stat line in, across all seasons.
    var allTime: PlayerTotals {
        PlayerTotals(skater: gameStats, goalie: goalieGameStats)
    }

    /// Totals over the games a scope includes: one season, regular season or
    /// playoffs only, or any combination.
    func totals(in scope: StatScope) -> PlayerTotals {
        PlayerTotals(
            skater: gameStats.filter { scope.includes($0.game) },
            goalie: goalieGameStats.filter { scope.includes($0.game) }
        )
    }

    // All-time shortcuts, kept so existing call sites read the same.

    var gamesPlayed: Int { allTime.gamesPlayed }
    var totalShots: Int { allTime.totalShots }
    var totalGoals: Int { allTime.totalGoals }
    var totalAssists: Int { allTime.totalAssists }
    var totalPoints: Int { allTime.totalPoints }
    var totalHits: Int { allTime.totalHits }
    var totalBlocks: Int { allTime.totalBlocks }
    var totalPenaltyMinutes: Int { allTime.totalPenaltyMinutes }
    var totalPowerPlayGoals: Int { allTime.totalPowerPlayGoals }
    var totalShortHandedGoals: Int { allTime.totalShortHandedGoals }
    var totalPowerPlayAssists: Int { allTime.totalPowerPlayAssists }
    var totalShortHandedAssists: Int { allTime.totalShortHandedAssists }
    var totalGameWinningGoals: Int { allTime.totalGameWinningGoals }
    var totalFaceoffWins: Int { allTime.totalFaceoffWins }
    var totalFaceoffLosses: Int { allTime.totalFaceoffLosses }
    var faceoffPercentage: Double { allTime.faceoffPercentage }
    var totalPlusMinus: Int { allTime.totalPlusMinus }
    var totalTimeOnIce: Int { allTime.totalTimeOnIce }
    var averageTimeOnIce: Double { allTime.averageTimeOnIce }

    var totalShotsAgainst: Int { allTime.totalShotsAgainst }
    var totalGoalsAgainst: Int { allTime.totalGoalsAgainst }
    var goalsAgainstAverage: Double { allTime.goalsAgainstAverage }
    var savePercentage: Double { allTime.savePercentage }
    var wins: Int { allTime.wins }
    var losses: Int { allTime.losses }
    var overtimeLosses: Int { allTime.overtimeLosses }
}
