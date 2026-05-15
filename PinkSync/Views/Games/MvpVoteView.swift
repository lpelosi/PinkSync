import SwiftUI

struct MvpVoteView: View {
    let game: Game
    @Environment(\.dismiss) private var dismiss

    @State private var summary: APIClient.MvpVoteAdminSummary?
    @State private var loadError: String?
    @State private var isLoading = true
    @State private var isClosing = false
    @State private var showingCloseConfirm = false
    @State private var closeError: String?
    @State private var showingCloseError = false
    @State private var isOpening = false
    @State private var showingOpenConfirm = false
    @State private var openError: String?
    @State private var showingOpenError = false
    @State private var openDurationMinutes: Int = 30

    private var isClosed: Bool { summary?.status == "closed" }
    private var isOpen: Bool { summary?.status == "open" }
    private var hasRecord: Bool { summary != nil }

    private struct Tally: Identifiable {
        let playerId: String
        let playerName: String
        let playerNumber: Int
        let votes: Int
        var id: String { playerId }
    }

    private var tallies: [Tally] {
        guard let summary else { return [] }
        let playerLookup: [String: APIClient.MvpVotePlayer] = Dictionary(
            (summary.lineup ?? []).compactMap { player -> (String, APIClient.MvpVotePlayer)? in
                guard let id = player.playerId else { return nil }
                return (id, player)
            },
            uniquingKeysWith: { first, _ in first }
        )

        var counts: [String: Int] = [:]
        for ballot in summary.ballots ?? [] {
            guard let id = ballot.votedForPlayerId else { continue }
            counts[id, default: 0] += 1
        }

        return counts.map { id, votes in
            let player = playerLookup[id]
            return Tally(
                playerId: id,
                playerName: player?.playerName ?? "Unknown",
                playerNumber: player?.playerNumber ?? 0,
                votes: votes
            )
        }.sorted { $0.votes > $1.votes }
    }

