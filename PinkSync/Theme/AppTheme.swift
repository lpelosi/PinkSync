import SwiftUI

enum AppTheme {
    // MARK: - Colors
    static let pink = Color(red: 1.0, green: 0.443, blue: 0.808)       // #FF71CE
    static let teal = Color(red: 0.004, green: 0.804, blue: 0.996)     // #01CDFE
    static let darkBg = Color(red: 0.02, green: 0.02, blue: 0.02)      // #050505

    static let increment = Color.green
    static let decrement = Color.red

    // MARK: - Fonts
    static let statValue = Font.system(size: 60, weight: .bold, design: .monospaced)
    static let statLabel = Font.system(size: 14, weight: .bold, design: .default)
    static let playerName = Font.system(size: 18, weight: .semibold)
    static let sectionHeader = Font.system(size: 22, weight: .heavy)
}
