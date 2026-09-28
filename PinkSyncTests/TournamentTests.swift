import XCTest
import SwiftData
@testable import PinkSync

/// Mirrors lib/tournaments.js on the server: a tournament game must be kept
/// out of the season numbers on the phone exactly as it is on the site.
final class TournamentTests: XCTestCase {
    private let seasons = Season.defaults
    private let classic = Tournament(
        id: "twin-cities-classic-2026",
        label: "Twin Cities Classic",
        start: "2026-10-02",
        end: "2026-10-04"
    )

    func testTitleCarriesTheYearOnce() {
        XCTAssertEqual(classic.title, "Twin Cities Classic 2026")

        var dated = classic
        dated.label = "Twin Cities Classic 2026"
        XCTAssertEqual(dated.title, "Twin Cities Classic 2026")
    }

    func testPickerSelectionTellsSeasonsAndTournamentsApart() {
        XCTAssertEqual(Tournament.tournamentId(fromSelection: classic.selectionId), classic.id)
        XCTAssertNil(Tournament.tournamentId(fromSelection: "2026-fall"))
        XCTAssertNil(Tournament.tournamentId(fromSelection: Season.allId))
        XCTAssertNil(Tournament.tournamentId(fromSelection: Tournament.selectionPrefix))
    }

    func testTournamentGamesStayOutOfTheSeasonNumbers() throws {
        let container = try TestSupport.makeContainer()
        let context = container.mainContext

        // Same day on purpose: a league game at home, the tournament away.
        let league = TestSupport.game(date: TestSupport.day("2026-10-02"), opponent: "WOLVES", in: context)
        let tournament = TestSupport.game(date: TestSupport.day("2026-10-02"), opponent: "Fighting Walleye Blue", in: context)
        tournament.tournamentId = classic.id

        let regular = StatScope(season: seasons[1], type: .regular, seasons: seasons)
        XCTAssertTrue(regular.includes(league))
        XCTAssertFalse(regular.includes(tournament))

        let playoffs = StatScope(season: seasons[1], type: .playoff, seasons: seasons)
        XCTAssertFalse(playoffs.includes(tournament))

        let everything = StatScope(season: seasons[1], type: nil, seasons: seasons)
        XCTAssertTrue(everything.includes(league))
        XCTAssertTrue(everything.includes(tournament), "All Games counts tournament play too")

        let onlyTheClassic = StatScope(season: nil, type: nil, seasons: seasons, tournamentId: classic.id)
        XCTAssertTrue(onlyTheClassic.includes(tournament))
        XCTAssertFalse(onlyTheClassic.includes(league))
    }

    func testStoreScopeFollowsThePickerSelection() throws {
        let container = try TestSupport.makeContainer()
        let context = container.mainContext
        let tournament = TestSupport.game(date: TestSupport.day("2026-10-03"), opponent: "Nordeasters", in: context)
        tournament.tournamentId = classic.id

        let store = SeasonStore()
        // The type filter is set aside: a tournament has no regular season.
        XCTAssertTrue(store.scope(seasonId: classic.selectionId, type: .regular).includes(tournament))
        XCTAssertFalse(store.scope(seasonId: "2026-fall", type: .regular).includes(tournament))
    }

    func testTheEnteredRosterDecidesWhoIsOnIt() throws {
        let container = try TestSupport.makeContainer()
        let context = container.mainContext
        let traveller = TestSupport.player("Traveller", number: 7, in: context)
        let homebody = TestSupport.player("Homebody", number: 12, in: context)

        var withRoster = classic
        // Stored ids may differ in case from the device's.
        withRoster.roster = [traveller.playerId.lowercased()]

        XCTAssertTrue(withRoster.isOnRoster(traveller))
        XCTAssertFalse(withRoster.isOnRoster(homebody))
    }

    func testWithNoRosterItIsWhoeverPlayed() throws {
        let container = try TestSupport.makeContainer()
        let context = container.mainContext
        let played = TestSupport.player("Played", number: 7, in: context)
        let watched = TestSupport.player("Watched", number: 12, in: context)

        let game = TestSupport.game(date: TestSupport.day("2026-10-02"), in: context)
        game.tournamentId = classic.id
        let line = GamePlayerStats()
        line.player = played
        line.game = game
        context.insert(line)
        try context.save()

        XCTAssertFalse(classic.hasRoster)
        XCTAssertTrue(classic.isOnRoster(played))
        XCTAssertFalse(classic.isOnRoster(watched))
    }

