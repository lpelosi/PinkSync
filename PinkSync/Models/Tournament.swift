import Foundation

/// A tournament as served by `GET /api/tournaments`: a named event with its
/// own dates, venue and travel roster.
///
/// Unlike a season, a tournament is not a date range games fall into — a
/// tournament weekend can overlap a league game back home. Games and bouts
/// carry a `tournamentId` instead, and tournament games are kept out of the
/// regular-season and playoff numbers.
struct Tournament: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var label: String
    /// Inclusive first day, `yyyy-MM-dd`.
    var start: String
    /// Inclusive last day, `yyyy-MM-dd`.
    var end: String
    var location: String?
    /// The bracket the team is entered in, e.g. "Level 4".
    var division: String?
    var url: String?
    /// Player ids of the travel roster. Nil or empty until one is entered.
    var roster: [String]?
    /// Player id of the captain for this tournament.
    var captain: String?
    /// Player ids of the alternate captains for this tournament.
    var alternates: [String]?

    /// Added by the server on read (`upcoming`, `in-progress`, `complete`);
    /// ignored by it on write.
    var status: String?
    var gamesPlayed: Int?

    /// The name with its year, so two editions of the same event can be told
    /// apart. A label that already carries a year is left alone.
    var title: String {
        if label.range(of: #"\b\d{4}\b"#, options: .regularExpression) != nil { return label }
        return "\(label) \(start.prefix(4))"
    }

    var hasRoster: Bool {
        !(roster ?? []).isEmpty
    }

    func contains(day: String) -> Bool {
        day >= start && day <= end
    }

    /// Whether a player belongs on this tournament's roster. The roster
    /// entered for the tournament decides; until there is one, anyone who has
    /// played in it counts. Matches `tournamentRosterIds` on the server.
    func isOnRoster(_ player: Player) -> Bool {
        if hasRoster {
            let playerId = player.playerId.uppercased()
            guard !playerId.isEmpty else { return false }
            return (roster ?? []).contains { $0.uppercased() == playerId }
        }
        return player.gameStats.contains { $0.game?.tournamentId == id }
            || player.goalieGameStats.contains { $0.game?.tournamentId == id }
    }
}

// MARK: - Letters

/// The letter a captain or an alternate wears. Named per tournament, so each
/// trip keeps its own record of who led the team.
enum Letter: String, CaseIterable, Identifiable, Sendable {
    case captain = "C"
    case alternate = "A"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .captain: "Captain"
        case .alternate: "Alternate"
        }
    }
}

extension Tournament {
    func letter(for player: Player) -> Letter? {
        letter(forPlayerId: player.playerId)
    }

    func letter(forPlayerId playerId: String) -> Letter? {
        let id = playerId.uppercased()
        guard !id.isEmpty else { return nil }
        if captain?.uppercased() == id { return .captain }
        if (alternates ?? []).contains(where: { $0.uppercased() == id }) { return .alternate }
        return nil
    }
}

// MARK: - Picker selection

extension Tournament {
    /// The season pickers hold one string. A season is its id, "all" is every
    /// season, and a tournament is its id behind this prefix — season ids are
    /// `[a-z0-9-]`, so the colon cannot collide with one.
    static let selectionPrefix = "tournament:"

    var selectionId: String {
        Self.selectionPrefix + id
    }

    /// The tournament id in a picker selection, or nil when the selection is a
    /// season.
    static func tournamentId(fromSelection selection: String) -> String? {
        guard selection.hasPrefix(selectionPrefix) else { return nil }
        let id = String(selection.dropFirst(selectionPrefix.count))
        return id.isEmpty ? nil : id
    }

    static func sorted(_ tournaments: [Tournament]) -> [Tournament] {
        tournaments.sorted { ($0.start, $0.id) < ($1.start, $1.id) }
    }
}
