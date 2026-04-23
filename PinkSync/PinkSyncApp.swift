import SwiftUI
import SwiftData

@main
struct PinkSyncApp: App {
    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
        .modelContainer(for: [
            Team.self,
            Player.self,
            Game.self,
            GamePlayerStats.self,
            GameGoalieStats.self,
            ShootoutRound.self,
            OpponentTeam.self
        ])
    }
}
