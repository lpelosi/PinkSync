import XCTest
import SwiftData
@testable import PinkSync

/// The coach's page is the team's record, counted the way the site's
/// `lib/teamRecord.js` counts it, plus the beer league split.
final class CoachRecordTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUpWithError() throws {
        container = try TestSupport.makeContainer()
    }

    private func game(_ result: String, day: String, gf: Int = 3, ga: Int = 2, drinking: Bool = false, tournament: String = "") -> Game {
        let g = TestSupport.game(date: TestSupport.day(day), in: context)
        g.result = result
        g.goalsFor = gf
        g.goalsAgainst = ga
        g.coachWasDrinking = drinking
        g.tournamentId = tournament
        return g
    }

    func testStandingsRules() throws {
        let games = [
            game("W", day: "2026-09-01"),
            game("SOW", day: "2026-09-02"),
            game("L", day: "2026-09-03", gf: 1, ga: 4),
            game("OTL", day: "2026-09-04", gf: 2, ga: 3),
            game("SOL", day: "2026-09-05", gf: 2, ga: 3),
            game("", day: "2026-09-06"),
        ]
        try context.save()

        let record = TeamRecord(games: games)
        XCTAssertEqual(record.gamesPlayed, 5, "a game with no result is not counted")
        XCTAssertEqual(record.wins, 2, "a shootout win is a win")
        XCTAssertEqual(record.losses, 1, "only a regulation loss is a loss")
        XCTAssertEqual(record.overtimeLosses, 2, "OT and shootout losses share the third column")
        XCTAssertEqual(record.display, "2-1-2")
        XCTAssertEqual(record.points, 6)
        XCTAssertEqual(record.pointsPercentage, 0.6, accuracy: 0.0001)
        XCTAssertEqual(record.goalDifferential, 3 + 3 + 1 + 2 + 2 - (2 + 2 + 4 + 3 + 3))
    }

    func testStreakReadsNewestFirstAcrossShootouts() throws {
        let games = [
            game("L", day: "2026-09-01"),
            game("W", day: "2026-09-02"),
            game("SOW", day: "2026-09-03"),
            game("", day: "2026-09-04"),
        ]
        try context.save()
        XCTAssertEqual(TeamRecord.streak(games), "W2")
        XCTAssertEqual(TeamRecord.streak([games[0]]), "L1")
        XCTAssertNil(TeamRecord.streak([games[3]]))
    }

    func testDrinkingSplit() throws {
        let games = [
            game("W", day: "2026-09-01", drinking: true),
            game("W", day: "2026-09-02", drinking: true),
            game("L", day: "2026-09-03"),
            game("OTL", day: "2026-09-04"),
        ]
        try context.save()

        let drinking = TeamRecord(games: games.filter(\.coachWasDrinking))
        let sober = TeamRecord(games: games.filter { !$0.coachWasDrinking })
        XCTAssertEqual(drinking.display, "2-0-0")
        XCTAssertEqual(sober.display, "0-1-1")
        XCTAssertGreaterThan(drinking.pointsPercentage, sober.pointsPercentage)
    }

    /// A season view is league play only; a tournament view is that
    /// tournament; All Seasons is everything. Same rules as the site.
    func testSelectionScopesLikeTheSite() throws {
        let league = game("W", day: "2026-10-01")
        let trip = game("L", day: "2026-10-03", tournament: "classic-2026")
        try context.save()
        let store = SeasonStore()
        let fall = store.season(for: TestSupport.day("2026-10-01"))!.id

        let season = TeamRecord.games([league, trip], selection: fall, seasonStore: store)
        XCTAssertEqual(season.map(\.gameId), [league.gameId], "tournament games stay out of a season's record")

        let tournament = TeamRecord.games([league, trip], selection: Tournament.selectionPrefix + "classic-2026", seasonStore: store)
        XCTAssertEqual(tournament.map(\.gameId), [trip.gameId])

        let all = TeamRecord.games([league, trip], selection: Season.allId, seasonStore: store)
        XCTAssertEqual(all.count, 2, "lifetime counts everything")
    }

    func testCoachFlagDefaultsOff() throws {
        let g = TestSupport.game(in: context)
        try context.save()
        XCTAssertFalse(g.coachWasDrinking)
    }
}
