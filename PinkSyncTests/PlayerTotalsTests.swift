import XCTest
import SwiftData
@testable import PinkSync

final class PlayerTotalsTests: XCTestCase {
    func testTotalsAreScopedBySeason() throws {
        let container = try TestSupport.makeContainer()
        let context = container.mainContext
        let player = TestSupport.player("Skater", number: 7, in: context)
        let summer = TestSupport.game(date: TestSupport.day("2026-06-01"), in: context)
        let fall = TestSupport.game(date: TestSupport.day("2026-09-01"), in: context)

        let summerLine = GamePlayerStats(goals: 2, assists: 1)
        summerLine.player = player
        summerLine.game = summer
        context.insert(summerLine)

        let fallLine = GamePlayerStats(goals: 1, assists: 0, penaltyMinutes: 2)
        fallLine.player = player
        fallLine.game = fall
        context.insert(fallLine)
        try context.save()

        let seasons = Season.defaults
        let fallOnly = player.totals(in: StatScope(season: seasons[1], type: nil, seasons: seasons))
        XCTAssertEqual(fallOnly.gamesPlayed, 1)
        XCTAssertEqual(fallOnly.totalGoals, 1)
        XCTAssertEqual(fallOnly.totalPenaltyMinutes, 2)

        let summerOnly = player.totals(in: StatScope(season: seasons[0], type: nil, seasons: seasons))
        XCTAssertEqual(summerOnly.totalPoints, 3)

        XCTAssertEqual(player.allTime.totalGoals, 3)
        XCTAssertEqual(player.totalPoints, 4, "the all-time shortcuts still read the same")
    }

    func testGoalieTotals() throws {
        let container = try TestSupport.makeContainer()
        let context = container.mainContext
        let goalie = TestSupport.player("Goalie", number: 1, goalie: true, in: context)
        let game = TestSupport.game(in: context)

        let line = GameGoalieStats(shotsAgainst: 30, goalsAgainst: 3, result: GameResult.win.rawValue)
        line.player = goalie
        line.game = game
        context.insert(line)
        try context.save()

        let totals = goalie.allTime
        XCTAssertEqual(totals.goalieGamesPlayed, 1)
        XCTAssertEqual(totals.wins, 1)
        XCTAssertEqual(totals.savePercentage, 0.9, accuracy: 0.0001)
        XCTAssertEqual(totals.goalsAgainstAverage, 3, accuracy: 0.0001)
    }

    func testSeasonMembership() throws {
        let container = try TestSupport.makeContainer()
        let player = TestSupport.player("Anyone", number: 3, in: container.mainContext)
        XCTAssertTrue(player.isMember(of: "2026-fall"), "no membership set means every season")
        player.seasonIds = ["2026-summer"]
        XCTAssertFalse(player.isMember(of: "2026-fall"))
        XCTAssertTrue(player.isMember(of: "2026-summer"))
    }
}
