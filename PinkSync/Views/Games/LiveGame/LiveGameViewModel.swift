import SwiftUI
import SwiftData
import UIKit

enum LiveAction: Identifiable {
    case shot, goal, hit, block, penaltyOurs
    case penaltyTheirs

    var id: String {
        switch self {
        case .shot: "shot"
        case .goal: "goal"
        case .hit: "hit"
        case .block: "block"
        case .penaltyOurs: "penaltyOurs"
        case .penaltyTheirs: "penaltyTheirs"
        }
    }
}

enum GoalFlowStep {
    case pickScorer
    case pickPrimaryAssist
    case pickSecondaryAssist
    case enterTime
}

enum GamePeriod: String {
    case regulation = "REG"
    case overtime = "OT"
    case shootout = "SO"
}

enum PenaltyType: String, CaseIterable, Identifiable {
    case minor = "Minor"
    case doubleMinor = "Double Minor"
    case major = "Major"
    case misconduct = "Misconduct"
    case gameMisconduct = "Game Misconduct"

    var id: String { rawValue }

    var minutes: Int {
        switch self {
        case .minor: 2
        case .doubleMinor: 4
        case .major: 5
        case .misconduct: 10
        case .gameMisconduct: 10
        }
    }

    var displayName: String {
        "\(rawValue) (\(minutes) min)"
    }
}

struct LiveEvent: Identifiable {
    let id = UUID()
    let timestamp = Date()
    let emoji: String
    let description: String
    let undoClosure: (() -> Void)?
}

@Observable
final class LiveGameViewModel: Identifiable {
    let id = UUID()
    let game: Game
    let modelContext: ModelContext

    var checkedInPlayers: [Player] = []
    var events: [LiveEvent] = []

    var currentAction: LiveAction?
    var goalFlowStep: GoalFlowStep = .pickScorer
    var pendingGoalScorer: Player?
    var pendingPrimaryAssist: Player?
    var pendingSecondaryAssist: Player?
    var pendingClockTime: String = ""
    var pendingIsPowerPlay: Bool = false

    var period: GamePeriod = .regulation
    var currentPeriod: Int = 1
    var ourShootoutGoals = 0
    var theirShootoutGoals = 0
    var shootoutRoundNumber = 0
    var isOurShootoutTurn = true

    // Quick-repeat
    var lastRecordedPlayer: Player?
    var lastRecordedAction: LiveAction?

    // Line management
    var playerLines: [PersistentIdentifier: Int] = [:]
    var activeLineFilter: Int?

    // Goal flash
    var goalFlashColor: Color?

    private let haptic = UIImpactFeedbackGenerator(style: .medium)

    init(game: Game, modelContext: ModelContext) {
        self.game = game
        self.modelContext = modelContext
        haptic.prepare()
    }

    var activeGoalie: Player? {
        game.startingGoalie
    }

    var skaters: [Player] {
        checkedInPlayers
            .filter { $0.persistentModelID != activeGoalie?.persistentModelID }
            .sorted { $0.number < $1.number }
    }

    var filteredSkaters: [Player] {
        guard let line = activeLineFilter else { return skaters }
        return skaters.filter { playerLines[$0.persistentModelID] == line }
    }

    var configuredLineNumbers: [Int] {
        Array(Set(playerLines.values)).sorted()
    }

    func initializeStatsForCheckedInPlayers() {
        for player in skaters {
            _ = findOrCreatePlayerStats(for: player)
        }
        if let goalie = activeGoalie {
            _ = findOrCreateGoalieStats(for: goalie)
        }
        save()
    }

    var periodLabel: String {
        switch currentPeriod {
        case 1: "1st"
        case 2: "2nd"
        case 3: "3rd"
        default: "OT"
        }
    }

    // MARK: - Find or Create

    func findOrCreatePlayerStats(for player: Player) -> GamePlayerStats {
        if let existing = game.playerStats.first(where: {
            $0.player?.persistentModelID == player.persistentModelID
        }) {
            return existing
        }
        let stats = GamePlayerStats()
        stats.player = player
        stats.game = game
        modelContext.insert(stats)
        return stats
    }