    func testRosterDecisionOnlySpeaksForTournamentGamesWithARoster() throws {
        let container = try TestSupport.makeContainer()
        let context = container.mainContext
        let traveller = TestSupport.player("Traveller", number: 7, in: context)
        let homebody = TestSupport.player("Homebody", number: 12, in: context)

        var withRoster = classic
        withRoster.roster = [traveller.playerId]
        let montreal = Tournament(id: "montreal-2027", label: "Montreal", start: "2027-05-14", end: "2027-05-16")
        let store = TournamentStore(tournaments: [withRoster, montreal])

        XCTAssertEqual(store.rosterDecision(for: traveller, tournamentId: classic.id), true)
        XCTAssertEqual(store.rosterDecision(for: homebody, tournamentId: classic.id), false)
        XCTAssertNil(store.rosterDecision(for: homebody, tournamentId: ""), "a league game")
        XCTAssertNil(store.rosterDecision(for: homebody, tournamentId: montreal.id), "no roster entered yet")
        XCTAssertNil(store.rosterDecision(for: homebody, tournamentId: "unknown"))

        XCTAssertEqual(store.title(for: classic.id), "Twin Cities Classic 2026")
        XCTAssertEqual(store.title(for: "unknown"), "unknown")
        XCTAssertNil(store.title(for: ""))
    }

    func testLettersAreReadPerTournament() throws {
        let container = try TestSupport.makeContainer()
        let context = container.mainContext
        let captain = TestSupport.player("Captain", number: 4, in: context)
        let alternate = TestSupport.player("Alternate", number: 64, in: context)
        let skater = TestSupport.player("Skater", number: 7, in: context)

        var lettered = classic
        lettered.captain = captain.playerId.lowercased()
        lettered.alternates = [alternate.playerId]

        XCTAssertEqual(lettered.letter(for: captain), .captain)
        XCTAssertEqual(lettered.letter(for: alternate), .alternate)
        XCTAssertNil(lettered.letter(for: skater))
        XCTAssertNil(classic.letter(for: captain), "another tournament, another set of letters")
    }

    func testTheDraftKeepsOneCaptainAndOnlyTravellingLetters() {
        var stored = classic
        stored.roster = ["AAA", "BBB", "CCC"]
        stored.captain = "aaa"
        stored.alternates = ["BBB"]
        var draft = TournamentDraft(tournament: stored)
        XCTAssertEqual(draft.letters, ["AAA": .captain, "BBB": .alternate])

        // Naming a new captain takes the C from the old one.
        draft.setLetter(.captain, for: "CCC")
        XCTAssertEqual(draft.letters, ["BBB": .alternate, "CCC": .captain])

        // Leaving the roster gives up the letter.
        draft.toggleRoster("BBB")
        let saved = draft.tournament(existing: [stored])
        XCTAssertEqual(saved.roster, ["AAA", "CCC"])
        XCTAssertEqual(saved.captain, "CCC")
        XCTAssertNil(saved.alternates)
        XCTAssertEqual(saved.id, classic.id)
    }

    func testLettersSurviveARoundTrip() throws {
        var stored = classic
        stored.roster = ["AAA", "BBB"]
        stored.captain = "AAA"
        stored.alternates = ["BBB"]

        let decoded = try JSONDecoder().decode(Tournament.self, from: JSONEncoder().encode(stored))
        XCTAssertEqual(decoded.captain, "AAA")
        XCTAssertEqual(decoded.alternates, ["BBB"])
    }

    func testABoutIsOnlyHiddenByItsOwnGame() {
        func bout(_ id: String, _ date: String, _ opponent: String) -> APIClient.ScheduleEntry {
            APIClient.ScheduleEntry(id: id, date: date, opponent: opponent, location: "BIG 1", time: "", isHome: nil, tournamentId: classic.id)
        }
        let poolGame = bout("pool", "2026-10-03", "Nordeasters")
        let final = bout("final", "2026-10-04", "Nordeasters")
        let schedule = [poolGame, final]
        let sameDay = TestSupport.day("2026-10-03")

        // The pool game was started from its bout, a day before the final
        // against the same team.
        let linked = GamesListView.BoutMatch(scheduleId: "pool", opponent: "Nordeasters", date: sameDay)
        XCTAssertEqual(GamesListView.upcoming(schedule, games: [linked]).map(\.id), ["final"])

        // A game with no bout of its own is still matched by opponent and day.
        let adHoc = GamesListView.BoutMatch(scheduleId: "", opponent: "Nordeasters", date: sameDay)
        XCTAssertEqual(GamesListView.upcoming([poolGame], games: [adHoc]).map(\.id), [])

        XCTAssertEqual(GamesListView.upcoming(schedule, games: []).map(\.id), ["pool", "final"])
    }

    func testTournamentsDecodeWithAndWithoutOptionalFields() throws {
        let json = """
        [
          {"id":"twin-cities-classic-2026","label":"Twin Cities Classic","start":"2026-10-02","end":"2026-10-04",
           "location":"Bloomington Ice Garden","division":"Level 4","roster":["ABC"],"status":"upcoming","gamesPlayed":0,
           "somethingNew":true},
          {"id":"montreal-2027","label":"Montreal","start":"2027-05-14","end":"2027-05-16"}
        ]
        """
        let decoded = try JSONDecoder().decode([Tournament].self, from: Data(json.utf8))
        XCTAssertEqual(decoded.map(\.id), ["twin-cities-classic-2026", "montreal-2027"])
        XCTAssertEqual(decoded[0].division, "Level 4")
        XCTAssertTrue(decoded[0].hasRoster)
        XCTAssertFalse(decoded[1].hasRoster)
    }
}
