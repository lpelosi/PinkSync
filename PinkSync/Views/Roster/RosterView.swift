import SwiftUI
import SwiftData

struct RosterView: View {
    @Query(sort: \Player.number) private var players: [Player]
    @State private var showingAddPlayer = false

    private var skaters: [Player] {
        players.filter { !$0.isGoalie }
    }

    private var goalies: [Player] {
        players.filter { $0.isGoalie }
    }

    var body: some View {
        List {
            Section("Goalies") {
                ForEach(goalies) { player in
                    NavigationLink(value: player) {
                        PlayerRow(player: player)
                    }
                }
            }

            Section("Skaters") {
                ForEach(skaters) { player in
                    NavigationLink(value: player) {
                        PlayerRow(player: player)
                    }
                }
            }
        }
        .navigationTitle("Roster")
        .navigationDestination(for: Player.self) { player in
            PlayerDetailView(player: player)
        }
        .toolbar {
            Button {
                showingAddPlayer = true
            } label: {
                Image(systemName: "plus")
            }
        }
        .sheet(isPresented: $showingAddPlayer) {
            NavigationStack {
                PlayerFormView(mode: .add)
            }
        }
    }
}
