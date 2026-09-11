import SwiftUI

/// Season selector shared by the Games, Roster and Stats tabs.
///
/// Lists seasons newest first with the current one marked, and optionally an
/// "All Seasons" entry whose tag is `Season.allId`.
struct SeasonPicker: View {
    @Environment(SeasonStore.self) private var seasonStore
    @Binding var seasonId: String
    var includeAll = true

    var body: some View {
        Picker("Season", selection: $seasonId) {
            ForEach(seasonStore.newestFirst) { season in
                Text(title(for: season)).tag(season.id)
            }
            if includeAll {
                Text("All Seasons").tag(Season.allId)
            }
        }
    }

    private func title(for season: Season) -> String {
        season.id == seasonStore.current?.id ? "\(season.label) (Current)" : season.label
    }
}
