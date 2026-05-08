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

struct ActivePenalty: Identifiable {
    let id = UUID()
    let playerName: String
    let playerNumber: Int
    let isOurs: Bool
    let type: PenaltyType
    let totalSeconds: Int
    var remainingSeconds: Int

    var display: String {
        let mins = remainingSeconds / 60
        let secs = remainingSeconds % 60
        return "#\(playerNumber > 0 ? "\(playerNumber)" : "?") \(mins):\(String(format: "%02d", secs))"
    }
}

struct LiveEvent: Identifiable {
    let id = UUID()
    let timestamp = Date()
    let emoji: String
    let description: String
    let undoClosure: (() -> Void)?
    var gameEvent: GameEvent?
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
    var pendingGoalStrength: Int = 0 // 0=ES, 1=PP, 2=SH

    var period: GamePeriod = .regulation
    var currentPeriod: Int = 1
    var ourShootoutGoals = 0
    var theirShootoutGoals = 0
    var shootoutRoundNumber = 0
    var isOurShootoutTurn = true

    // Quick-repeat
    var lastRecordedPlayer: Player?
    var lastRecordedAction: LiveAction?

    // Line management (values: "F1"-"F4" for forward lines, "D1"-"D3" for defense pairings)
    var playerLines: [PersistentIdentifier: String] = [:]
    var activeLineFilter: String?

    // Goal flash
    var goalFlashColor: Color?

    // Game clock
    var periodLengthMinutes: Int = 15
    var clockSeconds: Int = 0
    var clockRunning: Bool = false
    var isClockSetUp: Bool = false
    private var clockTask: Task<Void, Never>?

    // Active penalties
    var activePenalties: [ActivePenalty] = []

    // On-ice tracking
    var onIcePlayers: Set<PersistentIdentifier> = []
    var playerTOI: [PersistentIdentifier: Int] = [:]
    var currentShiftSeconds: [PersistentIdentifier: Int] = [:]
    var shiftStartClockTime: [PersistentIdentifier: String] = [:]

    // Game position assignment (C, LW, RW, LD, RD)
    var playerGamePosition: [PersistentIdentifier: String] = [:]

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

    var configuredForwardLines: [String] {
        Array(Set(playerLines.values.filter { $0.hasPrefix("F") })).sorted()
    }

    var configuredDefensePairings: [String] {
        Array(Set(playerLines.values.filter { $0.hasPrefix("D") })).sorted()
    }

    var hasLinesConfigured: Bool {
        !configuredForwardLines.isEmpty || !configuredDefensePairings.isEmpty
    }

    // MARK: - On Ice

    private static let positionOrder = ["LW": 0, "C": 1, "RW": 2, "LD": 3, "RD": 4]

    var onIceSkatersSorted: [Player] {
        let goalieId = activeGoalie?.persistentModelID
        return checkedInPlayers
            .filter { onIcePlayers.contains($0.persistentModelID) && $0.persistentModelID != goalieId }
            .sorted { a, b in
                let posA = Self.positionOrder[playerGamePosition[a.persistentModelID] ?? ""] ?? 5
                let posB = Self.positionOrder[playerGamePosition[b.persistentModelID] ?? ""] ?? 5
                if posA != posB { return posA < posB }
                return a.number < b.number
            }
    }

    func positionLabel(for player: Player) -> String {
        playerGamePosition[player.persistentModelID] ?? ""
    }

    var benchPlayers: [Player] {
        let goalieId = activeGoalie?.persistentModelID
        return checkedInPlayers
            .filter { !onIcePlayers.contains($0.persistentModelID) && $0.persistentModelID != goalieId }
            .sorted { $0.number < $1.number }
    }

    func putPlayerOnIce(_ player: Player) {
        onIcePlayers.insert(player.persistentModelID)
        currentShiftSeconds[player.persistentModelID] = 0
        shiftStartClockTime[player.persistentModelID] = currentClockTime
    }

    func takePlayerOffIce(_ player: Player) {
        closeShift(for: player)
        onIcePlayers.remove(player.persistentModelID)
        currentShiftSeconds.removeValue(forKey: player.persistentModelID)
        shiftStartClockTime.removeValue(forKey: player.persistentModelID)
    }

