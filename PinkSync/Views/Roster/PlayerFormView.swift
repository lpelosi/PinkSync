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
    @Query(sort: \Player.number) private var allPlayers: [Player]

    @State private var name = ""
    @State private var number = ""
    @State private var position = "Forward"
    @State private var isGoalie = false

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedPhotoData: Data?
    @State private var existingPhotoURL: URL?

    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var photoLoadError: String?

    private let positions = ["Goalie", "Defense", "Forward", "Center", "Left Wing", "Right Wing"]

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
                        } else if let existingPhotoURL {
                            AsyncImage(url: existingPhotoURL) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                            } placeholder: {
                                Image(systemName: "person.circle.fill")
                                    .resizable()
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 100, height: 100)
                            .clipShape(Circle())
                        } else {
                            Image(systemName: "person.circle.fill")
                                .resizable()
                                .foregroundStyle(.secondary)
                                .frame(width: 100, height: 100)
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
                existingPhotoURL = player.photoURL
            }
        }
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
                   existing.position != position || existing.isGoalie != goalieFlag {
                    playerInfoChanged = true
                }
                existing.name = name
                existing.number = num
                existing.position = position
                existing.isGoalie = goalieFlag
                player = existing
            }

            if let photoData = selectedPhotoData {
                let photoPath = try await APIClient.sendPlayerPhoto(
                    playerId: player.playerId,
                    photoData: photoData
                )
                player.photoPath = photoPath
            }

            if playerInfoChanged {
                try await APIClient.pushRoster(players: allPlayers)
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
