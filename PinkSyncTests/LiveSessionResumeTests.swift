import XCTest
import SwiftData
@testable import PinkSync

/// Leaving the live screen, a crash, or ending too early must never lose the
/// scorekeeper's ability to fix things.
final class LiveSessionResumeTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private var goalie: Player!
    private var skater: Player!
    private var game: Game!

    override func setUpWithError() throws {
        container = try TestSupport.makeContainer()
        goalie = TestSupport.player("Goalie", number: 1, goalie: true, in: context)
        skater = TestSupport.player("Skater", number: 7, in: context)
        game = TestSupport.game(in: context)
    }

    override func tearDown() {
        LiveSessionStore.delete(gameId: game.gameId)
    }

    private func resumed() throws -> LiveGameViewModel {
        try XCTUnwrap(LiveGameViewModel.resume(
            game: game, modelContext: context, lookup: [goalie, skater], eligible: [goalie, skater],
            publishesLiveScore: false
        ))
    }

    func testResumeRebuildsStateAndFeed() throws {
        let vm = TestSupport.liveVM(game: game, players: [goalie, skater], goalie: goalie, context: context)
        vm.setupClock(minutes: 15)
        vm.setClockTime(minutes: 9, seconds: 30)
        vm.recordGoal(scorer: skater, primaryAssist: nil, secondaryAssist: nil, clockTime: "10:00")
        vm.recordShot(player: skater)
        vm.recordPenalty(player: skater, type: .minor)
        vm.endPeriod()
        XCTAssertTrue(LiveSessionStore.exists(gameId: game.gameId))

        let back = try resumed()
        XCTAssertEqual(back.currentPeriod, 2)
        XCTAssertEqual(back.clockSeconds, 15 * 60)
        XCTAssertTrue(back.isClockSetUp)
        XCTAssertEqual(back.checkedInPlayers.count, 2)
        XCTAssertEqual(back.activeGoalie?.persistentModelID, goalie.persistentModelID)
        XCTAssertTrue(back.onIcePlayers.contains(goalie.persistentModelID))

        let plays = back.events.filter { $0.gameEvent != nil }
        XCTAssertEqual(plays.count, 3, "goal, shot, penalty")
        XCTAssertEqual(plays.map { $0.gameEvent!.type }, ["goal", "shot", "penalty"], "in the order they were recorded")
        XCTAssertTrue(back.events.contains { $0.kind == .transition && $0.goBackLabel == "1st Period" })
        XCTAssertEqual(back.events.last?.description, "— Resumed —")
    }

    func testRebuiltUndoReversesAGoal() throws {
        let vm = TestSupport.liveVM(game: game, players: [goalie, skater], goalie: goalie, context: context)
        vm.recordGoal(scorer: skater, primaryAssist: nil, secondaryAssist: nil)
        vm.recordShot(player: skater)
        XCTAssertEqual(game.goalsFor, 1)

        let back = try resumed()
        let goalIndex = try XCTUnwrap(back.events.firstIndex { $0.gameEvent?.type == "goal" })
        back.deleteEvent(at: goalIndex)

        XCTAssertEqual(game.goalsFor, 0)
        XCTAssertEqual(back.findOrCreatePlayerStats(for: skater).goals, 0)
        XCTAssertEqual(back.findOrCreatePlayerStats(for: skater).shots, 1, "the shot is untouched")
        XCTAssertFalse(game.events.contains { $0.type == "goal" })
    }

    func testResumedTransitionCanStillGoBack() throws {
        let vm = TestSupport.liveVM(game: game, players: [goalie, skater], goalie: goalie, context: context)
        vm.setupClock(minutes: 15)
        vm.setClockTime(minutes: 1, seconds: 0)
        vm.endPeriod()

        let back = try resumed()
        // The "Resumed" note sits last but must not hide Go Back or Undo.
        XCTAssertEqual(back.events.last?.kind, .note)
        XCTAssertTrue(back.canGoBack)
        XCTAssertEqual(back.goBackLabel, "1st Period")
        XCTAssertEqual(back.lastUndoableEvent?.kind, .transition)
        back.goBack()
        XCTAssertEqual(back.currentPeriod, 1)
        XCTAssertEqual(back.clockSeconds, 60)
        XCTAssertEqual(back.events.last?.description, "— Resumed —", "the note stays, only the transition is undone")
    }

    func testReopenAfterEndClearsWhatEndDerived() throws {
        let vm = TestSupport.liveVM(game: game, players: [goalie, skater], goalie: goalie, context: context)
        vm.recordGoal(scorer: skater, primaryAssist: nil, secondaryAssist: nil)
        vm.computeResult()
        XCTAssertEqual(game.result, "W")
        XCTAssertTrue(game.isComplete)
        XCTAssertEqual(vm.findOrCreatePlayerStats(for: skater).gameWinningGoals, 1)
        XCTAssertEqual(vm.findOrCreateGoalieStats(for: goalie).result, "W")

        let back = try resumed()
        back.reopenAfterEnd()
        XCTAssertNotNil(back.lastUndoableEvent, "Undo still reaches the last play after reopening")
        XCTAssertFalse(game.isComplete)
        XCTAssertEqual(game.result, "")
        XCTAssertEqual(back.findOrCreatePlayerStats(for: skater).gameWinningGoals, 0)
        XCTAssertEqual(back.findOrCreateGoalieStats(for: goalie).result, "")

        back.recordGoalAgainst()
        back.recordGoalAgainst()
        back.computeResult()
        XCTAssertEqual(game.result, "L")
    }

    func testEveryPlayShowsUpEvenIfTheSavedFeedMissedIt() throws {
        let vm = TestSupport.liveVM(game: game, players: [goalie, skater], goalie: goalie, context: context)
        vm.recordShot(player: skater)
        // Simulate a play that reached the store but not the saved feed.
        let stray = GameEvent(type: "hit", period: 1, playerId: skater.playerId, playerName: skater.name, playerNumber: skater.number)
        stray.game = game
        context.insert(stray)
        try context.save()

        let back = try resumed()
        XCTAssertEqual(back.events.filter { $0.gameEvent != nil }.count, 2)
        XCTAssertTrue(back.events.contains { $0.gameEvent?.type == "hit" })
    }
}
