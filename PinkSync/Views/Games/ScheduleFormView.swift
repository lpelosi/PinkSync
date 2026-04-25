import SwiftUI
import SwiftData

struct ScheduleFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \OpponentTeam.name) private var savedTeams: [OpponentTeam]

    @State private var date = Date()
    @State private var time = ""
    @State private var location = ""
    @State private var opponent = ""
    @State private var selectedTeamID: PersistentIdentifier?
    @State private var useCustomOpponent = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showError = false

    var onSaved: ((APIClient.ScheduleEntry) -> Void)?

    private var selectedTeam: OpponentTeam? {
        savedTeams.first { $0.persistentModelID == selectedTeamID }
    }

    private var resolvedOpponent: String {
        useCustomOpponent ? opponent : (selectedTeam?.name ?? "")
    }

    var body: some View {
        Form {
            Section {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                TextField("Time (e.g. 9:00 PM)", text: $time)
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

                Button {
                    useCustomOpponent = true
                    selectedTeamID = nil
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
                }
            }
        }
        .navigationTitle("Schedule Bout")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .disabled(isSaving)
            }
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Add") {
                        Task { await save() }
                    }
                    .disabled(resolvedOpponent.isEmpty)
                }
            }
        }
        .alert("Save Failed", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "An error occurred.")
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

    private func save() async {
        isSaving = true

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: date)

        do {
            let entry = try await APIClient.addScheduleEntry(
                date: dateString,
                opponent: resolvedOpponent,
                location: location,
                time: time
            )
            onSaved?(entry)
            await MainActor.run { dismiss() }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }

        isSaving = false
    }
}
