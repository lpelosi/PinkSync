import Foundation
import SwiftData
import XCTest
@testable import PinkSync

/// In-memory SwiftData plus the few fixtures the live-game tests share.
enum TestSupport {
    static func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Team.self,
            Player.self,
            Game.self,
            GamePlayerStats.self,
            GameGoalieStats.self,
            ShootoutRound.self,
            OpponentTeam.self,
            GameEvent.self,
            PlayerShift.self,
            configurations: config
        )
    }

    static func player(_ name: String, number: Int, goalie: Bool = false, in context: ModelContext) -> Player {
        let player = Player(name: name, number: number, position: goalie ? "Goalie" : "Forward", isGoalie: goalie)
        player.playerId = UUID().uuidString.uppercased()
        context.insert(player)
        return player
    }

    static func game(date: Date = Date(), opponent: String = "Warriors", in context: ModelContext) -> Game {
        let game = Game(date: date, opponent: opponent, location: "Ice Den")
        context.insert(game)
        return game
    }

    static func day(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: "\(iso)T12:00:00Z")!
    }

    /// A live view model with everyone checked in and network publishing off.
    static func liveVM(game: Game, players: [Player], goalie: Player?, context: ModelContext) -> LiveGameViewModel {
        // Players and games in the app are saved long before a game starts.
        // Save here too: SwiftData swaps temporary ids for permanent ones on
        // the first save, which would orphan ids the view model holds.
        try? context.save()
        game.startingGoalie = goalie
        let vm = LiveGameViewModel(game: game, modelContext: context)
        vm.publishesLiveScore = false
        vm.availablePlayers = players
        vm.checkedInPlayers = players
        vm.initializeStatsForCheckedInPlayers()
        return vm
    }
}