    func findOrCreateGoalieStats(for player: Player) -> GameGoalieStats {
        if let existing = game.goalieStats.first(where: {
            $0.player?.persistentModelID == player.persistentModelID
        }) {
            return existing
        }
        let stats = GameGoalieStats(
            shotsAgainst: 0,
            goalsAgainst: 0,
            result: game.result
        )
        stats.player = player
        stats.game = game
        modelContext.insert(stats)
        return stats
    }

    private func save() {
        try? modelContext.save()
    }

    private func fire() {
        haptic.impactOccurred()
        haptic.prepare()
    }

    func playerLabel(_ player: Player) -> String {
        let name = player.name.components(separatedBy: " ").last ?? player.name
        return "#\(player.number > 0 ? "\(player.number)" : "?") \(name)"
    }

    private func createEvent(
        type: String,
        player: Player? = nil,
        clockTime: String = "",
        assist1: Player? = nil,
        assist2: Player? = nil,
        penaltyMinutes: Int = 0,
        penaltyType: String = "",
        opponentNumber: String = "",
        isPowerPlay: Bool = false
    ) -> GameEvent {
        let event = GameEvent(
            type: type,
            period: currentPeriod,
            clockTime: clockTime,
            playerName: player?.name ?? "",
            playerNumber: player?.number ?? 0,
            assist1Name: assist1?.name ?? "",
            assist1Number: assist1?.number ?? 0,
            assist2Name: assist2?.name ?? "",
            assist2Number: assist2?.number ?? 0,
            penaltyMinutes: penaltyMinutes,
            penaltyType: penaltyType,
            opponentNumber: opponentNumber,
            isPowerPlay: isPowerPlay
        )
        event.game = game
        modelContext.insert(event)
        return event
    }

    // MARK: - Period Transitions

    func endPeriod() {
        events.append(LiveEvent(emoji: "⏱️", description: "— End of \(periodLabel) Period —", undoClosure: nil))
        currentPeriod += 1
        save()
        fire()
    }

    func goToOvertime() {
        period = .overtime
        currentPeriod = 4
        events.append(LiveEvent(emoji: "⏱️", description: "— OVERTIME —", undoClosure: nil))
        save()
        fire()
    }

    func goToShootout() {
        period = .shootout
        ourShootoutGoals = 0
        theirShootoutGoals = 0
        shootoutRoundNumber = 1
        isOurShootoutTurn = true
        events.append(LiveEvent(emoji: "🎯", description: "— SHOOTOUT —", undoClosure: nil))
        save()
        fire()
    }

    // MARK: - Shootout

    func recordShootoutAttempt(player: Player, isGoal: Bool) {
        let label = playerLabel(player)
        if isGoal {
            ourShootoutGoals += 1
            game.goalsFor += 1
            events.append(LiveEvent(emoji: "🎯", description: "SO Rd \(shootoutRoundNumber): \(label) — GOAL!") {
                self.ourShootoutGoals -= 1
                self.game.goalsFor -= 1
            })
        } else {
            events.append(LiveEvent(emoji: "🎯", description: "SO Rd \(shootoutRoundNumber): \(label) — Miss", undoClosure: nil))
        }
        isOurShootoutTurn = false
        save()
        fire()
    }

    func recordShootoutAttemptAgainst(isGoal: Bool) {
        guard let goalie = activeGoalie else { return }
        let goalieStats = findOrCreateGoalieStats(for: goalie)

        let round = ShootoutRound(roundNumber: shootoutRoundNumber, isGoal: isGoal)
        round.goalieStats = goalieStats
        modelContext.insert(round)

        if isGoal {
            theirShootoutGoals += 1
            game.goalsAgainst += 1
            events.append(LiveEvent(emoji: "🎯", description: "SO Rd \(shootoutRoundNumber): Opponent — GOAL") {
                self.theirShootoutGoals -= 1
                self.game.goalsAgainst -= 1
                self.modelContext.delete(round)
            })
        } else {
            let label = playerLabel(goalie)
            events.append(LiveEvent(emoji: "🎯", description: "SO Rd \(shootoutRoundNumber): \(label) — SAVE!") {
                self.modelContext.delete(round)
            })
        }

        isOurShootoutTurn = true
        shootoutRoundNumber += 1
        save()
        fire()
    }

