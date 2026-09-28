import XCTest
import SwiftData
@testable import PinkSync

/// One test per bug found in review of the season / live-scoring update.
final class ReviewRegressionTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private var starter: Player!
    private var relief: Player!
    private var skater: Player!
    private var game: Game!

    override func setUpWithError() throws {
        container = try TestSupport.makeContainer()
        starter = TestSupport.player("Starter", number: 1, goalie: true, in: context)
        relief = TestSupport.player("Relief", number: 30, goalie: true, in: context)
        skater = TestSupport.player("Skater", number: 7, in: context)
        game = TestSupport.game(in: context)
    }

    override func tearDown() {
        LiveSessionStore.delete(gameId: game.gameId)
    }

    private func liveVM() -> LiveGameViewModel {
        let vm = TestSupport.liveVM(game: game, players: [starter, skater], goalie: starter, context: context)
        vm.availablePlayers = [starter, relief, skater]
        return vm
    }

    private func resumed() throws -> LiveGameViewModel {
        try XCTUnwrap(LiveGameViewModel.resume(
            game: game, modelContext: context, lookup: [starter, relief, skater],
            eligible: [starter, relief, skater], publishesLiveScore: false
        ))
    }

    private func line(_ goalie: Player) -> GameGoalieStats? {
        game.goalieStats.first { $0.player?.persistentModelID == goalie.persistentModelID }
    }

    func testDeletingAResumedGoalNeverGivesTheGoalieASkaterLine() throws {
        let vm = liveVM()
        vm.recordGoal(scorer: skater, primaryAssist: nil, secondaryAssist: nil)
        XCTAssertEqual(vm.findOrCreatePlayerStats(for: skater).plusMinus, 0, "skater not on ice")
        let skaterLinesBefore = game.playerStats.count

        let back = try resumed()
        let index = try XCTUnwrap(back.events.firstIndex { $0.gameEvent?.type == "goal" })
        back.deleteEvent(at: index)

        XCTAssertEqual(game.playerStats.count, skaterLinesBefore)
        XCTAssertFalse(game.playerStats.contains { $0.player?.persistentModelID == starter.persistentModelID })
    }

    func testResumedPlusMinusReversalOnlyTouchesSkatersWhoWereOn() throws {
        let vm = liveVM()
        vm.putPlayerOnIce(skater)
        vm.recordGoalAgainst()
        XCTAssertEqual(vm.findOrCreatePlayerStats(for: skater).plusMinus, -1)

        let back = try resumed()
        let index = try XCTUnwrap(back.events.firstIndex { $0.gameEvent?.type == "goalAgainst" })
        back.deleteEvent(at: index)
        XCTAssertEqual(back.findOrCreatePlayerStats(for: skater).plusMinus, 0)
        XCTAssertFalse(game.playerStats.contains { $0.player?.persistentModelID == starter.persistentModelID })
    }

    func testEditingAShotAgainstKeepsItWithTheGoalieWhoFacedIt() throws {
        let vm = liveVM()
        vm.recordShotAgainst()
        vm.changeGoalie(to: relief)
        let index = try XCTUnwrap(vm.events.firstIndex { $0.gameEvent?.type == "shotAgainst" })

        vm.replaceEvent(at: index, player: nil, clockTime: "05:00", isPowerPlay: false, isShortHanded: false,
                        assist1: nil, assist2: nil, penaltyType: nil, faceoffWon: nil, opponentNumber: "", period: 1)

        XCTAssertEqual(line(starter)?.shotsAgainst, 1)
        XCTAssertEqual(line(relief)?.shotsAgainst ?? 0, 0)
        XCTAssertEqual(game.events.first { $0.type == "shotAgainst" }?.playerId, starter.playerId)
    }

    func testUndoneGoalieChangeLeavesNoPhantomLine() {
        let vm = liveVM()
        vm.changeGoalie(to: relief)
        XCTAssertNotNil(line(relief))
        vm.undoLast()
        XCTAssertNil(line(relief), "an accidental change must not credit a game played")
        XCTAssertNotNil(line(starter))
    }

    func testEndOfGameClearsOtherDecisionsAndEmptyLines() {
        let vm = liveVM()
        vm.recordGoal(scorer: skater, primaryAssist: nil, secondaryAssist: nil)
        vm.changeGoalie(to: relief)
        vm.changeGoalie(to: starter)          // relief went in and out without facing a shot
        vm.computeResult()

        XCTAssertEqual(line(starter)?.result, "W")
        XCTAssertNil(line(relief))
    }

    func testShootoutRoundsRestoreToTheGoalieWhoFacedThem() throws {
        game.goalsFor = 1
        game.goalsAgainst = 1
        let vm = liveVM()
        vm.goToOvertime()
        vm.goToShootout()
        vm.recordShootoutAttempt(player: skater, isGoal: false)
        vm.recordShootoutAttemptAgainst(isGoal: false)       // on the starter
        vm.changeGoalie(to: relief)
        vm.recordShootoutAttempt(player: skater, isGoal: false)
        vm.recordShootoutAttemptAgainst(isGoal: true)        // on the relief goalie

        let back = try resumed()
        let theirs = back.shootoutAttempts.filter { !$0.isOurs }
        XCTAssertEqual(theirs.count, 2)
        XCTAssertEqual(theirs[0].round?.goalieStats?.player?.persistentModelID, starter.persistentModelID)
        XCTAssertEqual(theirs[1].round?.goalieStats?.player?.persistentModelID, relief.persistentModelID)

        // Editing the first attempt after resume reaches the starter's stored round.
        back.updateShootoutAttempt(id: theirs[0].id, player: nil, isGoal: true)
        XCTAssertEqual(line(starter)?.shootoutRounds.first?.isGoal, true)
    }

    func testSendDecisionGoesToOneGoalieOnly() {
        let starterLine = GameGoalieStats(shotsAgainst: 10, goalsAgainst: 1, result: "")
        let reliefLine = GameGoalieStats(shotsAgainst: 20, goalsAgainst: 2, result: "")
        context.insert(starterLine)
        context.insert(reliefLine)
        let lines: [(GameGoalieStats, Player)] = [(starterLine, starter), (reliefLine, relief)]

        // Nothing decided (hand-entered / reopened): the starter, not both.
        XCTAssertEqual(APIClient.decisionHolders(lines: lines, startingGoalie: starter), [starter.persistentModelID])
        // No starter recorded: whoever faced the most shots.
        XCTAssertEqual(APIClient.decisionHolders(lines: lines, startingGoalie: nil), [relief.persistentModelID])
        // Live scoring decided it: exactly that goalie.
        reliefLine.result = "L"
        XCTAssertEqual(APIClient.decisionHolders(lines: lines, startingGoalie: starter), [relief.persistentModelID])
        // A single goalie always has it.
        XCTAssertEqual(APIClient.decisionHolders(lines: [(starterLine, starter)], startingGoalie: starter), [starter.persistentModelID])
    }
}
