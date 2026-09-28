import SwiftUI
import SwiftData
import PhotosUI

/// Every team and its logo, with a way to replace one. Logos live on the
/// website; a replacement made here is uploaded and reaches every device.
struct TeamLogosView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \OpponentTeam.name) private var teams: [OpponentTeam]

    @State private var pickedItem: PhotosPickerItem?
    @State private var teamBeingChanged: OpponentTeam?
    @State private var showingPicker = false
    @State private var isSyncing = false
    @State private var uploadingTeamID: PersistentIdentifier?
    @State private var message: String?
    @State private var showingMessage = false

    var body: some View {
        List {
            Section {
                ForEach(teams) { team in
                    Button {
                        teamBeingChanged = team
                        showingPicker = true
                    } label: {
                        HStack(spacing: 12) {
                            TeamLogoView(team: team, size: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(team.name)
                                    .foregroundStyle(.primary)
                                Text(status(of: team))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if uploadingTeamID == team.persistentModelID {
                                ProgressView()
                            } else {
                                Text("Replace")
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.pink)
                            }
                        }
                    }
                    .tint(.primary)
                    .disabled(uploadingTeamID != nil)
                }
            } footer: {
                Text("Pull down to fetch the latest logos from the website.")
            }
        }
        .navigationTitle("Team Logos")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if teams.isEmpty {
                ContentUnavailableView("No Teams Yet", systemImage: "photo.on.rectangle.angled", description: Text("Teams appear here once a game has been set up or the website has a logo for one."))
            }
        }
        .photosPicker(isPresented: $showingPicker, selection: $pickedItem, matching: .images)
        .onChange(of: pickedItem) {
            guard let item = pickedItem, let team = teamBeingChanged else { return }
            pickedItem = nil
            Task { await replaceLogo(of: team, with: item) }
        }
        .refreshable {
            await TeamLogoSync.sync(modelContext: modelContext)
        }
        .task {
            await TeamLogoSync.sync(modelContext: modelContext)
        }
        .alert("Team Logo", isPresented: $showingMessage) {
            Button("OK") {}
        } message: {
            Text(message ?? "")
        }
    }

    private func status(of team: OpponentTeam) -> String {
        if team.logoNeedsUpload { return "Changed here, not on the website yet" }
        if team.logoVersion != nil { return "From the website" }
        if team.logoData != nil || team.logoAsset != nil { return "On this device only" }
        return "No logo"
    }

    private func replaceLogo(of team: OpponentTeam, with item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self), UIImage(data: data) != nil else {
            message = "That picture could not be read. Try another one."
            showingMessage = true
            return
        }
        uploadingTeamID = team.persistentModelID
        let sent = await TeamLogoSync.setLogo(data, for: team, modelContext: modelContext)
        uploadingTeamID = nil
        if !sent {
            message = "The logo is changed on this device but did not reach the website. It will be sent again the next time the app syncs."
            showingMessage = true
        }
    }
}