    var body: some View {
        List {
            if isLoading && summary == nil {
                Section {
                    HStack {
                        ProgressView()
                        Text("Loading vote...")
                            .foregroundStyle(.secondary)
                    }
                }
            } else if let loadError {
                Section {
                    Label(loadError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            } else if let summary {
                statusSection(summary)

                if isClosed, let winner = summary.finalMvp {
                    winnerSection(winner)
                }

                if isOpen {
                    Section {
                        Button(role: .destructive) {
                            showingCloseConfirm = true
                        } label: {
                            HStack {
                                Spacer()
                                if isClosing {
                                    ProgressView().tint(.white)
                                } else {
                                    Label("Close MVP Voting", systemImage: "lock.fill")
                                        .font(.headline)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 6)
                        }
                        .listRowBackground(AppTheme.pink)
                        .foregroundStyle(.white)
                        .disabled(isClosing)
                    } footer: {
                        Text("Closes voting immediately and locks in the result. This cannot be undone.")
                    }
                } else if isClosed {
                    openVoteSection(label: "Reopen Voting", footer: "Extends the voting window. Existing votes are preserved.")
                }

                Section("Tallies") {
                    if tallies.isEmpty {
                        Text("No votes cast yet.")
                            .foregroundStyle(.secondary)
                            .italic()
                    } else {
                        ForEach(tallies) { tally in
                            HStack {
                                Text(tally.playerNumber > 0 ? "#\(tally.playerNumber)" : "--")
                                    .font(.system(.body, design: .monospaced, weight: .bold))
                                    .foregroundStyle(AppTheme.pink)
                                    .frame(width: 44, alignment: .leading)
                                Text(tally.playerName)
                                Spacer()
                                Text("\(tally.votes) \(tally.votes == 1 ? "Vote" : "Votes")")
                                    .font(.system(.body, design: .monospaced, weight: .semibold))
                            }
                        }
                    }
                }
            } else {
                Section {
                    Text("No MVP vote has been created for this game yet.")
                        .foregroundStyle(.secondary)
                }
                openVoteSection(label: "Open MVP Voting", footer: "Creates a new MVP vote for this game. The vote will run for the duration you select.")
            }
        }
        .navigationTitle("MVP Voting")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
        .task { await pollLoop() }
        .refreshable { await refresh() }
        .alert("Close MVP Voting?", isPresented: $showingCloseConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Close Vote", role: .destructive) {
                Task { await closeVote() }
            }
        } message: {
            Text("This will immediately lock voting and reveal the winner.")
        }
        .alert("Close Failed", isPresented: $showingCloseError) {
            Button("OK") {}
        } message: {
            Text(closeError ?? "Unknown error")
        }
        .alert(isClosed ? "Reopen MVP Voting?" : "Open MVP Voting?", isPresented: $showingOpenConfirm) {
            Button("Cancel", role: .cancel) {}
            Button(isClosed ? "Reopen" : "Open") {
                Task { await openVote() }
            }
        } message: {
            Text(isClosed
                 ? "Voting will be reopened for the selected duration. Existing votes are kept."
                 : "Voting will open for the selected duration. Fans will be able to vote from the website.")
        }
        .alert("Open Failed", isPresented: $showingOpenError) {
            Button("OK") {}
        } message: {
            Text(openError ?? "Unknown error")
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func openVoteSection(label: String, footer: String) -> some View {
        Section {
            Picker("Duration", selection: $openDurationMinutes) {
                Text("15 min").tag(15)
                Text("30 min").tag(30)
                Text("1 hour").tag(60)
                Text("3 hours").tag(180)
                Text("24 hours").tag(60 * 24)
            }

            Button {
                showingOpenConfirm = true
            } label: {
                HStack {
                    Spacer()
                    if isOpening {
                        ProgressView().tint(.white)
                    } else {
                        Label(label, systemImage: "play.circle.fill")
                            .font(.headline)
                    }
                    Spacer()
                }
                .padding(.vertical, 6)
            }
            .listRowBackground(AppTheme.teal)
            .foregroundStyle(.white)
            .disabled(isOpening)
        } footer: {
            Text(footer)
        }
    }

    @ViewBuilder
    private func statusSection(_ summary: APIClient.MvpVoteAdminSummary) -> some View {
        Section("Status") {
            HStack {
                Text("Status")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(summary.status.capitalized)
                    .font(.system(.body, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(statusColor(summary.status).opacity(0.18), in: Capsule())
                    .foregroundStyle(statusColor(summary.status))
            }
            HStack {
                Text("Total Votes Cast")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(summary.votedCount)")
                    .font(.system(.body, design: .monospaced, weight: .semibold))
            }
            if let eligible = summary.totalEligibleCount, eligible > 0 {
                HStack {
                    Text("Eligible Players")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(eligible)")
                        .font(.system(.body, design: .monospaced, weight: .semibold))
                }
            }
        }
    }

    @ViewBuilder
    private func winnerSection(_ winner: APIClient.MvpVoteFinalMvp) -> some View {
        Section("MVP Winner") {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "trophy.fill")
                        .foregroundStyle(AppTheme.pink)
                    Text(winner.playerName ?? "Unknown")
                        .font(.title2.bold())
                    if let number = winner.playerNumber, number > 0 {
                        Text("#\(number)")
                            .font(.system(.title3, design: .monospaced, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }
                if let votes = winner.votes {
                    Text("\(votes) \(votes == 1 ? "Vote" : "Votes")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "open": .green
        case "closed": AppTheme.pink
        default: .gray
        }
    }

    // MARK: - Actions

    private func refresh(silent: Bool = false) async {
        if !silent { isLoading = true }
        if !silent { loadError = nil }
        do {
            summary = try await APIClient.fetchMvpVoteAdminSummary(gameId: game.gameId)
            if silent { loadError = nil }
        } catch {
            if !silent {
                loadError = "Failed to load: \(error.localizedDescription)"
            }
        }
        if !silent { isLoading = false }
    }

    /// Initial load then poll for live updates while voting is open.
    /// Cancellation is handled by `.task` when the view disappears.
    private func pollLoop() async {
        await refresh()
        while !Task.isCancelled {
            let delay: Duration = isOpen ? .seconds(5) : .seconds(30)
            try? await Task.sleep(for: delay)
            if Task.isCancelled { break }
            await refresh(silent: true)
        }
    }

    private func closeVote() async {
        isClosing = true
        do {
            _ = try await APIClient.closeMvpVote(gameId: game.gameId)
            await refresh()
        } catch {
            closeError = error.localizedDescription
            showingCloseError = true
        }
        isClosing = false
    }

    private func openVote() async {
        isOpening = true
        do {
            _ = try await APIClient.openMvpVote(gameId: game.gameId, durationMinutes: openDurationMinutes)
            await refresh()
        } catch {
            openError = error.localizedDescription
            showingOpenError = true
        }
        isOpening = false
    }
}
