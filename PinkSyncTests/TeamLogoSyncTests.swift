import XCTest
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

    func testTeamNamesMatchHoweverTheyWereTyped() {
        XCTAssertEqual(TeamLogoSync.teamKey("  Orlando   Kraken "), "orlando kraken")
        XCTAssertEqual(TeamLogoSync.teamKey("WOLVES"), TeamLogoSync.teamKey("Wolves"))
    }
}
