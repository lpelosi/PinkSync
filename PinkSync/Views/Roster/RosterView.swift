import SwiftUI
import SwiftData

struct RosterView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    @Query(sort: \Player.number) private var players: [Player]

    @State private var showingAddPlayer = false
    @State private var isSyncing = false
    @State private var syncError: String?

    private var skaters: [Player] {
        players.filter { !$0.isGoalie }
    }

    private var goalies: [Player] {
        players.filter { $0.isGoalie }
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
            await syncFromServer()
        }
    }

    // MARK: - Sync

    private func syncFromServer() async {
        isSyncing = true
        syncError = nil

        do {
            let serverRoster = try await APIClient.fetchRoster()
            let serverIds = Set(serverRoster.map(\.playerId))

            for remote in serverRoster {
                if let local = players.first(where: { $0.playerId == remote.playerId }) {
                    // Update existing player
                    local.name = remote.name
                    local.number = remote.number
                    local.position = remote.position
                    local.isGoalie = remote.isGoalie
                    local.isActive = remote.isActive
                    local.photoPath = remote.photo
                } else {
                    // Create new player from server
                    let newPlayer = Player(
                        name: remote.name,
                        number: remote.number,
                        position: remote.position,
                        isGoalie: remote.isGoalie,
                        isActive: remote.isActive
                    )
                    newPlayer.playerId = remote.playerId
                    newPlayer.photoPath = remote.photo
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
