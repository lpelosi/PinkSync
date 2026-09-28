import SwiftUI
import SwiftData

/// Manage tournaments from the app: book one, fix its dates, set who is
/// travelling. Writes the whole list through `PUT /api/tournaments`; the
/// server validates it and refuses to drop a tournament that still has games
/// or bouts.
struct TournamentAdminView: View {
    @Environment(TournamentStore.self) private var tournamentStore

    @State private var editing: TournamentDraft?
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        List {
            Section {
                if tournamentStore.tournaments.isEmpty {
                    Text("No tournaments yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(tournamentStore.newestFirst) { tournament in
                    Button {
                        editing = TournamentDraft(tournament: tournament)
                    } label: {
                        tournamentRow(tournament)
                    }
                    .tint(.primary)
                }
            } header: {
                Text("Tournaments")
            } footer: {
                Text("A game belongs to a tournament when it is started from one of the tournament's bouts, or when the tournament is picked on the game. The date alone never decides it, so a league game on the same weekend stays a league game.")
            }

            Section {
                Button {
                    editing = TournamentDraft.new()
                } label: {
                    Label("Book a Tournament", systemImage: "plus.circle")
                }
            } footer: {
                Text("Add its games from the Games tab with Schedule Bout, picking the tournament on each.")
            }
        }
        .navigationTitle("Tournaments")
        .sheet(item: $editing) { draft in
            NavigationStack {
                TournamentFormView(draft: draft, tournaments: tournamentStore.tournaments) { updated in
                    await save(updated)
                }
            }
        }
        .alert("Could Not Save", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "An error occurred.")
        }
        .task { await tournamentStore.load() }
        .refreshable { await tournamentStore.load() }
    }

    private func tournamentRow(_ tournament: Tournament) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(tournament.title)
                    .font(.headline)
                Text("\(SeasonDay.display(tournament.start)) – \(SeasonDay.display(tournament.end))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(rosterSummary(tournament))
                    .font(.caption)
                    .foregroundStyle(tournament.hasRoster ? Color.secondary : Color.orange)
            }
            Spacer()
            if tournament.status == "in-progress" {
                Text("NOW")
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppTheme.pink.opacity(0.15), in: Capsule())
                    .foregroundStyle(AppTheme.pink)
            }
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func rosterSummary(_ tournament: Tournament) -> String {
        let count = tournament.roster?.count ?? 0
        return count == 0 ? "No roster set" : "\(count) on the roster"
    }

    /// Send a full list. `updated` already has the edited tournament merged in.
    private func save(_ updated: [Tournament]) async -> Bool {
        do {
            let accepted = try await APIClient.saveTournaments(updated)
            tournamentStore.replace(with: accepted)
            return true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            return false
        }
    }
}

// MARK: - Draft

struct TournamentDraft: Identifiable {
    let id: String
    let isNew: Bool
    var label: String
    var start: Date
    var end: Date
    var location: String
    var division: String
    /// Carried through untouched; the app has no field for it.
    let url: String?
    /// Player ids, upper-cased the way the server stores them.
    var roster: Set<String>
    /// Who wears a letter, by player id. Only players on the roster.
    var letters: [String: Letter]
    /// The goalies the team is bringing, by player id. Empty leaves it to the
    /// team roster's own goalie flags.
    var goalies: Set<String>

    init(tournament: Tournament) {
        id = tournament.id
        isNew = false
        label = tournament.label
        start = SeasonDay.date(from: tournament.start)
        end = SeasonDay.date(from: tournament.end)
        location = tournament.location ?? ""
        division = tournament.division ?? ""
        url = tournament.url
        roster = Set((tournament.roster ?? []).map { $0.uppercased() })
        var letters: [String: Letter] = [:]
        for playerId in tournament.alternates ?? [] {
            letters[playerId.uppercased()] = .alternate
        }
        if let captain = tournament.captain, !captain.isEmpty {
            letters[captain.uppercased()] = .captain
        }
        self.letters = letters
        goalies = Set((tournament.goalies ?? []).map { $0.uppercased() })
    }

