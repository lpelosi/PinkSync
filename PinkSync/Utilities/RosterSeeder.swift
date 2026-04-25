import Foundation
import SwiftData

enum RosterSeeder {
    struct PlayerData {
        let playerId: String
        let name: String
        let number: Int
        let position: String
        let isGoalie: Bool
    }

    // Stable UUIDs — these MUST match the website's roster.ts playerIds exactly.
    static let rosterData: [PlayerData] = [
        // Goalies
        PlayerData(playerId: "21DD54B3-D7E5-4341-A054-DC60F897D9DF", name: "James Phillips", number: 41, position: "Goalie", isGoalie: true),
        PlayerData(playerId: "12945F9E-8D09-4FE4-9474-4AAD1982BA14", name: "JP 'Chupa' Quinones", number: 24, position: "Forward", isGoalie: true),
        PlayerData(playerId: "409E990E-792C-43EE-A7F3-BD4B188DD271", name: "Louis 'Gramps' Pelosi", number: 35, position: "Forward", isGoalie: true),
        PlayerData(playerId: "C76CF8B2-EB8B-4FE3-99BC-B51B58B9A326", name: "Jordan 'Jordaddy' Jacobson", number: 74, position: "Defense", isGoalie: true),

        // Defense
        PlayerData(playerId: "FB343F79-1594-4AA2-B321-B29C4750BBC2", name: "Nick Mills", number: 1, position: "Defense", isGoalie: false),
        PlayerData(playerId: "73287971-1EFF-4D02-95CE-293BC6408486", name: "Sela 'Tequila' Dieden", number: 4, position: "Defense", isGoalie: false),
        PlayerData(playerId: "0415A42B-4737-4B7F-A198-311BDE6D9C55", name: "Matthew 'Fingerz' Valerio", number: 9, position: "Defense", isGoalie: false),
        PlayerData(playerId: "9B35CD9F-EB07-4730-8784-E88871DAA7CE", name: "Ryan Yates", number: 70, position: "Defense", isGoalie: false),
        PlayerData(playerId: "083FD534-E53E-4B5D-B1BF-77BA3B2A4686", name: "Dmitri Petrenko", number: 77, position: "Defense", isGoalie: false),
        PlayerData(playerId: "F16E1C10-9F36-4738-A1F7-6EDD11CB57FA", name: "Roger 'Tahiti' Garner", number: 83, position: "Defense", isGoalie: false),
        PlayerData(playerId: "C4F46887-83DF-4034-AD59-839F8876E1F5", name: "Marielle Schoffstall", number: 97, position: "Defense", isGoalie: false),
        PlayerData(playerId: "38A92CD9-71E9-4918-AB35-B360ADF552FB", name: "Aiden Lam", number: 0, position: "Defense", isGoalie: false),

        // Forwards
        PlayerData(playerId: "663EBB6A-2D96-4493-A3ED-C411A5366132", name: "Michael Khan", number: 6, position: "Forward", isGoalie: false),
        PlayerData(playerId: "F0CE505C-107F-42CE-A128-952E1ECC8E4E", name: "Derek Kirby", number: 7, position: "Forward", isGoalie: false),
        PlayerData(playerId: "0542A6DF-BD61-4EFE-AA35-0A64C707ECCE", name: "Joe Eppler", number: 8, position: "Forward", isGoalie: false),
        PlayerData(playerId: "CDB3D46B-DF6E-4134-9370-5AFCF53FB812", name: "Zach 'Smithy' Smith", number: 13, position: "Forward", isGoalie: false),
        PlayerData(playerId: "F365ABD4-2E4F-4847-80B6-5A13B8A6FD09", name: "Zoe Karabenick", number: 18, position: "Forward", isGoalie: false),
        PlayerData(playerId: "9C48FFE8-2C63-48CE-B141-3B19DB323491", name: "Emilio Rosario", number: 19, position: "Forward", isGoalie: false),
        PlayerData(playerId: "98C12730-89F5-4796-80F8-359B8942A1A9", name: "Kaitlin 'K-Train' Larson", number: 21, position: "Forward", isGoalie: false),
        PlayerData(playerId: "D4DD9CD6-4D3C-4FA8-B0C5-99971063BBD7", name: "Brett Anderson", number: 36, position: "Forward", isGoalie: false),
        PlayerData(playerId: "0690ACA7-F44C-4321-B3EF-1995E346F606", name: "Mathew Rozpedowski", number: 57, position: "Forward", isGoalie: false),
        PlayerData(playerId: "965C6950-5F71-488A-80F2-E8E31E10DD44", name: "Hunter 'Spaghetti' Kear", number: 69, position: "Forward", isGoalie: false),
        PlayerData(playerId: "750127B2-6666-4F41-8099-D8A4D6A38ED4", name: "Preston Mock", number: 71, position: "Forward", isGoalie: false),
        PlayerData(playerId: "4EA968C2-267E-4908-A92A-7FF3BA4B7EA3", name: "Justin 'Stribbs' Stribbel", number: 89, position: "Forward", isGoalie: false),
        PlayerData(playerId: "E9217139-88AB-4631-A15E-3B42970E7923", name: "Brad Love", number: 91, position: "Forward", isGoalie: false),
        PlayerData(playerId: "35086853-4274-4024-AA77-4C22A71C4699", name: "Zach Weisberg", number: 0, position: "Forward", isGoalie: false),
        PlayerData(playerId: "7A45803E-2C8B-4EF5-AC0E-5B2508594866", name: "Nick Welsh", number: 0, position: "Forward", isGoalie: false),
    ]

    /// Known name corrections: DB spelling → correct spelling.
    private static let nameCorrections: [String: String] = [
        "James Philips": "James Phillips",
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
                player.playerId = data.playerId
                player.team = team
                modelContext.insert(player)
            }

            try? modelContext.save()
        }

        // Always run migration on every launch until all players have IDs.
        migratePlayerIds(modelContext: modelContext)

        // Always check opponent teams independently
        seedOpponentTeamsIfNeeded(modelContext: modelContext)
    }

    /// Backfill playerId on existing players and fix known name typos.
    /// Runs on every launch; skips quickly once all players have IDs.
    private static func migratePlayerIds(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<Player>()
        guard let players = try? modelContext.fetch(descriptor) else { return }

        var changed = false

        for player in players {
            // Fix known name typos first
            if let corrected = nameCorrections[player.name] {
                player.name = corrected
                changed = true
            }

            // Assign playerId if empty
            if player.playerId.isEmpty {
                // Try exact match first (name + number)
                if let match = rosterData.first(where: { $0.name == player.name && $0.number == player.number }) {
                    player.playerId = match.playerId
                    changed = true
                }
                // Fallback: match by number alone (for non-zero numbers which are unique)
                else if player.number > 0,
                        let match = rosterData.first(where: { $0.number == player.number }) {
                    player.playerId = match.playerId
                    changed = true
                }
            }
        }

        if changed {
            try? modelContext.save()
        }
    }

    static func seedOpponentTeamsIfNeeded(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<OpponentTeam>()
        let existing = (try? modelContext.fetch(descriptor)) ?? []
        let existingNames = Set(existing.map(\.name))

        var changed = false
        for seed in OpponentTeam.seedTeams {
            if !existingNames.contains(seed.name) {
                let team = OpponentTeam(name: seed.name, logoAsset: seed.logoAsset)
                modelContext.insert(team)
                changed = true
            }
        }

        if changed {
            try? modelContext.save()
        }
    }
}
