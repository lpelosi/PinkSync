import SwiftUI
import SwiftData
import UIKit

struct GameDetailView: View {
    @Bindable var game: Game
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
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
    @State private var liveVM: LiveGameViewModel?
    @State private var pendingCheckedIn: [Player]?
    @State private var showingResetConfirm = false
    @State private var resetError: String?
    @State private var showingResetError = false
    @State private var isResetting = false
    @State private var showingLineupPicker = false
    @State private var mvpVoteSummary: APIClient.MvpVoteSummary?
    @State private var isLoadingMvpVote = false
    @State private var isClosingMvpVote = false
    @State private var mvpVoteError: String?
    @State private var showingMvpVoteError = false
    @State private var showingCloseMvpVoteConfirm = false

    private var goalies: [Player] {
        allPlayers.filter { $0.isGoalie }
    }

    private var lineupSkaters: [Player] {
        game.playerStats
            .compactMap { $0.player }
            .sorted { $0.number < $1.number }
    }

    private var hasLineup: Bool {
        !lineupSkaters.isEmpty
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
                        showingLiveCheckIn = true
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
                                if stats != nil && stats!.hasRecordedStats {
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

            if game.isSynced {
                mvpVoteSection
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
        .alert("End MVP Vote Early?", isPresented: $showingCloseMvpVoteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("End Vote", role: .destructive) {
                Task { await closeMvpVote() }
            }
        } message: {
            Text("This closes player voting now and shows the final MVP result.")
        }
        .alert("MVP Vote Error", isPresented: $showingMvpVoteError) {
            Button("OK") {}
        } message: {
            Text(mvpVoteError ?? "Unknown error")
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
        .fullScreenCover(item: $liveVM) { vm in
            LiveGameView(vm: vm) {
                liveVM = nil
            }
        }
        .task(id: game.gameId) {
            await loadMvpVoteStatus()
        }
    }

    // MARK: - Helpers

    private var mvpVoteSection: some View {
        Section("MVP Vote") {
            if isLoadingMvpVote && mvpVoteSummary == nil {
                HStack {
                    ProgressView()
                    Text("Loading vote status")
                        .foregroundStyle(.secondary)
                }
            } else if let summary = mvpVoteSummary {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: mvpVoteStatusIcon(summary))
                            .foregroundStyle(mvpVoteStatusColor(summary))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(mvpVoteStatusLabel(summary))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(mvpVoteStatusColor(summary))
                            Text(mvpVoteCountText(summary))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }

                    if summary.status == "open", let closesAt = summary.closesAt {
                        Text("Closes \(formatVoteDate(closesAt))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if summary.status == "closed" {
                        if let finalMvp = summary.finalMvp {
                            Text("Winner: #\(finalMvp.playerNumber) \(finalMvp.playerName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Voting closed with no ballots.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if summary.status == "blocked" {
                        Text("Voting could not open for this game.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if authManager.canManageGames && summary.status == "open" {
                    Button(role: .destructive) {
                        showingCloseMvpVoteConfirm = true
                    } label: {
                        HStack {
                            Spacer()
                            if isClosingMvpVote {
                                ProgressView()
                            } else {
                                Label("End Early", systemImage: "stop.circle")
                                    .font(.headline)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    .disabled(isClosingMvpVote)
                }
            } else {
                Text("No MVP vote found for this game yet.")
                    .foregroundStyle(.secondary)
            }

            Button {
                Task { await loadMvpVoteStatus() }
            } label: {
                Label("Refresh Vote Status", systemImage: "arrow.clockwise")
            }
            .disabled(isLoadingMvpVote)
        }
    }

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
            try? modelContext.save()
            await loadMvpVoteStatus()

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
            sendError = error.localizedDescription
            showingSendError = true
        }
        isSending = false
    }

    private func loadMvpVoteStatus() async {
        guard game.isSynced, !game.gameId.isEmpty else {
            mvpVoteSummary = nil
            return
        }

        isLoadingMvpVote = true
        defer { isLoadingMvpVote = false }

        do {
            mvpVoteSummary = try await APIClient.fetchMvpVoteStatus(gameId: game.gameId)
        } catch {
            mvpVoteError = error.localizedDescription
            showingMvpVoteError = true
        }
    }

    private func closeMvpVote() async {
        guard !game.gameId.isEmpty else { return }

        isClosingMvpVote = true
        defer { isClosingMvpVote = false }

        do {
            mvpVoteSummary = try await APIClient.closeMvpVote(gameId: game.gameId)
        } catch {
            mvpVoteError = error.localizedDescription
            showingMvpVoteError = true
        }
    }

    private func mvpVoteStatusLabel(_ summary: APIClient.MvpVoteSummary) -> String {
        switch summary.status {
        case "open": "Voting Live"
        case "closed": "Voting Closed"
        case "blocked": "Vote Unavailable"
        default: "Vote Status"
        }
    }

    private func mvpVoteStatusIcon(_ summary: APIClient.MvpVoteSummary) -> String {
        switch summary.status {
        case "open": "checkmark.circle.fill"
        case "closed": "lock.circle.fill"
        case "blocked": "exclamationmark.triangle.fill"
        default: "info.circle"
        }
    }

    private func mvpVoteStatusColor(_ summary: APIClient.MvpVoteSummary) -> Color {
        switch summary.status {
        case "open": AppTheme.teal
        case "closed": AppTheme.pink
        case "blocked": .orange
        default: .secondary
        }
    }

    private func mvpVoteCountText(_ summary: APIClient.MvpVoteSummary) -> String {
        let label = summary.totalBallotCount == 1 ? "vote" : "votes"
        if summary.votedCount != summary.totalBallotCount {
            return "\(summary.totalBallotCount) \(label) received, \(summary.votedCount) counted"
        }
        return "\(summary.totalBallotCount) \(label) received"
    }

    private func formatVoteDate(_ value: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: value) else { return value }
        return date.formatted(date: .omitted, time: .shortened)
    }
}

// MARK: - Goalie Picker

// MARK: - Lineup Picker

struct GameLineupPickerView: View {
    let game: Game
    let allPlayers: [Player]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIds: Set<PersistentIdentifier> = []

    private var skaters: [Player] {
        allPlayers.sorted { $0.number < $1.number }
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

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(skaters) { player in
                        let isSelected = selectedIds.contains(player.persistentModelID)
                        Button {
                            if isSelected {
                                selectedIds.remove(player.persistentModelID)
                            } else {
                                selectedIds.insert(player.persistentModelID)
                            }
                        } label: {
                            VStack(spacing: 4) {
                                Text(player.number > 0 ? "\(player.number)" : "—")
                                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                                    .foregroundStyle(isSelected ? .white : .secondary)
                                Text(lastName(player.name))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 80)
                            .background(isSelected ? AppTheme.pink : Color(.systemGray5), in: RoundedRectangle(cornerRadius: 12))
                        }
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
        }
    }

    private func applyLineup() {
        let currentIds = Set(game.playerStats.compactMap { $0.player?.persistentModelID })

        for player in skaters where selectedIds.contains(player.persistentModelID) && !currentIds.contains(player.persistentModelID) {
            let stats = GamePlayerStats()
            stats.player = player
            stats.game = game
            modelContext.insert(stats)
        }

        for stat in game.playerStats {
            guard let playerId = stat.player?.persistentModelID else { continue }
            if !selectedIds.contains(playerId) && !stat.hasRecordedStats {
                modelContext.delete(stat)
            }
        }

        try? modelContext.save()
    }

    private func lastName(_ name: String) -> String {
        name.components(separatedBy: " ").last ?? name
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
