import SwiftUI
import SwiftData
import UIKit

struct GameDetailView: View {
    @Bindable var game: Game
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    @Environment(SyncManager.self) private var syncManager
    @Query(sort: \Player.number) private var allPlayers: [Player]
    @Query private var savedTeams: [OpponentTeam]

    @Environment(\.dismiss) private var dismiss

    @State private var sendError: String?
    @State private var showingSendError = false
    @State private var isSending = false
    @State private var showingGoaliePicker = false
    @State private var showingSummary = false
    @State private var showingStatsEditor = false
    @State private var showingLiveCheckIn = false
    @State private var showingGoLiveConfirm = false
    @State private var liveVM: LiveGameViewModel?
    @State private var pendingCheckedIn: [Player]?
    @State private var showingResetConfirm = false
    @State private var resetError: String?
    @State private var showingResetError = false
    @State private var isResetting = false
    @State private var showingLineupPicker = false
    @State private var showingMvpVote = false
    @State private var showingEventEditor = false

    private var goalies: [Player] {
        allPlayers.filter { $0.isGoalie }
    }

    private var lineupSkaters: [Player] {
        game.playerStats
            .sorted { a, b in
                let an = a.effectiveJerseyNumber
                let bn = b.effectiveJerseyNumber
                // Push -1 (subs without override) to the end
                if (an < 0) != (bn < 0) { return an >= 0 }
                return an < bn
            }
            .compactMap { $0.player }
    }

    private var hasLineup: Bool {
        !game.playerStats.isEmpty
    }

