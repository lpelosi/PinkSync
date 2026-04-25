import SwiftUI
import SwiftData
import os

private let launchLogger = Logger(subsystem: "PinkSync", category: "Launch")

struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext
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

            Tab("Admin", systemImage: "gearshape", value: 4) {
                LazyTabContent {
                    NavigationStack {
                        AdminView()
                    }
                }
            }
        }
        .tint(AppTheme.pink)
        .task {
            let start = CFAbsoluteTimeGetCurrent()
            RosterSeeder.seedIfNeeded(modelContext: modelContext)
            launchLogger.info("⏱ Seeder done: \(String(format: "%.0f", (CFAbsoluteTimeGetCurrent() - start) * 1000))ms")
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
