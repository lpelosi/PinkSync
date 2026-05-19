import Foundation
import SwiftData

@Model
final class GameEvent {
    var type: String
    var period: Int
    var clockTime: String

    /// Stable identifier for the player involved (UUID). Authoritative — never use number alone.
    /// Defaults to "" for SwiftData migration; legacy events fall back to name+number lookup.
    var playerId: String = ""
    var playerName: String
    var playerNumber: Int

    /// Stable identifiers for assists. Default "" for migration.
    var assist1Id: String = ""
    var assist1Name: String
    var assist1Number: Int
    var assist2Id: String = ""
    var assist2Name: String
    var assist2Number: Int
    var penaltyMinutes: Int
    var penaltyType: String
    var opponentNumber: String
    var isPowerPlay: Bool = false
    var isShortHanded: Bool = false
    var onIcePlayerIds: String = ""
    var game: Game?

    init(
        type: String,
        period: Int,
        clockTime: String = "",
        playerId: String = "",
        playerName: String = "",
        playerNumber: Int = 0,
        assist1Id: String = "",
        assist1Name: String = "",
        assist1Number: Int = 0,
        assist2Id: String = "",
        assist2Name: String = "",
        assist2Number: Int = 0,
        penaltyMinutes: Int = 0,
        penaltyType: String = "",
        opponentNumber: String = "",
        isPowerPlay: Bool = false,
        isShortHanded: Bool = false
    ) {
        self.type = type
        self.period = period
        self.clockTime = clockTime
        self.playerId = playerId
        self.playerName = playerName
        self.playerNumber = playerNumber
        self.assist1Id = assist1Id
        self.assist1Name = assist1Name
        self.assist1Number = assist1Number
        self.assist2Id = assist2Id
        self.assist2Name = assist2Name
        self.assist2Number = assist2Number
        self.penaltyMinutes = penaltyMinutes
        self.penaltyType = penaltyType
        self.opponentNumber = opponentNumber
        self.isPowerPlay = isPowerPlay
        self.isShortHanded = isShortHanded
    }
}
