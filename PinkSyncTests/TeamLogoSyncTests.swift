import XCTest
import SwiftData
@testable import PinkSync

/// The server owns the logos. A device pulls, and pushes only what was
/// changed on it or what the server is missing.
@MainActor
final class TeamLogoSyncTests: XCTestCase {
    private let server = "/img/teams/wolves.jpg?v=200"

    func testPullsALogoTheDeviceDoesNotHave() {
        let step = TeamLogoSync.action(hasLocalLogo: false, hasBundledLogo: false, needsUpload: false, localVersion: nil, serverPath: server)
        XCTAssertEqual(step, .download(server))
    }

    func testPullsWhenTheServersLogoWasReplaced() {
        let step = TeamLogoSync.action(hasLocalLogo: true, hasBundledLogo: false, needsUpload: false, localVersion: "/img/teams/wolves.jpg?v=100", serverPath: server)
        XCTAssertEqual(step, .download(server))
    }

    func testLeavesALogoThatIsAlreadyCurrent() {
        let step = TeamLogoSync.action(hasLocalLogo: true, hasBundledLogo: true, needsUpload: false, localVersion: server, serverPath: server)
        XCTAssertEqual(step, .none)
    }

    func testTheServersLogoReplacesOneThatWasNeverMatchedWithIt() {
        // A logo from before logos were synced: the server's wins.
        let step = TeamLogoSync.action(hasLocalLogo: true, hasBundledLogo: false, needsUpload: false, localVersion: nil, serverPath: server)
        XCTAssertEqual(step, .download(server))
    }

    func testTheServersLogoWinsOverTheOneShippedInTheApp() {
        let step = TeamLogoSync.action(hasLocalLogo: false, hasBundledLogo: true, needsUpload: false, localVersion: nil, serverPath: server)
        XCTAssertEqual(step, .download(server))
    }

    func testPushesALogoChangedOnThisDevice() {
        let step = TeamLogoSync.action(hasLocalLogo: true, hasBundledLogo: false, needsUpload: true, localVersion: "/img/teams/wolves.jpg?v=100", serverPath: server)
        XCTAssertEqual(step, .upload)
    }

    func testPushesWhenTheServerHasNoLogoForTheTeam() {
        XCTAssertEqual(TeamLogoSync.action(hasLocalLogo: true, hasBundledLogo: false, needsUpload: false, localVersion: nil, serverPath: nil), .upload)
        XCTAssertEqual(TeamLogoSync.action(hasLocalLogo: false, hasBundledLogo: true, needsUpload: false, localVersion: nil, serverPath: nil), .upload)
    }

    func testNothingToDoWhenNobodyHasALogo() {
        XCTAssertEqual(TeamLogoSync.action(hasLocalLogo: false, hasBundledLogo: false, needsUpload: false, localVersion: nil, serverPath: nil), .none)
    }

    func testAChangeWithNoPictureBehindItPullsInstead() {
        let step = TeamLogoSync.action(hasLocalLogo: false, hasBundledLogo: false, needsUpload: true, localVersion: nil, serverPath: server)
        XCTAssertEqual(step, .download(server))
    }

    func testAnOpponentFindsItsTeamHoweverTheScheduleTypedIt() {
        let wolves = OpponentTeam(name: "Wolves", logoAsset: "wolves")
        let warriors = OpponentTeam(name: "Warriors")
        let teams = [warriors, wolves]

        XCTAssertTrue(TeamLogoSync.team(named: "WOLVES", in: teams) === wolves)
        XCTAssertTrue(TeamLogoSync.team(named: " wolves ", in: teams) === wolves)
        XCTAssertNil(TeamLogoSync.team(named: "Wolverines", in: teams))
        XCTAssertNil(TeamLogoSync.team(named: "", in: teams))

        // A team saved under the shouted name is the better match for it.
        let shouted = OpponentTeam(name: "WOLVES")
        XCTAssertTrue(TeamLogoSync.team(named: "WOLVES", in: teams + [shouted]) === shouted)
    }

    func testALeagueTeamIsListedUnderOneName() {
        XCTAssertEqual(OpponentTeam.listedName(for: "Wolves"), "WOLVES")
        XCTAssertEqual(OpponentTeam.listedName(for: " wolves "), "WOLVES")
        XCTAssertEqual(OpponentTeam.listedName(for: "WOLVES"), "WOLVES")
        XCTAssertEqual(OpponentTeam.listedName(for: "orlando kraken"), "Orlando Kraken")
        // Not a league team: left as it was typed.
        XCTAssertEqual(OpponentTeam.listedName(for: "Fighting Walleye Blue"), "Fighting Walleye Blue")
    }

    func testTeamsAndGamesSavedAsWolvesBecomeWOLVES() throws {
        let container = try TestSupport.makeContainer()
        let context = container.mainContext
        let logo = Data([0xff, 0xd8, 0xff])
        let old = OpponentTeam(name: "Wolves", logoAsset: "wolves", logoData: logo)
        old.logoVersion = server
        context.insert(old)
        context.insert(OpponentTeam(name: "WOLVES"))
        context.insert(OpponentTeam(name: "Warriors"))
        let game = TestSupport.game(opponent: "Wolves", in: context)
        let other = TestSupport.game(opponent: "Warriors", in: context)
        try context.save()

        XCTAssertTrue(RosterSeeder.useListedTeamNames(modelContext: context))

        let teams = try context.fetch(FetchDescriptor<OpponentTeam>())
        XCTAssertEqual(teams.map(\.name).sorted(), ["WOLVES", "Warriors"])
        let wolves = try XCTUnwrap(teams.first { $0.name == "WOLVES" })
        XCTAssertEqual(wolves.logoData, logo, "the logo the other copy held is kept")
        XCTAssertEqual(wolves.logoVersion, server)
        XCTAssertEqual(game.opponent, "WOLVES")
        XCTAssertEqual(other.opponent, "Warriors")

        XCTAssertFalse(RosterSeeder.useListedTeamNames(modelContext: context), "nothing left to change")
    }

    func testABoutIsMatchedToItsGameHoweverTheTeamWasTyped() {
        let bout = APIClient.ScheduleEntry(id: "b1", date: "2026-10-10", opponent: "Wolves", location: "Ice Den", time: "9:00 PM", isHome: true, tournamentId: nil)
        XCTAssertEqual(bout.listed.opponent, "WOLVES")

        let played = GamesListView.BoutMatch(scheduleId: "", opponent: "WOLVES", date: TestSupport.day("2026-10-10"))
        XCTAssertEqual(GamesListView.upcoming([bout], games: [played]).map(\.id), [])
    }

    func testTeamNamesMatchHoweverTheyWereTyped() {
        XCTAssertEqual(TeamLogoSync.teamKey("  Orlando   Kraken "), "orlando kraken")
        XCTAssertEqual(TeamLogoSync.teamKey("WOLVES"), TeamLogoSync.teamKey("Wolves"))
    }
}
