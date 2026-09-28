import XCTest
import SwiftData
@testable import PinkSync

/// Behaviour that depends on combining GitHub's June 7 "+/- fixes" commit
/// with the season / live-scoring work.
final class MergeRegressionTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUpWithError() throws {
        container = try TestSupport.makeContainer()
    }

    private func line(_ player: Player, in game: Game, goals: Int = 0, plusMinus: Int = 0) -> GamePlayerStats {
        let stats = GamePlayerStats(goals: goals, plusMinus: plusMinus)
        stats.player = player
        stats.game = game
        context.insert(stats)
        return stats
    }

    private func goalieLine(_ player: Player, in game: Game, sa: Int, ga: Int) -> GameGoalieStats {
        let stats = GameGoalieStats(shotsAgainst: sa, goalsAgainst: ga, result: "")
        stats.player = player
        stats.game = game
        context.insert(stats)
        return stats
    }

    // MARK: Plus/minus is applied once

    func testPostGameEditorAppliesPlusMinusExactlyOnce() throws {
        let goalie = TestSupport.player("Goalie", number: 1, goalie: true, in: context)
        let skater = TestSupport.player("Skater", number: 10, in: context)
        let game = TestSupport.game(in: context)
        _ = goalieLine(goalie, in: game, sa: 0, ga: 0)
        let skaterLine = line(skater, in: game)
        let event = GameEvent(type: "goalAgainst", period: 1, playerId: goalie.playerId)
        event.onIcePlayerIds = "\(skater.playerId),\(goalie.playerId)"
        event.game = game
        context.insert(event)
        try context.save()

        EventStatAdjuster.add(event, game: game)
        XCTAssertEqual(skaterLine.plusMinus, -1, "one adjustment, not the old and new code both")
        EventStatAdjuster.subtract(event, game: game)
        XCTAssertEqual(skaterLine.plusMinus, 0)
    }

    // MARK: Refresh never overwrites local fixes

    func testServerUpdatesOnlyReplaceGamesWithNothingNewerLocally() throws {
        let game = TestSupport.game(in: context)
        game.isSynced = true
        game.isComplete = true
        try context.save()
        XCTAssertTrue(game.acceptsServerUpdate)

        game.hasLocalEdits = true
        XCTAssertFalse(game.acceptsServerUpdate, "unsent edits")
        game.hasLocalEdits = false

        game.pendingSync = true
        XCTAssertFalse(game.acceptsServerUpdate, "failed send awaiting retry")
        game.pendingSync = false

        game.isComplete = false
        LiveSessionStore.save(LiveSessionState(
            gameId: game.gameId, savedAt: Date(), period: "REG", currentPeriod: 1, periodLengthMinutes: 15,
            clockSeconds: 0, isClockSetUp: false, activePenalties: [], checkedInPlayerIds: [], activeGoalieId: nil,
            onIcePlayerIds: [], playerTOI: [:], currentShiftSeconds: [:], shiftStartClockTime: [:], playerLines: [:],
            playerGamePosition: [:], playerGameRole: [:], shootoutAttempts: [], goalsBeforeShootoutFor: 0,
            goalsBeforeShootoutAgainst: 0, feed: []
        ))
        defer { LiveSessionStore.delete(gameId: game.gameId) }
        XCTAssertFalse(game.acceptsServerUpdate, "live scoring in progress")
    }

    func testLiveScoringAndReopeningMarkTheGameAsLocallyEdited() throws {
        let goalie = TestSupport.player("Goalie", number: 1, goalie: true, in: context)
        let skater = TestSupport.player("Skater", number: 10, in: context)
        let game = TestSupport.game(in: context)
        game.isSynced = true
        let vm = TestSupport.liveVM(game: game, players: [goalie, skater], goalie: goalie, context: context)
        defer { LiveSessionStore.delete(gameId: game.gameId) }
        game.hasLocalEdits = false

        vm.recordShot(player: skater)
        XCTAssertTrue(game.hasLocalEdits)

        game.hasLocalEdits = false
        vm.reopenAfterEnd()
        XCTAssertTrue(game.hasLocalEdits)
    }

    func testStatsSignatureNoticesAnyStatChange() throws {
        let goalie = TestSupport.player("Goalie", number: 1, goalie: true, in: context)
        let skater = TestSupport.player("Skater", number: 10, in: context)
        let game = TestSupport.game(in: context)
        let skaterLine = line(skater, in: game)
        let goalieStats = goalieLine(goalie, in: game, sa: 10, ga: 1)
        try context.save()

        let opened = game.statsSignature
        XCTAssertEqual(game.statsSignature, opened, "stable when nothing changes")
        skaterLine.hits += 1
        XCTAssertNotEqual(game.statsSignature, opened)
        skaterLine.hits -= 1
        goalieStats.result = "W"
        XCTAssertNotEqual(game.statsSignature, opened)
    }

    // MARK: Stats tab

    func testStatsTableShowsDualRolePlayersInBothTables() throws {
        let dual = TestSupport.player("Dual", number: 24, in: context)   // Forward who can play goal
        dual.isGoalie = true
        let skaterOnly = TestSupport.player("Skater", number: 10, in: context)
        let goalieOnly = TestSupport.player("Goalie", number: 1, goalie: true, in: context)
        let game = TestSupport.game(date: TestSupport.day("2026-09-10"), in: context)
        game.isComplete = true
        _ = line(dual, in: game, goals: 1)
        _ = line(skaterOnly, in: game, goals: 2)
        _ = goalieLine(goalieOnly, in: game, sa: 20, ga: 2)
        try context.save()

        let scope = StatScope(season: Season.defaults[1], type: nil, seasons: Season.defaults)
        let table = StatsTable(players: [dual, skaterOnly, goalieOnly], scope: scope, seasonId: "2026-fall", selectedGames: [])

        XCTAssertEqual(Set(table.skaters.map(\.player.name)), ["Dual", "Skater"])
        XCTAssertEqual(Set(table.goalies.map(\.player.name)), ["Dual", "Goalie"])
        let dualRow = try XCTUnwrap(table.skaters.first { $0.player.name == "Dual" })
        XCTAssertEqual(dualRow.totals.skaterGamesPlayed, 1)
        XCTAssertEqual(dualRow.totals.totalGoals, 1)
    }

    func testStatsTableNarrowsToPickedGamesWithinTheSeason() throws {
        let a = TestSupport.player("Alpha", number: 10, in: context)
        let b = TestSupport.player("Bravo", number: 20, in: context)
        let summer = TestSupport.game(date: TestSupport.day("2026-06-01"), in: context)
        let fall1 = TestSupport.game(date: TestSupport.day("2026-09-01"), in: context)
        let fall2 = TestSupport.game(date: TestSupport.day("2026-09-08"), in: context)
        _ = line(a, in: summer, goals: 5)
        _ = line(a, in: fall1, goals: 1)
        _ = line(b, in: fall2, goals: 2)
        try context.save()

        let fall = StatScope(season: Season.defaults[1], type: nil, seasons: Season.defaults)
        let whole = StatsTable(players: [a, b], scope: fall, seasonId: "2026-fall", selectedGames: [])
        XCTAssertEqual(whole.skaters.first { $0.player.name == "Alpha" }?.totals.totalGoals, 1, "summer goals excluded")

        let picked = StatsTable(players: [a, b], scope: fall, seasonId: "2026-fall", selectedGames: [fall2.persistentModelID])
        XCTAssertEqual(picked.skaters.map(\.player.name), ["Bravo"], "only players in the picked game")

        // A picked game outside the season contributes nothing.
        let outside = StatsTable(players: [a, b], scope: fall, seasonId: "2026-fall", selectedGames: [summer.persistentModelID])
        XCTAssertTrue(outside.skaters.isEmpty)
    }

    func testStatsTableRespectsSeasonRosterWhenNotPicking() throws {
        let member = TestSupport.player("Member", number: 10, in: context)
        member.seasonIds = ["2026-fall"]
        let former = TestSupport.player("Former", number: 20, in: context)
        former.seasonIds = ["2026-summer"]
        try context.save()

        let fall = StatScope(season: Season.defaults[1], type: nil, seasons: Season.defaults)
        let table = StatsTable(players: [member, former], scope: fall, seasonId: "2026-fall", selectedGames: [])
        XCTAssertEqual(table.skaters.map(\.player.name), ["Member"], "on the roster with no games yet still shows")

        let all = StatsTable(players: [member, former], scope: StatScope(season: nil, type: nil, seasons: Season.defaults),
                             seasonId: Season.allId, selectedGames: [])
        XCTAssertEqual(Set(all.skaters.map(\.player.name)), ["Member", "Former"])
    }
}
