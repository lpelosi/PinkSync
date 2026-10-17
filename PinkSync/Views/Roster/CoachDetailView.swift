import SwiftUI
import SwiftData

/// A staff member's page. A coach has no stat line, so this is the team's
/// record for the view being looked at, the lifetime record, and the beer
/// league split: how the team does when the coach is drinking.
struct CoachDetailView: View {
    let member: StaffMember
    @Environment(SeasonStore.self) private var seasonStore
    @Environment(TournamentStore.self) private var tournamentStore
    @Query(sort: \Game.date, order: .reverse) private var allGames: [Game]
    @State private var seasonId: String

    init(member: StaffMember, selection: String) {
        self.member = member
        _seasonId = State(initialValue: selection)
    }

    private var inView: [Game] {
        TeamRecord.games(allGames, selection: seasonId, seasonStore: seasonStore)
    }

    private var record: TeamRecord { TeamRecord(games: inView) }
    private var lifetime: TeamRecord { TeamRecord(games: allGames) }
    private var drinking: TeamRecord { TeamRecord(games: inView.filter(\.coachWasDrinking)) }
    private var sober: TeamRecord { TeamRecord(games: inView.filter { !$0.coachWasDrinking }) }

    private var viewTitle: String {
        if seasonId == Season.allId { return "All Seasons" }
        if let tournament = tournamentStore.tournament(forSelection: seasonId) { return tournament.title }
        return seasonStore.season(id: seasonId)?.label ?? "Season"
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    CachedPlayerPhoto(url: member.photoURL, size: 80)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(member.name)
                            .font(.title2.bold())
                        Text(member.role)
                            .foregroundStyle(.secondary)
                        Text("Behind the bench")
                            .font(.caption)
                            .foregroundStyle(AppTheme.beer)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                SeasonPicker(seasonId: $seasonId)
            } footer: {
                if seasonId != Season.allId && tournamentStore.tournament(forSelection: seasonId) == nil {
                    Text("League play, regular season and playoffs together. Tournament games count toward lifetime only.")
                }
            }

            Section(viewTitle) {
                statRow("Record", value: record.gamesPlayed > 0 ? record.display : "—")
                statRow("Games", value: "\(record.gamesPlayed)")
                statRow("Points %", value: record.gamesPlayed > 0 ? String(format: "%.3f", record.pointsPercentage) : "—")
                statRow("Goals For", value: "\(record.goalsFor)")
                statRow("Goals Against", value: "\(record.goalsAgainst)")
                statRow("Differential", value: signed(record.goalDifferential))
                statRow("Streak", value: TeamRecord.streak(inView) ?? "—")
            }

            Section("Lifetime") {
                statRow("Record", value: lifetime.gamesPlayed > 0 ? lifetime.display : "—")
                statRow("Games", value: "\(lifetime.gamesPlayed)")
                statRow("Points %", value: lifetime.gamesPlayed > 0 ? String(format: "%.3f", lifetime.pointsPercentage) : "—")
                statRow("Differential", value: signed(lifetime.goalDifferential))
            }

            Section {
                statRow("Games Drinking", value: "\(drinking.gamesPlayed)")
                statRow("Record Drinking", value: drinking.gamesPlayed > 0 ? drinking.display : "—")
                statRow("Record Sober", value: sober.gamesPlayed > 0 ? sober.display : "—")
                if drinking.gamesPlayed > 0 && sober.gamesPlayed > 0 {
                    statRow("Verdict", value: verdict)
                }
            } header: {
                Label("Whiskey and Yelling", systemImage: "mug.fill")
            } footer: {
                Text("Flag the coach on a game's Bench section, or from the live game's Lineup sheet. \(viewTitle) only.")
            }

            Section("About") {
                Text(member.bio)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(member.lastName)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Which version of the coach the team does better under.
    private var verdict: String {
        let gap = drinking.pointsPercentage - sober.pointsPercentage
        if abs(gap) < 0.001 { return "No difference" }
        return gap > 0 ? "Pour him another" : "Cut him off"
    }

    private func signed(_ n: Int) -> String { n > 0 ? "+\(n)" : "\(n)" }

    private func statRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(.body, design: .monospaced, weight: .semibold))
                .multilineTextAlignment(.trailing)
        }
    }
}
