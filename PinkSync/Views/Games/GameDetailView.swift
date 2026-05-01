import SwiftUI
import SwiftData
import UIKit

struct GameDetailView: View {
    @Bindable var game: Game
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    @Query(sort: \Player.number) private var allPlayers: [Player]
    @Query private var savedTeams: [OpponentTeam]

    @State private var sendError: String?
    @State private var showingSendError = false
    @State private var isSending = false
    @State private var showingGoaliePicker = false
    @State private var showingSummary = false
    @State private var showingLiveCheckIn = false
    @State private var liveVM: LiveGameViewModel?
    @State private var pendingCheckedIn: [Player]?

    private var goalies: [Player] {
        allPlayers.filter { $0.isGoalie }
    }

    // All players appear as skaters (including dual-role goalies)
    private var skaters: [Player] {
        allPlayers
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
                ForEach(skaters) { player in
                    let stats = playerStats(for: player)
                    NavigationLink {
                        PlayerStatsView(player: player, stats: stats, game: game)
                    } label: {
                        HStack {
                            PlayerRow(player: player)
                            if stats != nil {
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(AppTheme.pink)
                                    .font(.caption)
                            }
                        }
                    }
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
        }
        .navigationTitle("vs \(game.opponent)")
        .alert("Send Failed", isPresented: $showingSendError) {
            Button("OK") {}
        } message: {
            Text(sendError ?? "Unknown error")
        }
        .sheet(isPresented: $showingGoaliePicker) {
            NavigationStack {
                GoaliePickerView(game: game, goalies: goalies)
            }
        }
        .sheet(isPresented: $showingSummary) {
            NavigationStack {
                GameSummaryView(game: game)
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
    }

    // MARK: - Helpers

    private func playerStats(for player: Player) -> GamePlayerStats? {
        game.playerStats.first { $0.player?.persistentModelID == player.persistentModelID }
    }

    private func goalieStats(for player: Player) -> GameGoalieStats? {
        game.goalieStats.first { $0.player?.persistentModelID == player.persistentModelID }
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
        } catch {
            sendError = error.localizedDescription
            showingSendError = true
        }
        isSending = false
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
