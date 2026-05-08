import Foundation
import SwiftData

@Model
final class PlayerShift {
    var period: Int
    var duration: Int
    var startClockTime: String
    var endClockTime: String

    var gamePlayerStats: GamePlayerStats?

    init(period: Int, duration: Int, startClockTime: String, endClockTime: String) {
        self.period = period
        self.duration = duration
        self.startClockTime = startClockTime
        self.endClockTime = endClockTime
    }
}
