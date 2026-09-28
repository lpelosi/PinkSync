import SwiftUI

/// Manage seasons from the app: start a new one, flag playoffs, adjust dates.
/// Writes the whole list through `PUT /api/seasons`; the server validates
/// overlaps, a single current season, and seasons still on roster players.
struct SeasonAdminView: View {
    @Environment(SeasonStore.self) private var seasonStore

    @State private var editing: SeasonDraft?
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        List {
            Section {
                ForEach(seasonStore.newestFirst) { season in
                    Button {
                        editing = SeasonDraft(season: season)
                    } label: {
                        seasonRow(season)
                    }
                    .tint(.primary)
                }
            } header: {
                Text("Seasons")
            } footer: {
                Text("Games and scheduled bouts belong to a season by their date. Tap a season to edit it, flag playoffs, or make it the current one.")
            }

            if let current = seasonStore.current, current.playoffsStart == nil {
                Section {
                    Button {
                        Task { await startPlayoffs(current) }
                    } label: {
                        Label("Start Playoffs Today", systemImage: "trophy")
                    }
                    .disabled(isSaving)
                } footer: {
                    Text("Games from today on count as post-season for \(current.label). Stats and records keep regular season and playoffs apart.")
                }
            }

            Section {
                Button {
                    editing = SeasonDraft.new(after: seasonStore.newestFirst.first)
                } label: {
                    Label("Start New Season", systemImage: "plus.circle")
                }
                .disabled(isSaving)
            } footer: {
                Text("A new season becomes current. Roster membership for it is set per player on the Roster tab.")
            }
        }
        .navigationTitle("Seasons")
        .overlay {
            if isSaving {
                ProgressView().tint(AppTheme.pink)
            }
        }
        .sheet(item: $editing) { draft in
            NavigationStack {
                SeasonFormView(draft: draft, seasons: seasonStore.seasons) { updated in
                    await save(updated)
                }
            }
        }
        .alert("Could Not Save", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "An error occurred.")
        }
        .task { await seasonStore.load() }
        .refreshable { await seasonStore.load() }
    }

    private func seasonRow(_ season: Season) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(season.label)
                    .font(.headline)
                Text("\(SeasonDay.display(season.start)) – \(SeasonDay.display(season.end))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let playoffs = season.playoffsStart {
                    Text("Playoffs from \(SeasonDay.display(playoffs))")
                        .font(.caption)
                        .foregroundStyle(.purple)
                }
            }
            Spacer()
            if season.id == seasonStore.current?.id {
                Text("CURRENT")
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

    private func startPlayoffs(_ season: Season) async {
        var updated = season
        updated.playoffsStart = SeasonDay.string(from: Date())
        _ = await save(seasonStore.seasons.map { $0.id == season.id ? updated : $0 })
    }

    /// Send a full list. `updated` already has the edited season merged in.
    private func save(_ updated: [Season]) async -> Bool {
        isSaving = true
        defer { isSaving = false }
        do {
            let accepted = try await APIClient.saveSeasons(updated)
            seasonStore.replace(with: accepted)
            return true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            return false
        }
    }
}

// MARK: - Day helpers

/// Season boundaries are calendar days in the scorekeeper's own time zone,
/// as shown by the date picker.
nonisolated enum SeasonDay {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }

    static func date(from string: String) -> Date {
        formatter.date(from: string) ?? Date()
    }

    static func display(_ string: String) -> String {
        date(from: string).formatted(date: .abbreviated, time: .omitted)
    }
}

// MARK: - Draft

struct SeasonDraft: Identifiable {
    let id: String
    let isNew: Bool
    var label: String
    var start: Date
    var end: Date
    var hasPlayoffs: Bool
    var playoffsStart: Date
    var isCurrent: Bool

    init(season: Season) {
        id = season.id
        isNew = false
        label = season.label
        start = SeasonDay.date(from: season.start)
        end = SeasonDay.date(from: season.end)
        hasPlayoffs = season.playoffsStart != nil
        playoffsStart = season.playoffsStart.map(SeasonDay.date) ?? SeasonDay.date(from: season.end)
        isCurrent = season.isCurrent == true
    }

