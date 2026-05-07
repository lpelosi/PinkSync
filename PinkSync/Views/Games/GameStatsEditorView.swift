import SwiftUI
import SwiftData

struct GameStatsEditorView: View {
    let game: Game
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Player.number) private var allPlayers: [Player]

    @State private var showingAddPlayer = false

    private var playersWithStats: [Player] {
        game.playerStats.compactMap { $0.player }
            .sorted { ($0.number, $0.name) < ($1.number, $1.name) }
    }

    private var goaliesWithStats: [Player] {
        game.goalieStats.compactMap { $0.player }
            .sorted { ($0.number, $0.name) < ($1.number, $1.name) }
    }

    private var playersWithoutStats: [Player] {
        let existingIDs = Set(game.playerStats.compactMap { $0.player?.persistentModelID })
        return allPlayers.filter { $0.isActive && !existingIDs.contains($0.persistentModelID) }
    }

    var body: some View {
        List {
            if !goaliesWithStats.isEmpty {
                Section("Goalie Stats") {
                    ForEach(goaliesWithStats) { goalie in
                        if let stats = goalieStats(for: goalie) {
                            GoalieStatsEditRow(player: goalie, stats: stats)
                        }
                    }
                }
            }

            Section("Skater Stats") {
                if playersWithStats.isEmpty {
                    Text("No player stats recorded")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(playersWithStats) { player in
                        if let stats = playerStats(for: player) {
                            PlayerStatsEditRow(player: player, stats: stats)
                        }
                    }
                }
            }

            Section {
                Button {
                    showingAddPlayer = true
                } label: {
                    Label("Add Player Stats", systemImage: "plus.circle")
                        .foregroundStyle(AppTheme.pink)
                }
            }
        }
        .navigationTitle("Edit Stats")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    try? modelContext.save()
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $showingAddPlayer) {
            NavigationStack {
                AddPlayerStatsSheet(
                    game: game,
                    availablePlayers: playersWithoutStats
                )
            }
        }
    }

    private func playerStats(for player: Player) -> GamePlayerStats? {
        game.playerStats.first { $0.player?.persistentModelID == player.persistentModelID }
    }

    private func goalieStats(for player: Player) -> GameGoalieStats? {
        game.goalieStats.first { $0.player?.persistentModelID == player.persistentModelID }
    }
}

// MARK: - Player Stats Edit Row

struct PlayerStatsEditRow: View {
    let player: Player
    @Bindable var stats: GamePlayerStats

    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            statStepper("Shots", value: $stats.shots)
            statStepper("Goals", value: $stats.goals)
            statStepper("Assists", value: $stats.assists)
            statStepper("PPG", value: $stats.powerPlayGoals)
            statStepper("PPA", value: $stats.powerPlayAssists)
            statStepper("SHG", value: $stats.shortHandedGoals)
            statStepper("SHA", value: $stats.shortHandedAssists)
            statStepper("GWG", value: $stats.gameWinningGoals)
            statStepper("Hits", value: $stats.hits)
            statStepper("Blocks", value: $stats.blocks)
            statStepper("PIM", value: $stats.penaltyMinutes)
            statStepper("FO Wins", value: $stats.faceoffWins)
            statStepper("FO Losses", value: $stats.faceoffLosses)
        } label: {
            HStack(spacing: 8) {
                Text(player.displayNumber)
                    .font(.system(.caption, design: .monospaced, weight: .bold))
                    .foregroundStyle(AppTheme.pink)
                    .frame(width: 30)
                Text(player.name)
                    .font(.subheadline.bold())
                Spacer()
                statBadges
            }
        }
    }

    private var statBadges: some View {
        HStack(spacing: 4) {
            if stats.goals > 0 { badge("\(stats.goals)G") }
            if stats.assists > 0 { badge("\(stats.assists)A") }
            if stats.shots > 0 { badge("\(stats.shots)S") }
            if stats.faceoffWins + stats.faceoffLosses > 0 {
                badge("\(stats.faceoffWins)/\(stats.faceoffWins + stats.faceoffLosses) FO")
            }
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(AppTheme.pink.opacity(0.15))
            .foregroundStyle(AppTheme.pink)
            .clipShape(Capsule())
    }

    private func statStepper(_ label: String, value: Binding<Int>) -> some View {
        Stepper("\(label): \(value.wrappedValue)", value: value, in: 0...999)
    }
}

// MARK: - Goalie Stats Edit Row

struct GoalieStatsEditRow: View {
    let player: Player
    @Bindable var stats: GameGoalieStats

    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            statStepper("Shots Against", value: $stats.shotsAgainst)
            statStepper("Goals Against", value: $stats.goalsAgainst)
            Picker("Result", selection: $stats.result) {
                ForEach(GameResult.allCases) { result in
                    Text(result.displayName).tag(result.rawValue)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(player.displayNumber)
                    .font(.system(.caption, design: .monospaced, weight: .bold))
                    .foregroundStyle(AppTheme.pink)
                    .frame(width: 30)
                Text(player.name)
                    .font(.subheadline.bold())
                Spacer()
                HStack(spacing: 4) {
                    if stats.shotsAgainst > 0 {
                        Text("\(stats.saves)/\(stats.shotsAgainst) SV")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(AppTheme.teal.opacity(0.15))
                            .foregroundStyle(AppTheme.teal)
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    private func statStepper(_ label: String, value: Binding<Int>) -> some View {
        Stepper("\(label): \(value.wrappedValue)", value: value, in: 0...999)
    }
}

// MARK: - Add Player Stats Sheet

struct AddPlayerStatsSheet: View {
    let game: Game
    let availablePlayers: [Player]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if availablePlayers.isEmpty {
                Text("All players already have stats for this game")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(availablePlayers) { player in
                    Button {
                        let stats = GamePlayerStats()
                        stats.player = player
                        stats.game = game
                        modelContext.insert(stats)
                        try? modelContext.save()
                        dismiss()
                    } label: {
                        PlayerRow(player: player)
                    }
                    .tint(.primary)
                }
            }
        }
        .navigationTitle("Add Player")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }
}
