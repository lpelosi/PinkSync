import SwiftUI
import SwiftData

struct GoalieStatsView: View {
    let player: Player
    let game: Game

    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var resolvedStats: GameGoalieStats?
    @State private var shotsAgainst: Int = 0
    @State private var goalsAgainst: Int = 0

    private var saves: Int { shotsAgainst - goalsAgainst }
    private var savePercentage: Double {
        guard shotsAgainst > 0 else { return 0.0 }
        return Double(saves) / Double(shotsAgainst)
    }

    /// Result is derived from the game — single source of truth.
    private var currentResult: GameResult? {
        game.gameResult
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

                // Result display (derived from game-level result)
                if let gameResult = currentResult {
                    VStack(spacing: 4) {
                        Text("GAME RESULT")
                            .font(AppTheme.statLabel)
                            .foregroundStyle(.secondary)
                        Text(gameResult.displayName)
                            .font(.title2.bold())
                            .foregroundStyle(gameResult.isWin ? .green : .red)
                    }
                    .padding()
                } else {
                    Text("Set game result in the Score section")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding()
                }

                // Shootout section
                if currentResult?.isShootout == true, let gs = resolvedStats {
                    ShootoutView(goalieStats: gs)
                        .padding(.horizontal)
                }
            }
        }
        .navigationTitle(player.name)
        .onAppear { resolveAndLoad() }
        .onDisappear { saveStats() }
    }

    /// Find existing goalie stats for this player+game, or create a new record.
    private func resolveAndLoad() {
        if let existing = game.goalieStats.first(where: {
            $0.player?.persistentModelID == player.persistentModelID
        }) {
            resolvedStats = existing
            shotsAgainst = existing.shotsAgainst
            goalsAgainst = existing.goalsAgainst
        } else {
            let newStats = GameGoalieStats(
                shotsAgainst: 0,
                goalsAgainst: 0,
                result: game.result
            )
            newStats.player = player
            game.goalieStats.append(newStats)
            modelContext.insert(newStats)
            try? modelContext.save()
            resolvedStats = newStats
        }
    }

    private func saveStats() {
        guard let resolvedStats else { return }
        resolvedStats.shotsAgainst = shotsAgainst
        resolvedStats.goalsAgainst = goalsAgainst
        resolvedStats.result = game.result
        try? modelContext.save()
    }
}
