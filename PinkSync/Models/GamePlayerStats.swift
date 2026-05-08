import Foundation
import SwiftData

@Model
final class GamePlayerStats {
    var shots: Int
    var goals: Int
    var assists: Int
    var hits: Int
    var blocks: Int
    var penaltyMinutes: Int
    var powerPlayGoals: Int = 0
    var shortHandedGoals: Int = 0
    var powerPlayAssists: Int = 0
    var shortHandedAssists: Int = 0
    var gameWinningGoals: Int = 0
    var faceoffWins: Int = 0
    var faceoffLosses: Int = 0
    var timeOnIce: Int = 0
    var plusMinus: Int = 0

    var player: Player?
    var game: Game?

    @Relationship(deleteRule: .cascade, inverse: \PlayerShift.gamePlayerStats)
    var shifts: [PlayerShift] = []

    init(
        shots: Int = 0,
        goals: Int = 0,
        assists: Int = 0,
        hits: Int = 0,
        blocks: Int = 0,
        penaltyMinutes: Int = 0,
        powerPlayGoals: Int = 0,
        shortHandedGoals: Int = 0,
        powerPlayAssists: Int = 0,
        shortHandedAssists: Int = 0,
        gameWinningGoals: Int = 0,
        faceoffWins: Int = 0,
        faceoffLosses: Int = 0,
        timeOnIce: Int = 0,
        plusMinus: Int = 0
    ) {
        self.shots = shots
        self.goals = goals
        self.assists = assists
        self.hits = hits
        self.blocks = blocks
        self.penaltyMinutes = penaltyMinutes
        self.powerPlayGoals = powerPlayGoals
        self.shortHandedGoals = shortHandedGoals
        self.powerPlayAssists = powerPlayAssists
        self.shortHandedAssists = shortHandedAssists
        self.gameWinningGoals = gameWinningGoals
        self.faceoffWins = faceoffWins
        self.faceoffLosses = faceoffLosses
        self.timeOnIce = timeOnIce
        self.plusMinus = plusMinus
    }

    var hasRecordedStats: Bool {
        shots > 0 || goals > 0 || assists > 0 || hits > 0 || blocks > 0 ||
        penaltyMinutes > 0 || faceoffWins > 0 || faceoffLosses > 0 || timeOnIce > 0
    }

    var points: Int { goals + assists }
    var totalFaceoffs: Int { faceoffWins + faceoffLosses }
    var faceoffPercentage: Double {
        guard totalFaceoffs > 0 else { return 0 }
        return Double(faceoffWins) / Double(totalFaceoffs) * 100
    }
}
