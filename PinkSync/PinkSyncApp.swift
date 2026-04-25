import SwiftUI
import SwiftData
import os

private let launchStart = CFAbsoluteTimeGetCurrent()
private let logger = Logger(subsystem: "PinkSync", category: "Launch")

@main
struct PinkSyncApp: App {
    @State private var container: ModelContainer?

    var body: some Scene {
        WindowGroup {
            if let container {
                MainTabView()
                    .modelContainer(container)
                    .onAppear {
                        logger.info("⏱ MainTabView appeared: \(String(format: "%.0f", (CFAbsoluteTimeGetCurrent() - launchStart) * 1000))ms")
                    }
            } else {
                LaunchView()
                    .task {
                        let start = CFAbsoluteTimeGetCurrent()
                        let c = try! ModelContainer(for:
                            Team.self,
                            Player.self,
                            Game.self,
                            GamePlayerStats.self,
                            GameGoalieStats.self,
                            ShootoutRound.self,
                            OpponentTeam.self
                        )
                        logger.info("⏱ Container ready: \(String(format: "%.0f", (CFAbsoluteTimeGetCurrent() - start) * 1000))ms")
                        container = c
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
