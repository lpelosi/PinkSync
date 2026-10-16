import XCTest
import SwiftData
@testable import PinkSync

/// Beer league: a per-game "was drinking" flag on each skater and goalie
/// line. It must survive a send (it is part of the stats signature, so Edit
/// Stats marks the game as locally edited) and it must follow the player's
/// role in the live game.
final class DrinkingFlagTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private var goalie: Player!
    private var skater: Player!
    private var game: Game!

    override func setUpWithError() throws {
        container = try TestSupport.makeContainer()
        goalie = TestSupport.player("Goalie", number: 1, goalie: true, in: context)
        skater = TestSupport.player("Skater", number: 10, in: context)
        game = TestSupport.game(in: context)
    }

    override func tearDown() {
        LiveSessionStore.delete(gameId: game.gameId)
    }

    func testFlagDefaultsOffAndChangesSignature() throws {
        let line = GamePlayerStats()
        line.player = skater
        line.game = game
        context.insert(line)
        try context.save()

        XCTAssertFalse(line.wasDrinking)
        let sober = game.statsSignature
        line.wasDrinking = true
        XCTAssertNotEqual(game.statsSignature, sober, "Edit Stats relies on the signature to mark a local edit")
    }

    func testGoalieLineCarriesItsOwnFlag() throws {
        let line = GameGoalieStats()
        line.player = goalie
        line.game = game
        context.insert(line)
        try context.save()

        let sober = game.statsSignature
        line.wasDrinking = true
        XCTAssertNotEqual(game.statsSignature, sober)
    }

    func testLiveToggleFollowsRole() throws {
        let vm = TestSupport.liveVM(game: game, players: [goalie, skater], goalie: goalie, context: context)

        XCTAssertFalse(vm.isDrinking(skater))
        vm.setDrinking(skater, true)
        XCTAssertTrue(vm.isDrinking(skater))
        XCTAssertTrue(game.playerStats.first { $0.player?.persistentModelID == skater.persistentModelID }?.wasDrinking ?? false)

        vm.setDrinking(goalie, true)
        XCTAssertTrue(vm.isDrinking(goalie))
        XCTAssertTrue(game.goalieStats.first { $0.player?.persistentModelID == goalie.persistentModelID }?.wasDrinking ?? false)
        XCTAssertFalse(game.playerStats.contains { $0.player?.persistentModelID == goalie.persistentModelID },
                       "the goalie's flag lives on the goalie line, not a stray skater line")

        vm.setDrinking(skater, false)
        XCTAssertFalse(vm.isDrinking(skater))
        XCTAssertTrue(game.hasLocalEdits)
    }
}

extension DrinkingFlagTests {
    func testGamesDrinkingTotalsPerRole() throws {
        let other = TestSupport.game(opponent: "Wolves", in: context)
        let third = TestSupport.game(opponent: "Otterhawks", in: context)

        let sober = GamePlayerStats(goals: 1)
        sober.player = skater; sober.game = game
        let tipsy = GamePlayerStats()
        tipsy.player = skater; tipsy.game = other
        tipsy.wasDrinking = true
        let inGoal = GameGoalieStats()
        inGoal.player = skater; inGoal.game = third
        inGoal.wasDrinking = true
        for line in [sober, tipsy] { context.insert(line) }
        context.insert(inGoal)
        try context.save()

        let totals = skater.allTime
        XCTAssertEqual(totals.skaterGamesDrinking, 1)
        XCTAssertEqual(totals.goalieGamesDrinking, 1)
        XCTAssertEqual(totals.gamesDrinking, 2)
        XCTAssertEqual(totals.gamesPlayed, 3, "a sober game still counts as played")
    }
}
