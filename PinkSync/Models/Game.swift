import Foundation
import SwiftData

@Model
final class Game {
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