    /// Give a player a letter, or take it away with nil. There is one
    /// captain: naming a new one takes the C from whoever had it.
    mutating func setLetter(_ letter: Letter?, for playerId: String) {
        if letter == .captain {
            for (other, held) in letters where held == .captain {
                letters[other] = nil
            }
        }
        letters[playerId] = letter
    }

    /// Take a player off the roster or put them on it. Leaving the roster
    /// gives up the letter.
    mutating func toggleRoster(_ playerId: String) {
        if roster.contains(playerId) {
            roster.remove(playerId)
            letters[playerId] = nil
            goalies.remove(playerId)
        } else {
            roster.insert(playerId)
        }
    }

    /// A new tournament over the coming weekend.
    static func new(today: Date = Date()) -> TournamentDraft {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: 7, to: today) ?? today
        let end = calendar.date(byAdding: .day, value: 2, to: start) ?? start
        return TournamentDraft(start: start, end: end)
    }

    private init(start: Date, end: Date) {
        id = ""
        isNew = true
        label = ""
        self.start = start
        self.end = end
        location = ""
        division = ""
        url = nil
        roster = []
        letters = [:]
        goalies = []
    }

    /// A URL-safe id from the label and the year, unique among `existing`.
    func resolvedId(existing: [Tournament]) -> String {
        if !isNew { return id }
        let year = SeasonDay.string(from: start).prefix(4)
        let named = label.range(of: #"\b\d{4}\b"#, options: .regularExpression) == nil ? "\(label) \(year)" : label
        let base = named.lowercased()
            .map { $0.isASCII && ($0.isLetter || $0.isNumber) ? String($0) : "-" }
            .joined()
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        let slug = base.count < 2 ? "tournament-\(year)" : String(base.prefix(50))
        let taken = Set(existing.map(\.id))
        if !taken.contains(slug) { return slug }
        var n = 2
        while taken.contains("\(slug)-\(n)") { n += 1 }
        return "\(slug)-\(n)"
    }

    func tournament(existing: [Tournament]) -> Tournament {
        let trimmedLocation = location.trimmingCharacters(in: .whitespaces)
        let trimmedDivision = division.trimmingCharacters(in: .whitespaces)
        let worn = letters.filter { roster.contains($0.key) }
        let alternates = worn.filter { $0.value == .alternate }.keys.sorted()
        let inNet = goalies.filter { roster.contains($0) }.sorted()
        return Tournament(
            id: resolvedId(existing: existing),
            label: label.trimmingCharacters(in: .whitespaces),
            start: SeasonDay.string(from: start),
            end: SeasonDay.string(from: end),
            location: trimmedLocation.isEmpty ? nil : trimmedLocation,
            division: trimmedDivision.isEmpty ? nil : trimmedDivision,
            url: url,
            roster: roster.isEmpty ? nil : roster.sorted(),
            captain: worn.first { $0.value == .captain }?.key,
            alternates: alternates.isEmpty ? nil : alternates,
            goalies: inNet.isEmpty ? nil : inNet
        )
    }
}

// MARK: - Form

private struct TournamentFormView: View {
    @State var draft: TournamentDraft
    let tournaments: [Tournament]
    /// Receives the full, merged list. Returns whether the save went through.
    let onSave: ([Tournament]) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(SeasonStore.self) private var seasonStore
    @Query(sort: \Player.number) private var players: [Player]

    @State private var isSaving = false
    @State private var showingDeleteConfirm = false

    private var canSave: Bool {
        !draft.label.trimmingCharacters(in: .whitespaces).isEmpty && draft.start <= draft.end
    }

    /// Everyone who could travel: active players with an id the server knows.
    private var candidates: [Player] {
        players.filter { $0.isActive && !$0.playerId.isEmpty }
    }

    /// The league roster for the season the tournament falls in.
    private var seasonRosterIds: Set<String> {
        Set(candidates.filter { seasonStore.isOnRoster($0, on: draft.start) }.map { $0.playerId.uppercased() })
    }

