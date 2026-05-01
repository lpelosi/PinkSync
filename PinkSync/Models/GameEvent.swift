import Foundation
import SwiftData

@Model
final class GameEvent {
    var type: String
    var period: Int
    var clockTime: String
    var playerName: String
    var playerNumber: Int
    var assist1Name: String
    var assist1Number: Int
    var assist2Name: String
    var assist2Number: Int
    var penaltyMinutes: Int
    var penaltyType: String
    var opponentNumber: String
    var isPowerPlay: Bool = false
    var game: Game?

    init(
        type: String,
        period: Int,
        clockTime: String = "",
        playerName: String = "",
        playerNumber: Int = 0,
        assist1Name: String = "",
        assist1Number: Int = 0,
        assist2Name: String = "",
        assist2Number: Int = 0,
        penaltyMinutes: Int = 0,
        penaltyType: String = "",
        opponentNumber: String = "",
        isPowerPlay: Bool = false
    ) {
        self.type = type
        self.period = period
        self.clockTime = clockTime
        self.playerName = playerName
        self.playerNumber = playerNumber
        self.assist1Name = assist1Name
        self.assist1Number = assist1Number
        self.assist2Name = assist2Name
        self.assist2Number = assist2Number
        self.penaltyMinutes = penaltyMinutes
        self.penaltyType = penaltyType
        self.opponentNumber = opponentNumber
        self.isPowerPlay = isPowerPlay
    }
}
