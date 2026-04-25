import SwiftUI
import SwiftData
import LocalAuthentication

struct RosterView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Player.number) private var players: [Player]

    @State private var isUnlocked = false
    @State private var authError: String?
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
        Group {
            if isUnlocked {
                rosterContent
            } else {
                lockScreen
            }
        }
        .navigationTitle("Roster")
        .navigationDestination(for: Player.self) { player in
            PlayerDetailView(player: player)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                isUnlocked = false
            }
        }
    }

    // MARK: - Lock Screen

    private var lockScreen: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lock.shield")
                .font(.system(size: 64))
                .foregroundStyle(AppTheme.pink)

            Text("Roster Access")
                .font(.title2.bold())

            Text("Authenticate to manage the roster")
                .foregroundStyle(.secondary)
                .font(.subheadline)

            Button {
                authenticate()
            } label: {
                Label("Unlock", systemImage: "faceid")
                    .font(.headline)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.pink)

            if let authError {
                Text(authError)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            Spacer()
        }
        .padding()
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
            Button {
                showingAddPlayer = true
            } label: {
                Image(systemName: "plus")
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

    // MARK: - Authentication

    private func authenticate() {
        let context = LAContext()
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Authenticate to manage the roster"
            ) { success, authenticationError in
                DispatchQueue.main.async {
                    if success {
                        isUnlocked = true
                        authError = nil
                    } else {
                        authError = authenticationError?.localizedDescription
                    }
                }
            }
        } else {
            authError = error?.localizedDescription ?? "Authentication not available"
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
