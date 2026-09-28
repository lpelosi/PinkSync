import SwiftUI

/// The C or A a captain or alternate wears, shown next to their name. With no
/// letter it draws an empty outline, for the places a letter can be given.
struct LetterBadge: View {
    let letter: Letter?

    var body: some View {
        Text(letter?.rawValue ?? "")
            .font(.system(size: 13, weight: .heavy, design: .rounded))
            .foregroundStyle(.black)
            .frame(width: 24, height: 24)
            .background(fill, in: RoundedRectangle(cornerRadius: 5))
            .overlay {
                if letter == nil {
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(.tertiary, style: StrokeStyle(lineWidth: 1, dash: [3]))
                }
            }
            .accessibilityLabel(letter?.label ?? "No letter")
    }

    private var fill: Color {
        switch letter {
        case .captain: .yellow
        case .alternate: AppTheme.teal
        case nil: .clear
        }
    }
}
