import XCTest
import SwiftData
@testable import PinkSync

/// Mirrors lib/seasons.js on the server: a game must land in the same season
/// and game type on the phone as on the site.
final class SeasonTests: XCTestCase {
    private let seasons = Season.defaults

    func testDayInsideASeason() {
        XCTAssertEqual(Season.season(for: "2026-05-01", in: seasons)?.id, "2026-summer")
        XCTAssertEqual(Season.season(for: "2026-08-15", in: seasons)?.id, "2026-fall")
        XCTAssertEqual(Season.season(for: "2026-08-14", in: seasons)?.id, "2026-summer")
    }

    func testDaysOutsideEverySeasonClampToNearest() {
        XCTAssertEqual(Season.season(for: "2026-03-01", in: seasons)?.id, "2026-summer")
        XCTAssertEqual(Season.season(for: "2027-02-10", in: seasons)?.id, "2026-fall")
        XCTAssertEqual(Season.season(for: "", in: seasons)?.id, "2026-fall")
    }

    func testGapBetweenSeasonsAttachesToTheOneThatJustEnded() {
        let gapped = [
            Season(id: "a", label: "A", start: "2026-01-01", end: "2026-03-31"),
            Season(id: "b", label: "B", start: "2026-06-01", end: "2026-08-31")
        ]
        XCTAssertEqual(Season.season(for: "2026-04-15", in: gapped)?.id, "a")
    }

    func testCurrentPrefersFlagThenTodayThenLatest() {
        XCTAssertEqual(Season.current(in: seasons)?.id, "2026-fall")

        let unflagged = seasons.map { var s = $0; s.isCurrent = nil; return s }
        XCTAssertEqual(Season.current(in: unflagged, today: TestSupport.day("2026-05-01"))?.id, "2026-summer")
        XCTAssertEqual(Season.current(in: unflagged, today: TestSupport.day("2028-01-01"))?.id, "2026-fall")
    }

    func testGameTypeFollowsPlayoffsStart() {
        var fall = seasons[1]
        XCTAssertEqual(fall.gameType(for: "2026-12-01"), .regular, "no playoffsStart means everything is regular season")
        fall.playoffsStart = "2026-12-01"
        XCTAssertEqual(fall.gameType(for: "2026-11-30"), .regular)
        XCTAssertEqual(fall.gameType(for: "2026-12-01"), .playoff)
    }

    func testEveningGamesStayOnTheLocalCalendarDay() {
        // 9:30 PM local on the last day of summer — later than midnight UTC
        // anywhere in the Americas.
        var parts = DateComponents()
        parts.year = 2026; parts.month = 8; parts.day = 14; parts.hour = 21; parts.minute = 30
        let date = Calendar.current.date(from: parts)!

        XCTAssertEqual(Season.apiDay(for: date), "2026-08-14")
        XCTAssertTrue(Season.apiTimestamp(for: date).hasPrefix("2026-08-14T21:30:00"),
                      "the server slices the first ten characters of this")
        XCTAssertEqual(Season.season(for: Season.apiDay(for: date), in: seasons)?.id, "2026-summer")
        XCTAssertEqual(ISO8601DateFormatter().date(from: Season.apiTimestamp(for: date)), date,
                       "the offset form parses back to the same instant on sync")
    }

    func testMembershipKeepsSeasonsThisDeviceDoesNotKnow() {
        // Offline: only the bundled seasons are known, the player is on an older one.
        let stored = Season.membership(selected: ["2026-fall"], known: seasons, previous: ["2025-fall", "2026-summer"])
        XCTAssertEqual(stored, ["2026-fall", "2025-fall"], "summer untoggled, 2025 kept untouched")

        let fresh = Season.membership(selected: ["2026-summer", "2026-fall"], known: seasons, previous: nil)
        XCTAssertEqual(fresh, ["2026-summer", "2026-fall"])
    }

    func testStatScopeFiltersBySeasonAndType() throws {
        let container = try TestSupport.makeContainer()
        let context = container.mainContext
        var fall = seasons[1]
        fall.playoffsStart = "2026-12-01"
        let withPlayoffs = [seasons[0], fall]

        let regularGame = TestSupport.game(date: TestSupport.day("2026-09-11"), in: context)
        let playoffGame = TestSupport.game(date: TestSupport.day("2026-12-05"), in: context)
        let summerGame = TestSupport.game(date: TestSupport.day("2026-06-01"), in: context)

        let fallRegular = StatScope(season: fall, type: .regular, seasons: withPlayoffs)
        XCTAssertTrue(fallRegular.includes(regularGame))
        XCTAssertFalse(fallRegular.includes(playoffGame))
        XCTAssertFalse(fallRegular.includes(summerGame))

        let anyPlayoff = StatScope(season: nil, type: .playoff, seasons: withPlayoffs)
        XCTAssertTrue(anyPlayoff.includes(playoffGame))
        XCTAssertFalse(anyPlayoff.includes(regularGame))

        let everything = StatScope(season: nil, type: nil, seasons: withPlayoffs)
        XCTAssertTrue(everything.includes(summerGame))
        XCTAssertFalse(everything.includes(nil))
    }
}
