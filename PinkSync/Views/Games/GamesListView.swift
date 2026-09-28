import SwiftUI
import SwiftData

struct GamesListView: View {
    @Query(sort: \Game.date, order: .reverse) private var games: [Game]
    @Query(sort: \Player.number) private var players: [Player]
    @Query(sort: \OpponentTeam.name) private var savedTeams: [OpponentTeam]
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    @Environment(SyncManager.self) private var syncManager
    @Environment(SeasonStore.self) private var seasonStore
    @Environment(TournamentStore.self) private var tournamentStore
    @State private var seasonId: String?
    @State private var showingAddGame = false
    @State private var showingAddBout = false
    @State private var gameToDelete: Game?
    @State private var isDeletingGame = false
    @State private var deleteError: String?
    @State private var showDeleteError = false
    @State private var isSyncing = false
    @State private var syncError: String?
    @State private var schedule: [APIClient.ScheduleEntry] = []
    @State private var boutToDelete: APIClient.ScheduleEntry?
    @State private var navigateToGame: Game?

    private var filteredSchedule: [APIClient.ScheduleEntry] {
        Self.upcoming(schedule, games: games.map { game in
            BoutMatch(scheduleId: game.scheduleId, opponent: game.opponent, date: game.date)
        })
    }

    /// What is needed of a game to decide whether it is the one a bout was for.
    struct BoutMatch {
        let scheduleId: String
        let opponent: String
        let date: Date
    }

    /// The bouts that have no game yet.
    ///
    /// A game started from a bout accounts for that bout and no other. Only a
    /// game with no bout of its own — started with New Game, or recorded
    /// before bouts were linked — is matched by opponent and day. Otherwise
    /// the second meeting with a team in one weekend, a pool game and then
    /// the final, would vanish from the list the moment the first was played.
    static func upcoming(_ schedule: [APIClient.ScheduleEntry], games: [BoutMatch]) -> [APIClient.ScheduleEntry] {
        let linkedScheduleIds = Set(games.compactMap { $0.scheduleId.isEmpty ? nil : $0.scheduleId })
        let unlinked = games.filter { $0.scheduleId.isEmpty }
        return schedule.filter { entry in
            if linkedScheduleIds.contains(entry.id) { return false }
            let entryDate = boutDate(entry)
            return !unlinked.contains { game in
                let daysBetween = abs(Calendar.current.dateComponents([.day], from: game.date, to: entryDate).day ?? 999)
                return daysBetween <= 1 && TeamLogoSync.teamKey(game.opponent) == TeamLogoSync.teamKey(entry.opponent)
            }
        }
    }

    private var selectedSeasonId: String {
        seasonId ?? seasonStore.current?.id ?? Season.allId
    }

    private var seasonBinding: Binding<String> {
        Binding(get: { selectedSeasonId }, set: { seasonId = $0 })
    }

    /// Games in the selected season. Every season stays in the local store so
    /// stats and matchup history can look back; this list focuses on one.
    private var filteredGames: [Game] {
        if selectedSeasonId == Season.allId { return games }
        let scope = seasonStore.scope(seasonId: selectedSeasonId, type: nil)
        return games.filter { scope.includes($0) }
    }

