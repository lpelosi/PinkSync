import Foundation

/// A season as served by `GET /api/seasons`: a labelled date range.
///
/// Games and schedule entries belong to a season by their `date` — nothing is
/// stamped onto stored records, so the app keeps posting games with no season
/// field and both the server and the app classify by date.
struct Season: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    /// Inclusive first day, `yyyy-MM-dd`.
    let start: String
    /// Inclusive last day, `yyyy-MM-dd`.
    let end: String
    var isCurrent: Bool?
    /// Games on or after this day are post-season. Absent until the season
    /// reaches its playoffs, so nothing is reclassified early.
    var playoffsStart: String?

    /// Mirrors the server's `DEFAULT_SEASONS`, used until `/api/seasons` answers.
    static let defaults: [Season] = [
        Season(id: "2026-summer", label: "2026 Summer", start: "2026-04-01", end: "2026-08-14"),
        Season(id: "2026-fall", label: "2026 Fall", start: "2026-08-15", end: "2027-01-31", isCurrent: true)
    ]

    /// The query value that means "every season".
    static let allId = "all"

    func contains(day: String) -> Bool {
        day >= start && day <= end
    }

    /// Regular season or post-season for a day in this season.
    func gameType(for day: String) -> GameType {
        guard let playoffsStart, !day.isEmpty else { return .regular }
        return day >= playoffsStart ? .playoff : .regular
    }

    /// A game date as sent to the server: ISO 8601 with the device's UTC
    /// offset, e.g. `2026-08-14T19:30:00-04:00`. The server classifies games by
    /// the first ten characters, so this keeps an evening game on the calendar
    /// day it was played instead of rolling it to the next UTC day — which
    /// would move a season's last game into the next season, or a game played
    /// on the day playoffs start out of the playoffs.
    static func apiTimestamp(for date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    /// The `yyyy-MM-dd` day the server sees for a game date — the local
    /// calendar day, matching `apiTimestamp` and the admin's season dates.
    static func apiDay(for date: Date) -> String {
        String(apiTimestamp(for: date).prefix(10))
    }
}

/// Regular season vs post-season, matching the server's `?type=` values.
enum GameType: String, CaseIterable, Identifiable, Sendable {
    case regular
    case playoff

    var id: String { rawValue }

    var label: String {
        switch self {
        case .regular: "Regular"
        case .playoff: "Playoffs"
        }
    }
}

/// Which games a stat table should count. `season == nil` means every season,
/// `type == nil` means every kind of game: regular season, playoffs and
/// tournaments together.
///
/// Tournament games are tagged rather than dated, so they are neither regular
/// season nor playoffs whatever day they were played. A `tournamentId` makes
/// the scope that tournament alone and sets `season` and `type` aside. This
/// mirrors `?tournament=` and `?type=` on the server.
struct StatScope: Hashable, Sendable {
    var season: Season?
    var type: GameType?
    /// The season list used to classify dates. Needed even when `season` is nil
    /// so `type` can be resolved against the right `playoffsStart`.
    var seasons: [Season]
    var tournamentId: String? = nil

    /// Everything, all-time — what the app showed before seasons existed.
    static let allTime = StatScope(season: nil, type: nil, seasons: Season.defaults)

    func includes(_ game: Game?) -> Bool {
        guard let game else { return false }
        if let tournamentId { return game.tournamentId == tournamentId }
        let day = Season.apiDay(for: game.date)
        let owner = Season.season(for: day, in: seasons)
        if let season, owner?.id != season.id { return false }
        if let type {
            if !game.tournamentId.isEmpty { return false }
            if (owner?.gameType(for: day) ?? .regular) != type { return false }
        }
        return true
    }
}

extension Season {
    static func sorted(_ seasons: [Season]) -> [Season] {
        seasons.sorted { $0.start < $1.start }
    }

    /// The season a day belongs to, mirroring `lib/seasons.js` on the server:
    /// a day outside every range clamps to the nearest season, and a gap
    /// between two seasons attaches to the one that just ended.
    static func season(for day: String, in seasons: [Season]) -> Season? {
        let ordered = sorted(seasons)
        guard let first = ordered.first, let last = ordered.last else { return nil }
        if day.isEmpty { return last }
        if let match = ordered.first(where: { $0.contains(day: day) }) { return match }
        if day < first.start { return first }
        if day > last.end { return last }
        var previous = first
        for season in ordered where day > season.end {
            previous = season
        }
        return previous
    }

    /// Season membership to store after the player form is saved: the
    /// selected seasons this device knows about, in season order, plus any
    /// seasons the player already had that this device doesn't know about
    /// (those have no toggle, so they cannot have been changed).
    static func membership(selected: Set<String>, known: [Season], previous: [String]?) -> [String] {
        let knownIds = sorted(known).map(\.id)
        let unknown = (previous ?? []).filter { !knownIds.contains($0) }
        return knownIds.filter { selected.contains($0) } + unknown
    }

    /// The season flagged current, else the one containing today, else the latest.
    static func current(in seasons: [Season], today: Date = Date()) -> Season? {
        if let flagged = seasons.first(where: { $0.isCurrent == true }) { return flagged }
        let day = apiDay(for: today)
        let ordered = sorted(seasons)
        return ordered.first(where: { $0.contains(day: day) }) ?? ordered.last
    }
}
