import SwiftUI

struct PlayerRow: View {
    let player: Player

    var body: some View {
        HStack(spacing: 12) {
            Text(player.displayNumber)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(AppTheme.pink)
                .frame(width: 44)

            Text(player.name)
                .font(AppTheme.playerName)

            Spacer()

            Text(player.position)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(player.isGoalie ? AppTheme.pink.opacity(0.15) : AppTheme.teal.opacity(0.15))
                .foregroundStyle(player.isGoalie ? AppTheme.pink : AppTheme.teal)
                .clipShape(Capsule())
        }
    }
}