    func swapPlayer(on incoming: Player, off outgoing: Player) {
        takePlayerOffIce(outgoing)
        putPlayerOnIce(incoming)
    }

    func togglePlayerOnIce(_ player: Player) {
        if onIcePlayers.contains(player.persistentModelID) {
            takePlayerOffIce(player)
        } else {
            putPlayerOnIce(player)
        }
    }

    func sendLineOn(_ lineTag: String) {
        let isForwardLine = lineTag.hasPrefix("F")
        let linePlayers = checkedInPlayers.filter { playerLines[$0.persistentModelID] == lineTag }
        let goalieId = activeGoalie?.persistentModelID

        for player in checkedInPlayers where onIcePlayers.contains(player.persistentModelID) && player.persistentModelID != goalieId {
            // Skip players without a line assignment (rolling players stay on ice)
            guard playerLines[player.persistentModelID] != nil else { continue }
            let playerIsForward = isForwardPosition(player.position)
            if (isForwardLine && playerIsForward) || (!isForwardLine && !playerIsForward) {
                takePlayerOffIce(player)
            }
        }

        for player in linePlayers {
            putPlayerOnIce(player)
        }
        fire()
    }

    func isForwardPosition(_ position: String) -> Bool {
        ["Forward", "Center", "Left Wing", "Right Wing"].contains(position)
    }

    func onIcePlayerIdString() -> String {
        onIcePlayers.compactMap { id in
            checkedInPlayers.first(where: { $0.persistentModelID == id })?.playerId
        }.joined(separator: ",")
    }

