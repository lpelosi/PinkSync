import SwiftUI
import SwiftData

struct RosterView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    @Environment(SeasonStore.self) private var seasonStore
    @Environment(TournamentStore.self) private var tournamentStore
    @Query(sort: \Player.number) private var players: [Player]

    @State private var showingAddPlayer = false
    @State private var isSyncing = false
    @State private var syncError: String?
    @State private var seasonId: String?

    private var selectedSeasonId: String {
        seasonId ?? seasonStore.current?.id ?? Season.allId
    }

    private var seasonBinding: Binding<String> {
        Binding(get: { selectedSeasonId }, set: { seasonId = $0 })
    }

    /// Everyone who has ever played stays in the local store; this narrows to
    /// the season or the tournament being viewed, the same way the site's
    /// roster page does.
    private var visiblePlayers: [Player] {
        if selectedSeasonId == Season.allId { return players }
        if Tournament.tournamentId(fromSelection: selectedSeasonId) != nil {
            guard let tournament = tournamentStore.tournament(forSelection: selectedSeasonId) else { return [] }
            return players.filter { tournament.isOnRoster($0) }
        }
        return players.filter { $0.isMember(of: selectedSeasonId) }
    }

    private var skaters: [Player] {
        visiblePlayers.filter { !$0.isGoalie }
    }

    private var goalies: [Player] {
        visiblePlayers.filter { $0.isGoalie }
    }

    var body: some View {
        rosterContent
            .navigationTitle("Roster")
            .navigationDestination(for: Player.self) { player in
                PlayerDetailView(player: player)
            }
    }

    // MARK: - Roster Content

    private var rosterContent: some View {
        List {
            if isSyncing {
                Section {
                    HStack {
                        ProgressView()
                        Text("Syncing roster...")
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

            Section {
                SeasonPicker(seasonId: seasonBinding)
            }

            Section("Goalies") {
                ForEach(goalies) { player in
                    NavigationLink(value: player) {
                        PlayerRow(player: player)
                    }
                }
            }

            Section("Skaters") {
                ForEach(skaters) { player in
                    NavigationLink(value: player) {
                        PlayerRow(player: player)
                    }
                }
            }
        }
        .toolbar {
            if authManager.canEditRoster {
                Button {
                    showingAddPlayer = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddPlayer) {
            NavigationStack {
                PlayerFormView(mode: .add)
            }
        }
        .task {
            await syncFromServer()
        }
        .refreshable {
            async let roster: () = syncFromServer()
            async let tournaments: () = tournamentStore.load()
            _ = await (roster, tournaments)
        }
    }

    // MARK: - Sync

    private func syncFromServer() async {
        isSyncing = true
        syncError = nil

        do {
            // Every season: past-season players are needed locally to hydrate
            // their old games, and the season picker filters the view.
            let serverRoster = try await APIClient.fetchRoster(season: .all)
            let serverIds = Set(serverRoster.map(\.playerId))

            for remote in serverRoster {
                if let local = players.first(where: { $0.playerId == remote.playerId }) {
                    // Update existing player — server is authoritative
                    local.name = remote.name
                    local.number = remote.number
                    local.position = remote.position
                    local.isGoalie = remote.playsGoalie
                    local.isActive = remote.isActive
                    local.isSubstitute = remote.isSubstitute ?? false
                    local.photoPath = remote.photo
                    local.seasonIds = remote.seasons
                } else {
                    // Create new player from server
                    let newPlayer = Player(
                        name: remote.name,
                        number: remote.number,
                        position: remote.position,
                        isGoalie: remote.playsGoalie,
                        isActive: remote.isActive
                    )
                    newPlayer.playerId = remote.playerId
                    newPlayer.isSubstitute = remote.isSubstitute ?? false
                    newPlayer.photoPath = remote.photo
                    newPlayer.seasonIds = remote.seasons
                    // Assign to the team
                    let teamDescriptor = FetchDescriptor<Team>(
                        predicate: #Predicate { $0.name == "Frozen Flamingos" }
                    )
                    if let team = try? modelContext.fetch(teamDescriptor).first {
                        newPlayer.team = team
                    }
                    modelContext.insert(newPlayer)
                }
            }

            // Mark players not on the server as inactive
            for local in players {
                if !local.playerId.isEmpty && !serverIds.contains(local.playerId) {
                    local.isActive = false
                }
            }

            try modelContext.save()
        } catch {
            syncError = "Sync failed: \(error.localizedDescription)"
        }

        isSyncing = false
    }
}
