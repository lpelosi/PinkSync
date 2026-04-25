import Foundation
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

    var period: GamePeriod = .regulation
    var ourShootoutGoals = 0
    var theirShootoutGoals = 0
    var shootoutRoundNumber = 0
    var isOurShootoutTurn = true

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

    // MARK: - Period Transitions

    func goToOvertime() {
        period = .overtime
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
        let prefix = period == .overtime ? "OT " : ""
        events.append(LiveEvent(emoji: "🏒", description: "\(prefix)\(label) — Shot") {
            stats.shots -= 1
        })
        save()
        fire()
    }

    func recordGoal(scorer: Player, primaryAssist: Player?, secondaryAssist: Player?) {
        let scorerStats = findOrCreatePlayerStats(for: scorer)
        scorerStats.goals += 1
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
        let prefix = period == .overtime ? "OT " : ""
        events.append(LiveEvent(emoji: "🚨", description: "\(prefix)\(label) — GOAL\(assistText)") {
            scorerStats.goals -= 1
            self.game.goalsFor -= 1
            if let a1 = primaryAssist {
                self.findOrCreatePlayerStats(for: a1).assists -= 1
            }
            if let a2 = secondaryAssist {
                self.findOrCreatePlayerStats(for: a2).assists -= 1
            }
        })
        save()
        fire()
    }

    func recordHit(player: Player) {
        let stats = findOrCreatePlayerStats(for: player)
        stats.hits += 1
        let label = playerLabel(player)
        events.append(LiveEvent(emoji: "💥", description: "\(label) — Hit") {
            stats.hits -= 1
        })
        save()
        fire()
    }

    func recordBlock(player: Player) {
        let stats = findOrCreatePlayerStats(for: player)
        stats.blocks += 1
        let label = playerLabel(player)
        events.append(LiveEvent(emoji: "🛡️", description: "\(label) — Block") {
            stats.blocks -= 1
        })
        save()
        fire()
    }

    func recordPenalty(player: Player, type: PenaltyType) {
        let stats = findOrCreatePlayerStats(for: player)
        stats.penaltyMinutes += type.minutes
        let label = playerLabel(player)
        let mins = type.minutes
        events.append(LiveEvent(emoji: "🚫", description: "\(label) — \(type.rawValue) (\(mins) min)") {
            stats.penaltyMinutes -= mins
        })
        save()
        fire()
    }

    func recordShotAgainst() {
        guard let goalie = activeGoalie else { return }
        let stats = findOrCreateGoalieStats(for: goalie)
        stats.shotsAgainst += 1
        let label = playerLabel(goalie)
        let prefix = period == .overtime ? "OT " : ""
        events.append(LiveEvent(emoji: "🧤", description: "\(prefix)Shot Against (\(label))") {
            stats.shotsAgainst -= 1
        })
        save()
        fire()
    }

    func recordGoalAgainst() {
        guard let goalie = activeGoalie else { return }
        let stats = findOrCreateGoalieStats(for: goalie)
        stats.shotsAgainst += 1
        stats.goalsAgainst += 1
        game.goalsAgainst += 1
        let label = playerLabel(goalie)
        let prefix = period == .overtime ? "OT " : ""
        events.append(LiveEvent(emoji: "🚨", description: "\(prefix)GOAL AGAINST (\(label))") {
            stats.shotsAgainst -= 1
            stats.goalsAgainst -= 1
            self.game.goalsAgainst -= 1
        })
        save()
        fire()
    }

    func recordOpponentPenalty(jerseyNumber: String, type: PenaltyType) {
        let num = jerseyNumber.isEmpty ? "?" : jerseyNumber
        events.append(LiveEvent(emoji: "🚫", description: "OPP #\(num) — \(type.rawValue) (\(type.minutes) min)", undoClosure: nil))
        fire()
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
            finalizeGoal(secondaryAssist: nil)
        }
    }

    func goalFlowPickSecondaryAssist(_ player: Player?) {
        finalizeGoal(secondaryAssist: player)
    }

    private func finalizeGoal(secondaryAssist: Player?) {
        guard let scorer = pendingGoalScorer else { return }
        recordGoal(scorer: scorer, primaryAssist: pendingPrimaryAssist, secondaryAssist: secondaryAssist)
        pendingGoalScorer = nil
        pendingPrimaryAssist = nil
        currentAction = nil
    }

    var goalFlowExcludedPlayers: Set<PersistentIdentifier> {
        var excluded = Set<PersistentIdentifier>()
        if let s = pendingGoalScorer { excluded.insert(s.persistentModelID) }
        if let a = pendingPrimaryAssist { excluded.insert(a.persistentModelID) }
        return excluded
    }
}
