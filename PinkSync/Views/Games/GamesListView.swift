import SwiftUI
import SwiftData

struct GamesListView: View {
    @Query(sort: \Game.date, order: .reverse) private var games: [Game]
    @Environment(\.modelContext) private var modelContext
    @State private var showingAddGame = false
    @State private var gameToDelete: Game?

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
                    Text("2026 Season")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            // Games
            if games.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "sportscourt")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("No Games")
                            .font(.headline)
                        Text("Tap + to add a game")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                    .listRowBackground(Color.clear)
                }
            } else {
                Section("Games") {
                    ForEach(games) { game in
                        NavigationLink(value: game) {
                            gameRow(game)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if !game.isSynced {
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
        .toolbar {
            Button {
                showingAddGame = true
            } label: {
                Image(systemName: "plus")
            }
        }
        .sheet(isPresented: $showingAddGame) {
            NavigationStack {
                GameFormView()
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
                    modelContext.delete(game)
                    gameToDelete = nil
                }
            }
        } message: {
            if let game = gameToDelete {
                Text("Are you sure you want to delete the game vs \(game.opponent) on \(game.displayDate)? This cannot be undone.")
            }
        }
    }

    private func gameRow(_ game: Game) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("vs \(game.opponent)")
                    .font(.headline)
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

            if game.isSynced {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            }
        }
    }


}
