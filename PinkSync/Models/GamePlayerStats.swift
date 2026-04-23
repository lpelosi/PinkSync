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

    var player: Player?
    var game: Game?

    init(
        shots: Int = 0,
        goals: Int = 0,
        assists: Int = 0,
        hits: Int = 0,
        blocks: Int = 0,
        penaltyMinutes: Int = 0
    ) {
        self.shots = shots
        self.goals = goals
        self.assists = assists
        self.hits = hits
        self.blocks = blocks
        self.penaltyMinutes = penaltyMinutes
    }

    var points: Int { goals + assists }
}
