import Foundation
import SwiftData

@Model
final class Game {
    /// Stable identifier for server upsert — generated once at creation, never changes.
    /// Default "" allows lightweight migration for existing games; the server falls back to date+opponent.
    var gameId: String = ""
    var date: Date
    var opponent: String
    var location: String
    var goalsFor: Int
    var goalsAgainst: Int
    var result: String
    var isComplete: Bool
    var isSynced: Bool

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
