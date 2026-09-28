import XCTest
import SwiftData
@testable import PinkSync

/// Hockey's decision rule with a relief goalie: the win goes to the goalie in
/// net for the winning goal, the loss to the goalie who allowed the deciding
/// goal against. Everyone else who played gets no decision.
final class GoalieOfRecordTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private var starter: Player!
    private var relief: Player!
    private var skater: Player!
    private var game: Game!
    private var vm: LiveGameViewModel!

    override func setUpWithError() throws {
        container = try TestSupport.makeContainer()
        starter = TestSupport.player("Starter", number: 1, goalie: true, in: context)
        relief = TestSupport.player("Relief", number: 30, goalie: true, in: context)
        skater = TestSupport.player("Skater", number: 7, in: context)
        game = TestSupport.game(in: context)
        vm = TestSupport.liveVM(game: game, players: [starter, skater], goalie: starter, context: context)
        vm.availablePlayers = [starter, relief, skater]
    }

    override func tearDown() {
        LiveSessionStore.delete(gameId: game.gameId)
    }

    private func result(of goalie: Player) -> String {
        vm.findOrCreateGoalieStats(for: goalie).result
    }

    func testShotsAgainstFollowTheGoalieInNet() {
        vm.recordShotAgainst()
        vm.changeGoalie(to: relief)
        vm.recordShotAgainst()
        vm.recordGoalAgainst()
        XCTAssertEqual(vm.findOrCreateGoalieStats(for: starter).shotsAgainst, 1)
        XCTAssertEqual(vm.findOrCreateGoalieStats(for: relief).shotsAgainst, 2)
        XCTAssertEqual(vm.findOrCreateGoalieStats(for: relief).goalsAgainst, 1)
        XCTAssertTrue(vm.checkedInPlayers.contains { $0.persistentModelID == relief.persistentModelID })
    }

    func testReliefGoalieTakesTheLoss() {
        vm.recordGoal(scorer: skater, primaryAssist: nil, secondaryAssist: nil)   // 1-0
        vm.recordGoalAgainst()                                                    // 1-1 on the starter
        vm.changeGoalie(to: relief)
        vm.recordGoalAgainst()                                                    // 1-2, the deciding goal
        vm.recordGoalAgainst()                                                    // 1-3
        vm.computeResult()

        XCTAssertEqual(game.result, "L")
        XCTAssertEqual(result(of: relief), "L")
        XCTAssertEqual(result(of: starter), "", "no decision for the starter")
    }

    func testStarterKeepsTheLossWhenTheDecidingGoalWasTheirs() {
        vm.recordGoalAgainst()          // 0-1, the deciding goal, on the starter
        vm.changeGoalie(to: relief)
        vm.recordGoalAgainst()          // 0-2
        vm.computeResult()

        XCTAssertEqual(result(of: starter), "L")
        XCTAssertEqual(result(of: relief), "")
    }

    func testWinGoesToTheGoalieInNetForTheWinningGoal() {
        vm.recordGoalAgainst()                                                    // 0-1 on the starter
        vm.changeGoalie(to: relief)
        vm.recordGoal(scorer: skater, primaryAssist: nil, secondaryAssist: nil)   // 1-1
        vm.recordGoal(scorer: skater, primaryAssist: nil, secondaryAssist: nil)   // 2-1, winning goal with relief in net
        vm.computeResult()

        XCTAssertEqual(game.result, "W")
        XCTAssertEqual(result(of: relief), "W")
        XCTAssertEqual(result(of: starter), "")
        XCTAssertEqual(vm.findOrCreatePlayerStats(for: skater).gameWinningGoals, 1)
    }

    func testUndoingAGoalieChangePutsTheStarterBack() {
        vm.changeGoalie(to: relief)
        XCTAssertEqual(vm.activeGoalie?.persistentModelID, relief.persistentModelID)
        XCTAssertEqual(game.events.filter { $0.type == "goalieChange" }.count, 1)

        vm.undoLast()
        XCTAssertEqual(vm.activeGoalie?.persistentModelID, starter.persistentModelID)
        XCTAssertTrue(game.events.filter { $0.type == "goalieChange" }.isEmpty)
    }
}
