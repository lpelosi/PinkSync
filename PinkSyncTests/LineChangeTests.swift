import XCTest
import SwiftData
@testable import PinkSync

/// Lines are not fixed at puck drop. A skater can move up a line, or between
/// forward and defense, at any point, and nothing already recorded for them
/// may change because of it.
final class LineChangeTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private var goalie: Player!
    private var center: Player!
    private var winger: Player!
    private var defender: Player!
    private var game: Game!
    private var vm: LiveGameViewModel!

    override func setUpWithError() throws {
        container = try TestSupport.makeContainer()
        goalie = TestSupport.player("Goalie", number: 1, goalie: true, in: context)
        center = TestSupport.player("Center", number: 7, in: context)
        winger = TestSupport.player("Winger", number: 8, in: context)
        defender = TestSupport.player("Defender", number: 9, in: context)
        defender.position = "Defense"
        game = TestSupport.game(in: context)
        vm = TestSupport.liveVM(game: game, players: [goalie, center, winger, defender], goalie: goalie, context: context)
    }

    override func tearDown() {
        LiveSessionStore.delete(gameId: game.gameId)
    }

    private var lineChanges: [LiveEvent] {
        vm.events.filter { $0.emoji == "🔀" }
    }

    /// Record a play so the game counts as underway.
    private func dropThePuck() {
        vm.recordShot(player: center)
    }

    func testMovingUpALineKeepsTheShiftRunning() {
        let id = winger.persistentModelID
        vm.changeLine(of: winger, to: "F2")
        vm.sendLineOn("F2")
        dropThePuck()
        vm.playerTOI[id] = 40
        vm.currentShiftSeconds[id] = 40

        vm.changeLine(of: winger, to: "F1")

        XCTAssertEqual(vm.playerLines[id], "F1")
        XCTAssertTrue(vm.onIcePlayers.contains(id), "still on the ice")
        XCTAssertEqual(vm.currentShiftSeconds[id], 40, "the shift was not restarted")
        XCTAssertEqual(vm.playerTOI[id], 40)
        XCTAssertTrue(vm.findOrCreatePlayerStats(for: winger).shifts.isEmpty, "no shift was closed")
    }

    func testMovingAForwardToDefense() {
        let id = winger.persistentModelID
        vm.changeLine(of: winger, to: "F2")
        vm.setGamePosition("LW", for: winger)

        vm.changeLine(of: winger, to: "D1")

        XCTAssertEqual(vm.effectiveRole(for: winger), "Defense")
        XCTAssertEqual(vm.playerGameRole[id], "Defense")
        XCTAssertEqual(vm.playerLines[id], "D1")
        XCTAssertNil(vm.playerGamePosition[id], "a left wing is not a left defenseman")
        XCTAssertEqual(winger.position, "Forward", "the roster position is untouched")
    }

    func testMovingADefenderToForwardWithNoLine() {
        let id = defender.persistentModelID
        vm.changeLine(of: defender, to: "D2")

        vm.changeLine(of: defender, to: nil, role: "Forward")

        XCTAssertEqual(vm.effectiveRole(for: defender), "Forward")
        XCTAssertNil(vm.playerLines[id])
        XCTAssertEqual(vm.lineSummary(for: defender), "F")
    }

    func testMovingBackToTheRosterPositionDropsTheOverride() {
        let id = winger.persistentModelID
        vm.changeLine(of: winger, to: "D1")
        vm.changeLine(of: winger, to: "F3")

        XCTAssertNil(vm.playerGameRole[id])
        XCTAssertEqual(vm.effectiveRole(for: winger), "Forward")
        XCTAssertEqual(vm.playerLines[id], "F3")
    }

    func testComingOffALineKeepsTheRole() {
        vm.changeLine(of: winger, to: "D1")
        vm.changeLine(of: winger, to: nil)

        XCTAssertNil(vm.playerLines[winger.persistentModelID])
        XCTAssertEqual(vm.effectiveRole(for: winger), "Defense")
    }

    func testTheNextLineChangeUsesTheNewLines() {
        vm.changeLine(of: center, to: "F1")
        vm.changeLine(of: winger, to: "F2")
        vm.sendLineOn("F1")
        dropThePuck()

        vm.changeLine(of: winger, to: "F1")
        vm.sendLineOn("F2")
        XCTAssertFalse(vm.onIcePlayers.contains(winger.persistentModelID), "no longer on the second line")

        vm.sendLineOn("F1")
        XCTAssertTrue(vm.onIcePlayers.contains(winger.persistentModelID))
        XCTAssertTrue(vm.onIcePlayers.contains(center.persistentModelID))
    }

    func testSettingLinesBeforeTheGameStaysOutOfTheFeed() {
        vm.changeLine(of: center, to: "F1")
        vm.changeLine(of: winger, to: "D1")

        XCTAssertTrue(lineChanges.isEmpty)
        XCTAssertEqual(vm.playerLines[center.persistentModelID], "F1")
    }

    func testALineChangeDuringTheGameIsInTheFeed() {
        vm.changeLine(of: winger, to: "F2")
        dropThePuck()

        vm.changeLine(of: winger, to: "F1")
        vm.changeLine(of: center, to: "D1")

        XCTAssertEqual(lineChanges.map(\.description), [
            "\(vm.playerLabel(winger)) to F1",
            "\(vm.playerLabel(center)) to defense, D1"
        ])
    }

    func testUndoingALineChangePutsTheSkaterBack() {
        let id = winger.persistentModelID
        vm.changeLine(of: winger, to: "F2")
        vm.setGamePosition("RW", for: winger)
        dropThePuck()

        vm.changeLine(of: winger, to: "D1")
        vm.undoLast()

        XCTAssertEqual(vm.playerLines[id], "F2")
        XCTAssertEqual(vm.playerGamePosition[id], "RW")
        XCTAssertNil(vm.playerGameRole[id])
        XCTAssertTrue(lineChanges.isEmpty)
        XCTAssertEqual(game.events.filter { $0.type == "shot" }.count, 1, "the shot before it is untouched")
    }

    func testChoosingTheSameLineDoesNothing() {
        vm.changeLine(of: winger, to: "F2")
        dropThePuck()

        vm.changeLine(of: winger, to: "F2")

        XCTAssertTrue(lineChanges.isEmpty)
    }

    func testAnUnknownLineIsIgnored() {
        vm.changeLine(of: winger, to: "F9")
        vm.changeLine(of: winger, to: "G1")

        XCTAssertNil(vm.playerLines[winger.persistentModelID])
        XCTAssertEqual(vm.effectiveRole(for: winger), "Forward")
    }

    func testTheGoalieInNetCannotBeGivenALine() {
        vm.changeLine(of: goalie, to: "F1")

        XCTAssertNil(vm.playerLines[goalie.persistentModelID])
        XCTAssertNil(vm.playerGameRole[goalie.persistentModelID])
    }

    func testPlusMinusFollowsWhoIsOnTheIceNotTheLine() {
        vm.changeLine(of: center, to: "F1")
        vm.changeLine(of: winger, to: "F2")
        vm.sendLineOn("F1")
        dropThePuck()

        // Moved onto the first line on paper, but still on the bench.
        vm.changeLine(of: winger, to: "F1")
        vm.recordGoal(scorer: center, primaryAssist: nil, secondaryAssist: nil)

        XCTAssertEqual(vm.findOrCreatePlayerStats(for: center).plusMinus, 1)
        XCTAssertEqual(vm.findOrCreatePlayerStats(for: winger).plusMinus, 0)
    }

    func testLineChangesSurviveLeavingTheLiveScreen() throws {
        dropThePuck()
        vm.changeLine(of: winger, to: "D1")
        vm.setGamePosition("LD", for: winger)
        vm.changeLine(of: center, to: "F1")

        let everyone: [Player] = [goalie, center, winger, defender]
        let back = try XCTUnwrap(LiveGameViewModel.resume(
            game: game, modelContext: context, lookup: everyone, eligible: everyone,
            publishesLiveScore: false
        ))

        XCTAssertEqual(back.playerLines[winger.persistentModelID], "D1")
        XCTAssertEqual(back.playerGamePosition[winger.persistentModelID], "LD")
        XCTAssertEqual(back.effectiveRole(for: winger), "Defense")
        XCTAssertEqual(back.playerLines[center.persistentModelID], "F1")
        XCTAssertTrue(back.events.contains { $0.description == "\(back.playerLabel(winger)) to defense, D1" })
    }
}
