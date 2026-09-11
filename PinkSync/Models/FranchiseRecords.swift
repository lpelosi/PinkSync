import Foundation

/// The franchise record book from `GET /api/records`.
///
/// Four groups: best single season, best single game, career totals, and the
/// post-season book. The first three count regular-season games only.
struct FranchiseRecords: Decodable {
    struct PlayerRef: Decodable, Hashable {
        let playerId: String
        let name: String
        let number: Int?
    }

    struct SeasonRef: Decodable, Hashable {
        let id: String
        let label: String
    }

    struct GameRef: Decodable, Hashable {
        let date: String
        let opponent: String
        let gameId: String?
    }

    struct Record: Decodable, Identifiable, Hashable {
        let key: String
        let label: String
        let statLabel: String
        /// Nil when nobody has set the record yet.
        let value: Double?
        let player: PlayerRef?
        let season: SeasonRef?
        let game: GameRef?

        var id: String { key }

        var displayValue: String {
            guard let value else { return "—" }
            if statLabel == "SV%" { return String(format: "%.3f", value) }
            if value.rounded() == value { return "\(Int(value))" }
            return String(format: "%.1f", value)
        }

        /// Where the record happened: the season label, or the game's date and opponent.
        var context: String? {
            if let season { return season.label }
            if let game { return "\(displayDate(game.date)) vs \(game.opponent)" }
            return nil
        }

        private func displayDate(_ iso: String) -> String {
            let day = String(iso.prefix(10))
            let parts = day.split(separator: "-")
            guard parts.count == 3, let month = Int(parts[1]), let dayOfMonth = Int(parts[2]) else { return day }
            let months = ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
            return "\(months[month]) \(dayOfMonth), \(parts[0])"
        }
    }

    let season: [Record]
    let game: [Record]
    let career: [Record]
    /// Post-season book. Absent from servers older than the playoff-stats
    /// update, so it decodes as empty rather than failing the whole screen.
    let playoff: [Record]

    private enum CodingKeys: String, CodingKey {
        case season, game, career, playoff
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        season = try container.decodeIfPresent([Record].self, forKey: .season) ?? []
        game = try container.decodeIfPresent([Record].self, forKey: .game) ?? []
        career = try container.decodeIfPresent([Record].self, forKey: .career) ?? []
        playoff = try container.decodeIfPresent([Record].self, forKey: .playoff) ?? []
    }
}
