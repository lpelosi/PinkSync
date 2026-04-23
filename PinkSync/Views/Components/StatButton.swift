import SwiftUI

struct StatButton: View {
    let label: String
    @Binding var value: Int
    var minValue: Int = 0

    var body: some View {
        VStack(spacing: 8) {
            Text(label)
                .font(AppTheme.statLabel)
                .textCase(.uppercase)
                .tracking(1)
                .foregroundStyle(.secondary)

            Text("\(value)")
                .font(AppTheme.statValue)
                .foregroundStyle(AppTheme.pink)
                .contentTransition(.numericText())

            HStack(spacing: 32) {
                Button {
                    if value > minValue {
                        withAnimation(.snappy) { value -= 1 }
                    }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(value > minValue ? AppTheme.decrement : .gray.opacity(0.3))
                }
                .disabled(value <= minValue)

                Button {
                    withAnimation(.snappy) { value += 1 }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(AppTheme.increment)
                }
            }
            .buttonStyle(.plain)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
