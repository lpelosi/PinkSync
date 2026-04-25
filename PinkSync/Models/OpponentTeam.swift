import Foundation
import SwiftData

@Model
final class OpponentTeam {
    var name: String
    /// Asset catalog image name for bundled logos
    var logoAsset: String?
    /// User-provided logo image data (JPEG)
    @Attribute(.externalStorage) var logoData: Data?

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
        SeedInfo(name: "Otterhawks", logoAsset: "otterhawks"),
        SeedInfo(name: "District 5", logoAsset: "d5"),
        SeedInfo(name: "Frozen Flamingos", logoAsset: "flamingos_emblem"),
    ]
}
