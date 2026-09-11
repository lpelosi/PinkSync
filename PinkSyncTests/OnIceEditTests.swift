import XCTest
import SwiftData
@testable import PinkSync

/// Fixing who was on the ice for a goal — when entering it, from the live
/// feed, and after the game — moves the +/- to the right skaters.
final class OnIceEditTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private var goalie: Player!
    private var a: Player!
    private var b: Player!
    private var c: Player!
    private var scorer: Player!
    private var game: Game!
    private var vm: LiveGameViewModel!

    override func setUpWithError() throws {
        container = try TestSupport.makeContainer()
        goalie = TestSupport.player("Goalie", number: 1, goalie: true, in: context)
        a = TestSupport.player("Alpha", number: 10, in: context)
        b = TestSupport.player("Bravo", number: 20, in: context)
        c = TestSupport.player("Charlie", number: 30, in: context)
        scorer = TestSupport.player("Scorer", number: 7, in: context)
        game = TestSupport.game(in: context)
        vm = TestSupport.liveVM(game: game, players: [goalie, a, b, c, scorer], goalie: goalie, context: context)
    }

    override func tearDown() {
        LiveSessionStore.delete(gameId: game.gameId)
    }

    private func pm(_ player: Player) -> Int {
        game.playerStats.first { $0.player?.persistentModelID == player.persistentModelID }?.plusMinus ?? 0
    }

    // MARK: Entry

    func testGoalEntryStartsFromWhoIsOnAndAcceptsACorrection() {
        vm.putPlayerOnIce(a)
        vm.putPlayerOnIce(b)
        vm.startGoalFlow()
        XCTAssertEqual(vm.pendingOnIce, [a.persistentModelID, b.persistentModelID], "prefilled with the current line")

        vm.goalFlowPickScorer(scorer)        // scored from "the bench" — the line was wrong
        vm.goalFlowPickPrimaryAssist(nil)
        vm.pendingOnIce.remove(b.persistentModelID)
        vm.pendingOnIce.insert(c.persistentModelID)
        vm.finalizeGoalWithTime()

        XCTAssertEqual(pm(a), 1)
        XCTAssertEqual(pm(c), 1)
        XCTAssertEqual(pm(scorer), 1, "the scorer is always on the ice")
        XCTAssertEqual(pm(b), 0)
        XCTAssertFalse(game.playerStats.contains { $0.player?.persistentModelID == goalie.persistentModelID })

        let ids = game.events.first { $0.type == "goal" }?.onIcePlayerIds ?? ""
        XCTAssertTrue(ids.contains(goalie.playerId), "goalie stays in the stored list, as live scoring records it")
        XCTAssertFalse(ids.contains(b.playerId))

        // "Also make this the line on the ice now" (on by default)
        XCTAssertTrue(vm.onIcePlayers.contains(c.persistentModelID))
        XCTAssertTrue(vm.onIcePlayers.contains(scorer.persistentModelID))
        XCTAssertFalse(vm.onIcePlayers.contains(b.persistentModelID))
        XCTAssertTrue(vm.onIcePlayers.contains(goalie.persistentModelID), "the goalie is never taken off")
    }

    func testGoalEntryCanLeaveTheLiveLineAlone() {
        vm.putPlayerOnIce(a)
        vm.startGoalFlow()
        vm.goalFlowPickScorer(a)
        vm.goalFlowPickPrimaryAssist(nil)
        vm.pendingOnIce.insert(c.persistentModelID)
        vm.pendingOnIceUpdatesLine = false
        vm.finalizeGoalWithTime()

        XCTAssertEqual(pm(c), 1)
        XCTAssertFalse(vm.onIcePlayers.contains(c.persistentModelID))
    }

    func testGoalAgainstEntryUsesTheConfirmedSkaters() {
        vm.putPlayerOnIce(a)
        let confirmed: Set<PersistentIdentifier> = [b.persistentModelID]
        vm.recordGoalAgainst(onIce: vm.onIceSnapshot(skaterIds: confirmed, goalie: vm.activeGoalie))

        XCTAssertEqual(pm(b), -1)
        XCTAssertEqual(pm(a), 0)
        XCTAssertEqual(vm.findOrCreateGoalieStats(for: goalie).goalsAgainst, 1)
    }

    // MARK: Live feed edit

    func testEditingWhoWasOnMovesPlusMinus() throws {
        vm.putPlayerOnIce(a)
        vm.putPlayerOnIce(b)
        vm.recordGoal(scorer: scorer, primaryAssist: nil, secondaryAssist: nil)
        XCTAssertEqual(pm(a), 1)
        XCTAssertEqual(pm(b), 1)

        let index = try XCTUnwrap(vm.events.firstIndex { $0.gameEvent?.type == "goal" })
        vm.replaceEvent(at: index, player: scorer, clockTime: "", isPowerPlay: false, isShortHanded: false,
                        assist1: nil, assist2: nil, penaltyType: nil, faceoffWon: nil, opponentNumber: "",
                        period: 1, onIce: [a, c, scorer])

        XCTAssertEqual(pm(a), 1)
        XCTAssertEqual(pm(b), 0, "taken off the goal")
        XCTAssertEqual(pm(c), 1, "added to the goal")
        XCTAssertEqual(pm(scorer), 1)

        // A second, unrelated edit keeps the corrected list.
        let again = try XCTUnwrap(vm.events.firstIndex { $0.gameEvent?.type == "goal" })
        vm.replaceEvent(at: again, player: scorer, clockTime: "03:00", isPowerPlay: false, isShortHanded: false,
                        assist1: nil, assist2: nil, penaltyType: nil, faceoffWon: nil, opponentNumber: "", period: 1)
        XCTAssertEqual(pm(b), 0)
        XCTAssertEqual(pm(c), 1)
    }

    func testEditingWhoWasOnForAGoalAgainst() throws {
        vm.putPlayerOnIce(a)
        vm.recordGoalAgainst()
        let index = try XCTUnwrap(vm.events.firstIndex { $0.gameEvent?.type == "goalAgainst" })
        vm.replaceEvent(at: index, player: nil, clockTime: "", isPowerPlay: false, isShortHanded: false,
                        assist1: nil, assist2: nil, penaltyType: nil, faceoffWon: nil, opponentNumber: "",
                        period: 1, onIce: [b])
        XCTAssertEqual(pm(a), 0)
        XCTAssertEqual(pm(b), -1)
        XCTAssertEqual(vm.findOrCreateGoalieStats(for: goalie).goalsAgainst, 1, "still one goal against")
    }

    // MARK: Post-game editor

    func testPostGameOnIceChangeMovesPlusMinusAndKeepsTheGoalie() {
        vm.putPlayerOnIce(a)
        vm.recordGoalAgainst()
        XCTAssertEqual(pm(a), -1)
        let event = game.events.first { $0.type == "goalAgainst" }!
        let goalieIds = Set(game.goalieStats.compactMap { $0.player?.playerId })

        // The editor's save: reverse, change who was on, reapply.
        EventStatAdjuster.subtract(event, game: game)
        event.onIcePlayerIds = event.onIceIds(replacingSkatersWith: [b.playerId, c.playerId], goalieIds: goalieIds)
        EventStatAdjuster.add(event, game: game)

        XCTAssertEqual(pm(a), 0)
        XCTAssertEqual(pm(b), -1)
        XCTAssertEqual(pm(c), -1)
        XCTAssertTrue(event.onIcePlayerIds.contains(goalie.playerId))
        XCTAssertFalse(event.onIcePlayerIds.contains(a.playerId))
        XCTAssertEqual(vm.findOrCreateGoalieStats(for: goalie).goalsAgainst, 1)
    }

    func testOnIceIdsHelperDedupesAndDropsBlanks() {
        let event = GameEvent(type: "goal", period: 1)
        event.onIcePlayerIds = "G1,S1,S2"
        XCTAssertEqual(event.onIceIds(replacingSkatersWith: ["S3", "S3", ""], goalieIds: ["G1"]), "S3,G1")
    }
}