    var body: some View {
        List {
            // MARK: - Game Info
            Section("Game Info") {
                HStack {
                    Text("vs \(game.opponent)")
                        .font(.headline)
                    Spacer()
                    Text(game.displayDate)
                        .foregroundStyle(.secondary)
                }
                if !game.location.isEmpty {
                    HStack {
                        Text("Location")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(game.location)
                    }
                }
            }

            // MARK: - Score & Result
            Section("Score") {
                if authManager.canManageGames {
                    Stepper("Goals For: \(game.goalsFor)", value: $game.goalsFor, in: 0...99)
                    Stepper("Goals Against: \(game.goalsAgainst)", value: $game.goalsAgainst, in: 0...99)

                    Picker("Result", selection: $game.result) {
                        Text("None").tag("")
                        ForEach(GameResult.allCases) { result in
                            Text(result.displayName).tag(result.rawValue)
                        }
                    }
                } else {
                    HStack {
                        Text("Score")
                        Spacer()
                        Text(game.scoreDisplay)
                            .foregroundStyle(.secondary)
                    }
                    if let result = game.gameResult {
                        HStack {
                            Text("Result")
                            Spacer()
                            Text(result.displayName)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // MARK: - Starting Goalie
            Section("Starting Goalie") {
                if let goalie = game.startingGoalie {
                    NavigationLink {
                        GoalieStatsView(
                            player: goalie,
                            game: game
                        )
                    } label: {
                        HStack {
                            PlayerRow(player: goalie)
                            Spacer()
                            if goalieStats(for: goalie) != nil {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(AppTheme.pink)
                                    .font(.caption)
                            }
                        }
                    }

                    Button("Change Goalie") {
                        showingGoaliePicker = true
                    }
                    .foregroundStyle(AppTheme.pink)
                } else {
                    Button("Select Starting Goalie") {
                        showingGoaliePicker = true
                    }
                    .foregroundStyle(AppTheme.pink)
                }
            }

            // MARK: - Go Live
            if authManager.canManageGames {
                Section {
                    Button {
                        if hasLineup && game.startingGoalie != nil {
                            showingGoLiveConfirm = true
                        } else {
                            showingLiveCheckIn = true
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Label("Go Live", systemImage: "record.circle")
                                .font(.headline)
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                    .listRowBackground(AppTheme.teal)
                    .foregroundStyle(.white)
                }
            }

            // MARK: - Skaters
            Section("Skaters") {
                if hasLineup {
                    ForEach(lineupSkaters) { player in
                        let stats = playerStats(for: player)
                        NavigationLink {
                            PlayerStatsView(player: player, stats: stats, game: game)
                        } label: {
                            HStack {
                                PlayerRow(player: player)
                                if stats?.hasRecordedStats == true {
                                    Spacer()
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(AppTheme.pink)
                                        .font(.caption)
                                }
                            }
                        }
                    }

                    Button("Edit Lineup") {
                        showingLineupPicker = true
                    }
                    .foregroundStyle(AppTheme.teal)
                } else {
                    Button {
                        showingLineupPicker = true
                    } label: {
                        HStack {
                            Spacer()
                            Label("Set Lineup", systemImage: "person.3.fill")
                                .font(.headline)
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                    .foregroundStyle(AppTheme.pink)
                }
            }

            // MARK: - Edit Stats
            if authManager.canManageGames && !game.playerStats.isEmpty {
                Section {
                    Button {
                        showingStatsEditor = true
                    } label: {
                        HStack {
                            Spacer()
                            Label("Edit Stats", systemImage: "pencil.and.list.clipboard")
                                .font(.headline)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    .foregroundStyle(AppTheme.teal)
                }
            }

            // MARK: - Edit Events
            if authManager.canManageGames && !game.events.isEmpty {
                Section {
                    Button {
                        showingEventEditor = true
                    } label: {
                        HStack {
                            Spacer()
                            Label("Edit Events", systemImage: "list.bullet.rectangle")
                                .font(.headline)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    .foregroundStyle(AppTheme.teal)
                }
            }

            // MARK: - Game Summary
            Section {
                Button {
                    showingSummary = true
                } label: {
                    HStack {
                        Spacer()
                        Label("Game Summary", systemImage: "list.clipboard")
                            .font(.headline)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }

            // MARK: - Save & Send
            if authManager.canManageGames {
                Section {
                    Button {
                        Task { await sendStats() }
                    } label: {
                        HStack {
                            Spacer()
                            if isSending {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text(game.isSynced ? "Re-Send Stats" : "Save & Send")
                                    .font(.headline)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                    .listRowBackground(AppTheme.pink)
                    .foregroundStyle(.white)
                    .disabled(isSending)
                }
            }

            if game.isSynced {
                Section {
                    Label("Sent to server", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            } else if game.pendingSync {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: syncManager.isOnline ? "arrow.triangle.2.circlepath" : "wifi.slash")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(syncManager.isOnline ? "Waiting to send" : "Offline — will send when reconnected")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.orange)
                            if let last = game.lastSyncError {
                                Text(last)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
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
            }

            // MARK: - MVP Voting
            if authManager.canManageGames && game.isSynced && !game.gameId.isEmpty {
                Section {
                    Button {
                        showingMvpVote = true
                    } label: {
                        HStack {
                            Spacer()
                            Label("MVP Voting", systemImage: "trophy.fill")
                                .font(.headline)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    .foregroundStyle(AppTheme.teal)
                }
            }

            // MARK: - Reset Game
            if authManager.canManageGames && !game.scheduleId.isEmpty {
                Section {
                    Button(role: .destructive) {
                        showingResetConfirm = true
                    } label: {
                        HStack {
                            Spacer()
                            if isResetting {
                                ProgressView()
                            } else {
                                Label("Reset to Bout", systemImage: "arrow.uturn.backward")
                                    .font(.headline)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    .disabled(isResetting)
                } footer: {
                    Text("Clears all stats and returns this game to the schedule as an upcoming bout.")
                }
            }
        }
        .navigationTitle("vs \(game.opponent)")
        .alert("Send Failed", isPresented: $showingSendError) {
            Button("OK") {}
        } message: {
            Text(sendError ?? "Unknown error")
        }
        .alert("Reset Game?", isPresented: $showingResetConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                Task { await resetGame() }
            }
        } message: {
            Text("This will clear all stats and events for this game and return it to the schedule as an upcoming bout.")
        }
        .alert("Reset Failed", isPresented: $showingResetError) {
            Button("OK") {}
        } message: {
            Text(resetError ?? "Unknown error")
        }
        .sheet(isPresented: $showingGoaliePicker) {
            NavigationStack {
                GoaliePickerView(game: game, goalies: goalies)
            }
        }
        .sheet(isPresented: $showingLineupPicker) {
            NavigationStack {
                GameLineupPickerView(game: game, allPlayers: allPlayers)
            }
        }
        .sheet(isPresented: $showingMvpVote) {
            NavigationStack {
                MvpVoteView(game: game)
            }
        }
        .sheet(isPresented: $showingEventEditor) {
            NavigationStack {
                GameEventEditorView(game: game)
            }
        }
        .sheet(isPresented: $showingSummary) {
            NavigationStack {
                GameSummaryView(game: game)
            }
        }
        .sheet(isPresented: $showingStatsEditor) {
            NavigationStack {
                GameStatsEditorView(game: game)
            }
        }
        .sheet(isPresented: $showingLiveCheckIn, onDismiss: {
            if let players = pendingCheckedIn {
                pendingCheckedIn = nil
                let vm = LiveGameViewModel(game: game, modelContext: modelContext)
                vm.checkedInPlayers = players
                vm.initializeStatsForCheckedInPlayers()
                liveVM = vm
            }
        }) {
            LineupCheckInView(
                game: game,
                allPlayers: allPlayers.filter { $0.isActive }
            ) { checkedIn in
                pendingCheckedIn = checkedIn
                showingLiveCheckIn = false
            }
        }
        .sheet(isPresented: $showingGoLiveConfirm) {
            NavigationStack {
                GoLiveConfirmView(
                    game: game,
                    onStart: {
                        var players = lineupSkaters
                        if let goalie = game.startingGoalie, !players.contains(where: { $0.persistentModelID == goalie.persistentModelID }) {
                            players.insert(goalie, at: 0)
                        }
                        showingGoLiveConfirm = false
                        let vm = LiveGameViewModel(game: game, modelContext: modelContext)
                        vm.checkedInPlayers = players
                        vm.initializeStatsForCheckedInPlayers()
                        liveVM = vm
                    },
                    onEditLineup: {
                        showingGoLiveConfirm = false
                        showingLineupPicker = true
                    }
                )
            }
        }
        .fullScreenCover(item: $liveVM) { vm in
            LiveGameView(vm: vm) {
                liveVM = nil
            }
        }
    }

    // MARK: - Helpers

    private func playerStats(for player: Player) -> GamePlayerStats? {
        game.playerStats.first { $0.player?.persistentModelID == player.persistentModelID }
    }

    private func goalieStats(for player: Player) -> GameGoalieStats? {
        game.goalieStats.first { $0.player?.persistentModelID == player.persistentModelID }
    }

    private func resetGame() async {
        isResetting = true
        if game.isSynced && !game.gameId.isEmpty {
            do {
                try await APIClient.deleteGameFromServer(gameId: game.gameId)
            } catch {
                resetError = "Failed to remove from server: \(error.localizedDescription)"
                showingResetError = true
                isResetting = false
                return
            }
        }
        modelContext.delete(game)
        try? modelContext.save()
        isResetting = false
        dismiss()
    }

    private func sendStats() async {
        isSending = true
        game.isComplete = true
        try? modelContext.save()

        // Ensure a goalie stat record exists for the starting goalie
        if let goalie = game.startingGoalie,
           !game.goalieStats.contains(where: { $0.player?.persistentModelID == goalie.persistentModelID }) {
            let gs = GameGoalieStats()
            gs.player = goalie
            game.goalieStats.append(gs)
            modelContext.insert(gs)
            try? modelContext.save()
        }

        do {
            try await APIClient.sendGameStats(game: game)
            game.isSynced = true
            syncManager.markSent(game: game)
            try? modelContext.save()

            // Upload opponent logo if we have one (user photo or asset catalog)
            if let opponentTeam = savedTeams.first(where: { $0.name == game.opponent }) {
                if let logoData = opponentTeam.logoData {
                    await APIClient.sendTeamLogo(teamName: game.opponent, logoData: logoData)
                } else if let asset = opponentTeam.logoAsset,
                          let uiImage = UIImage(named: asset),
                          let pngData = uiImage.pngData() {
                    await APIClient.sendTeamLogo(teamName: game.opponent, logoData: pngData)
                }
            }
        } catch {
            syncManager.enqueue(game: game, error: error)
            sendError = "\(error.localizedDescription)\n\nWe'll keep trying in the background."
            showingSendError = true
        }
        isSending = false
    }
}

// MARK: - Lineup Picker

struct GameLineupPickerView: View {
    let game: Game
    let allPlayers: [Player]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIds: Set<PersistentIdentifier> = []

    /// Per-game number overrides keyed by player. Nil means "use roster number."
    @State private var jerseyOverrides: [PersistentIdentifier: Int] = [:]
    @State private var jerseyEditingPlayer: Player?
    @State private var jerseyInput: String = ""
    @State private var showingAddSub = false

    private var skaters: [Player] {
        allPlayers.sorted { a, b in
            // 1) Effective tonight-number ascending (subs/no-number to the end)
            let an = effectiveNumber(for: a)
            let bn = effectiveNumber(for: b)
            if an != bn { return an < bn }
            // 2) Fall back to name for stable order
            return a.name < b.name
        }
    }

    /// Effective jersey number for sort purposes, using the per-game override if entered
    /// in this picker, else the player's roster number, else `Int.max` for unnumbered subs.
    private func effectiveNumber(for player: Player) -> Int {
        if let override = jerseyOverrides[player.persistentModelID] { return override }
        if player.isSubstitute { return Int.max }
        return player.number
    }

    private let columns = [GridItem(.adaptive(minimum: 80), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("\(selectedIds.count) selected")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        showingAddSub = true
                    } label: {
                        Label("Add Sub", systemImage: "person.fill.badge.plus")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.pink)
                    }
                    Button(selectedIds.count == skaters.count ? "Deselect All" : "Select All") {
                        if selectedIds.count == skaters.count {
                            selectedIds.removeAll()
                        } else {
                            selectedIds = Set(skaters.map(\.persistentModelID))
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.teal)
                }
                .padding(.horizontal)

                Text("Tap a player to add to the lineup. Tap the # badge on a tile to set a per-game jersey number.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(skaters) { player in
                        playerTile(player)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle("Set Lineup")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    applyLineup()
                    dismiss()
                }
                .fontWeight(.bold)
            }
        }
        .onAppear {
            selectedIds = Set(
                game.playerStats.compactMap { $0.player?.persistentModelID }
            )
            // Hydrate jersey overrides from existing GamePlayerStats
            for stat in game.playerStats {
                if let id = stat.player?.persistentModelID, let override = stat.gameJerseyNumber {
                    jerseyOverrides[id] = override
                }
            }
        }
        .alert("Set Jersey for Tonight", isPresented: Binding(
            get: { jerseyEditingPlayer != nil },
            set: { if !$0 { jerseyEditingPlayer = nil; jerseyInput = "" } }
        )) {
            TextField("#", text: $jerseyInput)
                .keyboardType(.numberPad)
            Button("Clear", role: .destructive) {
                if let p = jerseyEditingPlayer {
                    jerseyOverrides.removeValue(forKey: p.persistentModelID)
                }
                jerseyEditingPlayer = nil
                jerseyInput = ""
            }
            Button("Save") {
                if let p = jerseyEditingPlayer, let num = Int(jerseyInput) {
                    jerseyOverrides[p.persistentModelID] = num
                }
                jerseyEditingPlayer = nil
                jerseyInput = ""
            }
            Button("Cancel", role: .cancel) {
                jerseyEditingPlayer = nil
                jerseyInput = ""
            }
        } message: {
            if let p = jerseyEditingPlayer {
                Text("\(p.name)'s number for this game only. Their roster number is \(p.isSubstitute ? "— (substitute)" : "#\(p.number)").")
            }
        }
        .sheet(isPresented: $showingAddSub) {
            NavigationStack {
                AddSubstituteSheet(game: game) { newPlayer, jerseyOverride in
                    selectedIds.insert(newPlayer.persistentModelID)
                    if let n = jerseyOverride {
                        jerseyOverrides[newPlayer.persistentModelID] = n
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func playerTile(_ player: Player) -> some View {
        let id = player.persistentModelID
        let isSelected = selectedIds.contains(id)
        let override = jerseyOverrides[id]
        let displayNumber: String = {
            if let override {
                return override == 0 ? "00" : "\(override)"
            }
            return player.jerseyText
        }()
        Button {
            if isSelected {
                selectedIds.remove(id)
            } else {
                selectedIds.insert(id)
            }
        } label: {
            VStack(spacing: 4) {
                Text(displayNumber)
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundStyle(isSelected ? .white : .secondary)
                Text(player.lastName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                    .lineLimit(1)
                if override != nil || player.isSubstitute {
                    Text(player.isSubstitute ? "SUB" : "TONIGHT")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(AppTheme.teal, in: Capsule())
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 80)
            .background(isSelected ? AppTheme.pink : Color(.systemGray5), in: RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .topTrailing) {
                Button {
                    jerseyEditingPlayer = player
                    jerseyInput = override.map { "\($0)" } ?? ""
                } label: {
                    Image(systemName: "number")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(AppTheme.teal, in: Circle())
                }
                .buttonStyle(.plain)
                .padding(4)
            }
        }
        .contextMenu {
            Button {
                jerseyEditingPlayer = player
                jerseyInput = override.map { "\($0)" } ?? ""
            } label: {
                Label(override == nil ? "Set Game Number" : "Change Game Number (currently #\(override!))", systemImage: "number")
            }
            if override != nil {
                Button(role: .destructive) {
                    jerseyOverrides.removeValue(forKey: id)
                } label: {
                    Label("Clear Game Number", systemImage: "xmark.circle")
                }
            }
        }
    }

    private func applyLineup() {
        let currentIds = Set(game.playerStats.compactMap { $0.player?.persistentModelID })

        // Create stat records for newly added players, and update existing ones with overrides
        for player in skaters where selectedIds.contains(player.persistentModelID) {
            let id = player.persistentModelID
            if let existing = game.playerStats.first(where: { $0.player?.persistentModelID == id }) {
                existing.gameJerseyNumber = jerseyOverrides[id]
            } else if !currentIds.contains(id) {
                let stats = GamePlayerStats()
                stats.player = player
                stats.game = game
                stats.gameJerseyNumber = jerseyOverrides[id]
                modelContext.insert(stats)
            }
        }

        for stat in game.playerStats {
            guard let playerId = stat.player?.persistentModelID else { continue }
            if !selectedIds.contains(playerId) && !stat.hasRecordedStats {
                modelContext.delete(stat)
            }
        }

        try? modelContext.save()
    }
}

// MARK: - Add Substitute Sheet

private struct AddSubstituteSheet: View {
    let game: Game
    let onAdded: (Player, Int?) -> Void
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var jerseyForTonight: String = ""
    @State private var position: String = "Forward"
    @State private var isGoalie: Bool = false
    @State private var error: String?

    var body: some View {
        Form {
            Section("Name") {
                TextField("Full name", text: $name)
                    .textInputAutocapitalization(.words)
            }
            Section("Position") {
                Picker("Position", selection: $position) {
                    Text("Forward").tag("Forward")
                    Text("Defense").tag("Defense")
                    Text("Goalie").tag("Goalie")
                }
                .pickerStyle(.segmented)
            }
            Section {
                TextField("Jersey for tonight (optional)", text: $jerseyForTonight)
                    .keyboardType(.numberPad)
            } footer: {
                Text("Subs don't get a permanent jersey number — only this game. Leave blank if unknown.")
            }
            if let error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle("Add Substitute")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") { add() }
                    .fontWeight(.bold)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onChange(of: position) { _, newValue in
            isGoalie = (newValue == "Goalie")
        }
    }

    private func add() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let jerseyOverride: Int? = Int(jerseyForTonight.trimmingCharacters(in: .whitespaces))

        let player = Player(
            name: trimmedName,
            number: 0,
            position: position,
            isGoalie: isGoalie,
            isActive: true
        )
        player.playerId = UUID().uuidString
        player.isSubstitute = true

        // Attach to the team
        let teamDescriptor = FetchDescriptor<Team>(
            predicate: #Predicate { $0.name == "Frozen Flamingos" }
        )
        if let team = try? modelContext.fetch(teamDescriptor).first {
            player.team = team
        }
        modelContext.insert(player)
        try? modelContext.save()

        onAdded(player, jerseyOverride)
        dismiss()
    }
}

// MARK: - Go Live Confirm

private struct GoLiveConfirmView: View {
    let game: Game
    let onStart: () -> Void
    let onEditLineup: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var sortedStats: [GamePlayerStats] {
        game.playerStats
            .filter { $0.player != nil }
            .sorted { a, b in
                let an = a.effectiveJerseyNumber
                let bn = b.effectiveJerseyNumber
                // Subs (-1) at the bottom
                if (an < 0) != (bn < 0) { return an >= 0 }
                return an < bn
            }
    }

    var body: some View {
        List {
            if let goalie = game.startingGoalie {
                Section("Starting Goalie") {
                    HStack {
                        Text(goalie.displayNumber)
                            .font(.system(.body, design: .monospaced, weight: .bold))
                            .foregroundStyle(AppTheme.pink)
                            .frame(width: 50, alignment: .leading)
                        Text(goalie.name)
                        Spacer()
                    }
                }
            }

            Section("Skaters (\(sortedStats.count))") {
                ForEach(sortedStats, id: \.persistentModelID) { stat in
                    if let player = stat.player {
                        HStack {
                            Text(stat.effectiveJerseyText == "—" ? "—" : "#\(stat.effectiveJerseyText)")
                                .font(.system(.body, design: .monospaced, weight: .bold))
                                .foregroundStyle(AppTheme.pink)
                                .frame(width: 50, alignment: .leading)
                            Text(player.name)
                            if player.isSubstitute {
                                Text("SUB")
                                    .font(.system(size: 9, weight: .heavy))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(AppTheme.teal, in: Capsule())
                            }
                            if stat.gameJerseyNumber != nil && !player.isSubstitute {
                                Text("TONIGHT")
                                    .font(.system(size: 9, weight: .heavy))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(AppTheme.teal, in: Capsule())
                            }
                            Spacer()
                        }
                    }
                }
            }

            Section {
                Button {
                    onStart()
                } label: {
                    HStack {
                        Spacer()
                        Label("Start Tracking", systemImage: "record.circle")
                            .font(.headline)
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
                .listRowBackground(AppTheme.teal)
                .foregroundStyle(.white)

                Button {
                    onEditLineup()
                } label: {
                    HStack {
                        Spacer()
                        Label("Edit Lineup", systemImage: "person.3.fill")
                            .font(.subheadline)
                        Spacer()
                    }
                }
                .foregroundStyle(AppTheme.pink)
            }
        }
        .navigationTitle("Go Live")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }
}

// MARK: - Goalie Picker

struct GoaliePickerView: View {
    let game: Game
    let goalies: [Player]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(goalies) { goalie in
                Button {
                    game.startingGoalie = goalie
                    dismiss()
                } label: {
                    HStack {
                        PlayerRow(player: goalie)
                        Spacer()
                        if game.startingGoalie?.persistentModelID == goalie.persistentModelID {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(AppTheme.pink)
                        }
                    }
                }
                .tint(.primary)
            }
        }
        .navigationTitle("Select Goalie")
        .toolbar {
            Button("Done") { dismiss() }
        }
    }
}
