import SwiftUI
import SwiftData

struct AdminView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    @Query(sort: \Game.date, order: .reverse) private var games: [Game]

    @State private var showDeleteAllConfirmation = false
    @State private var showDeleteSingleConfirmation = false
    @State private var gameToDelete: Game?

    @State private var isDeleting = false
    @State private var deleteResult: String?
    @State private var showDeleteResult = false

    @State private var showDeleteError = false
    @State private var deleteError: String?

    @State private var showUserManagement = false

    var body: some View {
        adminContent
            .navigationTitle("Admin")
    }

    // MARK: - Admin Content

    private var adminContent: some View {
        List {
            // Summary
            Section {
                HStack {
                    Text("Total Games")
                    Spacer()
                    Text("\(games.count)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                HStack {
                    Text("Synced to Website")
                    Spacer()
                    Text("\(games.filter(\.isSynced).count)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            } header: {
                Text("Game Data")
            }

            // Game list with swipe-to-delete
            if !games.isEmpty {
                Section {
                    ForEach(games) { game in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("vs \(game.opponent)")
                                    .font(.subheadline.bold())
                                Text(game.displayDate)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if game.isSynced {
                                Image(systemName: "cloud.fill")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.pink)
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                gameToDelete = game
                                showDeleteSingleConfirmation = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    Text("Games")
                } footer: {
                    Text("Swipe to delete individual games. Synced games will also be removed from the website.")
                }
            }

            // User Management
            Section {
                NavigationLink {
                    UserManagementView()
                } label: {
                    Label("Manage Users", systemImage: "person.badge.key")
                }
            } header: {
                Text("Users")
            }

            // Signed-In User
            if let user = authManager.currentUser {
                Section {
                    HStack {
                        Text("Signed in as")
                        Spacer()
                        Text(user.displayName)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Role")
                        Spacer()
                        Text(user.role.displayName)
                            .foregroundStyle(.secondary)
                    }
                    Button("Sign Out", role: .destructive) {
                        authManager.logout()
                    }
                } header: {
                    Text("Account")
                }
            }

            // Delete All
            Section {
                Button(role: .destructive) {
                    showDeleteAllConfirmation = true
                } label: {
                    HStack {
                        if isDeleting {
                            ProgressView()
                                .tint(.red)
                        } else {
                            Image(systemName: "trash")
                        }
                        Text("Delete All Games")
                    }
                }
                .disabled(games.isEmpty || isDeleting)
            } header: {
                Text("Actions")
            } footer: {
                Text("Deletes all games from the app and removes synced games from the website.")
            }
        }
        // Single game delete confirmation
        .alert("Delete Game?", isPresented: $showDeleteSingleConfirmation) {
            Button("Cancel", role: .cancel) { gameToDelete = nil }
            Button("Delete", role: .destructive) {
                if let game = gameToDelete {
                    Task { await deleteSingleGame(game) }
                }
                gameToDelete = nil
            }
        } message: {
            if let game = gameToDelete {
                Text("Delete vs \(game.opponent) (\(game.displayDate))?\(game.isSynced ? " This will also remove it from the website." : "")")
            }
        }
        // Delete All confirmation
        .alert("Delete All Games?", isPresented: $showDeleteAllConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete All", role: .destructive) {
                Task { await deleteAllGames() }
            }
        } message: {
            let syncedCount = games.filter(\.isSynced).count
            Text("This will delete all \(games.count) game(s) from the app\(syncedCount > 0 ? " and remove \(syncedCount) synced game(s) from the website" : "").")
        }
        // Result
        .alert("Done", isPresented: $showDeleteResult) {
            Button("OK") {}
        } message: {
            Text(deleteResult ?? "Games deleted.")
        }
        // Error
        .alert("Delete Error", isPresented: $showDeleteError) {
            Button("OK") {}
        } message: {
            Text(deleteError ?? "An error occurred.")
        }
    }

    // MARK: - Deletion

    private func deleteSingleGame(_ game: Game) async {
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

        // Delete locally
        modelContext.delete(game)
        try? modelContext.save()
    }

    private func deleteAllGames() async {
        isDeleting = true

        // Delete synced games from server
        let syncedGames = games.filter { $0.isSynced && !$0.gameId.isEmpty }
        var serverFails = 0

        for game in syncedGames {
            do {
                try await APIClient.deleteGameFromServer(gameId: game.gameId)
            } catch {
                serverFails += 1
            }
        }

        // Delete all locally regardless of server result
        for game in games {
            modelContext.delete(game)
        }
        try? modelContext.save()

        isDeleting = false

        if serverFails > 0 {
            deleteResult = "All games deleted locally. \(serverFails) of \(syncedGames.count) failed to delete from the website."
        } else if syncedGames.isEmpty {
            deleteResult = "All games deleted."
        } else {
            deleteResult = "All games deleted from the app and the website."
        }
        showDeleteResult = true
    }
}