    // MARK: - End Game & Auto Result

    func computeResult() {
        let result: GameResult
        switch period {
        case .regulation:
            result = game.goalsFor > game.goalsAgainst ? .win : .loss
        case .overtime:
            result = game.goalsFor > game.goalsAgainst ? .win : .overtimeLoss
        case .shootout:
            result = game.goalsFor > game.goalsAgainst ? .shootoutWin : .shootoutLoss
        }

        game.result = result.rawValue
        game.isComplete = true

        if let goalie = activeGoalie {
            let goalieStats = findOrCreateGoalieStats(for: goalie)
            goalieStats.result = result.rawValue
        }

        save()
    }

    // MARK: - Record Actions

    func recordShot(player: Player) {
        let stats = findOrCreatePlayerStats(for: player)
        stats.shots += 1
        let label = playerLabel(player)
        let event = createEvent(type: "shot", player: player)
        events.append(LiveEvent(emoji: "🏒", description: "\(periodLabel) \(label) — Shot") {
            stats.shots -= 1
            self.removeGameEvent(event)
        })
        lastRecordedPlayer = player
        lastRecordedAction = .shot
        save()
        fire()
    }

    func recordGoal(scorer: Player, primaryAssist: Player?, secondaryAssist: Player?, clockTime: String = "", isPowerPlay: Bool = false) {
        let scorerStats = findOrCreatePlayerStats(for: scorer)
        scorerStats.goals += 1
        if isPowerPlay { scorerStats.powerPlayGoals += 1 }
        game.goalsFor += 1

        var assistText = ""
        if let a1 = primaryAssist {
            let a1Stats = findOrCreatePlayerStats(for: a1)
            a1Stats.assists += 1
            assistText = " (A: \(playerLabel(a1))"
            if let a2 = secondaryAssist {
                let a2Stats = findOrCreatePlayerStats(for: a2)
                a2Stats.assists += 1
                assistText += ", \(playerLabel(a2))"
            }
            assistText += ")"
        }

        let label = playerLabel(scorer)
        let timeStr = clockTime.isEmpty ? "" : " \(clockTime)"
        let ppStr = isPowerPlay ? " PP" : ""
        let event = createEvent(type: "goal", player: scorer, clockTime: clockTime, assist1: primaryAssist, assist2: secondaryAssist, isPowerPlay: isPowerPlay)
        let wasPP = isPowerPlay
        events.append(LiveEvent(emoji: "🚨", description: "\(periodLabel)\(timeStr) \(label) — GOAL\(ppStr)\(assistText)") {
            scorerStats.goals -= 1
            if wasPP { scorerStats.powerPlayGoals -= 1 }
            self.game.goalsFor -= 1
            if let a1 = primaryAssist {
                self.findOrCreatePlayerStats(for: a1).assists -= 1
            }
            if let a2 = secondaryAssist {
                self.findOrCreatePlayerStats(for: a2).assists -= 1
            }
            self.removeGameEvent(event)
        })
        lastRecordedPlayer = nil
        lastRecordedAction = nil
        triggerGoalFlash(.pink)
        save()
        fire()
    }

    func recordHit(player: Player) {
        let stats = findOrCreatePlayerStats(for: player)
        stats.hits += 1
        let label = playerLabel(player)
        let event = createEvent(type: "hit", player: player)
        events.append(LiveEvent(emoji: "💥", description: "\(periodLabel) \(label) — Hit") {
            stats.hits -= 1
            self.removeGameEvent(event)
        })
        lastRecordedPlayer = player
        lastRecordedAction = .hit
        save()
        fire()
    }

    func recordBlock(player: Player) {
        let stats = findOrCreatePlayerStats(for: player)
        stats.blocks += 1
        let label = playerLabel(player)
        let event = createEvent(type: "block", player: player)
        events.append(LiveEvent(emoji: "🛡️", description: "\(periodLabel) \(label) — Block") {
            stats.blocks -= 1
            self.removeGameEvent(event)
        })
        lastRecordedPlayer = player
        lastRecordedAction = .block
        save()
        fire()
    }

