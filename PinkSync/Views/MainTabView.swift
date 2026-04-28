import SwiftUI
import SwiftData

struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Games", systemImage: "sportscourt", value: 0) {
                NavigationStack {
                    GamesListView()
                }
            }

            Tab("Roster", systemImage: "person.3", value: 1) {
                LazyTabContent {
                    NavigationStack {
                        RosterView()
                    }
                }
            }

            Tab("History", systemImage: "clock.arrow.circlepath", value: 2) {
                LazyTabContent {
                    NavigationStack {
                        MatchupHistoryView()
                    }
                }
            }

            Tab("Stats", systemImage: "chart.bar", value: 3) {
                LazyTabContent {
                    NavigationStack {
                        StatsView()
                    }
                }
            }

            if authManager.canManageUsers {
                Tab("Admin", systemImage: "gearshape", value: 4) {
                    LazyTabContent {
                        NavigationStack {
                            AdminView()
                        }
                    }
                }
            }

            Tab("Profile", systemImage: "person.circle", value: 5) {
                LazyTabContent {
                    NavigationStack {
                        ProfileView()
                    }
                }
            }
        }
        .tint(AppTheme.pink)
        .task {
            RosterSeeder.seedIfNeeded(modelContext: modelContext)
        }
    }
}

private struct LazyTabContent<Content: View>: View {
    @State private var hasAppeared = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        if hasAppeared {
            content()
        } else {
            Color.clear.onAppear { hasAppeared = true }
        }
    }
}
