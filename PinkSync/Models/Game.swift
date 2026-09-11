import Foundation
import SwiftData

@Model
final class Game {
    /// Stable identifier for server upsert — generated once at creation, never changes.
    /// Default "" allows lightweight migration for existing games; the server falls back to date+opponent.
    var gameId: String = ""
    var scheduleId: String = ""
    var date: Date
    var opponent: String
    var location: String
    var goalsFor: Int
    var goalsAgainst: Int
    var result: String
    var isComplete: Bool
    var isSynced: Bool

    /// True when a Save & Send attempt failed and is awaiting automatic retry.
    /// Default false allows lightweight SwiftData migration for existing games.
    var pendingSync: Bool = false

    /// Last sync error message (shown to admins), if any.
    var lastSyncError: String? = nil

    /// True when this device has changes the server doesn't have yet: edits
    /// after a send, a reopened game, live scoring. Cleared by a successful
    /// send. Default false allows lightweight SwiftData migration.
    var hasLocalEdits: Bool = false

    var team: Team?
    var startingGoalie: Player?

    @Relationship(deleteRule: .cascade, inverse: \GamePlayerStats.game)
    var playerStats: [GamePlayerStats] = []

    @Relationship(deleteRule: .cascade, inverse: \GameGoalieStats.game)
    var goalieStats: [GameGoalieStats] = []

    @Relationship(deleteRule: .cascade, inverse: \GameEvent.game)
    var events: [GameEvent] = []

    init(
        date: Date,
        opponent: String,
        location: String,
        goalsFor: Int = 0,
        goalsAgainst: Int = 0,
        result: String = "",
        isComplete: Bool = false,
        isSynced: Bool = false
    ) {
        self.gameId = UUID().uuidString
        self.date = date
        self.opponent = opponent
        self.location = location
        self.goalsFor = goalsFor
        self.goalsAgainst = goalsAgainst
        self.result = result
        self.isComplete = isComplete
        self.isSynced = isSynced
    }

    var gameResult: GameResult? {
        GameResult(rawValue: result)
    }

    var displayDate: String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    var scoreDisplay: String {
        "\(goalsFor) - \(goalsAgainst)"
    }
}

extension Game {
    /// Every skater and goalie stat value in one string, to tell whether an
    /// editor changed anything (autosave means SwiftData's hasChanges can't).
    var statsSignature: String {
        let skaters = playerStats.map { s in
            [s.player?.playerId ?? "", "\(s.shots)", "\(s.goals)", "\(s.assists)", "\(s.hits)", "\(s.blocks)",
             "\(s.penaltyMinutes)", "\(s.powerPlayGoals)", "\(s.shortHandedGoals)", "\(s.powerPlayAssists)",
             "\(s.shortHandedAssists)", "\(s.gameWinningGoals)", "\(s.faceoffWins)", "\(s.faceoffLosses)",
             "\(s.plusMinus)"].joined(separator: ":")
        }
        let goalies = goalieStats.map { g in
            [g.player?.playerId ?? "", "\(g.shotsAgainst)", "\(g.goalsAgainst)", g.result].joined(separator: ":")
        }
        return (skaters.sorted() + ["|"] + goalies.sorted()).joined(separator: ";")
    }

    /// Whether a Games-tab sync may replace this game with the server's copy.
    /// Never while this device holds changes the server doesn't — unsent
    /// edits, a failed send awaiting retry, or live scoring in progress —
    /// or a pull-to-refresh would silently undo the scorekeeper's fixes.
    var acceptsServerUpdate: Bool {
        !hasLocalEdits && !pendingSync && !(LiveSessionStore.exists(gameId: gameId) && !isComplete)
    }
}
