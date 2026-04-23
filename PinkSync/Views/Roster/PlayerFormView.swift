import SwiftUI
import SwiftData

struct PlayerFormView: View {
    enum Mode {
        case add
        case edit(Player)
    }

    let mode: Mode
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name = ""
    @State private var number = ""
    @State private var position = "Forward"
    @State private var isGoalie = false

    private let positions = ["Goalie", "Defense", "Forward", "Center", "Left Wing", "Right Wing"]

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                TextField("Number", text: $number)
                    .keyboardType(.numberPad)
            }

            Section {
                Picker("Position", selection: $position) {
                    ForEach(positions, id: \.self) { pos in
                        Text(pos).tag(pos)
                    }
                }

                Toggle("Also plays Goalie", isOn: $isGoalie)
            }
        }
        .navigationTitle(isEditing ? "Edit Player" : "Add Player")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save()
                    dismiss()
                }
                .disabled(name.isEmpty)
            }
        }
        .onAppear {
            if case .edit(let player) = mode {
                name = player.name
                number = "\(player.number)"
                position = player.position
                isGoalie = player.isGoalie
            }
        }
    }

    private func save() {
        let num = Int(number) ?? 0

        switch mode {
        case .add:
            // Find the team to associate with
            let descriptor = FetchDescriptor<Team>()
            let team = (try? modelContext.fetch(descriptor))?.first

            let player = Player(
                name: name,
                number: num,
                position: position,
                isGoalie: isGoalie || position == "Goalie"
            )
            player.team = team
            modelContext.insert(player)

        case .edit(let player):
            player.name = name
            player.number = num
            player.position = position
            player.isGoalie = isGoalie || position == "Goalie"
        }

        try? modelContext.save()
    }
}
