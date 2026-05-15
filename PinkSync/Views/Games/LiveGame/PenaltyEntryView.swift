import SwiftUI
import SwiftData

struct PenaltyEntryView: View {
    let isOurs: Bool
    let players: [Player]
    let excluded: Set<PersistentIdentifier>
    var benchPlayers: [Player] = []
    let onRecord: (Player?, String, PenaltyType, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedPlayer: Player?
    @State private var opponentNumber = ""
    @State private var clockTime = ""
    @State private var step: Step = .pickPlayer
    @State private var showAll = false

    private enum Step {
        case pickPlayer
        case pickType
    }

    private var availablePlayers: [Player] {
        players
            .filter { !excluded.contains($0.persistentModelID) }
            .sorted { $0.number < $1.number }
    }

    private var availableBench: [Player] {
        benchPlayers
            .filter { !excluded.contains($0.persistentModelID) }
            .filter { p in !players.contains(where: { $0.persistentModelID == p.persistentModelID }) }
            .sorted { $0.number < $1.number }
    }

    private let columns = [GridItem(.adaptive(minimum: 80), spacing: 12)]

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .pickPlayer:
                    if isOurs {
                        ourPlayerPicker
                    } else {
                        theirNumberEntry
                    }
                case .pickType:
                    penaltyTypePicker
                }
            }
            .navigationTitle(isOurs ? "Our Penalty" : "Opponent Penalty")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var ourPlayerPicker: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(availablePlayers) { player in
                    penaltyPlayerButton(player, color: AppTheme.pink)
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
                            penaltyPlayerButton(player, color: Color(.systemGray3))
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
        }
    }

    private func penaltyPlayerButton(_ player: Player, color: Color) -> some View {
        Button {
            selectedPlayer = player
            step = .pickType
        } label: {
            VStack(spacing: 4) {
                Text(player.number > 0 ? "\(player.number)" : "—")
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

    private var theirNumberEntry: some View {
        VStack(spacing: 24) {
            Text("Opponent Jersey #")
                .font(.headline)

            TextField("#", text: $opponentNumber)
                .font(.system(size: 40, weight: .bold, design: .monospaced))
                .multilineTextAlignment(.center)
                .keyboardType(.numberPad)
                .frame(width: 120)
                .padding()
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))

            Button("Next") {
                step = .pickType
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(AppTheme.teal, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 40)

            Spacer()
        }
        .padding(.top, 40)
    }

    private var penaltyTypePicker: some View {
        List {
            Section {
                ClockTimeField(time: $clockTime)
            } header: {
                Text("Period Time (optional)")
            }

            Section("Penalty Type") {
                ForEach(PenaltyType.allCases) { type in
                    Button {
                        onRecord(selectedPlayer, opponentNumber, type, clockTime)
                        dismiss()
                    } label: {
                        HStack {
                            Text(type.rawValue)
                                .font(.headline)
                            Spacer()
                            Text("\(type.minutes) min")
                                .foregroundStyle(.secondary)
                                .font(.system(.body, design: .monospaced))
                        }
                        .padding(.vertical, 6)
                    }
                    .tint(.primary)
                }
            }
        }
    }
}
