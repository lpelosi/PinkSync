import SwiftUI
import SwiftData

struct StatsView: View {
    @Query(sort: \Player.number) private var players: [Player]
    @Query(filter: #Predicate<Game> { $0.isComplete }, sort: \Game.date, order: .reverse)
    private var completedGames: [Game]
    @Environment(AuthManager.self) private var authManager
    @Environment(SeasonStore.self) private var seasonStore
    @Environment(TournamentStore.self) private var tournamentStore

    /// Nil until the user picks; falls back to the current season.
    @State private var seasonId: String?
    @State private var typeFilter: TypeFilter = .regular
    @State private var skaterSortKey = "P"
    @State private var goalieSortKey = "W"
    /// Hand-picked games within the chosen season and game type. Empty means
    /// every game in that scope.
    @State private var selectedGameIDs: Set<PersistentIdentifier> = []
    @State private var isPickingGames = false

    /// Regular season is the default, the way hockey stats are quoted and the
    /// way the site's leader cards are scoped.
    private enum TypeFilter: String, CaseIterable, Identifiable {
        case regular, playoff, all

        var id: String { rawValue }

        var label: String {
            switch self {
            case .regular: "Regular"
            case .playoff: "Playoffs"
            case .all: "All Games"
            }
        }

        var gameType: GameType? {
            switch self {
            case .regular: .regular
            case .playoff: .playoff
            case .all: nil
            }
        }
    }

    private var selectedSeasonId: String {
        seasonId ?? seasonStore.current?.id ?? Season.allId
    }

    private var seasonBinding: Binding<String> {
        Binding(get: { selectedSeasonId }, set: { seasonId = $0 })
    }

    private var scope: StatScope {
        seasonStore.scope(seasonId: selectedSeasonId, type: typeFilter.gameType)
    }

    /// The tournament being viewed, when the picker is on one.
    private var selectedTournament: Tournament? {
        tournamentStore.tournament(forSelection: selectedSeasonId)
    }

    private var isTournamentSelected: Bool {
        Tournament.tournamentId(fromSelection: selectedSeasonId) != nil
    }

    /// Completed games in the chosen season and game type — what the game
    /// picker offers.
    private var gamesInScope: [Game] {
        let scope = self.scope
        return completedGames.filter { scope.includes($0) }
    }

    private var isPicking: Bool { !selectedGameIDs.isEmpty }

    var body: some View {
        let table = StatsTable(players: players, scope: scope, seasonId: selectedSeasonId, selectedGames: selectedGameIDs, tournament: selectedTournament)
        let skaters = sortSkaters(table.skaters)
        let goalies = sortGoalies(table.goalies)

        return List {
            Section {
                SeasonPicker(seasonId: seasonBinding)
                // A tournament has no regular season or playoffs to split.
                if !isTournamentSelected {
                    Picker("Games", selection: $typeFilter) {
                        ForEach(TypeFilter.allCases) { filter in
                            Text(filter.label).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                scopeBar
                NavigationLink {
                    RecordsView()
                } label: {
                    Label("Franchise Records", systemImage: "trophy")
                }
            }

            Section("Skaters") {
                skaterHeader

                if skaters.isEmpty {
                    Text("No skater stats for the selected scope.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(skaters) { row in
                        skaterRow(row)
                    }
                }
            }

            Section("Goalies") {
                goalieHeader

                if goalies.isEmpty {
                    Text("No goalie stats for the selected scope.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(goalies) { row in
                        goalieRow(row)
                    }
                }
            }
        }
        .navigationTitle("Stats")
        .listStyle(.plain)
        .sheet(isPresented: $isPickingGames) {
            GameScopePickerView(games: gamesInScope, selection: $selectedGameIDs)
        }
        // A hand-picked list of games belongs to one season and game type.
        .onChange(of: selectedSeasonId) { selectedGameIDs.removeAll() }
        .onChange(of: typeFilter) { selectedGameIDs.removeAll() }
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
                if isPicking {
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
        guard isPicking else { return "Pick specific games" }
        if selectedGameIDs.count == 1,
           let game = completedGames.first(where: { selectedGameIDs.contains($0.persistentModelID) }) {
            return "vs \(game.opponent), \(game.date.formatted(date: .abbreviated, time: .omitted))"
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

    private func skaterRow(_ row: StatsTable.Row) -> some View {
        let player = row.player
        let totals = row.totals
        return HStack(spacing: 0) {
            Text(player.jerseyText)
                .frame(width: 30, alignment: .leading)
            Text(player.name)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(totals.skaterGamesPlayed)").frame(width: 32)
            Text("\(totals.totalGoals)").frame(width: 28)
            Text("\(totals.totalAssists)").frame(width: 28)
            Text("\(totals.totalPoints)").frame(width: 28)
            if authManager.canManageGames {
                Text(totals.totalPlusMinus > 0 ? "+\(totals.totalPlusMinus)" : "\(totals.totalPlusMinus)").frame(width: 32)
            }
            Text("\(totals.totalPowerPlayGoals)").frame(width: 32)
            Text((totals.totalFaceoffWins + totals.totalFaceoffLosses) > 0 ? String(format: "%.0f", totals.faceoffPercentage) : "-").frame(width: 36)
            Text("\(totals.totalShots)").frame(width: 36)
            Text("\(totals.totalPenaltyMinutes)").frame(width: 36)
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

    private func goalieRow(_ row: StatsTable.Row) -> some View {
        let player = row.player
        let totals = row.totals
        return HStack(spacing: 0) {
            Text(player.jerseyText)
                .frame(width: 30, alignment: .leading)
            Text(player.name)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(totals.goalieGamesPlayed)").frame(width: 32)
            Text("\(totals.wins)").frame(width: 28)
            Text("\(totals.losses)").frame(width: 28)
            Text("\(totals.overtimeLosses)").frame(width: 32)
            Text(totals.goalieGamesPlayed > 0 ? String(format: "%.2f", totals.goalsAgainstAverage) : "-").frame(width: 40)
            Text(totals.totalShotsAgainst > 0 ? String(format: "%.3f", totals.savePercentage) : "-").frame(width: 44)
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

    private func sortSkaters(_ rows: [StatsTable.Row]) -> [StatsTable.Row] {
        rows.sorted { a, b in
            switch skaterSortKey {
            case "#": a.player.number < b.player.number
            case "GP": a.totals.skaterGamesPlayed > b.totals.skaterGamesPlayed
            case "G": a.totals.totalGoals > b.totals.totalGoals
            case "A": a.totals.totalAssists > b.totals.totalAssists
            case "P": a.totals.totalPoints > b.totals.totalPoints
            case "+/-": a.totals.totalPlusMinus > b.totals.totalPlusMinus
            case "PPG": a.totals.totalPowerPlayGoals > b.totals.totalPowerPlayGoals
            case "FO%": a.totals.faceoffPercentage > b.totals.faceoffPercentage
            case "SOG": a.totals.totalShots > b.totals.totalShots
            case "PIM": a.totals.totalPenaltyMinutes > b.totals.totalPenaltyMinutes
            default: a.totals.totalPoints > b.totals.totalPoints
            }
        }
    }

    private func sortGoalies(_ rows: [StatsTable.Row]) -> [StatsTable.Row] {
        rows.sorted { a, b in
            switch goalieSortKey {
            case "#": a.player.number < b.player.number
            case "GP": a.totals.goalieGamesPlayed > b.totals.goalieGamesPlayed
            case "W": a.totals.wins > b.totals.wins
            case "L": a.totals.losses > b.totals.losses
            case "OTL": a.totals.overtimeLosses > b.totals.overtimeLosses
            case "GAA": a.totals.goalsAgainstAverage < b.totals.goalsAgainstAverage
            case "SV%": a.totals.savePercentage > b.totals.savePercentage
            default: a.totals.wins > b.totals.wins
            }
        }
    }
}

// MARK: - Table

/// The rows behind the Stats tab: the chosen season and game type, optionally
/// narrowed to hand-picked games.
///
/// Skaters are everyone whose position isn't Goalie, so a dual-role player
/// keeps their skating line; goalies are anyone who can play in net or has.
/// Without hand-picked games, a player shows if they are on the season's
/// roster — the travel roster, when a tournament is being viewed — or played
/// in scope. With hand-picked games, only if they played in at least one of
/// them.
struct StatsTable {
    struct Row: Identifiable {
        let player: Player
        let totals: PlayerTotals
        var id: PersistentIdentifier { player.persistentModelID }
    }

    let skaters: [Row]
    let goalies: [Row]

    init(players: [Player], scope: StatScope, seasonId: String, selectedGames: Set<PersistentIdentifier>, tournament: Tournament? = nil) {
        let picking = !selectedGames.isEmpty
        func counts(_ game: Game?) -> Bool {
            guard let game, scope.includes(game) else { return false }
            return !picking || selectedGames.contains(game.persistentModelID)
        }

        var skaters: [Row] = []
        var goalies: [Row] = []
        for player in players {
            let totals = PlayerTotals(
                skater: player.gameStats.filter { counts($0.game) },
                goalie: player.goalieGameStats.filter { counts($0.game) }
            )
            let onRoster: Bool
            if !player.isActive {
                // No longer on the server's roster: only what they played.
                onRoster = false
            } else if let tournament {
                onRoster = tournament.isOnRoster(player)
            } else if Tournament.tournamentId(fromSelection: seasonId) != nil {
                // A tournament this device has no record of: only who played.
                onRoster = false
            } else {
                onRoster = seasonId == Season.allId || player.isMember(of: seasonId)
            }

            // A tournament that names its goalies lists them as goalies and
            // everyone else as skaters. Whoever actually played the other
            // role still gets that line, so no stat is ever hidden.
            let listedSkater = tournament?.listsAsSkater(player) ?? true
            let listedGoalie = tournament?.listsAsGoalie(player) ?? true

            if player.position != Position.goalie.rawValue {
                let played = !totals.gameStats.isEmpty
                if picking ? played : ((onRoster && listedSkater) || played) {
                    skaters.append(Row(player: player, totals: totals))
                }
            }
            if player.isGoalie || !player.goalieGameStats.isEmpty {
                let played = !totals.goalieGameStats.isEmpty
                if picking ? played : ((onRoster && listedGoalie) || played) {
                    goalies.append(Row(player: player, totals: totals))
                }
            }
        }
        self.skaters = skaters
        self.goalies = goalies
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
                            Text("Every Game Shown")
                            Spacer()
                            if selection.isEmpty {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(AppTheme.pink)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                } footer: {
                    Text("Games listed are the completed ones in the season and game type, or the tournament, you picked on the Stats tab.")
                }

                Section("Specific Games") {
                    if games.isEmpty {
                        Text("No completed games in this season and game type.")
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
