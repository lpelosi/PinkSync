import SwiftUI

/// Small beer-league marker for a player who was drinking during a game.
/// Shown wherever a per-game stat line is listed; toggled on the lineup,
/// in Edit Stats, on a player's stat card and from the live Lineup sheet.
struct DrinkingBadge: View {
    var compact = false

    var body: some View {
        Image(systemName: "mug.fill")
            .font(.system(size: compact ? 9 : 11, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, compact ? 4 : 6)
            .padding(.vertical, compact ? 1 : 3)
            .background(AppTheme.beer, in: Capsule())
            .accessibilityLabel("Drinking")
    }
}
