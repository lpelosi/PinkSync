import XCTest
import SwiftData
@testable import PinkSync

/// The website's lower third shows the latest play. It has to follow what
/// the scorekeeper records, and come down when a play is taken back.
final class LivePlayTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private var goalie: Player!
    private var scorer: Player!
    private var helper: Player!
    private var game: Game!
    private var vm: LiveGameViewModel!

    override func setUpWithError() throws {
        container = try TestSupport.makeContainer()
        goalie = TestSupport.player("Goalie", number: 1, goalie: true, in: context)
        scorer = TestSupport.player("Scorer", number: 7, in: context)
        helper = TestSupport.player("Helper", number: 8, in: context)
        game = TestSupport.game(in: context)
        vm = TestSupport.liveVM(game: game, players: [goalie, scorer, helper], goalie: goalie, context: context)
    }

    override func tearDown() {
        LiveSessionStore.delete(gameId: game.gameId)
    }

    func testNothingToAnnounceBeforeAPlay() {
        XCTAssertNil(vm.lastLivePlay)
        XCTAssertNil(vm.liveScorePayload().lastPlay)
    }

    func testAGoalNamesTheScorerAndAssists() throws {
        vm.recordGoal(scorer: scorer, primaryAssist: helper, secondaryAssist: nil, isPowerPlay: true)

        let play = try XCTUnwrap(vm.liveScorePayload().lastPlay)
        XCTAssertEqual(play.type, "goal")
        XCTAssertEqual(play.playerId, scorer.playerId)
        XCTAssertEqual(play.playerName, "Scorer")
        XCTAssertEqual(play.playerNumber, 7)
        XCTAssertEqual(play.assists, [APIClient.LivePlay.Assist(name: "Helper", number: 8)])
        XCTAssertEqual(play.strength, "PP")
    }

    func testAShotAgainstIsASaveByTheGoalieInNet() throws {
        vm.recordShotAgainst()

        let play = try XCTUnwrap(vm.lastLivePlay)
        XCTAssertEqual(play.type, "save")
        XCTAssertEqual(play.playerId, goalie.playerId)
    }

    func testBlocksHitsAndPenaltiesAreAnnounced() {
        vm.recordBlock(player: helper)
        XCTAssertEqual(vm.lastLivePlay?.type, "block")

        vm.recordHit(player: scorer)
        XCTAssertEqual(vm.lastLivePlay?.type, "hit")
        XCTAssertEqual(vm.lastLivePlay?.playerId, scorer.playerId)

        vm.recordPenalty(player: helper, type: .minor)
        XCTAssertEqual(vm.lastLivePlay?.type, "penalty")
        XCTAssertEqual(vm.lastLivePlay?.note, PenaltyType.minor.rawValue)
    }

    func testAShotOnGoalIsAnnounced() {
        vm.recordShot(player: helper)

        XCTAssertEqual(vm.lastLivePlay?.type, "shot")
        XCTAssertEqual(vm.lastLivePlay?.playerId, helper.playerId)
    }

    func testFaceoffsAndGoalsAgainstAreNot() {
        vm.recordGoal(scorer: scorer, primaryAssist: nil, secondaryAssist: nil)
        let goal = vm.lastLivePlay

        vm.recordFaceoff(player: helper, won: true)
        vm.recordGoalAgainst()

        XCTAssertEqual(vm.lastLivePlay, goal, "the goal is still the latest play worth showing")
    }

    func testEveryPlayGetsItsOwnId() {
        vm.recordHit(player: scorer)
        let first = vm.lastLivePlay?.id
        vm.recordHit(player: scorer)

        XCTAssertNotNil(first)
        XCTAssertNotEqual(vm.lastLivePlay?.id, first)
    }

    func testUndoingThePlayTakesItDown() {
        vm.recordGoal(scorer: scorer, primaryAssist: nil, secondaryAssist: nil)
        vm.undoLast()

        XCTAssertNil(vm.lastLivePlay)
        XCTAssertNil(vm.liveScorePayload().lastPlay)
    }

    func testUndoingAnEarlierPlayLeavesTheLatestUp() throws {
        vm.recordHit(player: helper)
        vm.recordGoal(scorer: scorer, primaryAssist: nil, secondaryAssist: nil)

        let hitIndex = try XCTUnwrap(vm.events.firstIndex { $0.gameEvent?.type == "hit" })
        vm.deleteEvent(at: hitIndex)

        XCTAssertEqual(vm.lastLivePlay?.type, "goal")
    }

    func testCorrectingAnOldPlayIsNotAnnounced() throws {
        vm.recordHit(player: helper)
        vm.recordGoal(scorer: scorer, primaryAssist: nil, secondaryAssist: nil)
        let goal = vm.lastLivePlay

        let hitIndex = try XCTUnwrap(vm.events.firstIndex { $0.gameEvent?.type == "hit" })
        vm.replaceEvent(
            at: hitIndex, player: scorer, clockTime: "", isPowerPlay: false, isShortHanded: false,
            assist1: nil, assist2: nil, penaltyType: nil, faceoffWon: nil, opponentNumber: "", period: 1
        )

        XCTAssertEqual(vm.lastLivePlay, goal)
    }
}
