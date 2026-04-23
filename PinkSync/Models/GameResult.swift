import Foundation

enum GameResult: String, Codable, CaseIterable, Identifiable {
    case win = "W"
    case loss = "L"
    case overtimeLoss = "OTL"
    case shootoutWin = "SOW"
    case shootoutLoss = "SOL"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .win: "Win"
        case .loss: "Loss"
        case .overtimeLoss: "OT Loss"
        case .shootoutWin: "SO Win"
        case .shootoutLoss: "SO Loss"
        }
    }

    var shortName: String { rawValue }

    var isWin: Bool {
        self == .win || self == .shootoutWin
    }

    var isShootout: Bool {
        self == .shootoutWin || self == .shootoutLoss
    }
}
