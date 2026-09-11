import Foundation
import SwiftData

@Model
final class Team {
    var name: String
    var abbreviation: String

    @Relationship(deleteRule: .cascade, inverse: \Player.team)
    var players: [Player] = []

    @Relationship(deleteRule: .cascade, inverse: \Game.team)
    var games: [Game] = []

    init(name: String, abbreviation: String) {
        self.name = name
        self.abbreviation = abbreviation
    }
}
