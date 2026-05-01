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
    var faceoffWins: Int = 0
    var faceoffLosses: Int = 0

    var player: Player?
    var game: Game?

    init(
        shots: Int = 0,
        goals: Int = 0,
        assists: Int = 0,
        hits: Int = 0,
        blocks: Int = 0,
        penaltyMinutes: Int = 0,
        powerPlayGoals: Int = 0,
        faceoffWins: Int = 0,
        faceoffLosses: Int = 0
    ) {
        self.shots = shots
        self.goals = goals
        self.assists = assists
        self.hits = hits
        self.blocks = blocks
        self.penaltyMinutes = penaltyMinutes
        self.powerPlayGoals = powerPlayGoals
        self.faceoffWins = faceoffWins
        self.faceoffLosses = faceoffLosses
    }

    var points: Int { goals + assists }
    var totalFaceoffs: Int { faceoffWins + faceoffLosses }
    var faceoffPercentage: Double {
        guard totalFaceoffs > 0 else { return 0 }
        return Double(faceoffWins) / Double(totalFaceoffs) * 100
    }
}
