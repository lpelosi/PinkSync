import SwiftUI

/// Season selector shared by the Games, Roster and Stats tabs.
///
/// Lists seasons newest first with the current one marked, optionally an
/// "All Seasons" entry whose tag is `Season.allId`, and then the tournaments,
/// tagged with `Tournament.selectionId`. A season and a tournament are one
/// choice: the screen shows either, never both.
struct SeasonPicker: View {
    @Environment(SeasonStore.self) private var seasonStore
    @Environment(TournamentStore.self) private var tournamentStore
    @Binding var seasonId: String
    var includeAll = true
    var includeTournaments = true

    var body: some View {
        Picker("Season", selection: $seasonId) {
            ForEach(seasonStore.newestFirst) { season in
                Text(title(for: season)).tag(season.id)
            }
            if includeAll {
                Text("All Seasons").tag(Season.allId)
            }
            if includeTournaments && !tournamentStore.tournaments.isEmpty {
                Section("Tournaments") {
                    ForEach(tournamentStore.newestFirst) { tournament in
                        Text(tournament.title).tag(tournament.selectionId)
                    }
                }
            }
        }
    }

    private func title(for season: Season) -> String {
        season.id == seasonStore.current?.id ? "\(season.label) (Current)" : season.label
    }
}
