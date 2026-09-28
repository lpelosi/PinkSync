import SwiftUI

/// All-time franchise records, as computed by the server across every season.
struct RecordsView: View {
    @State private var records: FranchiseRecords?
    @State private var isLoading = false
    @State private var loadError: String?

    var body: some View {
        List {
            if isLoading && records == nil {
                Section {
                    HStack {
                        ProgressView()
                        Text("Loading records...")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                }
            }

            if let loadError {
                Section {
                    Label(loadError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            }

            if let records {
                recordSection("Single Season", records.season)
                recordSection("Single Game", records.game)
                recordSection("Career", records.career)
                recordSection("Playoffs", records.playoff)
            }
        }
        .navigationTitle("Franchise Records")
        .task { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder
    private func recordSection(_ title: String, _ items: [FranchiseRecords.Record]) -> some View {
        if !items.isEmpty {
            Section(title) {
                ForEach(items) { record in
                    recordRow(record)
                }
            }
        }
    }

    private func recordRow(_ record: FranchiseRecords.Record) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(record.label)
                    .font(.subheadline.weight(.semibold))
                if let player = record.player {
                    Text(holderName(player))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Not yet set")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                if let context = record.context {
                    Text(context)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(record.displayValue)
                    .font(.system(.title3, design: .monospaced, weight: .bold))
                    .foregroundStyle(record.value == nil ? .secondary : AppTheme.pink)
                Text(record.statLabel)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func holderName(_ player: FranchiseRecords.PlayerRef) -> String {
        if let number = player.number, number > 0 {
            return "#\(number) \(player.name)"
        }
        return player.name
    }

    private func load() async {
        isLoading = true
        loadError = nil
        do {
            records = try await APIClient.fetchRecords()
        } catch {
            loadError = "Could not load records: \(error.localizedDescription)"
        }
        isLoading = false
    }
}
