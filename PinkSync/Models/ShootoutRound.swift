import Foundation
import SwiftData

@Model
final class ShootoutRound {
    var roundNumber: Int
    var isGoal: Bool

    var goalieStats: GameGoalieStats?

    init(roundNumber: Int, isGoal: Bool) {
        self.roundNumber = roundNumber
        self.isGoal = isGoal
    }

    var resultDescription: String {
        isGoal ? "Goal" : "Save"
    }
}
