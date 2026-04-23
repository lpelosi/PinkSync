import Foundation

enum Position: String, Codable, CaseIterable, Identifiable {
    case goalie = "Goalie"
    case defense = "Defense"
    case forward = "Forward"
    case center = "Center"
    case leftWing = "Left Wing"
    case rightWing = "Right Wing"

    var id: String { rawValue }
}
