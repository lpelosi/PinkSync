import SwiftUI

struct PlayerDetailView: View {
    let player: Player
    @State private var showingEdit = false

    var body: some View {
        List {
            Section {
                HStack {
                    Text(player.displayNumber)
                        .font(.system(size: 40, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppTheme.pink)
                    VStack(alignment: .leading) {
                        Text(player.name)
                            .font(.title2.bold())
                        Text(player.position)
                            .foregroundStyle(.secondary)
                        if player.isGoalie && player.position != "Goalie" {
                            Text("Also plays Goalie")
                                .font(.caption)
                                .foregroundStyle(AppTheme.pink)
                        }
                    }
                }
            }

            if player.isGoalie {
                Section("Goalie Stats") {
                    statRow("Games Played", value: "\(player.goalieGameStats.count)")
                    statRow("Wins", value: "\(player.wins)")
                    statRow("Losses", value: "\(player.losses)")
                    statRow("OT Losses", value: "\(player.overtimeLosses)")
                    statRow("Shots Against", value: "\(player.totalShotsAgainst)")
                    statRow("Goals Against", value: "\(player.totalGoalsAgainst)")
                    statRow("GAA", value: String(format: "%.2f", player.goalsAgainstAverage))
                    statRow("SV%", value: String(format: "%.3f", player.savePercentage))
                }
            }

            Section("Skater Stats") {
                statRow("Games Played", value: "\(player.gamesPlayed)")
                statRow("Goals", value: "\(player.totalGoals)")
                statRow("Assists", value: "\(player.totalAssists)")
                statRow("Points", value: "\(player.totalPoints)")
                statRow("Shots", value: "\(player.totalShots)")
                statRow("Hits", value: "\(player.totalHits)")
                statRow("Blocks", value: "\(player.totalBlocks)")
                statRow("PIM", value: "\(player.totalPenaltyMinutes)")
            }
        }
        .navigationTitle(player.name)
        .toolbar {
            Button("Edit") {
                showingEdit = true
            }
        }
        .sheet(isPresented: $showingEdit) {
            NavigationStack {
                PlayerFormView(mode: .edit(player))
            }
        }
    }

    private func statRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(.body, design: .monospaced, weight: .semibold))
        }
    }
}
