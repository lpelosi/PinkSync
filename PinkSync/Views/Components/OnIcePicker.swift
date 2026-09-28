import SwiftUI
import SwiftData

/// Pick which skaters were on the ice for a goal. Shared by goal entry, goal
/// against entry, the live feed editor and the post-game editor, so fixing
/// who gets the +/- looks and works the same everywhere.
///
/// `required` players (the scorer and assists) are always on the ice — a
/// player can't score or assist from the bench — so they show locked on.
struct OnIcePicker: View {
    let players: [Player]
    @Binding var selection: Set<PersistentIdentifier>
    var required: Set<PersistentIdentifier> = []
    var jerseyText: (Player) -> String = { $0.jerseyText }
    var title = "ON ICE FOR THIS GOAL"

    private let columns = [GridItem(.adaptive(minimum: 62), spacing: 8)]

    private var count: Int { selection.union(required).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(count) skater\(count == 1 ? "" : "s")")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(count == 0 || count > 5 ? .orange : .secondary)
                if selection.subtracting(required).isEmpty == false {
                    Button("Clear") { selection = [] }
                        .font(.caption)
                        .foregroundStyle(AppTheme.teal)
                }
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(players) { player in
                    tile(player)
                }
            }

            Text(hint)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var hint: String {
        if count > 5 {
            return "More than 5 skaters selected — double-check. Tap a number to take them off."
        }
        return "Tap numbers to fix who was on. They get the +/- (none on a power-play goal). Scorer and assists are always on."
    }

    private func tile(_ player: Player) -> some View {
        let id = player.persistentModelID
        let isRequired = required.contains(id)
        let isOn = isRequired || selection.contains(id)
        return Button {
            guard !isRequired else { return }
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
        } label: {
            VStack(spacing: 1) {
                HStack(spacing: 2) {
                    Text(jerseyText(player))
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                    if isRequired {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 8))
                    }
                }
                Text(player.lastName)
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(isOn ? .white : .primary)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(isOn ? AppTheme.pink : Color(.systemGray5), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(player.name), \(isOn ? "on ice" : "not on ice")\(isRequired ? ", scorer or assist" : "")")
    }
}
