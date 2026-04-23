import SwiftUI
import SwiftData

struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        TabView {
            Tab("Games", systemImage: "sportscourt") {
                NavigationStack {
                    GamesListView()
                }
            }

            Tab("Roster", systemImage: "person.3") {
                NavigationStack {
                    RosterView()
                }
            }

            Tab("History", systemImage: "clock.arrow.circlepath") {
                NavigationStack {
                    MatchupHistoryView()
                }
            }

            Tab("Stats", systemImage: "chart.bar") {
                NavigationStack {
                    StatsView()
                }
            }
        }
        .tint(AppTheme.pink)
        .onAppear {
            RosterSeeder.seedIfNeeded(modelContext: modelContext)
        }
    }
}
