import SwiftUI
import SwiftData

struct GameSummaryView: View {
    let game: Game
    @Environment(\.dismiss) private var dismiss

    private var skaterStats: [GamePlayerStats] {
        game.playerStats
            .filter { $0.player != nil }
            .sorted { ($0.player?.number ?? 0) < ($1.player?.number ?? 0) }
    }

    private var goalieStatsList: [GameGoalieStats] {
        game.goalieStats.filter { $0.player != nil }
    }

    private var hasEvents: Bool {
        !game.events.isEmpty
    }

    private var periods: [Int] {
        let eventPeriods = Set(game.events.map(\.period))
        return eventPeriods.sorted()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                headerSection

                if hasEvents {
                    periodScoringSection
                    shotsByPeriodSection
                    goalDetailsSection
                    penaltyDetailsSection
                }

                if let goalie = game.startingGoalie {
                    goalieSection(goalie)
                }

                if !skaterStats.isEmpty {
                    skaterStatsSection
                }

                if skaterStats.isEmpty && goalieStatsList.isEmpty {
                    ContentUnavailableView(
                        "No Stats Recorded",
                        systemImage: "chart.bar",
                        description: Text("Tap on players in the game to start recording stats")
                    )
                    .padding(.top, 40)
                }
            }
        }
        .navigationTitle("Game Summary")
        .toolbar {
            Button("Done") { dismiss() }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            Text("vs \(game.opponent)")
                .font(.title.bold())
            Text(game.displayDate)
                .foregroundStyle(.secondary)
            if !game.location.isEmpty {
                Text(game.location)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(game.scoreDisplay)
                .font(.system(size: 48, weight: .bold, design: .monospaced))
                .foregroundStyle(AppTheme.pink)

            if let result = game.gameResult {
                Text(result.displayName)
                    .font(.headline)
                    .foregroundStyle(result.isWin ? .green : .red)
            }
        }
        .padding(.top)
    }

    // MARK: - Period Scoring

    private var periodScoringSection: some View {
        let goalsFor = eventCountsByPeriod(type: "goal")
        let goalsAgainst = eventCountsByPeriod(type: "goalAgainst")
        guard !goalsFor.isEmpty || !goalsAgainst.isEmpty else { return AnyView(EmptyView()) }

        return AnyView(
            VStack(spacing: 8) {
                sectionHeader("SCORING BY PERIOD")
                periodGrid(label1: "FF", counts1: goalsFor, label2: "OPP", counts2: goalsAgainst, total1: game.goalsFor, total2: game.goalsAgainst)
            }
            .padding(.horizontal)
        )
    }

    // MARK: - Shots by Period

    private var shotsByPeriodSection: some View {
        let shotsFor = eventCountsByPeriod(type: "shot")
        let shotsAgainst = eventCountsByPeriod(type: "shotAgainst")
        guard !shotsFor.isEmpty || !shotsAgainst.isEmpty else { return AnyView(EmptyView()) }

        let totalFor = shotsFor.values.reduce(0, +)
        let totalAgainst = shotsAgainst.values.reduce(0, +)

        return AnyView(
            VStack(spacing: 8) {
                sectionHeader("SHOTS BY PERIOD")
                periodGrid(label1: "FF", counts1: shotsFor, label2: "OPP", counts2: shotsAgainst, total1: totalFor, total2: totalAgainst)
            }
            .padding(.horizontal)
        )
    }

    // MARK: - Goal Details

    private var goalDetailsSection: some View {
        let goals = game.events.filter { $0.type == "goal" || $0.type == "goalAgainst" }
        guard !goals.isEmpty else { return AnyView(EmptyView()) }

        let grouped = Dictionary(grouping: goals, by: \.period)

        return AnyView(
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("GOAL DETAILS")

                ForEach(grouped.keys.sorted(), id: \.self) { period in
                    Text(periodName(period))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)

                    ForEach(grouped[period]!, id: \.persistentModelID) { event in
                        goalEventRow(event)
                    }
                }
            }
            .padding(.horizontal)
        )
    }

    private func goalEventRow(_ event: GameEvent) -> some View {
        HStack(spacing: 4) {
            if !event.clockTime.isEmpty {
                Text(event.clockTime)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
                Text("—")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            if event.isPowerPlay {
                Text("PP")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.orange, in: Capsule())
            }

            if event.type == "goalAgainst" {
                Text("Opponent Goal")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.teal)
            } else {
                let num = event.playerNumber > 0 ? "#\(event.playerNumber)" : ""
                Text("\(num) \(event.playerName)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppTheme.pink)

                if !event.assist1Name.isEmpty {
                    let a1Num = event.assist1Number > 0 ? "#\(event.assist1Number)" : ""
                    var assistStr = "(A: \(a1Num) \(event.assist1Name)"
                    let _ = {
                        if !event.assist2Name.isEmpty {
                            let a2Num = event.assist2Number > 0 ? "#\(event.assist2Number)" : ""
                            assistStr += ", \(a2Num) \(event.assist2Name)"
                        }
                        assistStr += ")"
                    }()
                    Text(assistStr)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }

    // MARK: - Penalty Details

    private var penaltyDetailsSection: some View {
        let penalties = game.events.filter { $0.type == "penalty" || $0.type == "penaltyAgainst" }
        guard !penalties.isEmpty else { return AnyView(EmptyView()) }

        let grouped = Dictionary(grouping: penalties, by: \.period)

        return AnyView(
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("PENALTIES")

                ForEach(grouped.keys.sorted(), id: \.self) { period in
                    Text(periodName(period))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)

                    ForEach(grouped[period]!, id: \.persistentModelID) { event in
                        penaltyEventRow(event)
                    }
                }
            }
            .padding(.horizontal)
        )
    }

    private func penaltyEventRow(_ event: GameEvent) -> some View {
        HStack(spacing: 4) {
            if !event.clockTime.isEmpty {
                Text(event.clockTime)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
                Text("—")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            if event.type == "penaltyAgainst" {
                let num = event.opponentNumber.isEmpty ? "?" : event.opponentNumber
                Text("OPP #\(num)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppTheme.teal)
            } else {
                let num = event.playerNumber > 0 ? "#\(event.playerNumber)" : ""
                Text("\(num) \(event.playerName)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppTheme.pink)
            }

            if !event.penaltyType.isEmpty {
                Text("- \(event.penaltyType) (\(event.penaltyMinutes) min)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }

    // MARK: - Goalie Section

    private func goalieSection(_ goalie: Player) -> some View {
        VStack(spacing: 8) {
            Text("STARTING GOALIE")
                .font(.system(size: 11, weight: .bold))
                .tracking(1)
                .foregroundStyle(.secondary)

            HStack {
                Text(goalie.displayNumber)
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppTheme.pink)
                Text(goalie.name)
                    .font(.headline)
            }

            if let gs = goalieStatsList.first(where: {
                $0.player?.persistentModelID == goalie.persistentModelID
            }) {
                HStack(spacing: 24) {
                    miniStat("SA", value: "\(gs.shotsAgainst)")
                    miniStat("GA", value: "\(gs.goalsAgainst)")
                    miniStat("SV", value: "\(gs.saves)")
                    miniStat("SV%", value: String(format: "%.3f", gs.savePercentage))
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(AppTheme.pink.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    // MARK: - Skater Stats Table

    private var skaterStatsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SKATER STATS")
                .font(.system(size: 11, weight: .bold))
                .tracking(1)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            HStack(spacing: 0) {
                Text("#").frame(width: 30, alignment: .leading)
                Text("Player").frame(maxWidth: .infinity, alignment: .leading)
                Text("SOG").frame(width: 32)
                Text("G").frame(width: 24)
                Text("A").frame(width: 24)
                Text("PPG").frame(width: 30)
                Text("H").frame(width: 24)
                Text("BLK").frame(width: 30)
                Text("FO%").frame(width: 34)
                Text("PIM").frame(width: 30)
            }
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.secondary)
            .padding(.horizontal)

            Divider()

            ForEach(skaterStats) { stat in
                if let player = stat.player {
                    HStack(spacing: 0) {
                        Text(player.number > 0 ? "\(player.number)" : "--")
                            .frame(width: 30, alignment: .leading)
                        Text(player.name)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(stat.shots)").frame(width: 32)
                        Text("\(stat.goals)").frame(width: 24)
                        Text("\(stat.assists)").frame(width: 24)
                        Text("\(stat.powerPlayGoals)").frame(width: 30)
                        Text("\(stat.hits)").frame(width: 24)
                        Text("\(stat.blocks)").frame(width: 30)
                        Text(stat.totalFaceoffs > 0 ? String(format: "%.0f", stat.faceoffPercentage) : "-").frame(width: 34)
                        Text("\(stat.penaltyMinutes)").frame(width: 30)
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .tracking(1)
            .foregroundStyle(.secondary)
    }

    private func miniStat(_ label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.body, design: .monospaced, weight: .bold))
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
        }
    }

    private func periodName(_ period: Int) -> String {
        switch period {
        case 1: "1st Period"
        case 2: "2nd Period"
        case 3: "3rd Period"
        default: "Overtime"
        }
    }

    private func eventCountsByPeriod(type: String) -> [Int: Int] {
        var counts: [Int: Int] = [:]
        for event in game.events where event.type == type {
            counts[event.period, default: 0] += 1
        }
        return counts
    }

    private func periodGrid(label1: String, counts1: [Int: Int], label2: String, counts2: [Int: Int], total1: Int, total2: Int) -> some View {
        let allPeriods = periods.isEmpty ? [1, 2, 3] : periods

        return VStack(spacing: 4) {
            HStack(spacing: 0) {
                Text("").frame(width: 36, alignment: .leading)
                ForEach(allPeriods, id: \.self) { p in
                    Text(shortPeriodName(p))
                        .frame(width: 36)
                }
                Text("Total")
                    .frame(width: 44)
            }
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.secondary)

            HStack(spacing: 0) {
                Text(label1)
                    .foregroundStyle(AppTheme.pink)
                    .frame(width: 36, alignment: .leading)
                ForEach(allPeriods, id: \.self) { p in
                    Text("\(counts1[p] ?? 0)")
                        .frame(width: 36)
                }
                Text("\(total1)")
                    .fontWeight(.bold)
                    .frame(width: 44)
            }
            .font(.system(size: 13, design: .monospaced))

            HStack(spacing: 0) {
                Text(label2)
                    .foregroundStyle(AppTheme.teal)
                    .frame(width: 36, alignment: .leading)
                ForEach(allPeriods, id: \.self) { p in
                    Text("\(counts2[p] ?? 0)")
                        .frame(width: 36)
                }
                Text("\(total2)")
                    .fontWeight(.bold)
                    .frame(width: 44)
            }
            .font(.system(size: 13, design: .monospaced))
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func shortPeriodName(_ period: Int) -> String {
        switch period {
        case 1: "1st"
        case 2: "2nd"
        case 3: "3rd"
        default: "OT"
        }
    }
}
