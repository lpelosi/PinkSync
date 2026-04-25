import SwiftUI
import SwiftData

struct LivePlayerPickerView: View {
    let players: [Player]
    let title: String
    let skipLabel: String?
    let excluded: Set<PersistentIdentifier>
    let onPick: (Player?) -> Void

    @Environment(\.dismiss) private var dismiss

    private var availablePlayers: [Player] {
        players
            .filter { !excluded.contains($0.persistentModelID) }
            .sorted { $0.number < $1.number }
    }

    private let columns = [GridItem(.adaptive(minimum: 80), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(availablePlayers) { player in
                        Button {
                            onPick(player)
                            dismiss()
                        } label: {
                            VStack(spacing: 4) {
                                Text(player.number > 0 ? "\(player.number)" : "—")
                                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.white)
                                Text(lastName(player.name))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.8))
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 80)
                            .background(AppTheme.pink, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                .padding()

                if let skipLabel {
                    Button {
                        onPick(nil)
                        dismiss()
                    } label: {
                        Text(skipLabel)
                            .font(.headline)
                            .foregroundStyle(AppTheme.teal)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func lastName(_ name: String) -> String {
        let parts = name.components(separatedBy: " ")
        return parts.last ?? name
    }
}
