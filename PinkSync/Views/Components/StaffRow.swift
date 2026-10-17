import SwiftUI

struct StaffRow: View {
    let member: StaffMember

    var body: some View {
        HStack(spacing: 12) {
            CachedPlayerPhoto(url: member.photoURL)

            Text(member.name)
                .font(AppTheme.playerName)

            Spacer()

            Text(member.role)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(AppTheme.beer.opacity(0.15))
                .foregroundStyle(AppTheme.beer)
                .clipShape(Capsule())
        }
    }
}
