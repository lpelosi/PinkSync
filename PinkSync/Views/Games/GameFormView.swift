import SwiftUI
import SwiftData
import PhotosUI

struct GameFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Player.number) private var allPlayers: [Player]
    @Query(sort: \OpponentTeam.name) private var savedTeams: [OpponentTeam]

    @State private var date = Date()
    @State private var opponent = ""
    @State private var location = ""
    @State private var selectedGoalieID: PersistentIdentifier?
    @State private var selectedTeamID: PersistentIdentifier?
    @State private var useCustomOpponent = false

    // Save new team states
    @State private var saveNewTeam = false
    @State private var newTeamPhotoItem: PhotosPickerItem?
    @State private var newTeamLogoData: Data?

    private var goalies: [Player] {
        allPlayers.filter { $0.isGoalie }
    }

    private var selectedTeam: OpponentTeam? {
        savedTeams.first { $0.persistentModelID == selectedTeamID }
    }

    /// The resolved opponent name from either picker or custom input
    private var resolvedOpponent: String {
        useCustomOpponent ? opponent : (selectedTeam?.name ?? "")
    }

    var body: some View {
        Form {
            Section {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                TextField("Location", text: $location)
            }

            Section("Opponent") {
                ForEach(savedTeams) { team in
                    Button {
                        selectedTeamID = team.persistentModelID
                        useCustomOpponent = false
                        opponent = ""
                    } label: {
                        HStack(spacing: 12) {
                            teamLogo(team: team, size: 36)
                            Text(team.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            if !useCustomOpponent && selectedTeamID == team.persistentModelID {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(AppTheme.pink)
                            }
                        }
                    }
                    .tint(.primary)
                }

                // Custom opponent option
                Button {
                    useCustomOpponent = true
                    selectedTeamID = nil
                    saveNewTeam = false
                    newTeamLogoData = nil
                    newTeamPhotoItem = nil
                } label: {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 36, height: 36)
                            .overlay(
                                Image(systemName: "pencil")
                                    .foregroundStyle(.gray)
                            )
                        Text("Other Team")
                            .foregroundStyle(.primary)
                        Spacer()
                        if useCustomOpponent {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(AppTheme.pink)
                        }
                    }
                }
                .tint(.primary)

                if useCustomOpponent {
                    TextField("Team Name", text: $opponent)

                    Toggle("Save team for later", isOn: $saveNewTeam)

                    if saveNewTeam {
                        HStack {
                            if let data = newTeamLogoData,
                               let uiImage = UIImage(data: data) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 44, height: 44)
                                    .clipShape(Circle())
                            }

                            PhotosPicker(
                                selection: $newTeamPhotoItem,
                                matching: .images
                            ) {
                                Label(
                                    newTeamLogoData == nil ? "Add Team Logo" : "Change Logo",
                                    systemImage: "photo"
                                )
                            }

                            if newTeamLogoData != nil {
                                Spacer()
                                Button("Remove", role: .destructive) {
                                    newTeamLogoData = nil
                                    newTeamPhotoItem = nil
                                }
                                .font(.caption)
                            }
                        }
                    }
                }
            }

            Section("Starting Goalie") {
                ForEach(goalies) { goalie in
                    Button {
                        selectedGoalieID = goalie.persistentModelID
                    } label: {
                        HStack {
                            PlayerRow(player: goalie)
                            Spacer()
                            if selectedGoalieID == goalie.persistentModelID {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(AppTheme.pink)
                            }
                        }
                    }
                    .tint(.primary)
                }
            }
        }
        .navigationTitle("New Game")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create") {
                    createGame()
                    dismiss()
                }
                .disabled(resolvedOpponent.isEmpty || selectedGoalieID == nil)
            }
        }
        .onChange(of: newTeamPhotoItem) {
            Task {
                if let data = try? await newTeamPhotoItem?.loadTransferable(type: Data.self) {
                    newTeamLogoData = data
                }
            }
        }
    }

    @ViewBuilder
    private func teamLogo(team: OpponentTeam, size: CGFloat) -> some View {
        if let data = team.logoData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else if let asset = team.logoAsset {
            Image(asset)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: size, height: size)
                .overlay(
                    Text(String(team.name.prefix(1)))
                        .font(.system(size: size * 0.4, weight: .bold))
                        .foregroundStyle(.gray)
                )
        }
    }

    private func createGame() {
        let descriptor = FetchDescriptor<Team>()
        let team = (try? modelContext.fetch(descriptor))?.first

        // Save custom team if requested
        if useCustomOpponent && saveNewTeam && !opponent.isEmpty {
            let newTeam = OpponentTeam(name: opponent, logoData: newTeamLogoData)
            modelContext.insert(newTeam)
        }

        let game = Game(date: date, opponent: resolvedOpponent, location: location)
        game.team = team
        game.startingGoalie = goalies.first { $0.persistentModelID == selectedGoalieID }
        modelContext.insert(game)
        try? modelContext.save()
    }
}
