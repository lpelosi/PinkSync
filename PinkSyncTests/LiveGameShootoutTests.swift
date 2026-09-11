import XCTest
import SwiftData
@testable import PinkSync

final class LiveGameShootoutTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private var goalie: Player!
    private var shooter: Player!
    private var game: Game!
    private var vm: LiveGameViewModel!

    override func setUpWithError() throws {
        container = try TestSupport.makeContainer()
        goalie = TestSupport.player("Goalie", number: 1, goalie: true, in: context)
        shooter = TestSupport.player("Shooter", number: 7, in: context)
        game = TestSupport.game(in: context)
        game.goalsFor = 2
        game.goalsAgainst = 2
        vm = TestSupport.liveVM(game: game, players: [goalie, shooter], goalie: goalie, context: context)
        vm.goToOvertime()
        vm.goToShootout()
    }

    override func tearDown() {
        LiveSessionStore.delete(gameId: game.gameId)
    }

    func testAttemptsDriveScoreTurnAndRound() {
        XCTAssertTrue(vm.isOurShootoutTurn)
        XCTAssertEqual(vm.shootoutRoundNumber, 1)

        vm.recordShootoutAttempt(player: shooter, isGoal: true)
        XCTAssertEqual(game.goalsFor, 3)
        XCTAssertFalse(vm.isOurShootoutTurn)
        XCTAssertEqual(vm.shootoutRoundNumber, 1, "their shot of round 1 is still to come")

        vm.recordShootoutAttemptAgainst(isGoal: false)
        XCTAssertEqual(game.goalsAgainst, 2)
        XCTAssertTrue(vm.isOurShootoutTurn)
        XCTAssertEqual(vm.shootoutRoundNumber, 2)
        XCTAssertEqual(vm.findOrCreateGoalieStats(for: goalie).shootoutRounds.count, 1)
        XCTAssertEqual(vm.events.last?.description, "SO Rd 1: #1 Goalie — SAVE!")
    }

    func testUndoRestoresTurnAndRemovesTheGoalieRound() {
        vm.recordShootoutAttempt(player: shooter, isGoal: false)
        vm.recordShootoutAttemptAgainst(isGoal: true)
        XCTAssertEqual(game.goalsAgainst, 3)

        vm.undoLast()
        XCTAssertEqual(vm.shootoutAttempts.count, 1)
        XCTAssertEqual(game.goalsAgainst, 2)
        XCTAssertFalse(vm.isOurShootoutTurn, "back to their shot")
        XCTAssertEqual(vm.shootoutRoundNumber, 1)
        XCTAssertTrue(vm.findOrCreateGoalieStats(for: goalie).shootoutRounds.isEmpty)
    }

    func testEditAndRemoveRecomputeEverything() throws {
        vm.recordShootoutAttempt(player: shooter, isGoal: true)
        let id = try XCTUnwrap(vm.shootoutAttempts.first?.id)

        vm.updateShootoutAttempt(id: id, player: shooter, isGoal: false)
        XCTAssertEqual(game.goalsFor, 2)
        XCTAssertEqual(vm.events.last?.description, "SO Rd 1: #7 Shooter — Miss")

        vm.removeShootoutAttempt(id: id, removeEvent: true)
        XCTAssertTrue(vm.shootoutAttempts.isEmpty)
        XCTAssertTrue(vm.isOurShootoutTurn)
        XCTAssertFalse(vm.events.contains { $0.shootoutAttemptId == id })
    }

    func testOpponentMayShootFirst() {
        vm.recordShootoutAttemptAgainst(isGoal: true)
        XCTAssertEqual(game.goalsAgainst, 3)
        XCTAssertTrue(vm.isOurShootoutTurn)
        XCTAssertEqual(vm.shootoutRoundNumber, 1)

        vm.recordShootoutAttempt(player: shooter, isGoal: true)
        XCTAssertEqual(vm.shootoutRoundNumber, 2)
    }

    func testGoingBackFromShootoutRestoresTheScore() {
        XCTAssertTrue(vm.canGoBack)
        XCTAssertEqual(vm.goBackLabel, "Overtime")
        vm.goBack()
        XCTAssertEqual(vm.period, .overtime)
        XCTAssertEqual(game.goalsFor, 2)
        XCTAssertEqual(game.goalsAgainst, 2)
    }

    func testShootoutResultAtGameEnd() {
        vm.recordShootoutAttempt(player: shooter, isGoal: true)
        vm.recordShootoutAttemptAgainst(isGoal: false)
        vm.computeResult()
        XCTAssertEqual(game.result, GameResult.shootoutWin.rawValue)
        XCTAssertEqual(vm.findOrCreateGoalieStats(for: goalie).result, GameResult.shootoutWin.rawValue)
        XCTAssertTrue(game.isComplete)
    }
}
