import SwiftUI
import SwiftData

struct StatsView: View {
    @Query(sort: \Player.number) private var players: [Player]
    @Query(filter: #Predicate<Game> { $0.isComplete }, sort: \Game.date, order: .reverse)
    private var completedGames: [Game]
    @Environment(AuthManager.self) private var authManager

    @State private var skaterSortKey = "P"
    @State private var goalieSortKey = "W"
    /// Empty set means "All Games" (the default).
    @State private var selectedGameIDs: Set<PersistentIdentifier> = []
    @State private var isPickingGames = false

    private var isFiltered: Bool { !selectedGameIDs.isEmpty }

    private func filteredSkaterStats(for player: Player) -> [GamePlayerStats] {
        guard isFiltered else { return player.gameStats }
        return player.gameStats.filter { stat in
            guard let game = stat.game else { return false }
            return selectedGameIDs.contains(game.persistentModelID)
        }
    }

    private func filteredGoalieStats(for player: Player) -> [GameGoalieStats] {
        guard isFiltered else { return player.goalieGameStats }
        return player.goalieGameStats.filter { stat in
            guard let game = stat.game else { return false }
            return selectedGameIDs.contains(game.persistentModelID)
        }
    }

    private var skaterAggregates: [SkaterAggregate] {
        let candidates = players.filter { $0.position != Position.goalie.rawValue }
        let aggregates = candidates.compactMap { player -> SkaterAggregate? in
            let stats = filteredSkaterStats(for: player)
            // When scoped to specific games, hide players who didn't play in any of them.
            if isFiltered && stats.isEmpty { return nil }
            return SkaterAggregate(player: player, stats: stats)
        }
        return sortSkaterAggregates(aggregates)
    }

    private var goalieAggregates: [GoalieAggregate] {
        let candidates = players.filter { player in
            if isFiltered {
                return !filteredGoalieStats(for: player).isEmpty
            }
            return player.isGoalie || !player.goalieGameStats.isEmpty
        }
        let aggregates = candidates.map { GoalieAggregate(player: $0, stats: filteredGoalieStats(for: $0)) }
        return sortGoalieAggregates(aggregates)
    }

    var body: some View {
        List {
            Section {
                scopeBar
            }

            Section("Skaters") {
                skaterHeader

                if skaterAggregates.isEmpty {
                    Text("No skater stats for the selected scope.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(skaterAggregates, id: \.player.persistentModelID) { agg in
                        skaterRow(agg)
                    }
                }
            }

            Section("Goalies") {
                goalieHeader

                if goalieAggregates.isEmpty {
                    Text("No goalie stats for the selected scope.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(goalieAggregates, id: \.player.persistentModelID) { agg in
                        goalieRow(agg)
                    }
                }
            }
        }
        .navigationTitle("Stats")
        .listStyle(.plain)
        .sheet(isPresented: $isPickingGames) {
            GameScopePickerView(games: completedGames, selection: $selectedGameIDs)
        }
    }

    // MARK: - Scope Bar

    private var scopeBar: some View {
        Button {
            isPickingGames = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease.circle.fill")
                Text(scopeLabel)
                    .lineLimit(1)
                Spacer()
                if isFiltered {
                    Button("Clear") {
                        selectedGameIDs.removeAll()
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .foregroundStyle(AppTheme.pink)
            .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.plain)
    }

    private var scopeLabel: String {
        guard isFiltered else { return "All Games" }
        if selectedGameIDs.count == 1,
           let game = completedGames.first(where: { selectedGameIDs.contains($0.persistentModelID) }) {
            return "vs \(game.opponent) — \(game.date.formatted(date: .abbreviated, time: .omitted))"
        }
        return "\(selectedGameIDs.count) Games Selected"
    }

    // MARK: - Skater Table

    private var skaterHeader: some View {
        HStack(spacing: 0) {
            sortableHeader("#", width: 30, key: "#", isSkater: true, alignment: .leading)
            Text("Name").frame(maxWidth: .infinity, alignment: .leading)
            sortableHeader("GP", width: 32, key: "GP", isSkater: true)
            sortableHeader("G", width: 28, key: "G", isSkater: true)
            sortableHeader("A", width: 28, key: "A", isSkater: true)
            sortableHeader("P", width: 28, key: "P", isSkater: true)
            if authManager.canManageGames {
                sortableHeader("+/-", width: 32, key: "+/-", isSkater: true)
            }
            sortableHeader("PPG", width: 32, key: "PPG", isSkater: true)
            sortableHeader("FO%", width: 36, key: "FO%", isSkater: true)
            sortableHeader("SOG", width: 36, key: "SOG", isSkater: true)
            sortableHeader("PIM", width: 36, key: "PIM", isSkater: true)
        }
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(.secondary)
    }

    private func skaterRow(_ agg: SkaterAggregate) -> some View {
        HStack(spacing: 0) {
            Text(agg.player.jerseyText)
                .frame(width: 30, alignment: .leading)
            Text(agg.player.name)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(agg.gamesPlayed)").frame(width: 32)
            Text("\(agg.goals)").frame(width: 28)
            Text("\(agg.assists)").frame(width: 28)
            Text("\(agg.points)").frame(width: 28)
            if authManager.canManageGames {
                Text(agg.plusMinus > 0 ? "+\(agg.plusMinus)" : "\(agg.plusMinus)").frame(width: 32)
            }
            Text("\(agg.powerPlayGoals)").frame(width: 32)
            Text(agg.totalFaceoffs > 0 ? String(format: "%.0f", agg.faceoffPercentage) : "-").frame(width: 36)
            Text("\(agg.shots)").frame(width: 36)
            Text("\(agg.penaltyMinutes)").frame(width: 36)
        }
        .font(.system(size: 12, design: .monospaced))
    }

    // MARK: - Goalie Table

    private var goalieHeader: some View {
        HStack(spacing: 0) {
            sortableHeader("#", width: 30, key: "#", isSkater: false, alignment: .leading)
            Text("Name").frame(maxWidth: .infinity, alignment: .leading)
            sortableHeader("GP", width: 32, key: "GP", isSkater: false)
            sortableHeader("W", width: 28, key: "W", isSkater: false)
            sortableHeader("L", width: 28, key: "L", isSkater: false)
            sortableHeader("OTL", width: 32, key: "OTL", isSkater: false)
            sortableHeader("GAA", width: 40, key: "GAA", isSkater: false)
            sortableHeader("SV%", width: 44, key: "SV%", isSkater: false)
        }
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(.secondary)
    }

    private func goalieRow(_ agg: GoalieAggregate) -> some View {
        HStack(spacing: 0) {
            Text(agg.player.jerseyText)
                .frame(width: 30, alignment: .leading)
            Text(agg.player.name)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(agg.gamesPlayed)").frame(width: 32)
            Text("\(agg.wins)").frame(width: 28)
            Text("\(agg.losses)").frame(width: 28)
            Text("\(agg.overtimeLosses)").frame(width: 32)
            Text(agg.gamesPlayed > 0 ? String(format: "%.2f", agg.goalsAgainstAverage) : "-").frame(width: 40)
            Text(agg.shotsAgainst > 0 ? String(format: "%.3f", agg.savePercentage) : "-").frame(width: 44)
        }
        .font(.system(size: 12, design: .monospaced))
    }

    // MARK: - Sorting

    private func sortableHeader(_ title: String, width: CGFloat, key: String, isSkater: Bool, alignment: Alignment = .center) -> some View {
        Button {
            if isSkater { skaterSortKey = key } else { goalieSortKey = key }
        } label: {
            Text(title)
                .foregroundStyle((isSkater ? skaterSortKey : goalieSortKey) == key ? AppTheme.pink : .secondary)
                .frame(width: width, alignment: alignment)
        }
        .buttonStyle(.plain)
    }

    private func sortSkaterAggregates(_ aggregates: [SkaterAggregate]) -> [SkaterAggregate] {
        aggregates.sorted { a, b in
            switch skaterSortKey {
            case "#": a.player.number < b.player.number
            case "GP": a.gamesPlayed > b.gamesPlayed
            case "G": a.goals > b.goals
            case "A": a.assists > b.assists
            case "P": a.points > b.points
            case "+/-": a.plusMinus > b.plusMinus
            case "PPG": a.powerPlayGoals > b.powerPlayGoals
            case "FO%": a.faceoffPercentage > b.faceoffPercentage
            case "SOG": a.shots > b.shots
            case "PIM": a.penaltyMinutes > b.penaltyMinutes
            default: a.points > b.points
            }
        }
    }

    private func sortGoalieAggregates(_ aggregates: [GoalieAggregate]) -> [GoalieAggregate] {
        aggregates.sorted { a, b in
            switch goalieSortKey {
            case "#": a.player.number < b.player.number
            case "GP": a.gamesPlayed > b.gamesPlayed
            case "W": a.wins > b.wins
            case "L": a.losses > b.losses
            case "OTL": a.overtimeLosses > b.overtimeLosses
            case "GAA": a.goalsAgainstAverage < b.goalsAgainstAverage
            case "SV%": a.savePercentage > b.savePercentage
            default: a.wins > b.wins
            }
        }
    }
}

// MARK: - Aggregates

private struct SkaterAggregate {
    let player: Player
    let gamesPlayed: Int
    let goals: Int
    let assists: Int
    let plusMinus: Int
    let powerPlayGoals: Int
    let shots: Int
    let penaltyMinutes: Int
    let faceoffWins: Int
    let faceoffLosses: Int

    init(player: Player, stats: [GamePlayerStats]) {
        self.player = player
        self.gamesPlayed = stats.count
        self.goals = stats.reduce(0) { $0 + $1.goals }
        self.assists = stats.reduce(0) { $0 + $1.assists }
        self.plusMinus = stats.reduce(0) { $0 + $1.plusMinus }
        self.powerPlayGoals = stats.reduce(0) { $0 + $1.powerPlayGoals }
        self.shots = stats.reduce(0) { $0 + $1.shots }
        self.penaltyMinutes = stats.reduce(0) { $0 + $1.penaltyMinutes }
        self.faceoffWins = stats.reduce(0) { $0 + $1.faceoffWins }
        self.faceoffLosses = stats.reduce(0) { $0 + $1.faceoffLosses }
    }

    var points: Int { goals + assists }
    var totalFaceoffs: Int { faceoffWins + faceoffLosses }
    var faceoffPercentage: Double {
        guard totalFaceoffs > 0 else { return 0 }
        return Double(faceoffWins) / Double(totalFaceoffs) * 100
    }
}

private struct GoalieAggregate {
    let player: Player
    let gamesPlayed: Int
    let wins: Int
    let losses: Int
    let overtimeLosses: Int
    let shotsAgainst: Int
    let goalsAgainst: Int

    init(player: Player, stats: [GameGoalieStats]) {
        self.player = player
        self.gamesPlayed = stats.count
        self.wins = stats.filter {
            $0.result == GameResult.win.rawValue || $0.result == GameResult.shootoutWin.rawValue
        }.count
        self.losses = stats.filter {
            $0.result == GameResult.loss.rawValue || $0.result == GameResult.shootoutLoss.rawValue
        }.count
        self.overtimeLosses = stats.filter { $0.result == GameResult.overtimeLoss.rawValue }.count
        self.shotsAgainst = stats.reduce(0) { $0 + $1.shotsAgainst }
        self.goalsAgainst = stats.reduce(0) { $0 + $1.goalsAgainst }
    }

    var goalsAgainstAverage: Double {
        guard gamesPlayed > 0 else { return 0.0 }
        return Double(goalsAgainst) / Double(gamesPlayed)
    }

    var savePercentage: Double {
        guard shotsAgainst > 0 else { return 0.0 }
        return Double(shotsAgainst - goalsAgainst) / Double(shotsAgainst)
    }
}

// MARK: - Game Scope Picker

private struct GameScopePickerView: View {
    let games: [Game]
    @Binding var selection: Set<PersistentIdentifier>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        selection.removeAll()
                    } label: {
                        HStack {
                            Image(systemName: "infinity")
                            Text("All Games")
                            Spacer()
                            if selection.isEmpty {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(AppTheme.pink)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                }

                Section("Specific Games") {
                    if games.isEmpty {
                        Text("No completed games yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(games) { game in
                            Button {
                                if selection.contains(game.persistentModelID) {
                                    selection.remove(game.persistentModelID)
                                } else {
                                    selection.insert(game.persistentModelID)
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("vs \(game.opponent)")
                                            .font(.subheadline.weight(.semibold))
                                        HStack(spacing: 6) {
                                            Text(game.date.formatted(date: .abbreviated, time: .omitted))
                                            if !game.result.isEmpty {
                                                Text("•")
                                                Text("\(game.result) \(game.goalsFor)-\(game.goalsAgainst)")
                                            }
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }
                                    .foregroundStyle(.primary)
                                    Spacer()
                                    if selection.contains(game.persistentModelID) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(AppTheme.pink)
                                    } else {
                                        Image(systemName: "circle")
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Filter Stats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.bold)
                }
            }
        }
    }
}
