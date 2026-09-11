import XCTest
import SwiftData
@testable import PinkSync

/// +/- belongs to the skaters on the ice when the goal was scored, and stays
/// with them however, and whenever, the goal is corrected.
final class PlusMinusTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private var goalie: Player!
    private var onForGoal: Player!
    private var onLater: Player!
    private var scorer: Player!
    private var game: Game!
    private var vm: LiveGameViewModel!

    override func setUpWithError() throws {
        container = try TestSupport.makeContainer()
        goalie = TestSupport.player("Goalie", number: 1, goalie: true, in: context)
        onForGoal = TestSupport.player("On For Goal", number: 10, in: context)
        onLater = TestSupport.player("On Later", number: 20, in: context)
        scorer = TestSupport.player("Scorer", number: 7, in: context)
        game = TestSupport.game(in: context)
        vm = TestSupport.liveVM(game: game, players: [goalie, onForGoal, onLater, scorer], goalie: goalie, context: context)
    }

    override func tearDown() {
        LiveSessionStore.delete(gameId: game.gameId)
    }

    private func pm(_ player: Player) -> Int {
        game.playerStats.first { $0.player?.persistentModelID == player.persistentModelID }?.plusMinus ?? 0
    }

    private func lineChange() {
        vm.takePlayerOffIce(onForGoal)
        vm.takePlayerOffIce(scorer)
        vm.putPlayerOnIce(onLater)
    }

    private func edit(_ type: String, isPowerPlay: Bool = false) throws {
        let index = try XCTUnwrap(vm.events.firstIndex { $0.gameEvent?.type == type })
        vm.replaceEvent(at: index, player: type == "goal" ? scorer : nil, clockTime: "04:00",
                        isPowerPlay: isPowerPlay, isShortHanded: false, assist1: nil, assist2: nil,
                        penaltyType: nil, faceoffWon: nil, opponentNumber: "", period: 1)
    }

    // MARK: Live edits

    func testEditingAGoalLaterKeepsPlusMinusWithWhoWasOn() throws {
        vm.putPlayerOnIce(onForGoal)
        vm.putPlayerOnIce(scorer)
        vm.recordGoal(scorer: scorer, primaryAssist: nil, secondaryAssist: nil)
        XCTAssertEqual(pm(onForGoal), 1)
        XCTAssertEqual(pm(scorer), 1)

        lineChange()
        try edit("goal")

        XCTAssertEqual(pm(onForGoal), 1, "still credited after the line change")
        XCTAssertEqual(pm(scorer), 1)
        XCTAssertEqual(pm(onLater), 0, "was on the bench for the goal")
        XCTAssertFalse(game.playerStats.contains { $0.player?.persistentModelID == goalie.persistentModelID })
        let ids = try XCTUnwrap(game.events.first { $0.type == "goal" }?.onIcePlayerIds)
        XCTAssertTrue(ids.contains(onForGoal.playerId))
        XCTAssertFalse(ids.contains(onLater.playerId), "the edited goal keeps its original on-ice list")
    }

    func testEditingAGoalAgainstLaterKeepsPlusMinusWithWhoWasOn() throws {
        vm.putPlayerOnIce(onForGoal)
        vm.recordGoalAgainst()
        XCTAssertEqual(pm(onForGoal), -1)

        lineChange()
        try edit("goalAgainst")

        XCTAssertEqual(pm(onForGoal), -1)
        XCTAssertEqual(pm(onLater), 0)
    }

    func testMarkingAGoalPowerPlayRemovesPlusMinusAndBack() throws {
        vm.putPlayerOnIce(onForGoal)
        vm.recordGoal(scorer: scorer, primaryAssist: nil, secondaryAssist: nil)
        lineChange()

        try edit("goal", isPowerPlay: true)
        XCTAssertEqual(pm(onForGoal), 0, "power-play goals carry no +/-")

        try edit("goal", isPowerPlay: false)
        XCTAssertEqual(pm(onForGoal), 1, "back to even strength, back to the original skaters")
        XCTAssertEqual(pm(onLater), 0)
    }

    // MARK: Post-game editor

    func testPostGameDeleteReversesPlusMinus() {
        vm.putPlayerOnIce(onForGoal)
        vm.recordGoalAgainst()
        XCTAssertEqual(pm(onForGoal), -1)

        let event = game.events.first { $0.type == "goalAgainst" }!
        EventStatAdjuster.subtract(event, game: game)
        XCTAssertEqual(pm(onForGoal), 0)
        XCTAssertEqual(vm.findOrCreateGoalieStats(for: goalie).goalsAgainst, 0)
    }

    func testPostGamePowerPlayToggleUsesTheStoredSkaters() {
        vm.putPlayerOnIce(onForGoal)
        vm.recordGoal(scorer: scorer, primaryAssist: nil, secondaryAssist: nil)
        lineChange()
        let event = game.events.first { $0.type == "goal" }!

        // The editor's save: reverse, change, reapply.
        EventStatAdjuster.subtract(event, game: game)
        event.isPowerPlay = true
        EventStatAdjuster.add(event, game: game)
        XCTAssertEqual(pm(onForGoal), 0)
        XCTAssertEqual(pm(onLater), 0)

        EventStatAdjuster.subtract(event, game: game)
        event.isPowerPlay = false
        EventStatAdjuster.add(event, game: game)
        XCTAssertEqual(pm(onForGoal), 1)
    }

    func testPostGameScorerChangeCreditsTheNewScorer() {
        vm.recordGoal(scorer: scorer, primaryAssist: nil, secondaryAssist: nil)
        let event = game.events.first { $0.type == "goal" }!

        EventStatAdjuster.subtract(event, game: game)
        event.playerId = onLater.playerId
        event.playerName = onLater.name
        event.playerNumber = onLater.number
        EventStatAdjuster.add(event, game: game)

        XCTAssertEqual(vm.findOrCreatePlayerStats(for: scorer).goals, 0)
        XCTAssertEqual(vm.findOrCreatePlayerStats(for: onLater).goals, 1)
    }

    func testResumedDeleteStillReversesPlusMinusOnce() throws {
        vm.putPlayerOnIce(onForGoal)
        vm.recordGoal(scorer: scorer, primaryAssist: nil, secondaryAssist: nil)
        XCTAssertEqual(pm(onForGoal), 1)

        let back = try XCTUnwrap(LiveGameViewModel.resume(
            game: game, modelContext: context, lookup: [goalie, onForGoal, onLater, scorer],
            eligible: [goalie, onForGoal, onLater, scorer], publishesLiveScore: false
        ))
        let index = try XCTUnwrap(back.events.firstIndex { $0.gameEvent?.type == "goal" })
        back.deleteEvent(at: index)
        XCTAssertEqual(pm(onForGoal), 0, "reversed exactly once")
        XCTAssertEqual(game.goalsFor, 0)
    }
}
