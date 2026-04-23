import SwiftUI
import SwiftData

struct PlayerStatsView: View {
    let player: Player
    let stats: GamePlayerStats?
    let game: Game

    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var shots: Int = 0
    @State private var goals: Int = 0
    @State private var assists: Int = 0
    @State private var hits: Int = 0
    @State private var blocks: Int = 0
    @State private var penaltyMinutes: Int = 0

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
                    StatButton(label: "Shots", value: $shots)
                    StatButton(label: "Goals", value: $goals)
                    StatButton(label: "Assists", value: $assists)
                    StatButton(label: "Hits", value: $hits)
                    StatButton(label: "Blocks", value: $blocks)
                    StatButton(label: "PIM", value: $penaltyMinutes)
                }
                .padding(.horizontal)
            }
        }
        .navigationTitle(player.name)
        .onAppear { loadStats() }
        .onDisappear { saveStats() }
    }

    private func loadStats() {
        guard let stats else { return }
        shots = stats.shots
        goals = stats.goals
        assists = stats.assists
        hits = stats.hits
        blocks = stats.blocks
        penaltyMinutes = stats.penaltyMinutes
    }

    private func saveStats() {
        // Only save if at least one stat was recorded
        let hasStats = shots > 0 || goals > 0 || assists > 0 || hits > 0 || blocks > 0 || penaltyMinutes > 0

        if let stats {
            // Update existing
            stats.shots = shots
            stats.goals = goals
            stats.assists = assists
            stats.hits = hits
            stats.blocks = blocks
            stats.penaltyMinutes = penaltyMinutes
        } else if hasStats {
            // Create new
            let newStats = GamePlayerStats(
                shots: shots,
                goals: goals,
                assists: assists,
                hits: hits,
                blocks: blocks,
                penaltyMinutes: penaltyMinutes
            )
            newStats.player = player
            newStats.game = game
            modelContext.insert(newStats)
        }
        try? modelContext.save()
    }
}
