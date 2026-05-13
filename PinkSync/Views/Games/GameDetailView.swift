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
    @State private var isLoadingMvpVoteSummary = false
    @State private var mvpVoteSummaryError: String?

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

    private var shouldShowMvpVoting: Bool {
        authManager.canManageGames && game.isSynced && !game.gameId.isEmpty
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

            if shouldShowMvpVoting {
                Section("MVP Voting") {
                    if isLoadingMvpVoteSummary {
                        HStack {
                            ProgressView()
                            Text("Loading vote summary...")
                                .foregroundStyle(.secondary)
                        }
                    } else if let summary = mvpVoteSummary {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(mvpVotingStatusLabel(summary.status))
                                    .font(.caption.bold())
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(mvpVotingStatusColor(summary.status).opacity(0.18))
                                    .foregroundStyle(mvpVotingStatusColor(summary.status))
                                    .clipShape(Capsule())
                                Spacer()
                                if let finalMvp = summary.finalMvp {
                                    Text("Voted MVP: \(finalMvp.playerName)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.trailing)
                                } else if !summary.stars.isEmpty {
                                    Text("Three Stars of the Game: \(summary.stars.prefix(3).map(\.playerName).joined(separator: ", "))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.trailing)
                                } else if let algorithmicMvp = summary.algorithmicMvp {
                                    Text("Three Stars of the Game: \(algorithmicMvp.playerName)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.trailing)
                                }
                            }

                            HStack(spacing: 20) {
                                compactMetric("Eligible", "\(summary.totalEligibleCount)")
                                compactMetric("Ballots", "\(summary.totalBallotCount)")
                                compactMetric("Votes", "\(summary.votedCount)")
                            }

                            if let timelineText = mvpVotingTimelineText(summary) {
                                Text(timelineText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if let blockedReason = mvpVotingBlockedReason(summary.blockedReason) {
                                Text(blockedReason)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                        .padding(.vertical, 4)
                    } else if let mvpVoteSummaryError {
                        Label(mvpVoteSummaryError, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Text("Voting hasn't opened for this synced game yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button("Refresh Summary") {
                        Task { await loadMvpVoteSummary(force: true) }
                    }
                    .foregroundStyle(AppTheme.teal)
                    .disabled(isLoadingMvpVoteSummary)
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
        .task(id: "\(game.gameId)-\(game.isSynced)") {
            await loadMvpVoteSummary()
        }
    }

    // MARK: - Helpers

    private func playerStats(for player: Player) -> GamePlayerStats? {
        game.playerStats.first { $0.player?.persistentModelID == player.persistentModelID }
    }

    private func goalieStats(for player: Player) -> GameGoalieStats? {
        game.goalieStats.first { $0.player?.persistentModelID == player.persistentModelID }
    }

    private func compactMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.headline, design: .monospaced, weight: .bold))
            Text(label)
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
        }
    }

    private func mvpVotingStatusColor(_ status: String) -> Color {
        switch status {
        case "open": return AppTheme.teal
        case "submitted", "closed": return AppTheme.pink
        case "blocked": return .orange
        default: return .secondary
        }
    }

    private func mvpVotingStatusLabel(_ status: String) -> String {
        switch status {
        case "open": return "Open"
        case "submitted": return "Submitted"
        case "closed": return "Closed"
        case "blocked": return "Blocked"
        default: return status.capitalized
        }
    }

    private func formattedVoteTimestamp(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: raw) else { return raw }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func mvpVotingTimelineText(_ summary: APIClient.MvpVoteSummary) -> String? {
        if summary.status == "open", let closesAt = formattedVoteTimestamp(summary.closesAt) {
            return "Voting closes \(closesAt)"
        }
        if summary.status == "closed", let closedAt = formattedVoteTimestamp(summary.closedAt ?? summary.closesAt) {
            return "Voting closed \(closedAt)"
        }
        if let openedAt = formattedVoteTimestamp(summary.openedAt) {
            return "Opened \(openedAt)"
        }
        return nil
    }

    private func mvpVotingBlockedReason(_ reason: String?) -> String? {
        switch reason {
        case "no_candidates":
            return "Voting could not open because this game did not have any eligible players."
        default:
            return nil
        }
    }

    private func loadMvpVoteSummary(force: Bool = false) async {
        guard shouldShowMvpVoting else {
            mvpVoteSummary = nil
            mvpVoteSummaryError = nil
            return
        }
        if isLoadingMvpVoteSummary && !force { return }

        isLoadingMvpVoteSummary = true
        mvpVoteSummaryError = nil
        do {
            mvpVoteSummary = try await APIClient.fetchMvpVoteSummary(gameId: game.gameId)
        } catch {
            mvpVoteSummary = nil
            mvpVoteSummaryError = "Couldn't load the MVP voting summary."
        }
        isLoadingMvpVoteSummary = false
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
            await loadMvpVoteSummary(force: true)
        } catch {
            sendError = error.localizedDescription
            showingSendError = true
        }
        isSending = false
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