    func recordFaceoff(player: Player, won: Bool) {
        let stats = findOrCreatePlayerStats(for: player)
        if won { stats.faceoffWins += 1 } else { stats.faceoffLosses += 1 }
        let label = playerLabel(player)
        let result = won ? "Won" : "Lost"
        let event = createEvent(type: won ? "faceoffWin" : "faceoffLoss", player: player)
        events.append(LiveEvent(emoji: "🏑", description: "\(periodLabel) \(label) — FO \(result)") {
            if won { stats.faceoffWins -= 1 } else { stats.faceoffLosses -= 1 }
            self.removeGameEvent(event)
        })
        save()
        fire()
    }

    func recordPenalty(player: Player, type: PenaltyType, clockTime: String = "") {
        let stats = findOrCreatePlayerStats(for: player)
        stats.penaltyMinutes += type.minutes
        let label = playerLabel(player)
        let mins = type.minutes
        let timeStr = clockTime.isEmpty ? "" : " \(clockTime)"
        let event = createEvent(type: "penalty", player: player, clockTime: clockTime, penaltyMinutes: type.minutes, penaltyType: type.rawValue)
        events.append(LiveEvent(emoji: "🚫", description: "\(periodLabel)\(timeStr) \(label) — \(type.rawValue) (\(mins) min)") {
            stats.penaltyMinutes -= mins
            self.removeGameEvent(event)
        })
        save()
        fire()
    }

    func recordShotAgainst() {
        guard let goalie = activeGoalie else { return }
        let stats = findOrCreateGoalieStats(for: goalie)
        stats.shotsAgainst += 1
        let label = playerLabel(goalie)
        let event = createEvent(type: "shotAgainst")
        events.append(LiveEvent(emoji: "🧤", description: "\(periodLabel) Shot Against (\(label))") {
            stats.shotsAgainst -= 1
            self.removeGameEvent(event)
        })
        save()
        fire()
    }

    func recordGoalAgainst(clockTime: String = "", isPowerPlay: Bool = false) {
        guard let goalie = activeGoalie else { return }
        let stats = findOrCreateGoalieStats(for: goalie)
        stats.shotsAgainst += 1
        stats.goalsAgainst += 1
        game.goalsAgainst += 1
        let label = playerLabel(goalie)
        let timeStr = clockTime.isEmpty ? "" : " \(clockTime)"
        let ppStr = isPowerPlay ? " PP" : ""
        let event = createEvent(type: "goalAgainst", clockTime: clockTime, isPowerPlay: isPowerPlay)
        events.append(LiveEvent(emoji: "🚨", description: "\(periodLabel)\(timeStr) GOAL AGAINST\(ppStr) (\(label))") {
            stats.shotsAgainst -= 1
            stats.goalsAgainst -= 1
            self.game.goalsAgainst -= 1
            self.removeGameEvent(event)
        })
        triggerGoalFlash(.teal)
        save()
        fire()
    }

    func recordOpponentPenalty(jerseyNumber: String, type: PenaltyType, clockTime: String = "") {
        let num = jerseyNumber.isEmpty ? "?" : jerseyNumber
        let timeStr = clockTime.isEmpty ? "" : " \(clockTime)"
        let event = createEvent(type: "penaltyAgainst", clockTime: clockTime, penaltyMinutes: type.minutes, penaltyType: type.rawValue, opponentNumber: jerseyNumber)
        events.append(LiveEvent(emoji: "🚫", description: "\(periodLabel)\(timeStr) OPP #\(num) — \(type.rawValue) (\(type.minutes) min)") {
            self.removeGameEvent(event)
        })
        save()
        fire()
    }

    private func removeGameEvent(_ event: GameEvent) {
        modelContext.delete(event)
        try? modelContext.save()
    }

    func undoLast() {
        guard let last = events.last, last.undoClosure != nil else { return }
        last.undoClosure?()
        events.removeLast()
        save()
        haptic.impactOccurred()
        haptic.prepare()
    }

