import SwiftUI
import SwiftData

struct LivePlayerPickerView: View {
    let players: [Player]
    let title: String
    let skipLabel: String?
    let excluded: Set<PersistentIdentifier>
    let onPick: (Player?) -> Void
    var benchPlayers: [Player] = []
    var jerseyText: (Player) -> String = { $0.jerseyText }

    @Environment(\.dismiss) private var dismiss
    @State private var showAll = false

    private var availablePlayers: [Player] {
        players.filter { !excluded.contains($0.persistentModelID) }
    }

    private var availableBench: [Player] {
        benchPlayers
            .filter { !excluded.contains($0.persistentModelID) }
            .filter { p in !players.contains(where: { $0.persistentModelID == p.persistentModelID }) }
    }

    private let columns = [GridItem(.adaptive(minimum: 80), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(availablePlayers) { player in
                        playerButton(player, color: AppTheme.pink)
                    }
                }
                .padding()

                if !availableBench.isEmpty {
                    if showAll {
                        Text("ALL PLAYERS")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)

                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(availableBench) { player in
                                playerButton(player, color: Color(.systemGray3))
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom)
                    } else {
                        Button {
                            showAll = true
                        } label: {
                            Text("Show All Players")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(AppTheme.teal)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                    }
                }

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

    private func playerButton(_ player: Player, color: Color) -> some View {
        Button {
            onPick(player)
            dismiss()
        } label: {
            VStack(spacing: 4) {
                Text(jerseyText(player))
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                Text(player.lastName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 80)
            .background(color, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