    var body: some View {
        List {
            // Logo header
            Section {
                VStack(spacing: 8) {
                    Image("TeamLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 120)
                    Text("Frozen Flamingos")
                        .font(.system(size: 22, weight: .heavy, design: .default))
                        .foregroundStyle(AppTheme.pink)
                    Text(seasonStore.current?.label ?? "Season")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            // Pending send queue
            if syncManager.pendingCount > 0 {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: syncManager.isOnline ? "arrow.triangle.2.circlepath" : "wifi.slash")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(syncManager.pendingCount) game\(syncManager.pendingCount == 1 ? "" : "s") waiting to send")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.orange)
                            if !syncManager.isOnline {
                                Text("Will retry when back online")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if syncManager.isRetrying {
                            ProgressView()
                        } else if syncManager.isOnline {
                            Button("Retry") {
                                Task { await syncManager.retryNow() }
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.pink)
                        }
                    }
                }
            } else if !syncManager.isOnline {
                // Show offline indicator even without a queue
                Section {
                    Label("Offline", systemImage: "wifi.slash")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            // Sync status
            if isSyncing {
                Section {
                    HStack {
                        ProgressView()
                        Text("Syncing games...")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                }
            }

            if let syncError {
                Section {
                    Label(syncError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            }

            // Upcoming Bouts
            if !filteredSchedule.isEmpty {
                Section("Upcoming") {
                    ForEach(filteredSchedule) { entry in
                        Button {
                            if authManager.canManageGames {
                                createGameFromBout(entry)
                            }
                        } label: {
                            boutRow(entry)
                        }
                        .tint(.primary)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if authManager.canManageSchedule {
                                Button(role: .destructive) {
                                    boutToDelete = entry
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }

            // Games
            Section {
                SeasonPicker(seasonId: seasonBinding)
            }

            if filteredGames.isEmpty && !isSyncing {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "sportscourt")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("No Games")
                            .font(.headline)
                        Text(games.isEmpty ? "Tap + to add a game" : (Tournament.tournamentId(fromSelection: selectedSeasonId) == nil ? "No games in this season yet" : "No games in this tournament yet"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                    .listRowBackground(Color.clear)
                }
            } else if !filteredGames.isEmpty {
                Section("Games") {
                    ForEach(filteredGames) { game in
                        NavigationLink(value: game) {
                            gameRow(game)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if authManager.canManageGames {
                                Button(role: .destructive) {
                                    gameToDelete = game
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Games")
        .navigationDestination(for: Game.self) { game in
            GameDetailView(game: game)
        }
        .navigationDestination(item: $navigateToGame) { game in
            GameDetailView(game: game)
        }
        .toolbar {
            if authManager.canManageGames || authManager.canManageSchedule {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        if authManager.canManageGames {
                            Button {
                                showingAddGame = true
                            } label: {
                                Label("New Game", systemImage: "hockey.puck")
                            }
                        }
                        if authManager.canManageSchedule {
                            Button {
                                showingAddBout = true
                            } label: {
                                Label("Schedule Bout", systemImage: "calendar.badge.plus")
                            }
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddGame) {
            NavigationStack {
                GameFormView()
            }
        }
        .sheet(isPresented: $showingAddBout) {
            NavigationStack {
                ScheduleFormView { newEntry in
                    schedule.append(newEntry)
                    schedule.sort { $0.date < $1.date }
                }
            }
        }
        .alert(
            "Delete Game?",
            isPresented: Binding(
                get: { gameToDelete != nil },
                set: { if !$0 { gameToDelete = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) {
                gameToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let game = gameToDelete {
                    Task { await deleteGame(game) }
                }
                gameToDelete = nil
            }
        } message: {
            if let game = gameToDelete {
                Text("Delete vs \(game.opponent) on \(game.displayDate)?\(game.isSynced ? " This will also remove it from the website." : "") This cannot be undone.")
            }
        }
        .alert("Delete Failed", isPresented: $showDeleteError) {
            Button("OK") {}
        } message: {
            Text(deleteError ?? "An error occurred.")
        }
        .alert(
            "Delete Bout?",
            isPresented: Binding(
                get: { boutToDelete != nil },
                set: { if !$0 { boutToDelete = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { boutToDelete = nil }
            Button("Delete", role: .destructive) {
                if let bout = boutToDelete {
                    Task { await deleteBout(bout) }
                }
                boutToDelete = nil
            }
        } message: {
            if let bout = boutToDelete {
                Text("Remove \(bout.opponent) on \(bout.displayDate) from the schedule?")
            }
        }
        .task {
            async let s: () = syncGamesFromServer()
            async let f: () = fetchSchedule()
            async let l: () = syncTeamLogos()
            _ = await (s, f, l)
        }
        .refreshable {
            async let s: () = syncGamesFromServer()
            async let f: () = fetchSchedule()
            async let t: () = tournamentStore.load()
            async let l: () = syncTeamLogos()
            _ = await (s, f, t, l)
        }
    }

    // MARK: - Create from Bout

    private static func boutDate(_ entry: APIClient.ScheduleEntry) -> Date {
        let parts = entry.date.split(separator: "-")
        if parts.count == 3,
           let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) {
            var comps = DateComponents()
            comps.year = y
            comps.month = m
            comps.day = d
            if let parsed = Calendar.current.date(from: comps) {
                return parsed
            }
        }
        return Date()
    }

    private func createGameFromBout(_ entry: APIClient.ScheduleEntry) {
        let teamDescriptor = FetchDescriptor<Team>(
            predicate: #Predicate { $0.name == "Frozen Flamingos" }
        )
        let team = try? modelContext.fetch(teamDescriptor).first

        let game = Game(date: Self.boutDate(entry), opponent: entry.opponent, location: entry.location)
        game.scheduleId = entry.id
        game.tournamentId = entry.tournamentId ?? ""
        game.team = team
        modelContext.insert(game)
        try? modelContext.save()

        navigateToGame = game
    }

    // MARK: - Delete

    private func deleteGame(_ game: Game) async {
        // Delete from server first if synced
        if game.isSynced && !game.gameId.isEmpty {
            do {
                try await APIClient.deleteGameFromServer(gameId: game.gameId)
            } catch {
                deleteError = "Failed to delete from server: \(error.localizedDescription)"
                showDeleteError = true
                return
            }
        }

        LiveSessionStore.delete(gameId: game.gameId)
        APIClient.takeDownLiveScore(for: game.gameId)
        modelContext.delete(game)
        try? modelContext.save()
    }

    // MARK: - Sync

    private func syncTeamLogos() async {
        await TeamLogoSync.sync(modelContext: modelContext)
    }

    private func syncGamesFromServer() async {
        isSyncing = true
        syncError = nil

        do {
            // Every season. The server now scopes /api/games to the current
            // season by default, and the reconcile below deletes local synced
            // games the server did not return — asking for one season would
            // wipe every archived game off the device.
            let serverGames = try await APIClient.fetchGames(season: .all)
            let serverIds = Set(serverGames.compactMap(\.gameId))

            let dateFormatter = ISO8601DateFormatter()

            // Build player lookup by playerId for efficient stat hydration
            let playerById: [String: Player] = Dictionary(
                players.compactMap { p in
                    p.playerId.isEmpty ? nil : (p.playerId, p)
                },
                uniquingKeysWith: { first, _ in first }
            )

            // Also build lookup by number for legacy data without playerId
            let playerByNumber: [Int: Player] = Dictionary(
                players.compactMap { p in
                    p.number > 0 ? (p.number, p) : nil
                },
                uniquingKeysWith: { first, _ in first }
            )

            // Fetch team for assignment
            let teamDescriptor = FetchDescriptor<Team>(
                predicate: #Predicate { $0.name == "Frozen Flamingos" }
            )
            let team = try? modelContext.fetch(teamDescriptor).first

            for remote in serverGames {
                let remoteId = remote.gameId ?? ""
                guard !remoteId.isEmpty else { continue }

                if let local = games.first(where: { $0.gameId == remoteId }) {
                    // The server's copy replaces the local one only when this
                    // device has nothing newer; otherwise the scorekeeper's
                    // unsent fixes would vanish on refresh.
                    guard local.acceptsServerUpdate else { continue }
                    updateGame(local, from: remote, dateFormatter: dateFormatter, playerById: playerById, playerByNumber: playerByNumber)
                } else {
                    // Create new game from server
                    let parsedDate = dateFormatter.date(from: remote.date) ?? Date()

                    let newGame = Game(
                        date: parsedDate,
                        opponent: OpponentTeam.listedName(for: remote.opponent),
                        location: remote.location ?? "",
                        goalsFor: remote.goalsFor,
                        goalsAgainst: remote.goalsAgainst,
                        result: remote.result,
                        isComplete: true,
                        isSynced: true
                    )
                    newGame.gameId = remoteId
                    newGame.scheduleId = remote.scheduleId ?? ""
                    newGame.tournamentId = remote.tournamentId ?? ""
                    newGame.team = team
                    if let sg = remote.startingGoalie {
                        newGame.startingGoalie = findPlayer(sg.playerId, number: sg.playerNumber, playerById: playerById, playerByNumber: playerByNumber)
                    }

                    modelContext.insert(newGame)

                    hydratePlayerStats(for: newGame, from: remote.playerStats ?? [], playerById: playerById, playerByNumber: playerByNumber)
                    hydrateGoalieStats(for: newGame, from: remote.goalieStats ?? [], playerById: playerById, playerByNumber: playerByNumber)
                }
            }

            // Remove local synced games that no longer exist on server (deleted from another device)
            for local in games {
                if !local.gameId.isEmpty && local.isSynced && !local.hasLocalEdits && !serverIds.contains(local.gameId) {
                    LiveSessionStore.delete(gameId: local.gameId)
                    APIClient.takeDownLiveScore(for: local.gameId)
                    modelContext.delete(local)
                }
            }

            try modelContext.save()
        } catch {
            syncError = "Sync failed: \(error.localizedDescription)"
        }

        isSyncing = false
    }

    /// Find a local player by playerId (preferred) or jersey number (fallback for legacy data).
    private func findPlayer(
        _ playerId: String?,
        number: Int,
        playerById: [String: Player],
        playerByNumber: [Int: Player]
    ) -> Player? {
        if let id = playerId, !id.isEmpty, let player = playerById[id] {
            return player
        }
        if number > 0, let player = playerByNumber[number] {
            return player
        }
        return nil
    }

    private func updateGame(
        _ local: Game,
        from remote: APIClient.GameResponse,
        dateFormatter: ISO8601DateFormatter,
        playerById: [String: Player],
        playerByNumber: [Int: Player]
    ) {
        local.date = dateFormatter.date(from: remote.date) ?? local.date
        local.opponent = OpponentTeam.listedName(for: remote.opponent)
        local.location = remote.location ?? ""
        local.goalsFor = remote.goalsFor
        local.goalsAgainst = remote.goalsAgainst
        local.result = remote.result
        local.isComplete = true
        local.isSynced = true
        if let sid = remote.scheduleId, !sid.isEmpty {
            local.scheduleId = sid
        }
        // The server is the authority on which tournament a game belongs to:
        // it files a game by its bout even when this device sent no tournament.
        local.tournamentId = remote.tournamentId ?? ""
        if let sg = remote.startingGoalie {
            local.startingGoalie = findPlayer(sg.playerId, number: sg.playerNumber, playerById: playerById, playerByNumber: playerByNumber)
        }

        // Always re-hydrate player/goalie stats from the server. The previous
        // "unchanged" heuristic skipped re-hydration when score/result/opponent and
        // playerStats.count matched — which left mutations like +/- updates stranded
        // on the originating device.
        // Replace player stats (delete old, insert new)
        for oldStat in local.playerStats {
            modelContext.delete(oldStat)
        }
        local.playerStats.removeAll()
        hydratePlayerStats(for: local, from: remote.playerStats ?? [], playerById: playerById, playerByNumber: playerByNumber)

        // Replace goalie stats (cascade deletes shootout rounds)
        for oldStat in local.goalieStats {
            modelContext.delete(oldStat)
        }
        local.goalieStats.removeAll()
        hydrateGoalieStats(for: local, from: remote.goalieStats ?? [], playerById: playerById, playerByNumber: playerByNumber)
    }

    private func hydratePlayerStats(
        for game: Game,
        from remoteStats: [APIClient.GamePlayerStatResponse],
        playerById: [String: Player],
        playerByNumber: [Int: Player]
    ) {
        for remoteStat in remoteStats {
            let stat = GamePlayerStats(
                shots: remoteStat.shots ?? 0,
                goals: remoteStat.goals ?? 0,
                assists: remoteStat.assists ?? 0,
                hits: remoteStat.hits ?? 0,
                blocks: remoteStat.blocks ?? 0,
                penaltyMinutes: remoteStat.penaltyMinutes ?? 0,
                powerPlayGoals: remoteStat.powerPlayGoals ?? 0,
                shortHandedGoals: remoteStat.shortHandedGoals ?? 0,
                powerPlayAssists: remoteStat.powerPlayAssists ?? 0,
                shortHandedAssists: remoteStat.shortHandedAssists ?? 0,
                gameWinningGoals: remoteStat.gameWinningGoals ?? 0,
                faceoffWins: remoteStat.faceoffWins ?? 0,
                faceoffLosses: remoteStat.faceoffLosses ?? 0,
                timeOnIce: remoteStat.timeOnIce ?? 0,
                plusMinus: remoteStat.plusMinus ?? 0
            )
            stat.player = findPlayer(remoteStat.playerId, number: remoteStat.playerNumber, playerById: playerById, playerByNumber: playerByNumber)
            game.playerStats.append(stat)
            modelContext.insert(stat)

            // Hydrate per-shift records
            for remoteShift in remoteStat.shifts ?? [] {
                let shift = PlayerShift(
                    period: remoteShift.period,
                    duration: remoteShift.duration,
                    startClockTime: remoteShift.startClockTime ?? "",
                    endClockTime: remoteShift.endClockTime ?? ""
                )
                shift.gamePlayerStats = stat
                modelContext.insert(shift)
            }
        }
    }

    private func hydrateGoalieStats(
        for game: Game,
        from remoteStats: [APIClient.GameGoalieStatResponse],
        playerById: [String: Player],
        playerByNumber: [Int: Player]
    ) {
        for remoteStat in remoteStats {
            let stat = GameGoalieStats(
                shotsAgainst: remoteStat.shotsAgainst,
                goalsAgainst: remoteStat.goalsAgainst,
                result: remoteStat.result
            )
            stat.player = findPlayer(remoteStat.playerId, number: remoteStat.playerNumber, playerById: playerById, playerByNumber: playerByNumber)
            game.goalieStats.append(stat)
            modelContext.insert(stat)

            // Hydrate shootout rounds
            for remoteRound in (remoteStat.shootoutRounds ?? []) {
                let round = ShootoutRound(
                    roundNumber: remoteRound.roundNumber,
                    isGoal: remoteRound.isGoal
                )
                stat.shootoutRounds.append(round)
                modelContext.insert(round)
            }
        }
    }

    // MARK: - Schedule

    private func fetchSchedule() async {
        do {
            // Every season: the server now defaults to the current one, which
            // would hide a bout dated after the season ends (or left over at a
            // rollover) from the only screen that can start or delete it.
            schedule = try await APIClient.fetchSchedule(season: .all)
        } catch {
            // Schedule fetch is best-effort; don't show error for it
        }
    }

    private func deleteBout(_ bout: APIClient.ScheduleEntry) async {
        do {
            try await APIClient.deleteScheduleEntry(id: bout.id)
            schedule.removeAll { $0.id == bout.id }
        } catch {
            deleteError = "Failed to delete bout: \(error.localizedDescription)"
            showDeleteError = true
        }
    }

    @ViewBuilder
    private func boutRow(_ entry: APIClient.ScheduleEntry) -> some View {
        HStack(spacing: 12) {
            if let team = TeamLogoSync.team(named: entry.opponent, in: savedTeams) {
                boutTeamLogo(team: team, size: 36)
            } else {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Text(String(entry.opponent.prefix(1)))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.gray)
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.matchupTitle)
                    .font(.headline)
                if let tournament = tournamentStore.title(for: entry.tournamentId ?? "") {
                    tournamentTag(tournament)
                }
                HStack(spacing: 8) {
                    Text(entry.displayDate)
                    if !entry.time.isEmpty {
                        Text("·")
                        Text(entry.time)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if !entry.location.isEmpty {
                    Text(entry.location)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Image(systemName: "calendar")
                .foregroundStyle(AppTheme.pink)
                .font(.caption)
        }
    }

    @ViewBuilder
    private func boutTeamLogo(team: OpponentTeam, size: CGFloat) -> some View {
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
                .fill(Color.gray.opacity(0.3))
                .frame(width: size, height: size)
                .overlay(
                    Text(String(team.name.prefix(1)))
                        .font(.system(size: size * 0.4, weight: .bold))
                        .foregroundStyle(.gray)
                )
        }
    }

    // MARK: - Row

    private func tournamentTag(_ title: String) -> some View {
        Label(title, systemImage: "trophy.fill")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(AppTheme.pink)
            .lineLimit(1)
    }

    private func gameRow(_ game: Game) -> some View {
        HStack(spacing: 12) {
            if let team = TeamLogoSync.team(named: game.opponent, in: savedTeams) {
                boutTeamLogo(team: team, size: 36)
            } else {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Text(String(game.opponent.prefix(1)))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.gray)
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("vs \(game.opponent)")
                    .font(.headline)
                if let tournament = tournamentStore.title(for: game.tournamentId) {
                    tournamentTag(tournament)
                }
                Text(game.displayDate)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if game.isComplete {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(game.scoreDisplay)
                        .font(.system(.body, design: .monospaced, weight: .bold))
                    if let result = game.gameResult {
                        Text(result.shortName)
                            .font(.caption.bold())
                            .foregroundStyle(result.isWin ? .green : .red)
                    }
                }
            }

            if game.isSynced && game.hasLocalEdits {
                // Sent before, changed since: Save & Send to update the website.
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                    .accessibilityLabel("Edited since sent")
            } else if game.isSynced {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            }
        }
    }
}
