import Foundation
import SwiftData

@Model
final class GameGoalieStats {
    var shotsAgainst: Int
    var goalsAgainst: Int
    var result: String

    var player: Player?
    var game: Game?

    @Relationship(deleteRule: .cascade, inverse: \ShootoutRound.goalieStats)
    var shootoutRounds: [ShootoutRound] = []

    init(
        shotsAgainst: Int = 0,
        goalsAgainst: Int = 0,
        result: String = GameResult.win.rawValue
    ) {
        self.shotsAgainst = shotsAgainst
        self.goalsAgainst = goalsAgainst
        self.result = result
    }

    var saves: Int { shotsAgainst - goalsAgainst }

    var savePercentage: Double {
        guard shotsAgainst > 0 else { return 0.0 }
        return Double(saves) / Double(shotsAgainst)
    }

    var gameResult: GameResult? {
        GameResult(rawValue: result)
    }

    var hasShootout: Bool {
        result == GameResult.shootoutWin.rawValue || result == GameResult.shootoutLoss.rawValue
    }
}
