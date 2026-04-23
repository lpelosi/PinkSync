import SwiftUI
import SwiftData

struct GoalieStatsView: View {
    let player: Player
    let stats: GameGoalieStats?
    let game: Game

    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var shotsAgainst: Int = 0
    @State private var goalsAgainst: Int = 0
    @State private var result: String = GameResult.win.rawValue

    private var saves: Int { shotsAgainst - goalsAgainst }
    private var savePercentage: Double {
        guard shotsAgainst > 0 else { return 0.0 }
        return Double(saves) / Double(shotsAgainst)
    }

    private var currentResult: GameResult? {
        GameResult(rawValue: result)
    }

    private var columns: [GridItem] {
        let count = sizeClass == .regular ? 3 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: count)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Player header
                HStack {
                    Text(player.displayNumber)
                        .font(.system(size: 36, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppTheme.pink)
                    Text(player.name)
                        .font(.title2.bold())
                }
                .padding(.top)

                // Stat grid
                LazyVGrid(columns: columns, spacing: 12) {
                    StatButton(label: "Shots Against", value: $shotsAgainst)
                    StatButton(label: "Goals Against", value: $goalsAgainst)
                }
                .padding(.horizontal)

                // Computed stats
                HStack(spacing: 32) {
                    VStack {
                        Text("Saves")
                            .font(AppTheme.statLabel)
                            .foregroundStyle(.secondary)
                        Text("\(saves)")
                            .font(.title.bold().monospacedDigit())
                    }
                    VStack {
                        Text("SV%")
                            .font(AppTheme.statLabel)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.3f", savePercentage))
                            .font(.title.bold().monospacedDigit())
                    }
                }
                .padding()

                // Result picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("RESULT")
                        .font(AppTheme.statLabel)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)

                    Picker("Result", selection: $result) {
                        ForEach(GameResult.allCases) { r in
                            Text(r.displayName).tag(r.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                }

                // Shootout section
                if currentResult?.isShootout == true {
                    ShootoutView(goalieStats: resolveOrCreateStats())
                        .padding(.horizontal)
                }
            }
        }
        .navigationTitle(player.name)
        .onAppear { loadStats() }
        .onDisappear { saveStats() }
    }

    private func loadStats() {
        guard let stats else { return }
        shotsAgainst = stats.shotsAgainst
        goalsAgainst = stats.goalsAgainst
        result = stats.result
    }

    private func saveStats() {
        if let stats {
            stats.shotsAgainst = shotsAgainst
            stats.goalsAgainst = goalsAgainst
            stats.result = result
        } else if shotsAgainst > 0 || goalsAgainst > 0 {
            let newStats = GameGoalieStats(
                shotsAgainst: shotsAgainst,
                goalsAgainst: goalsAgainst,
                result: result
            )
            newStats.player = player
            newStats.game = game
            modelContext.insert(newStats)
        }
        try? modelContext.save()
    }

    private func resolveOrCreateStats() -> GameGoalieStats {
        if let stats { return stats }

        let newStats = GameGoalieStats(
            shotsAgainst: shotsAgainst,
            goalsAgainst: goalsAgainst,
            result: result
        )
        newStats.player = player
        newStats.game = game
        modelContext.insert(newStats)
        try? modelContext.save()
        return newStats
    }
}
