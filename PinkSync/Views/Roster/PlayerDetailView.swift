import SwiftUI

struct PlayerDetailView: View {
    let player: Player
    @Environment(AuthManager.self) private var authManager
    @Environment(SeasonStore.self) private var seasonStore
    @State private var showingEdit = false
    @State private var seasonId: String?

    private var selectedSeasonId: String {
        seasonId ?? seasonStore.current?.id ?? Season.allId
    }

    private var seasonBinding: Binding<String> {
        Binding(get: { selectedSeasonId }, set: { seasonId = $0 })
    }

    /// Regular season and playoffs together: a player page is a full record,
    /// not the leader-board view.
    private var totals: PlayerTotals {
        player.totals(in: seasonStore.scope(seasonId: selectedSeasonId, type: nil))
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    CachedPlayerPhoto(url: player.photoURL, size: 80)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(player.displayNumber)
                            .font(.system(size: 32, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppTheme.pink)
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

            Section {
                SeasonPicker(seasonId: seasonBinding)
                if let seasonIds = player.seasonIds {
                    let labels = seasonStore.newestFirst
                        .filter { seasonIds.contains($0.id) }
                        .map(\.label)
                    statRow("On Roster", value: labels.isEmpty ? "No seasons" : labels.joined(separator: ", "))
                }
            }

            if player.isGoalie {
                Section("Goalie Stats") {
                    statRow("Games Played", value: "\(totals.goalieGamesPlayed)")
                    statRow("Wins", value: "\(totals.wins)")
                    statRow("Losses", value: "\(totals.losses)")
                    statRow("OT Losses", value: "\(totals.overtimeLosses)")
                    statRow("Shots Against", value: "\(totals.totalShotsAgainst)")
                    statRow("Goals Against", value: "\(totals.totalGoalsAgainst)")
                    statRow("GAA", value: String(format: "%.2f", totals.goalsAgainstAverage))
                    statRow("SV%", value: String(format: "%.3f", totals.savePercentage))
                }
            }

            Section("Skater Stats") {
                statRow("Games Played", value: "\(totals.gamesPlayed)")
                statRow("Goals", value: "\(totals.totalGoals)")
                statRow("Assists", value: "\(totals.totalAssists)")
                statRow("Points", value: "\(totals.totalPoints)")
                statRow("PPG", value: "\(totals.totalPowerPlayGoals)")
                statRow("PPA", value: "\(totals.totalPowerPlayAssists)")
                statRow("SHG", value: "\(totals.totalShortHandedGoals)")
                statRow("SHA", value: "\(totals.totalShortHandedAssists)")
                statRow("GWG", value: "\(totals.totalGameWinningGoals)")
                statRow("Shots", value: "\(totals.totalShots)")
                statRow("Hits", value: "\(totals.totalHits)")
                statRow("Blocks", value: "\(totals.totalBlocks)")
                statRow("PIM", value: "\(totals.totalPenaltyMinutes)")
            }

            if totals.totalFaceoffWins + totals.totalFaceoffLosses > 0 {
                Section("Faceoffs") {
                    statRow("Wins", value: "\(totals.totalFaceoffWins)")
                    statRow("Losses", value: "\(totals.totalFaceoffLosses)")
                    statRow("FO%", value: String(format: "%.1f%%", totals.faceoffPercentage))
                }
            }
        }
        .navigationTitle(player.name)
        .toolbar {
            if authManager.canEditRoster || authManager.canUploadPhotos {
                Button("Edit") {
                    showingEdit = true
                }
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
                .multilineTextAlignment(.trailing)
        }
    }
}