    func formatTOI(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    func closeShift(for player: Player) {
        let id = player.persistentModelID
        let duration = currentShiftSeconds[id] ?? 0
        guard duration > 0 else { return }
        let startTime = shiftStartClockTime[id] ?? ""
        let endTime = currentClockTime
        let shift = PlayerShift(period: currentPeriod, duration: duration, startClockTime: startTime, endClockTime: endTime)
        let stats = findOrCreatePlayerStats(for: player)
        shift.gamePlayerStats = stats
        modelContext.insert(shift)
    }

    func closeAllShifts() {
        let goalieId = activeGoalie?.persistentModelID
        for id in onIcePlayers {
            guard id != goalieId else { continue }
            if let player = checkedInPlayers.first(where: { $0.persistentModelID == id }) {
                closeShift(for: player)
                currentShiftSeconds[id] = 0
                shiftStartClockTime[id] = currentClockTime
            }
        }
    }

    func persistTOI() {
        for (playerId, seconds) in playerTOI {
            if let player = checkedInPlayers.first(where: { $0.persistentModelID == playerId }) {
                let stats = findOrCreatePlayerStats(for: player)
                stats.timeOnIce = seconds
            }
        }
    }

    func initializeStatsForCheckedInPlayers() {
        for player in skaters {
            _ = findOrCreatePlayerStats(for: player)
        }
        if let goalie = activeGoalie {
            _ = findOrCreateGoalieStats(for: goalie)
            onIcePlayers.insert(goalie.persistentModelID)
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

    var totalShotsFor: Int {
        game.playerStats.reduce(0) { $0 + $1.shots }
    }

    var totalShotsAgainst: Int {
        game.goalieStats.reduce(0) { $0 + $1.shotsAgainst }
    }

    // MARK: - Game Clock

    var clockDisplay: String {
        let mins = clockSeconds / 60
        let secs = clockSeconds % 60
        return String(format: "%d:%02d", mins, secs)
    }

    var currentClockTime: String {
        guard isClockSetUp else { return "" }
        return clockDisplay
    }

    var ourPenalties: [ActivePenalty] {
        activePenalties.filter { $0.isOurs }
    }

    var theirPenalties: [ActivePenalty] {
        activePenalties.filter { !$0.isOurs }
    }

    var onPowerPlay: Bool { theirPenalties.count > ourPenalties.count }
    var shortHanded: Bool { ourPenalties.count > theirPenalties.count }

    func setupClock(minutes: Int) {
        periodLengthMinutes = minutes
        clockSeconds = minutes * 60
        isClockSetUp = true
    }

    func toggleClock() {
        if clockRunning { stopClock() } else { startClock() }
    }

    func startClock() {
        guard clockSeconds > 0 else { return }
        clockRunning = true
        clockTask = Task { @MainActor in
            while !Task.isCancelled && clockRunning && clockSeconds > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, clockRunning else { break }
                clockSeconds -= 1
                for i in activePenalties.indices {
                    if activePenalties[i].remainingSeconds > 0 {
                        activePenalties[i].remainingSeconds -= 1
                    }
                }
                activePenalties.removeAll { $0.remainingSeconds <= 0 }
                for playerId in onIcePlayers {
                    playerTOI[playerId, default: 0] += 1
                    currentShiftSeconds[playerId, default: 0] += 1
                }
                if clockSeconds == 0 {
                    clockRunning = false
                }
            }
        }
    }

    func stopClock() {
        clockRunning = false
        clockTask?.cancel()
        clockTask = nil
    }

    func setClockTime(minutes: Int, seconds: Int) {
        clockSeconds = minutes * 60 + seconds
    }

    @discardableResult
    func addPenalty(playerName: String, playerNumber: Int, isOurs: Bool, type: PenaltyType) -> UUID {
        let penalty = ActivePenalty(
            playerName: playerName,
            playerNumber: playerNumber,
            isOurs: isOurs,
            type: type,
            totalSeconds: type.minutes * 60,
            remainingSeconds: type.minutes * 60
        )
        activePenalties.append(penalty)
        return penalty.id
    }

    func clearShortestMinorPenalty(ours: Bool) {
        guard let idx = activePenalties
            .enumerated()
            .filter({ $0.element.isOurs == ours && ($0.element.type == .minor || $0.element.type == .doubleMinor) })
            .min(by: { $0.element.remainingSeconds < $1.element.remainingSeconds })?
            .offset
        else { return }
        activePenalties.remove(at: idx)
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
        isPowerPlay: Bool = false,
        isShortHanded: Bool = false,
        onIcePlayerIds: String = ""
    ) -> GameEvent {
        let resolvedClockTime = clockTime.isEmpty ? currentClockTime : clockTime
        let event = GameEvent(
            type: type,
            period: currentPeriod,
            clockTime: resolvedClockTime,
            playerName: player?.name ?? "",
            playerNumber: player?.number ?? 0,
            assist1Name: assist1?.name ?? "",
            assist1Number: assist1?.number ?? 0,
            assist2Name: assist2?.name ?? "",
            assist2Number: assist2?.number ?? 0,
            penaltyMinutes: penaltyMinutes,
            penaltyType: penaltyType,
            opponentNumber: opponentNumber,
            isPowerPlay: isPowerPlay,
            isShortHanded: isShortHanded
        )
        event.onIcePlayerIds = onIcePlayerIds
        event.game = game
        modelContext.insert(event)
        return event
    }

    // MARK: - Period Transitions

    func endPeriod() {
        let skippedSeconds = clockSeconds
        stopClock()
        closeAllShifts()
        // Sync penalty timers: subtract remaining clock time
        for i in activePenalties.indices {
            activePenalties[i].remainingSeconds -= skippedSeconds
        }
        activePenalties.removeAll { $0.remainingSeconds <= 0 }
        events.append(LiveEvent(emoji: "⏱️", description: "— End of \(periodLabel) Period —", undoClosure: nil))
        currentPeriod += 1
        if isClockSetUp {
            clockSeconds = periodLengthMinutes * 60
        }
        save()
        fire()
    }

    func goToOvertime() {
        stopClock()
        closeAllShifts()
        period = .overtime
        currentPeriod = 4
        if isClockSetUp {
            clockSeconds = 5 * 60
        }
        events.append(LiveEvent(emoji: "⏱️", description: "— OVERTIME —", undoClosure: nil))
        save()
        fire()
    }

    func goToShootout() {
        stopClock()
        closeAllShifts()
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

        closeAllShifts()
        persistTOI()

        // GWG: the Nth goal where N = opponent final goals + 1 (reg/OT only)
        if period != .shootout && game.goalsFor > game.goalsAgainst {
            let gwgNumber = game.goalsAgainst + 1
            var goalCount = 0
            for event in events {
                guard let ge = event.gameEvent, ge.type == "goal" else { continue }
                goalCount += 1
                if goalCount == gwgNumber {
                    if let player = findPlayer(named: ge.playerName, number: ge.playerNumber) {
                        findOrCreatePlayerStats(for: player).gameWinningGoals += 1
                    }
                    break
                }
            }
        }

        save()
    }

    // MARK: - Record Actions

    func recordShot(player: Player) {
        let stats = findOrCreatePlayerStats(for: player)
        stats.shots += 1
        let label = playerLabel(player)
        let event = createEvent(type: "shot", player: player)
        events.append(LiveEvent(emoji: "🏒", description: "\(periodLabel) \(label) — Shot", undoClosure: {
            stats.shots -= 1
            self.removeGameEvent(event)
        }, gameEvent: event))
        lastRecordedPlayer = player
        lastRecordedAction = .shot
        save()
        fire()
    }

    func recordGoal(scorer: Player, primaryAssist: Player?, secondaryAssist: Player?, clockTime: String = "", isPowerPlay: Bool = false, isShortHanded: Bool = false) {
        let scorerStats = findOrCreatePlayerStats(for: scorer)
        scorerStats.goals += 1
        if isPowerPlay { scorerStats.powerPlayGoals += 1 }
        if isShortHanded { scorerStats.shortHandedGoals += 1 }
        game.goalsFor += 1

        var assistText = ""
        if let a1 = primaryAssist {
            let a1Stats = findOrCreatePlayerStats(for: a1)
            a1Stats.assists += 1
            if isPowerPlay { a1Stats.powerPlayAssists += 1 }
            if isShortHanded { a1Stats.shortHandedAssists += 1 }
            assistText = " (A: \(playerLabel(a1))"
            if let a2 = secondaryAssist {
                let a2Stats = findOrCreatePlayerStats(for: a2)
                a2Stats.assists += 1
                if isPowerPlay { a2Stats.powerPlayAssists += 1 }
                if isShortHanded { a2Stats.shortHandedAssists += 1 }
                assistText += ", \(playerLabel(a2))"
            }
            assistText += ")"
        }

        // +/- applies on even-strength and short-handed goals, not power play
        var plusMinusPlayers: [Player] = []
        if !isPowerPlay {
            let goalieId = activeGoalie?.persistentModelID
            plusMinusPlayers = checkedInPlayers.filter {
                onIcePlayers.contains($0.persistentModelID) && $0.persistentModelID != goalieId
            }
            for p in plusMinusPlayers {
                findOrCreatePlayerStats(for: p).plusMinus += 1
            }
        }

        let label = playerLabel(scorer)
        let timeStr = clockTime.isEmpty ? "" : " \(clockTime)"
        let strengthStr = isPowerPlay ? " PP" : isShortHanded ? " SH" : ""
        let event = createEvent(type: "goal", player: scorer, clockTime: clockTime, assist1: primaryAssist, assist2: secondaryAssist, isPowerPlay: isPowerPlay, isShortHanded: isShortHanded, onIcePlayerIds: onIcePlayerIdString())
        let wasPP = isPowerPlay
        let wasSH = isShortHanded
        let pmSnapshot = plusMinusPlayers
        events.append(LiveEvent(emoji: "🚨", description: "\(periodLabel)\(timeStr) \(label) — GOAL\(strengthStr)\(assistText)", undoClosure: {
            scorerStats.goals -= 1
            if wasPP { scorerStats.powerPlayGoals -= 1 }
            if wasSH { scorerStats.shortHandedGoals -= 1 }
            self.game.goalsFor -= 1
            if let a1 = primaryAssist {
                let a1s = self.findOrCreatePlayerStats(for: a1)
                a1s.assists -= 1
                if wasPP { a1s.powerPlayAssists -= 1 }
                if wasSH { a1s.shortHandedAssists -= 1 }
            }
            if let a2 = secondaryAssist {
                let a2s = self.findOrCreatePlayerStats(for: a2)
                a2s.assists -= 1
                if wasPP { a2s.powerPlayAssists -= 1 }
                if wasSH { a2s.shortHandedAssists -= 1 }
            }
            for p in pmSnapshot {
                self.findOrCreatePlayerStats(for: p).plusMinus -= 1
            }
            self.removeGameEvent(event)
        }, gameEvent: event))
        lastRecordedPlayer = nil
        lastRecordedAction = nil
        // PPG clears the opponent's shortest minor penalty
        if isPowerPlay {
            clearShortestMinorPenalty(ours: false)
        }
        triggerGoalFlash(.pink)
        save()
        fire()
    }

    func recordHit(player: Player) {
        let stats = findOrCreatePlayerStats(for: player)
        stats.hits += 1
        let label = playerLabel(player)
        let event = createEvent(type: "hit", player: player)
        events.append(LiveEvent(emoji: "💥", description: "\(periodLabel) \(label) — Hit", undoClosure: {
            stats.hits -= 1
            self.removeGameEvent(event)
        }, gameEvent: event))
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
        events.append(LiveEvent(emoji: "🛡️", description: "\(periodLabel) \(label) — Block", undoClosure: {
            stats.blocks -= 1
            self.removeGameEvent(event)
        }, gameEvent: event))
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
        events.append(LiveEvent(emoji: "🏑", description: "\(periodLabel) \(label) — FO \(result)", undoClosure: {
            if won { stats.faceoffWins -= 1 } else { stats.faceoffLosses -= 1 }
            self.removeGameEvent(event)
        }, gameEvent: event))
        save()
        fire()
    }

    func recordPenalty(player: Player, type: PenaltyType, clockTime: String = "") {
        let stats = findOrCreatePlayerStats(for: player)
        stats.penaltyMinutes += type.minutes
        let label = playerLabel(player)
        let mins = type.minutes
        let resolvedTime = clockTime.isEmpty ? currentClockTime : clockTime
        let timeStr = resolvedTime.isEmpty ? "" : " \(resolvedTime)"
        let event = createEvent(type: "penalty", player: player, clockTime: clockTime, penaltyMinutes: type.minutes, penaltyType: type.rawValue)
        let penaltyId = addPenalty(playerName: player.name, playerNumber: player.number, isOurs: true, type: type)
        events.append(LiveEvent(emoji: "🚫", description: "\(periodLabel)\(timeStr) \(label) — \(type.rawValue) (\(mins) min)", undoClosure: {
            stats.penaltyMinutes -= mins
            self.activePenalties.removeAll { $0.id == penaltyId }
            self.removeGameEvent(event)
        }, gameEvent: event))
        save()
        fire()
    }

    func recordShotAgainst() {
        guard let goalie = activeGoalie else { return }
        let stats = findOrCreateGoalieStats(for: goalie)
        stats.shotsAgainst += 1
        let label = playerLabel(goalie)
        let event = createEvent(type: "shotAgainst")
        events.append(LiveEvent(emoji: "🧤", description: "\(periodLabel) Shot Against (\(label))", undoClosure: {
            stats.shotsAgainst -= 1
            self.removeGameEvent(event)
        }, gameEvent: event))
        save()
        fire()
    }

    func recordGoalAgainst(clockTime: String = "", isPowerPlay: Bool = false) {
        guard let goalie = activeGoalie else { return }
        let stats = findOrCreateGoalieStats(for: goalie)
        stats.shotsAgainst += 1
        stats.goalsAgainst += 1
        game.goalsAgainst += 1

        // +/- applies on even-strength and short-handed goals, not power play
        var plusMinusPlayers: [Player] = []
        if !isPowerPlay {
            let goalieId = activeGoalie?.persistentModelID
            plusMinusPlayers = checkedInPlayers.filter {
                onIcePlayers.contains($0.persistentModelID) && $0.persistentModelID != goalieId
            }
            for p in plusMinusPlayers {
                findOrCreatePlayerStats(for: p).plusMinus -= 1
            }
        }

        let label = playerLabel(goalie)
        let timeStr = clockTime.isEmpty ? "" : " \(clockTime)"
        let ppStr = isPowerPlay ? " PP" : ""
        let event = createEvent(type: "goalAgainst", clockTime: clockTime, isPowerPlay: isPowerPlay, onIcePlayerIds: onIcePlayerIdString())
        let pmSnapshot = plusMinusPlayers
        events.append(LiveEvent(emoji: "🚨", description: "\(periodLabel)\(timeStr) GOAL AGAINST\(ppStr) (\(label))", undoClosure: {
            stats.shotsAgainst -= 1
            stats.goalsAgainst -= 1
            self.game.goalsAgainst -= 1
            for p in pmSnapshot {
                self.findOrCreatePlayerStats(for: p).plusMinus += 1
            }
            self.removeGameEvent(event)
        }, gameEvent: event))
        // PPG against us clears our shortest minor penalty
        if isPowerPlay {
            clearShortestMinorPenalty(ours: true)
        }
        triggerGoalFlash(.teal)
        save()
        fire()
    }

    func recordOpponentPenalty(jerseyNumber: String, type: PenaltyType, clockTime: String = "") {
        let num = jerseyNumber.isEmpty ? "?" : jerseyNumber
        let resolvedTime = clockTime.isEmpty ? currentClockTime : clockTime
        let timeStr = resolvedTime.isEmpty ? "" : " \(resolvedTime)"
        let event = createEvent(type: "penaltyAgainst", clockTime: clockTime, penaltyMinutes: type.minutes, penaltyType: type.rawValue, opponentNumber: jerseyNumber)
        let jerseyNum = Int(jerseyNumber) ?? 0
        let penaltyId = addPenalty(playerName: "", playerNumber: jerseyNum, isOurs: false, type: type)
        events.append(LiveEvent(emoji: "🚫", description: "\(periodLabel)\(timeStr) OPP #\(num) — \(type.rawValue) (\(type.minutes) min)", undoClosure: {
            self.activePenalties.removeAll { $0.id == penaltyId }
            self.removeGameEvent(event)
        }, gameEvent: event))
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
        pendingClockTime = currentClockTime
        if onPowerPlay { pendingGoalStrength = 1 }
        else if shortHanded { pendingGoalStrength = 2 }
        else { pendingGoalStrength = 0 }
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
        recordGoal(scorer: scorer, primaryAssist: pendingPrimaryAssist, secondaryAssist: pendingSecondaryAssist, clockTime: pendingClockTime, isPowerPlay: pendingGoalStrength == 1, isShortHanded: pendingGoalStrength == 2)
        pendingGoalScorer = nil
        pendingPrimaryAssist = nil
        pendingSecondaryAssist = nil
        pendingClockTime = ""
        pendingGoalStrength = 0
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

    // MARK: - Edit Event (delete + re-record)

    func replaceEvent(at index: Int, player: Player?, clockTime: String, isPowerPlay: Bool, isShortHanded: Bool, assist1: Player?, assist2: Player?, penaltyType: PenaltyType?, faceoffWon: Bool?, opponentNumber: String, period: Int) {
        guard events.indices.contains(index), let gameEvent = events[index].gameEvent else { return }
        let eventType = gameEvent.type

        // Undo old stats
        events[index].undoClosure?()
        events.remove(at: index)

        // Temporarily set period to match the edited event
        let savedPeriod = currentPeriod
        currentPeriod = period

        // Re-record based on type
        switch eventType {
        case "shot":
            if let player { recordShot(player: player) }
        case "goal":
            if let player {
                recordGoal(scorer: player, primaryAssist: assist1, secondaryAssist: assist2, clockTime: clockTime, isPowerPlay: isPowerPlay, isShortHanded: isShortHanded)
            }
        case "hit":
            if let player { recordHit(player: player) }
        case "block":
            if let player { recordBlock(player: player) }
        case "faceoffWin", "faceoffLoss":
            if let player, let won = faceoffWon { recordFaceoff(player: player, won: won) }
        case "penalty":
            if let player, let pType = penaltyType { recordPenalty(player: player, type: pType, clockTime: clockTime) }
        case "shotAgainst":
            recordShotAgainst()
        case "goalAgainst":
            recordGoalAgainst(clockTime: clockTime, isPowerPlay: isPowerPlay)
        case "penaltyAgainst":
            if let pType = penaltyType { recordOpponentPenalty(jerseyNumber: opponentNumber, type: pType, clockTime: clockTime) }
        default:
            break
        }

        currentPeriod = savedPeriod
        save()
    }

    func findPlayer(named name: String, number: Int) -> Player? {
        checkedInPlayers.first { $0.name == name && $0.number == number }
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
