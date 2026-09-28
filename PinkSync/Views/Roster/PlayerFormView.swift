import SwiftUI
import SwiftData
import PhotosUI
import UIKit

/// Wrapper for reliable image data loading from PhotosPicker.
struct PickedPhoto: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
            // Validate we can create a UIImage from the data
            guard UIImage(data: data) != nil else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return PickedPhoto(data: data)
        }
    }
}

struct PlayerFormView: View {
    enum Mode {
        case add
        case edit(Player)
    }

    let mode: Mode
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SeasonStore.self) private var seasonStore
    @Environment(AuthManager.self) private var authManager

    /// Photographers open this form to set a photo; the server rejects any
    /// other change from them, so those fields are read-only for them.
    private var canEditDetails: Bool { authManager.canEditRoster }

    @State private var name = ""
    @State private var number = ""
    @State private var position = "Forward"
    @State private var isGoalie = false
    @State private var isSubstitute = false

    /// Seasons the player is on the roster for. Starts from the server's
    /// membership; a player with none set is shown as on every season.
    @State private var selectedSeasonIds: Set<String> = []
    @State private var initialSeasonIds: Set<String> = []
    @State private var seasonsPrepared = false

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedPhotoData: Data?
    @State private var existingPhotoURL: URL?

    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var photoLoadError: String?

    private let positions = ["Goalie", "Defense", "Left Defense", "Right Defense", "Forward", "Center", "Left Wing", "Right Wing"]

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    var body: some View {
        Form {
            // Photo section
            Section {
                HStack {
                    Spacer()
                    ZStack {
                        if let selectedPhotoData,
                           let uiImage = UIImage(data: selectedPhotoData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 100, height: 100)
                                .clipShape(Circle())
                        } else {
                            CachedPlayerPhoto(url: existingPhotoURL, size: 100)
                        }
                    }
                    Spacer()
                }
                .listRowBackground(Color.clear)

                if let photoLoadError {
                    Text(photoLoadError)
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                PhotosPicker(
                    selection: $selectedPhotoItem,
                    matching: .images,
                    preferredItemEncoding: .compatible
                ) {
                    Label("Choose Photo", systemImage: "photo")
                }
                .onChange(of: selectedPhotoItem) { _, newItem in
                    guard let newItem else { return }
                    photoLoadError = nil
                    Task {
                        do {
                            if let photo = try await newItem.loadTransferable(type: PickedPhoto.self) {
                                selectedPhotoData = photo.data
                            } else {
                                photoLoadError = "Could not read photo data"
                            }
                        } catch {
                            photoLoadError = "Photo load failed: \(error.localizedDescription)"
                        }
                    }
                }
            }

            Section {
                TextField("Name", text: $name)
                TextField("Number", text: $number)
                    .keyboardType(.numberPad)
            } footer: {
                if !canEditDetails {
                    Text("Only roster managers and admins can change player details. You can update the photo.")
                }
            }
            .disabled(!canEditDetails)

            Section {
                Picker("Position", selection: $position) {
                    ForEach(positions, id: \.self) { pos in
                        Text(pos).tag(pos)
                    }
                }

                Toggle("Also plays Goalie", isOn: $isGoalie)
            }
            .disabled(!canEditDetails)

            Section {
                Toggle("Substitute Player", isOn: $isSubstitute)
            } footer: {
                Text("Subs don't have a permanent jersey number — they wear another player's jersey on a game-by-game basis. Their existing stats are preserved.")
            }
            .disabled(!canEditDetails)

            Section {
                ForEach(seasonStore.newestFirst) { season in
                    Toggle(seasonTitle(season), isOn: seasonToggle(season.id))
                }
            } header: {
                Text("Seasons")
            } footer: {
                Text("Which seasons this player appears on the roster for. Their stats from other seasons are kept either way.")
            }
            .disabled(!canEditDetails)
        }
        .navigationTitle(isEditing ? "Edit Player" : "Add Player")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .disabled(isSaving)
            }
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
        .alert("Save Failed", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "An error occurred.")
        }
        .onAppear {
            if case .edit(let player) = mode {
                name = player.name
                number = "\(player.number)"
                position = player.position
                isGoalie = player.isGoalie
                isSubstitute = player.isSubstitute
                existingPhotoURL = player.photoURL
            }
            prepareSeasons()
        }
    }

    // MARK: - Seasons

    private func seasonTitle(_ season: Season) -> String {
        season.id == seasonStore.current?.id ? "\(season.label) (Current)" : season.label
    }

    private func seasonToggle(_ seasonId: String) -> Binding<Bool> {
        Binding(
            get: { selectedSeasonIds.contains(seasonId) },
            set: { isOn in
                if isOn { selectedSeasonIds.insert(seasonId) } else { selectedSeasonIds.remove(seasonId) }
            }
        )
    }

    private func prepareSeasons() {
        guard !seasonsPrepared else { return }
        seasonsPrepared = true
        let everySeason = Set(seasonStore.seasons.map(\.id))
        switch mode {
        case .add:
            // A new player joins the season being played now.
            selectedSeasonIds = Set([seasonStore.current?.id].compactMap { $0 })
            initialSeasonIds = []
        case .edit(let player):
            selectedSeasonIds = player.seasonIds.map(Set.init) ?? everySeason
            initialSeasonIds = selectedSeasonIds
        }
    }

    /// The membership to store, in season order. Nil when an existing player
    /// with no membership set was left untouched, so the server keeps treating
    /// them as on every season rather than being pinned to today's list.
    private func resolvedSeasonIds(for player: Player) -> [String]? {
        if player.seasonIds == nil, case .edit = mode, selectedSeasonIds == initialSeasonIds {
            return nil
        }
        // Seasons this device doesn't know about (the season list failed to
        // load, or a newer app added one) have no toggle here, so they can't
        // have been changed — keep them rather than silently dropping them.
        return Season.membership(selected: selectedSeasonIds, known: seasonStore.seasons, previous: player.seasonIds)
    }

    private func save() async {
        isSaving = true
        let num = Int(number) ?? 0

        do {
            let player: Player
            var playerInfoChanged = false

            switch mode {
            case .add:
                player = Player(
                    name: name,
                    number: num,
                    position: position,
                    isGoalie: isGoalie || position == "Goalie"
                )
                player.playerId = UUID().uuidString.uppercased()
                player.isSubstitute = isSubstitute
                let teamDescriptor = FetchDescriptor<Team>(
                    predicate: #Predicate { $0.name == "Frozen Flamingos" }
                )
                if let team = try? modelContext.fetch(teamDescriptor).first {
                    player.team = team
                }
                modelContext.insert(player)
                playerInfoChanged = true

            case .edit(let existing):
                let goalieFlag = isGoalie || position == "Goalie"
                if existing.name != name || existing.number != num ||
                   existing.position != position || existing.isGoalie != goalieFlag ||
                   existing.isSubstitute != isSubstitute ||
                   selectedSeasonIds != initialSeasonIds {
                    playerInfoChanged = true
                }
                existing.name = name
                existing.number = num
                existing.position = position
                existing.isGoalie = goalieFlag
                existing.isSubstitute = isSubstitute
                player = existing
            }

            if let seasonIds = resolvedSeasonIds(for: player) {
                player.seasonIds = seasonIds
            }

            if let photoData = selectedPhotoData {
                let photoPath = try await APIClient.sendPlayerPhoto(
                    playerId: player.playerId,
                    photoData: photoData
                )
                player.photoPath = photoPath
            }

            if playerInfoChanged && canEditDetails {
                try await APIClient.savePlayer(player)
            }

            try modelContext.save()
            await MainActor.run { dismiss() }
        } catch {
            if case .add = mode {
                modelContext.rollback()
            }
            errorMessage = "Could not save to server: \(error.localizedDescription)"
            showError = true
        }

        isSaving = false
    }
}
