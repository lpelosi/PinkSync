import SwiftUI
import SwiftData

struct MatchupHistoryView: View {
    @Query(sort: \Game.date, order: .reverse) private var allGames: [Game]
    @Query(sort: \OpponentTeam.name) private var savedTeams: [OpponentTeam]
    @State private var selectedOpponent: String = "All"
    @State private var selectedGame: Game?

    /// Unique opponent names from completed games, sorted alphabetically
    private var opponents: [String] {
        let names = Set(allGames.filter { $0.isComplete }.map { $0.opponent })
        return names.sorted()
    }

    /// Games filtered by selected opponent, already sorted newest-first by @Query
    private var filteredGames: [Game] {
        allGames.filter { game in
            guard game.isComplete else { return false }
            if selectedOpponent == "All" { return true }
            return game.opponent == selectedOpponent
        }
    }

    /// Look up saved team by opponent name
    private func savedTeam(for opponent: String) -> OpponentTeam? {
        savedTeams.first { $0.name == opponent }
    }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Team Filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    filterChip(label: "All", team: nil, isSelected: selectedOpponent == "All") {
                        selectedOpponent = "All"
                    }

                    ForEach(opponents, id: \.self) { opponent in
                        filterChip(
                            label: opponent,
                            team: savedTeam(for: opponent),
                            isSelected: selectedOpponent == opponent
                        ) {
                            selectedOpponent = opponent
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            }

            Divider()

            // MARK: - Game List
            if filteredGames.isEmpty {
                ContentUnavailableView(
                    "No Matchups",
                    systemImage: "clock",
                    description: Text("Completed games will appear here")
                )
            } else {
                List(filteredGames) { game in
                    Button {
                        selectedGame = game
                    } label: {
                        MatchupRow(game: game, team: savedTeam(for: game.opponent))
                    }
                    .tint(.primary)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("History")
        .sheet(item: $selectedGame) { game in
            NavigationStack {
                GameSummaryView(game: game)
            }
        }
    }

    // MARK: - Filter Chip
    private func filterChip(label: String, team: OpponentTeam?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let team {
                    TeamLogoView(team: team, size: 20)
                }
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSelected ? AppTheme.pink : Color(.systemGray6))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
    }
}

// MARK: - Team Logo View

struct TeamLogoView: View {
    let team: OpponentTeam
    let size: CGFloat

    var body: some View {
        if let data = team.logoData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else if let asset = team.logoAsset {
            Image(asset)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(Color(.systemGray5))
                .frame(width: size, height: size)
                .overlay(
                    Text(String(team.name.prefix(1)))
                        .font(.system(size: size * 0.4, weight: .bold))
                        .foregroundStyle(.secondary)
                )
        }
    }
}

// MARK: - Matchup Row

private struct MatchupRow: View {
    let game: Game
    let team: OpponentTeam?

    var body: some View {
        HStack(spacing: 12) {
            // Opponent logo
            if let team {
                TeamLogoView(team: team, size: 40)
            } else {
                Circle()
                    .fill(Color(.systemGray5))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Text(String(game.opponent.prefix(1)))
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    )
            }

            // Game info
            VStack(alignment: .leading, spacing: 4) {
                Text("vs \(game.opponent)")
                    .font(.headline)
                HStack(spacing: 8) {
                    Text(game.displayDate)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !game.location.isEmpty {
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text(game.location)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            // Score + result
            VStack(alignment: .trailing, spacing: 4) {
                Text(game.scoreDisplay)
                    .font(.system(.title3, design: .monospaced, weight: .bold))
                if let result = game.gameResult {
                    Text(result.displayName)
                        .font(.caption.bold())
                        .foregroundStyle(result.isWin ? .green : .red)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
