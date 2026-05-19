import SwiftUI
import SwiftData

@main
struct PinkSyncApp: App {
    @State private var container: ModelContainer?
    @State private var authManager = AuthManager()
    @State private var syncManager: SyncManager?
    @State private var containerError: String?
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if let containerError {
                    ErrorView(message: containerError)
                } else if let container, let syncManager {
                    if authManager.isLoading {
                        LaunchView()
                    } else if authManager.isAuthenticated {
                        MainTabView()
                            .modelContainer(container)
                            .environment(authManager)
                            .environment(syncManager)
                    } else {
                        LoginView()
                            .environment(authManager)
                    }
                } else {
                    LaunchView()
                        .task {
                            do {
                                let c = try ModelContainer(for:
                                    Team.self,
                                    Player.self,
                                    Game.self,
                                    GamePlayerStats.self,
                                    GameGoalieStats.self,
                                    ShootoutRound.self,
                                    OpponentTeam.self,
                                    GameEvent.self,
                                    PlayerShift.self
                                )
                                APIClient.authManager = authManager
                                container = c
                                syncManager = SyncManager(container: c)
                            } catch {
                                containerError = error.localizedDescription
                            }
                        }
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active, let syncManager {
                    Task { await syncManager.retryNow() }
                }
            }
        }
    }
}

private struct LaunchView: View {
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                Image("TeamLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 120)
                Text("Frozen Flamingos")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(AppTheme.pink)
                ProgressView()
                    .tint(AppTheme.pink)
            }
        }
    }
}

private struct ErrorView: View {
    let message: String

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.red)
                Text("Unable to Load Data")
                    .font(.title2.bold())
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
    }
}
