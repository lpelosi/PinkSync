import XCTest
import SwiftData
@testable import PinkSync

final class LiveGameTransitionTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private var goalie: Player!
    private var skater: Player!
    private var game: Game!
    private var vm: LiveGameViewModel!

    override func setUpWithError() throws {
        container = try TestSupport.makeContainer()
        goalie = TestSupport.player("Goalie", number: 1, goalie: true, in: context)
        skater = TestSupport.player("Skater", number: 7, in: context)
        game = TestSupport.game(in: context)
        vm = TestSupport.liveVM(game: game, players: [goalie, skater], goalie: goalie, context: context)
        vm.setupClock(minutes: 15)
    }

    override func tearDown() {
        LiveSessionStore.delete(gameId: game.gameId)
    }

    func testGoBackRestoresPeriodClockAndPenalties() {
        vm.setClockTime(minutes: 3, seconds: 20)
        vm.recordPenalty(player: skater, type: .minor)
        XCTAssertEqual(vm.activePenalties.count, 1)

        vm.endPeriod()
        XCTAssertEqual(vm.currentPeriod, 2)
        XCTAssertEqual(vm.clockSeconds, 15 * 60)
        XCTAssertTrue(vm.activePenalties.isEmpty, "a 2:00 minor expires when 3:20 is skipped")
        XCTAssertTrue(vm.canGoBack)
        XCTAssertEqual(vm.goBackLabel, "1st Period")

        vm.goBack()
        XCTAssertEqual(vm.currentPeriod, 1)
        XCTAssertEqual(vm.clockSeconds, 200)
        XCTAssertEqual(vm.activePenalties.count, 1)
        XCTAssertFalse(vm.canGoBack)
        XCTAssertEqual(vm.events.count, 1, "only the penalty remains in the feed")
        XCTAssertEqual(vm.findOrCreatePlayerStats(for: skater).penaltyMinutes, 2, "the penalty itself is untouched")
    }

    func testGoBackIsHiddenOnceAPlayIsRecordedInTheNewPeriod() {
        vm.endPeriod()
        vm.recordShot(player: skater)
        XCTAssertFalse(vm.canGoBack)

        vm.undoLast()
        XCTAssertTrue(vm.canGoBack, "deleting that play brings the option back")
    }

    func testOvertimeAndSetPeriodAreUndoable() {
        vm.endPeriod()
        vm.endPeriod()
        XCTAssertEqual(vm.currentPeriod, 3)

        vm.goToOvertime()
        XCTAssertEqual(vm.period, .overtime)
        XCTAssertEqual(vm.clockSeconds, 5 * 60)
        vm.goBack()
        XCTAssertEqual(vm.period, .regulation)
        XCTAssertEqual(vm.currentPeriod, 3)

        vm.setPeriod(number: 1)
        XCTAssertEqual(vm.currentPeriod, 1)
        XCTAssertEqual(vm.goBackLabel, "3rd Period")
        vm.goBack()
        XCTAssertEqual(vm.currentPeriod, 3)
    }

    func testPlayRecordedAfterGoingBackLandsInTheRestoredPeriod() {
        vm.endPeriod()
        vm.goBack()
        vm.recordShot(player: skater)
        XCTAssertEqual(vm.events.last?.gameEvent?.period, 1)
    }
}
