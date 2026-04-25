import SwiftUI
import SwiftData

struct LineupCheckInView: View {
    let game: Game
    let allPlayers: [Player]
    let onStart: ([Player]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var checkedIds: Set<PersistentIdentifier> = []
    @State private var selectedGoalieId: PersistentIdentifier?

    private var goalies: [Player] {
        allPlayers.filter { $0.isGoalie }.sorted { $0.number < $1.number }
    }

    private var selectedGoalie: Player? {
        goalies.first { $0.persistentModelID == selectedGoalieId }
    }

    private var skaters: [Player] {
        allPlayers
            .filter { $0.persistentModelID != selectedGoalieId }
            .sorted { $0.number < $1.number }
    }

    private let columns = [GridItem(.adaptive(minimum: 80), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Starting Goalie")
                        .font(.headline)
                        .padding(.horizontal)

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(goalies) { goalie in
                            let isSelected = selectedGoalieId == goalie.persistentModelID
                            Button {
                                selectedGoalieId = goalie.persistentModelID
                            } label: {
                                playerCircle(goalie, checked: isSelected, locked: isSelected)
                            }
                        }
                    }
                    .padding(.horizontal)

                    HStack {
                        Text("Skaters")
                            .font(.headline)
                        Spacer()
                        Button(checkedIds.count == skaters.count ? "Deselect All" : "Select All") {
                            if checkedIds.count == skaters.count {
                                checkedIds.removeAll()
                            } else {
                                checkedIds = Set(skaters.map(\.persistentModelID))
                            }
                        }
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.teal)
                    }
                    .padding(.horizontal)

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(skaters) { player in
                            let isChecked = checkedIds.contains(player.persistentModelID)
                            Button {
                                if isChecked {
                                    checkedIds.remove(player.persistentModelID)
                                } else {
                                    checkedIds.insert(player.persistentModelID)
                                }
                            } label: {
                                playerCircle(player, checked: isChecked, locked: false)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle("Check In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start Tracking") {
                        if let goalie = selectedGoalie {
                            game.startingGoalie = goalie
                        }
                        var selected = skaters.filter { checkedIds.contains($0.persistentModelID) }
                        if let goalie = selectedGoalie { selected.insert(goalie, at: 0) }
                        onStart(selected)
                    }
                    .fontWeight(.bold)
                    .disabled(checkedIds.isEmpty || selectedGoalieId == nil)
                }
            }
            .onAppear {
                selectedGoalieId = game.startingGoalie?.persistentModelID
            }
        }
    }

    @ViewBuilder
    private func playerCircle(_ player: Player, checked: Bool, locked: Bool) -> some View {
        VStack(spacing: 4) {
            Text(player.number > 0 ? "\(player.number)" : "—")
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .foregroundStyle(checked ? .white : .secondary)
            Text(lastName(player.name))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(checked ? .white.opacity(0.8) : .secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 80)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(checked ? AppTheme.pink : Color(.systemGray5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(locked ? AppTheme.teal : .clear, lineWidth: 2)
        )
    }

    private func lastName(_ name: String) -> String {
        name.components(separatedBy: " ").last ?? name
    }
}
