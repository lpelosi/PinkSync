import Foundation
import os

private let logger = Logger(subsystem: "PinkSync", category: "SeasonStore")

/// The season list from `GET /api/seasons`, shared through the environment.
///
/// Starts on the bundled defaults so every view can classify games before the
/// network answers, then follows the server once it does. Created once at app
/// launch, next to `AuthManager` and `SyncManager`.
@Observable
@MainActor
final class SeasonStore {
    private(set) var seasons: [Season] = Season.defaults
    private(set) var hasLoaded = false

    /// The season the site shows by default and the one new games land in.
    var current: Season? {
        Season.current(in: seasons)
    }

    /// Newest first, the order people expect in a picker.
    var newestFirst: [Season] {
        Season.sorted(seasons).reversed()
    }

    func load() async {
        do {
            let fetched = try await APIClient.fetchSeasons()
            if !fetched.isEmpty {
                seasons = fetched
            }
            hasLoaded = true
        } catch {
            // Keep whatever we have; the defaults mirror the server's own.
            logger.error("Season fetch failed: \(error.localizedDescription)")
        }
    }

    /// Adopt a list the server just accepted (after `PUT /api/seasons`).
    func replace(with seasons: [Season]) {
        guard !seasons.isEmpty else { return }
        self.seasons = seasons
        hasLoaded = true
    }

    func season(id: String) -> Season? {
        seasons.first { $0.id == id }
    }

    func season(for date: Date) -> Season? {
        Season.season(for: Season.apiDay(for: date), in: seasons)
    }

    func gameType(for date: Date) -> GameType {
        let day = Season.apiDay(for: date)
        return Season.season(for: day, in: seasons)?.gameType(for: day) ?? .regular
    }

    /// Whether a player was on the roster for the season a game date falls in.
    /// Used by lineup and goalie pickers so a game only offers that season's
    /// players, the same set the site's roster page shows for it.
    func isOnRoster(_ player: Player, on date: Date) -> Bool {
        guard let season = season(for: date) else { return true }
        return player.isMember(of: season.id)
    }

    /// A scope for the given picker selection. `Season.allId` means every
    /// season, and a tournament selection means that tournament's games alone,
    /// whatever `type` says.
    func scope(seasonId: String, type: GameType?) -> StatScope {
        if let tournamentId = Tournament.tournamentId(fromSelection: seasonId) {
            return StatScope(season: nil, type: nil, seasons: seasons, tournamentId: tournamentId)
        }
        return StatScope(season: seasonId == Season.allId ? nil : season(id: seasonId), type: type, seasons: seasons)
    }
}
