import Foundation

struct AuthUser: Codable, Sendable {
    let userId: String
    let email: String
    let displayName: String
    let role: UserRole
}

enum UserRole: String, Codable, CaseIterable, Sendable {
    case player
    case rosterManager = "roster_manager"
    case photographer
    case scheduleManager = "schedule_manager"
    case admin

    var displayName: String {
        switch self {
        case .player: return "Player"
        case .rosterManager: return "Roster Manager"
        case .photographer: return "Photographer"
        case .scheduleManager: return "Schedule Manager"
        case .admin: return "Admin"
        }
    }
}
