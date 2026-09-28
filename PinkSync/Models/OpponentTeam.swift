import Foundation
import SwiftData

@Model
final class OpponentTeam {
    var name: String
    /// Asset catalog image name for bundled logos
    var logoAsset: String?
    /// The logo as shown: a copy of the server's, or one picked on this device
    /// that has yet to be uploaded.
    @Attribute(.externalStorage) var logoData: Data?
    /// The server's versioned path for the logo `logoData` is a copy of. The
    /// server is the source of truth: when its path differs, the copy is stale.
    /// Nil when the logo has never been matched with the server.
    var logoVersion: String?
    /// The logo was changed on this device and the server has not had it yet.
    var logoNeedsUpload: Bool = false

    init(name: String, logoAsset: String? = nil, logoData: Data? = nil) {
        self.name = name
        self.logoAsset = logoAsset
        self.logoData = logoData
    }

    /// Seed data for known league teams
    struct SeedInfo {
        let name: String
        let logoAsset: String?
    }

    static let seedTeams: [SeedInfo] = [
        SeedInfo(name: "Orlando Kraken", logoAsset: "kraken"),
        SeedInfo(name: "Warriors", logoAsset: "warriors"),
        SeedInfo(name: "Dangleberry Puckhounds", logoAsset: "puckhounds"),
        SeedInfo(name: "Whiskey Tangos", logoAsset: "tangos"),
        SeedInfo(name: "Wolves", logoAsset: "wolves"),
        SeedInfo(name: "Otterhawks", logoAsset: "otterhawks"),
        SeedInfo(name: "District 5", logoAsset: "d5"),
        SeedInfo(name: "Frozen Flamingos", logoAsset: "flamingos_emblem"),
    ]
}