    // MARK: - Goal Flow

    func startGoalFlow() {
        goalFlowStep = .pickScorer
        pendingGoalScorer = nil
        pendingPrimaryAssist = nil
        pendingSecondaryAssist = nil
        pendingClockTime = ""
        pendingIsPowerPlay = false
        currentAction = .goal
    }

    func goalFlowPickScorer(_ player: Player) {
        pendingGoalScorer = player
        goalFlowStep = .pickPrimaryAssist
    }

    func goalFlowPickPrimaryAssist(_ player: Player?) {
        if let player {
            pendingPrimaryAssist = player
            goalFlowStep = .pickSecondaryAssist
        } else {
            pendingPrimaryAssist = nil
            goalFlowStep = .enterTime
        }
    }

    func goalFlowPickSecondaryAssist(_ player: Player?) {
        pendingSecondaryAssist = player
        goalFlowStep = .enterTime
    }

    func finalizeGoalWithTime() {
        guard let scorer = pendingGoalScorer else { return }
        recordGoal(scorer: scorer, primaryAssist: pendingPrimaryAssist, secondaryAssist: pendingSecondaryAssist, clockTime: pendingClockTime, isPowerPlay: pendingIsPowerPlay)
        pendingGoalScorer = nil
        pendingPrimaryAssist = nil
        pendingSecondaryAssist = nil
        pendingClockTime = ""
        pendingIsPowerPlay = false
        currentAction = nil
    }

    var goalFlowExcludedPlayers: Set<PersistentIdentifier> {
        var excluded = Set<PersistentIdentifier>()
        if let s = pendingGoalScorer { excluded.insert(s.persistentModelID) }
        if let a = pendingPrimaryAssist { excluded.insert(a.persistentModelID) }
        return excluded
    }

    // MARK: - Delete Any Event

    func deleteEvent(at index: Int) {
        guard events.indices.contains(index) else { return }
        let event = events[index]
        event.undoClosure?()
        events.remove(at: index)
        save()
        haptic.impactOccurred()
        haptic.prepare()
    }

    // MARK: - Goal Flash

    private func triggerGoalFlash(_ color: Color) {
        goalFlashColor = color
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.6))
            goalFlashColor = nil
        }
    }

    // MARK: - Period Summary

    struct PeriodSummaryData {
        let period: String
        let shotsFor: Int
        let shotsAgainst: Int
        let goalsFor: Int
        let goalsAgainst: Int
        let penalties: Int
        let faceoffWins: Int
        let faceoffLosses: Int
    }

    func currentPeriodSummary() -> PeriodSummaryData {
        let periodEvents = game.events.filter { $0.period == currentPeriod }
        return PeriodSummaryData(
            period: periodLabel,
            shotsFor: periodEvents.filter { $0.type == "shot" }.count,
            shotsAgainst: periodEvents.filter { $0.type == "shotAgainst" || $0.type == "goalAgainst" }.count,
            goalsFor: periodEvents.filter { $0.type == "goal" }.count,
            goalsAgainst: periodEvents.filter { $0.type == "goalAgainst" }.count,
            penalties: periodEvents.filter { $0.type == "penalty" || $0.type == "penaltyAgainst" }.count,
            faceoffWins: periodEvents.filter { $0.type == "faceoffWin" }.count,
            faceoffLosses: periodEvents.filter { $0.type == "faceoffLoss" }.count
        )
    }

    // MARK: - Quick Repeat

    var quickRepeatLabel: String? {
        guard let player = lastRecordedPlayer, let action = lastRecordedAction else { return nil }
        let actionName: String
        switch action {
        case .shot: actionName = "Shot"
        case .hit: actionName = "Hit"
        case .block: actionName = "Block"
        default: return nil
        }
        return "\(actionName) — \(playerLabel(player))"
    }

    func executeQuickRepeat() {
        guard let player = lastRecordedPlayer, let action = lastRecordedAction else { return }
        switch action {
        case .shot: recordShot(player: player)
        case .hit: recordHit(player: player)
        case .block: recordBlock(player: player)
        default: break
        }
    }
}
