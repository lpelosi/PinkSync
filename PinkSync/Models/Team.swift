import Foundation
import SwiftData

@Model
final class Team {
    var name: String
    var abbreviation: String
    var season: String

    @Relationship(deleteRule: .cascade, inverse: \Player.team)
    var players: [Player] = []

    @Relationship(deleteRule: .cascade, inverse: \Game.team)
    var games: [Game] = []

    init(name: String, abbreviation: String, season: String) {
        self.name = name
        self.abbreviation = abbreviation
        self.season = season
    }
}
