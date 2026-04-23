import SwiftUI
import SwiftData

struct GameSummaryView: View {
    let game: Game
    @Environment(\.dismiss) private var dismiss

    private var skaterStats: [GamePlayerStats] {
        game.playerStats
            .filter { $0.player != nil }
            .sorted { ($0.player?.number ?? 0) < ($1.player?.number ?? 0) }
    }

    private var goalieStatsList: [GameGoalieStats] {
        game.goalieStats.filter { $0.player != nil }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // MARK: - Header
                VStack(spacing: 8) {
                    Text("vs \(game.opponent)")
                        .font(.title.bold())
                    Text(game.displayDate)
                        .foregroundStyle(.secondary)
                    if !game.location.isEmpty {
                        Text(game.location)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Score
                    Text(game.scoreDisplay)
                        .font(.system(size: 48, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppTheme.pink)

                    if let result = game.gameResult {
                        Text(result.displayName)
                            .font(.headline)
                            .foregroundStyle(result.isWin ? .green : .red)
                    }
                }
                .padding(.top)

                // MARK: - Starting Goalie
                if let goalie = game.startingGoalie {
                    VStack(spacing: 8) {
                        Text("STARTING GOALIE")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1)
                            .foregroundStyle(.secondary)

                        HStack {
                            Text(goalie.displayNumber)
                                .font(.system(size: 20, weight: .bold, design: .monospaced))
                                .foregroundStyle(AppTheme.pink)
                            Text(goalie.name)
                                .font(.headline)
                        }

                        if let gs = goalieStatsList.first(where: {
                            $0.player?.persistentModelID == goalie.persistentModelID
                        }) {
                            HStack(spacing: 24) {
                                miniStat("SA", value: "\(gs.shotsAgainst)")
                                miniStat("GA", value: "\(gs.goalsAgainst)")
                                miniStat("SV", value: "\(gs.saves)")
                                miniStat("SV%", value: String(format: "%.3f", gs.savePercentage))
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(AppTheme.pink.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                }

                // MARK: - Skater Stats Table
                if !skaterStats.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SKATER STATS")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)

                        // Header
                        HStack(spacing: 0) {
                            Text("#").frame(width: 30, alignment: .leading)
                            Text("Player").frame(maxWidth: .infinity, alignment: .leading)
                            Text("SOG").frame(width: 36)
                            Text("G").frame(width: 28)
                            Text("A").frame(width: 28)
                            Text("H").frame(width: 28)
                            Text("BLK").frame(width: 32)
                            Text("PIM").frame(width: 32)
                        }
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)

                        Divider()

                        ForEach(skaterStats) { stat in
                            if let player = stat.player {
                                HStack(spacing: 0) {
                                    Text(player.number > 0 ? "\(player.number)" : "--")
                                        .frame(width: 30, alignment: .leading)
                                    Text(player.name)
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text("\(stat.shots)").frame(width: 36)
                                    Text("\(stat.goals)").frame(width: 28)
                                    Text("\(stat.assists)").frame(width: 28)
                                    Text("\(stat.hits)").frame(width: 28)
                                    Text("\(stat.blocks)").frame(width: 32)
                                    Text("\(stat.penaltyMinutes)").frame(width: 32)
                                }
                                .font(.system(size: 12, design: .monospaced))
                                .padding(.horizontal)
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }

                // MARK: - Empty State
                if skaterStats.isEmpty && goalieStatsList.isEmpty {
                    ContentUnavailableView(
                        "No Stats Recorded",
                        systemImage: "chart.bar",
                        description: Text("Tap on players in the game to start recording stats")
                    )
                    .padding(.top, 40)
                }
            }
        }
        .navigationTitle("Game Summary")
        .toolbar {
            Button("Done") { dismiss() }
        }
    }

    private func miniStat(_ label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.body, design: .monospaced, weight: .bold))
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
        }
    }
}
