import Foundation
import os

private let logger = Logger(subsystem: "PinkSync", category: "TournamentStore")

/// The tournament list from `GET /api/tournaments`, shared through the
/// environment next to `SeasonStore`.
///
/// The last list the server sent is kept on the device. A rink far from home
/// is exactly where the network is worst, and the travel roster and the
/// tournament names have to be there anyway.
@Observable
@MainActor
final class TournamentStore {
    private(set) var tournaments: [Tournament]
    private(set) var hasLoaded = false

    private static let cacheKey = "tournaments.cache.v1"

    init(tournaments: [Tournament]? = nil) {
        self.tournaments = tournaments ?? Self.cached()
    }

    /// Newest first, the order people expect in a picker.
    var newestFirst: [Tournament] {
        Tournament.sorted(tournaments).reversed()
    }

    func load() async {
        do {
            replace(with: try await APIClient.fetchTournaments())
        } catch {
            // Keep the cached list; it is better than none at the rink.
            logger.error("Tournament fetch failed: \(error.localizedDescription)")
        }
    }

    /// Adopt a list the server just sent or accepted. An empty list is a real
    /// answer: there are no tournaments.
    func replace(with tournaments: [Tournament]) {
        self.tournaments = tournaments
        hasLoaded = true
        if let data = try? JSONEncoder().encode(tournaments) {
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
        }
    }

    func tournament(id: String) -> Tournament? {
        guard !id.isEmpty else { return nil }
        return tournaments.first { $0.id == id }
    }

    /// The tournament a season picker selection points at, or nil when the
    /// selection is a season.
    func tournament(forSelection selection: String) -> Tournament? {
        Tournament.tournamentId(fromSelection: selection).flatMap { tournament(id: $0) }
    }

    /// What to call a game's tournament on screen. Falls back to the raw id so
    /// a tagged game never looks like a league game while the list is missing.
    func title(for tournamentId: String) -> String? {
        guard !tournamentId.isEmpty else { return nil }
        return tournament(id: tournamentId)?.title ?? tournamentId
    }

    /// Whether the travel roster allows a player into a tournament game's
    /// lineup. Nil when the roster has no say — the game is not a tournament
    /// game, or no roster has been entered — and the caller should fall back
    /// to the season roster.
    func rosterDecision(for player: Player, tournamentId: String) -> Bool? {
        guard let tournament = tournament(id: tournamentId), tournament.hasRoster else { return nil }
        return tournament.isOnRoster(player)
    }

    /// The goalies to offer for a game. For a tournament game that is the
    /// travel roster's goalies, the named ones first; nil for a league game,
    /// where the caller's own season rule applies.
    func goalieChoices(tournamentId: String, from players: [Player]) -> [Player]? {
        guard let tournament = tournament(id: tournamentId),
              tournament.hasRoster || tournament.namesGoalies else { return nil }
        return tournament.goalieChoices(from: players)
    }

    private static func cached() -> [Tournament] {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let tournaments = try? JSONDecoder().decode([Tournament].self, from: data) else { return [] }
        return tournaments
    }
}
