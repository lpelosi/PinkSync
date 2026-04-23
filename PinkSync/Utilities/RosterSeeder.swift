import Foundation
import SwiftData

enum RosterSeeder {
    struct PlayerData {
        let name: String
        let number: Int
        let position: String
        let isGoalie: Bool
    }

    static let rosterData: [PlayerData] = [
        // Goalies
        PlayerData(name: "James Philips", number: 41, position: "Goalie", isGoalie: true),
        PlayerData(name: "JP 'Chupa' Quinones", number: 24, position: "Forward", isGoalie: true),
        PlayerData(name: "Louis 'Gramps' Pelosi", number: 35, position: "Forward", isGoalie: true),
        PlayerData(name: "Jordan 'Jordaddy' Jacobson", number: 74, position: "Defense", isGoalie: true),

        // Defense
        PlayerData(name: "Nick Mills", number: 1, position: "Defense", isGoalie: false),
        PlayerData(name: "Sela 'Tequila' Dieden", number: 4, position: "Defense", isGoalie: false),
        PlayerData(name: "Matthew 'Fingerz' Valerio", number: 9, position: "Defense", isGoalie: false),
        PlayerData(name: "Ryan Yates", number: 70, position: "Defense", isGoalie: false),
        PlayerData(name: "Dmitri Petrenko", number: 77, position: "Defense", isGoalie: false),
        PlayerData(name: "Roger 'Tahiti' Garner", number: 83, position: "Defense", isGoalie: false),
        PlayerData(name: "Marielle Schoffstall", number: 97, position: "Defense", isGoalie: false),
        PlayerData(name: "Aiden Lam", number: 0, position: "Defense", isGoalie: false),

        // Forwards
        PlayerData(name: "Michael Khan", number: 6, position: "Forward", isGoalie: false),
        PlayerData(name: "Derek Kirby", number: 7, position: "Forward", isGoalie: false),
        PlayerData(name: "Joe Eppler", number: 8, position: "Forward", isGoalie: false),
        PlayerData(name: "Zach 'Smithy' Smith", number: 13, position: "Forward", isGoalie: false),
        PlayerData(name: "Zoe Karabenick", number: 18, position: "Forward", isGoalie: false),
        PlayerData(name: "Emilio Rosario", number: 19, position: "Forward", isGoalie: false),
        PlayerData(name: "Kaitlin 'K-Train' Larson", number: 21, position: "Forward", isGoalie: false),
        PlayerData(name: "Brett Anderson", number: 36, position: "Forward", isGoalie: false),
        PlayerData(name: "Mathew Rozpedowski", number: 57, position: "Forward", isGoalie: false),
        PlayerData(name: "Hunter 'Spaghetti' Kear", number: 69, position: "Forward", isGoalie: false),
        PlayerData(name: "Preston Mock", number: 71, position: "Forward", isGoalie: false),
        PlayerData(name: "Justin 'Stribbs' Stribbel", number: 89, position: "Forward", isGoalie: false),
        PlayerData(name: "Brad Love", number: 91, position: "Forward", isGoalie: false),
        PlayerData(name: "Zach Weisberg", number: 0, position: "Forward", isGoalie: false),
        PlayerData(name: "Nick Welsh", number: 0, position: "Forward", isGoalie: false),
    ]

    static func seedIfNeeded(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<Team>()
        let existingTeams = (try? modelContext.fetch(descriptor)) ?? []

        if existingTeams.isEmpty {
            let team = Team(name: "Frozen Flamingos", abbreviation: "FF", season: "2026")
            modelContext.insert(team)

            for data in rosterData {
                let player = Player(
                    name: data.name,
                    number: data.number,
                    position: data.position,
                    isGoalie: data.isGoalie
                )
                player.team = team
                modelContext.insert(player)
            }

            try? modelContext.save()
        }

        // Always check opponent teams independently
        seedOpponentTeamsIfNeeded(modelContext: modelContext)
    }

    static func seedOpponentTeamsIfNeeded(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<OpponentTeam>()
        let existing = (try? modelContext.fetch(descriptor)) ?? []

        guard existing.isEmpty else { return }

        for seed in OpponentTeam.seedTeams {
            let team = OpponentTeam(name: seed.name, logoAsset: seed.logoAsset)
            modelContext.insert(team)
        }

        try? modelContext.save()
    }
}