    /// A new season starting the day after the latest one ends.
    static func new(after latest: Season?) -> SeasonDraft {
        let calendar = Calendar.current
        let start = latest.map { calendar.date(byAdding: .day, value: 1, to: SeasonDay.date(from: $0.end)) ?? Date() } ?? Date()
        let end = calendar.date(byAdding: .month, value: 5, to: start) ?? start
        let year = calendar.component(.year, from: start)
        return SeasonDraft(id: "", label: "\(year) Season", start: start, end: end, isCurrent: true)
    }

    private init(id: String, label: String, start: Date, end: Date, isCurrent: Bool) {
        self.id = id
        isNew = true
        self.label = label
        self.start = start
        self.end = end
        hasPlayoffs = false
        playoffsStart = end
        self.isCurrent = isCurrent
    }

    /// A URL-safe id from the label, unique among `existing`.
    func resolvedId(existing: [Season]) -> String {
        if !isNew { return id }
        let base = label.lowercased()
            .map { $0.isLetter || $0.isNumber ? String($0) : "-" }
            .joined()
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        let slug = base.isEmpty ? "season" : String(base.prefix(30))
        let taken = Set(existing.map(\.id))
        if !taken.contains(slug) { return slug }
        var n = 2
        while taken.contains("\(slug)-\(n)") { n += 1 }
        return "\(slug)-\(n)"
    }

    func season(existing: [Season]) -> Season {
        Season(
            id: resolvedId(existing: existing),
            label: label.trimmingCharacters(in: .whitespaces),
            start: SeasonDay.string(from: start),
            end: SeasonDay.string(from: end),
            isCurrent: isCurrent ? true : nil,
            playoffsStart: hasPlayoffs ? SeasonDay.string(from: playoffsStart) : nil
        )
    }
}

// MARK: - Form

private struct SeasonFormView: View {
    @State var draft: SeasonDraft
    let seasons: [Season]
    /// Receives the full, merged list. Returns whether the save went through.
    let onSave: ([Season]) async -> Bool
    @Environment(\.dismiss) private var dismiss

    @State private var isSaving = false
    @State private var showingDeleteConfirm = false

    private var canSave: Bool {
        !draft.label.trimmingCharacters(in: .whitespaces).isEmpty
            && draft.start <= draft.end
            && (!draft.hasPlayoffs || (draft.playoffsStart >= draft.start && draft.playoffsStart <= draft.end))
    }

    var body: some View {
        Form {
            Section("Season") {
                TextField("Label (e.g. 2027 Spring)", text: $draft.label)
                DatePicker("First day", selection: $draft.start, displayedComponents: .date)
                DatePicker("Last day", selection: $draft.end, displayedComponents: .date)
                if !draft.isNew {
                    LabeledContent("ID", value: draft.id)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle("Playoffs have started", isOn: $draft.hasPlayoffs)
                if draft.hasPlayoffs {
                    DatePicker("First playoff day", selection: $draft.playoffsStart, in: draft.start...draft.end, displayedComponents: .date)
                }
            } footer: {
                Text("Games on or after the first playoff day count as post-season. Nothing recorded before it changes.")
            }

            Section {
                Toggle("Current season", isOn: $draft.isCurrent)
            } footer: {
                Text("The current season is what the site and the app open to. Only one season can be current.")
            }

            if !draft.isNew {
                Section {
                    Button("Delete Season", role: .destructive) {
                        showingDeleteConfirm = true
                    }
                } footer: {
                    Text("Refused while any player is still on the roster for this season. Games keep their dates and fall into the nearest remaining season.")
                }
            }
        }
        .navigationTitle(draft.isNew ? "New Season" : "Edit Season")
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

    private func save() async {
        isSaving = true
        let edited = draft.season(existing: seasons)
        var merged = seasons.filter { $0.id != edited.id }
        if edited.isCurrent == true {
            merged = merged.map { var s = $0; s.isCurrent = nil; return s }
        }
        merged.append(edited)
        if await onSave(merged) {
            dismiss()
        }
        isSaving = false
    }

    private func delete() async {
        isSaving = true
        if await onSave(seasons.filter { $0.id != draft.id }) {
            dismiss()
        }
        isSaving = false
    }
}
