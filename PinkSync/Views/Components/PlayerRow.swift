import SwiftUI

struct PlayerRow: View {
    let player: Player

    var body: some View {
        HStack(spacing: 12) {
            // Player photo thumbnail
            if let photoURL = player.photoURL {
                AsyncImage(url: photoURL) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Image(systemName: "person.circle.fill")
                        .resizable()
                        .foregroundStyle(.tertiary)
                }
                .frame(width: 32, height: 32)
                .clipShape(Circle())
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .foregroundStyle(.tertiary)
                    .frame(width: 32, height: 32)
            }

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