    var body: some View {
        Form {
            Section("Tournament") {
                TextField("Name (e.g. Twin Cities Classic)", text: $draft.label)
                DatePicker("First day", selection: $draft.start, displayedComponents: .date)
                DatePicker("Last day", selection: $draft.end, displayedComponents: .date)
                TextField("Location", text: $draft.location)
                TextField("Division (e.g. Level 4)", text: $draft.division)
                if !draft.isNew {
                    LabeledContent("ID", value: draft.id)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("Select the Season Roster") {
                    draft.roster = seasonRosterIds
                    draft.letters = draft.letters.filter { seasonRosterIds.contains($0.key) }
                    draft.goalies = draft.goalies.intersection(seasonRosterIds)
                }
                Button("Clear", role: .destructive) {
                    draft.roster.removeAll()
                    draft.letters.removeAll()
                    draft.goalies.removeAll()
                }
                .disabled(draft.roster.isEmpty)

                ForEach(candidates) { player in
                    let playerId = player.playerId.uppercased()
                    let travelling = draft.roster.contains(playerId)
                    HStack {
                        Button {
                            draft.toggleRoster(playerId)
                        } label: {
                            HStack {
                                Image(systemName: travelling ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(travelling ? AnyShapeStyle(AppTheme.pink) : AnyShapeStyle(.tertiary))
                                PlayerRow(player: player)
                            }
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        if travelling {
                            if draft.goalies.contains(playerId) {
                                Text("G")
                                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                                    .foregroundStyle(.white)
                                    .frame(width: 24, height: 24)
                                    .background(AppTheme.pink, in: RoundedRectangle(cornerRadius: 5))
                                    .accessibilityLabel("Goalie at this tournament")
                            }
                            letterMenu(for: playerId, name: player.name)
                        }
                    }
                }
            } header: {
                Text("Travel Roster (\(draft.roster.count))")
            } footer: {
                Text("Only these players are offered for the tournament's lineups, and only they appear on its roster and stats pages. A pickup has to be added on the Roster tab first. With nobody selected, the roster is whoever plays.\n\nTap the box next to a travelling player to name the captain (C), the alternates (A) and the goalies (G). They are kept for this tournament only. Once a goalie is named, only named goalies are listed as goalies for the tournament; everyone else is listed as a skater, and can still be put in net for a game.")
            }

            if !draft.isNew {
                Section {
                    Button("Delete Tournament", role: .destructive) {
                        showingDeleteConfirm = true
                    }
                } footer: {
                    Text("Refused while the tournament still has games or bouts.")
                }
            }
        }
        .navigationTitle(draft.isNew ? "New Tournament" : "Edit Tournament")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .disabled(isSaving)
            }
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Save") { Task { await save() } }
                        .disabled(!canSave)
                }
            }
        }
        .alert("Delete \(draft.label)?", isPresented: $showingDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { Task { await delete() } }
        }
    }

    /// C, A or no letter for one travelling player.
    private func letterMenu(for playerId: String, name: String) -> some View {
        let held = draft.letters[playerId]
        return Menu {
            ForEach(Letter.allCases) { letter in
                Button {
                    draft.setLetter(letter, for: playerId)
                } label: {
                    if held == letter {
                        Label(letter.label, systemImage: "checkmark")
                    } else {
                        Text(letter.label)
                    }
                }
            }
            if held != nil {
                Button("No Letter", role: .destructive) {
                    draft.setLetter(nil, for: playerId)
                }
            }
            Divider()
            Button {
                if draft.goalies.contains(playerId) {
                    draft.goalies.remove(playerId)
                } else {
                    draft.goalies.insert(playerId)
                }
            } label: {
                if draft.goalies.contains(playerId) {
                    Label("Goalie at This Tournament", systemImage: "checkmark")
                } else {
                    Text("Goalie at This Tournament")
                }
            }
        } label: {
            LetterBadge(letter: held)
        }
        .accessibilityLabel(held.map { "\(name), \($0.label). Change letter or goalie." } ?? "\(name), no letter. Give a letter or name as goalie.")
    }

    private func save() async {
        isSaving = true
        let edited = draft.tournament(existing: tournaments)
        var merged = tournaments.filter { $0.id != edited.id }
        merged.append(edited)
        if await onSave(merged) {
            dismiss()
        }
        isSaving = false
    }

    private func delete() async {
        isSaving = true
        if await onSave(tournaments.filter { $0.id != draft.id }) {
            dismiss()
        }
        isSaving = false
    }
}
