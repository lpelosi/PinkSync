import SwiftUI
import SwiftData

struct StatsView: View {
    @Query(sort: \Player.number) private var players: [Player]

    @State private var skaterSortKey = "P"
    @State private var goalieSortKey = "W"

    private var skaters: [Player] {
        let filtered = players.filter { !$0.isGoalie }
        return sortSkaters(filtered)
    }

    private var goalies: [Player] {
        let filtered = players.filter { $0.isGoalie }
        return sortGoalies(filtered)
    }

    var body: some View {
        List {
            Section("Skaters") {
                // Header
                skaterHeader

                ForEach(skaters) { player in
                    skaterRow(player)
                }
            }

            Section("Goalies") {
                goalieHeader

                ForEach(goalies) { player in
                    goalieRow(player)
                }
            }
        }
        .navigationTitle("Stats")
        .listStyle(.plain)
    }

    // MARK: - Skater Table

    private var skaterHeader: some View {
        HStack(spacing: 0) {
            Text("#").frame(width: 30, alignment: .leading)
            Text("Name").frame(maxWidth: .infinity, alignment: .leading)
            sortableHeader("GP", width: 32, key: "GP", isSkater: true)
            sortableHeader("G", width: 28, key: "G", isSkater: true)
            sortableHeader("A", width: 28, key: "A", isSkater: true)
            sortableHeader("P", width: 28, key: "P", isSkater: true)
            sortableHeader("SOG", width: 36, key: "SOG", isSkater: true)
            sortableHeader("PIM", width: 36, key: "PIM", isSkater: true)
        }
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(.secondary)
    }

    private func skaterRow(_ player: Player) -> some View {
        HStack(spacing: 0) {
            Text(player.number > 0 ? "\(player.number)" : "--")
                .frame(width: 30, alignment: .leading)
            Text(player.name)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(player.gamesPlayed)").frame(width: 32)
            Text("\(player.totalGoals)").frame(width: 28)
            Text("\(player.totalAssists)").frame(width: 28)
            Text("\(player.totalPoints)").frame(width: 28)
            Text("\(player.totalShots)").frame(width: 36)
            Text("\(player.totalPenaltyMinutes)").frame(width: 36)
        }
        .font(.system(size: 12, design: .monospaced))
    }

    // MARK: - Goalie Table

    private var goalieHeader: some View {
        HStack(spacing: 0) {
            Text("#").frame(width: 30, alignment: .leading)
            Text("Name").frame(maxWidth: .infinity, alignment: .leading)
            sortableHeader("GP", width: 32, key: "GP", isSkater: false)
            sortableHeader("W", width: 28, key: "W", isSkater: false)
            sortableHeader("L", width: 28, key: "L", isSkater: false)
            sortableHeader("OTL", width: 32, key: "OTL", isSkater: false)
            sortableHeader("GAA", width: 40, key: "GAA", isSkater: false)
            sortableHeader("SV%", width: 44, key: "SV%", isSkater: false)
        }
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(.secondary)
    }

    private func goalieRow(_ player: Player) -> some View {
        HStack(spacing: 0) {
            Text(player.number > 0 ? "\(player.number)" : "--")
                .frame(width: 30, alignment: .leading)
            Text(player.name)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(player.goalieGameStats.count)").frame(width: 32)
            Text("\(player.wins)").frame(width: 28)
            Text("\(player.losses)").frame(width: 28)
            Text("\(player.overtimeLosses)").frame(width: 32)
            Text(String(format: "%.2f", player.goalsAgainstAverage)).frame(width: 40)
            Text(String(format: "%.3f", player.savePercentage)).frame(width: 44)
        }
        .font(.system(size: 12, design: .monospaced))
    }

    // MARK: - Sorting

    private func sortableHeader(_ title: String, width: CGFloat, key: String, isSkater: Bool) -> some View {
        Button {
            if isSkater { skaterSortKey = key } else { goalieSortKey = key }
        } label: {
            Text(title)
                .foregroundStyle((isSkater ? skaterSortKey : goalieSortKey) == key ? AppTheme.pink : .secondary)
                .frame(width: width)
        }
        .buttonStyle(.plain)
    }

    private func sortSkaters(_ players: [Player]) -> [Player] {
        players.sorted { a, b in
            switch skaterSortKey {
            case "GP": a.gamesPlayed > b.gamesPlayed
            case "G": a.totalGoals > b.totalGoals
            case "A": a.totalAssists > b.totalAssists
            case "P": a.totalPoints > b.totalPoints
            case "SOG": a.totalShots > b.totalShots
            case "PIM": a.totalPenaltyMinutes > b.totalPenaltyMinutes
            default: a.totalPoints > b.totalPoints
            }
        }
    }

    private func sortGoalies(_ players: [Player]) -> [Player] {
        players.sorted { a, b in
            switch goalieSortKey {
            case "GP": a.goalieGameStats.count > b.goalieGameStats.count
            case "W": a.wins > b.wins
            case "L": a.losses > b.losses
            case "OTL": a.overtimeLosses > b.overtimeLosses
            case "GAA": a.goalsAgainstAverage < b.goalsAgainstAverage
            case "SV%": a.savePercentage > b.savePercentage
            default: a.wins > b.wins
            }
        }
    }
}
