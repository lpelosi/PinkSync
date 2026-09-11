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
    enum Kind {
        /// A recorded play — shot, goal, penalty, faceoff…
        case action
        /// A period change. Undoing it puts the game back where it was.
        case transition
        /// One shootout attempt, editable after the fact.
        case shootout
        /// Information only ("Resumed", "Game reopened"). Never undoable and
        /// skipped when looking for the last thing to undo or go back from.
        case note
    }

    let id = UUID()
    let timestamp = Date()
    let emoji: String
    var description: String
    let undoClosure: (() -> Void)?
    var gameEvent: GameEvent?
    var kind: Kind = .action
    /// For `.shootout` events, the attempt this line describes.
    var shootoutAttemptId: UUID?
    /// For `.transition` events, what "go back" returns to, e.g. "2nd Period".
    var goBackLabel: String?
    /// For `.transition` events, the state "go back" restores. Kept on the
    /// event so it survives a save/resume of the session.
    var transitionSnapshot: LiveTransitionSnapshot?
}

/// One shot in a shootout, ours or theirs. Kept as a list so a result or
/// shooter can be corrected afterwards and the score, round numbers and whose
/// turn it is are all re-derived rather than patched.
struct ShootoutAttempt: Identifiable {
    let id = UUID()
    var isOurs: Bool
    var player: Player?
    var isGoal: Bool
    /// Persisted for the goalie's record on opponent attempts.
    var round: ShootoutRound?
    /// Derived: the round this attempt belongs to.
    var roundNumber: Int = 1
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
    /// Skaters confirmed on the ice for the goal being entered. Starts as
    /// whoever the app thinks is on; the scorekeeper can fix it before saving.
    var pendingOnIce: Set<PersistentIdentifier> = []
    /// Whether that correction should also become the line on the ice now.
    var pendingOnIceUpdatesLine = true

    var period: GamePeriod = .regulation
    var currentPeriod: Int = 1

    // Shootout. The attempt list is the source of truth; the rest is derived
    // by `recomputeShootout()` so edits and undos can never leave the turn or
    // the score out of step.
    var shootoutAttempts: [ShootoutAttempt] = []
    private(set) var ourShootoutGoals = 0
    private(set) var theirShootoutGoals = 0
    /// The round the next shot belongs to.
    private(set) var shootoutRoundNumber = 1
    /// Whose shot is expected next. A suggestion only — either side can be
    /// recorded at any time, since the order on the ice is not always ours-first.
    private(set) var isOurShootoutTurn = true
    /// The score when the shootout started; shootout goals are added on top.
    private var goalsBeforeShootout = (for: 0, against: 0)

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

    /// Per-game role override ("Forward" or "Defense") for players whose roster position
    /// differs from where they're slotted for this game. Empty/missing means use roster position.
    var playerGameRole: [PersistentIdentifier: String] = [:]

    private let haptic = UIImpactFeedbackGenerator(style: .medium)

    // Live scoreboard on the website. Pushed at most every few seconds while
    // scoring, taken down when the game ends. Off in tests.
    var publishesLiveScore = true
    private var livePublishingSuspended = false
    private var livePushTask: Task<Void, Never>?
    private var livePushPending = false
    private static let livePushInterval: Duration = .seconds(5)

    init(game: Game, modelContext: ModelContext) {
        self.game = game
        self.modelContext = modelContext
        haptic.prepare()
    }

    /// The goalie in net right now. Starts as the game's starting goalie and
    /// changes with `changeGoalie(to:)` when a relief goalie comes in.
    var activeGoalie: Player?

    /// Roster players eligible for this game, for adding someone to the lineup
    /// or changing goalie mid-game. Set by whoever creates the view model.
    var availablePlayers: [Player] = []

    /// Eligible players not yet in the lineup.
    var lineupCandidates: [Player] {
        availablePlayers
            .filter { candidate in !checkedInPlayers.contains { $0.persistentModelID == candidate.persistentModelID } }
            .sorted { sortKey(for: $0) < sortKey(for: $1) }
    }

    /// Goalies who could take over in net.
    var goalieCandidates: [Player] {
        let pool = availablePlayers + checkedInPlayers
        var seen = Set<PersistentIdentifier>()
        return pool.filter { player in
            guard player.isGoalie, player.persistentModelID != activeGoalie?.persistentModelID else { return false }
            return seen.insert(player.persistentModelID).inserted
        }
        .sorted { $0.number < $1.number }
    }

    // MARK: - Lineup Changes

    /// Check a player in after the game has started — a late arrival, or
    /// someone missed at check-in.
    func addToLineup(_ player: Player, silently: Bool = false) {
        guard !checkedInPlayers.contains(where: { $0.persistentModelID == player.persistentModelID }) else { return }
        checkedInPlayers.append(player)
        if player.persistentModelID != activeGoalie?.persistentModelID {
            _ = findOrCreatePlayerStats(for: player)
        }
        if !silently {
            events.append(LiveEvent(
                emoji: "➕",
                description: "\(playerLabel(player)) added to lineup",
                undoClosure: { [weak self] in self?.removeFromLineup(player, silently: true) }
            ))
        }
        save()
        fire()
    }

    /// A player can leave the lineup only while nothing has been recorded for
    /// them, so no stat silently disappears with them.
    func canRemoveFromLineup(_ player: Player) -> Bool {
        let id = player.persistentModelID
        guard id != activeGoalie?.persistentModelID, !onIcePlayers.contains(id) else { return false }
        if (playerTOI[id] ?? 0) > 0 { return false }
        if let stats = game.playerStats.first(where: { $0.player?.persistentModelID == id }) {
            return !stats.hasRecordedStats && stats.plusMinus == 0 && stats.shifts.isEmpty
        }
        return true
    }

    func removeFromLineup(_ player: Player, silently: Bool = false) {
        guard canRemoveFromLineup(player) else { return }
        let id = player.persistentModelID
        checkedInPlayers.removeAll { $0.persistentModelID == id }
        if let stats = game.playerStats.first(where: { $0.player?.persistentModelID == id }) {
            modelContext.delete(stats)
        }
        playerLines.removeValue(forKey: id)
        playerGamePosition.removeValue(forKey: id)
        playerGameRole.removeValue(forKey: id)
        playerTOI.removeValue(forKey: id)
        if !silently {
            events.append(LiveEvent(
                emoji: "➖",
                description: "\(playerLabel(player)) removed from lineup",
                undoClosure: { [weak self] in self?.addToLineup(player, silently: true) }
            ))
        }
        save()
        fire()
    }

    /// Put a different goalie in net. Shots against from here on are theirs.
    /// The previous goalie stays in the lineup. Undoable from the feed.
    func changeGoalie(to goalie: Player) {
        guard goalie.persistentModelID != activeGoalie?.persistentModelID else { return }
        let previous = activeGoalie
        let hadLine = game.goalieStats.contains { $0.player?.persistentModelID == goalie.persistentModelID }
        applyGoalie(goalie)
        let description = previous.map { "\(playerLabel(goalie)) in goal for \(playerLabel($0))" }
            ?? "\(playerLabel(goalie)) in goal"
        // Persisted so the goalie of record can be worked out at the end and
        // after a resume: the goalie in net at any moment is the last change
        // before it, else the starter.
        let event = createEvent(type: "goalieChange", player: goalie)
        events.append(LiveEvent(
            emoji: "🥅",
            description: description,
            undoClosure: { [weak self] in
                guard let self else { return }
                if let previous { self.applyGoalie(previous) }
                if !hadLine { self.pruneEmptyGoalieLine(for: goalie) }
                self.removeGameEvent(event)
            },
            gameEvent: event
        ))
        save()
        fire()
    }

    /// Drop a goalie's stat line when it holds nothing: no shots, no goals,
    /// no shootout rounds, no decision, and they are neither the starter nor
    /// in net now. Otherwise an accidental or undone goalie change would
    /// credit them a game played.
    func pruneEmptyGoalieLine(for goalie: Player) {
        let id = goalie.persistentModelID
        guard id != activeGoalie?.persistentModelID,
              id != game.startingGoalie?.persistentModelID,
              let line = game.goalieStats.first(where: { $0.player?.persistentModelID == id }),
              line.shotsAgainst == 0, line.goalsAgainst == 0,
              line.shootoutRounds.isEmpty, line.result.isEmpty else { return }
        game.goalieStats.removeAll { $0.persistentModelID == line.persistentModelID }
        modelContext.delete(line)
    }

    /// The goalie in net when `gameEvent` was recorded: the goalie stamped on
    /// it (shots and goals against), else the last goalie change before it,
    /// else the starter.
    func goalieInNet(at gameEvent: GameEvent) -> Player? {
        let pool = checkedInPlayers + availablePlayers
        if gameEvent.type == "shotAgainst" || gameEvent.type == "goalAgainst",
           !gameEvent.playerId.isEmpty,
           let stamped = pool.first(where: { $0.playerId == gameEvent.playerId }) {
            return stamped
        }
        let change = GameEvent.chronological(game.events)
            .filter { $0.type == "goalieChange" && $0.createdAt < gameEvent.createdAt }
            .last
        if let change, let player = pool.first(where: { $0.playerId == change.playerId }) {
            return player
        }
        return game.startingGoalie
    }

    private func applyGoalie(_ goalie: Player) {
        if let old = activeGoalie {
            onIcePlayers.remove(old.persistentModelID)
        }
        if !checkedInPlayers.contains(where: { $0.persistentModelID == goalie.persistentModelID }) {
            checkedInPlayers.append(goalie)
        }
        activeGoalie = goalie
        _ = findOrCreateGoalieStats(for: goalie)
        onIcePlayers.insert(goalie.persistentModelID)
        currentShiftSeconds.removeValue(forKey: goalie.persistentModelID)
        shiftStartClockTime.removeValue(forKey: goalie.persistentModelID)
    }

    var skaters: [Player] {
        checkedInPlayers
            .filter { $0.persistentModelID != activeGoalie?.persistentModelID }
            .sorted { sortKey(for: $0) < sortKey(for: $1) }
    }

    /// Sort key honoring per-game overrides. Subs with no override sort to the end.
    func sortKey(for player: Player) -> Int {
        effectiveNumber(for: player) ?? Int.max
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
                return sortKey(for: a) < sortKey(for: b)
            }
    }

    func positionLabel(for player: Player) -> String {
        playerGamePosition[player.persistentModelID] ?? ""
    }

    var benchPlayers: [Player] {
        let goalieId = activeGoalie?.persistentModelID
        return checkedInPlayers
            .filter { !onIcePlayers.contains($0.persistentModelID) && $0.persistentModelID != goalieId }
            .sorted { sortKey(for: $0) < sortKey(for: $1) }
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
            let playerIsForward = isForwardForGame(player)
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

    /// Per-game effective role. Returns the override if set, otherwise derived from the roster position.
    func effectiveRole(for player: Player) -> String {
        if let override = playerGameRole[player.persistentModelID], !override.isEmpty {
            return override
        }
        return isForwardPosition(player.position) ? "Forward" : "Defense"
    }

    func isForwardForGame(_ player: Player) -> Bool {
        effectiveRole(for: player) == "Forward"
    }

    /// Flip a player's game-only role. Clears their position/line assignments since
    /// a Forward's "C" doesn't carry over to Defense pairings.
    func setGameRole(_ role: String, for player: Player) {
        let id = player.persistentModelID
        let rosterIsForward = isForwardPosition(player.position)
        let matchesRoster = (role == "Forward" && rosterIsForward) || (role == "Defense" && !rosterIsForward)
        if matchesRoster {
            playerGameRole.removeValue(forKey: id)
        } else {
            playerGameRole[id] = role
        }
        playerGamePosition.removeValue(forKey: id)
        playerLines.removeValue(forKey: id)
    }

    /// Who was on the ice for a goal: the skaters who get +/-, and the id list
    /// stored on the event (goalie included, as recorded live).
    struct OnIceSnapshot {
        var skaters: [Player]
        var storedIds: String
    }

    /// A snapshot from a picked set of skaters, with the goalie in net added
    /// to the stored ids the way live scoring records them.
    func onIceSnapshot(skaterIds: Set<PersistentIdentifier>, goalie: Player?) -> OnIceSnapshot {
        var seen = Set<PersistentIdentifier>()
        let skaters = (checkedInPlayers + availablePlayers).filter {
            skaterIds.contains($0.persistentModelID)
                && $0.persistentModelID != goalie?.persistentModelID
                && seen.insert($0.persistentModelID).inserted
        }
        let ids = (skaters.map(\.playerId) + [goalie?.playerId ?? ""]).filter { !$0.isEmpty }
        return OnIceSnapshot(skaters: skaters, storedIds: ids.joined(separator: ","))
    }

    /// Make the line on the ice match a corrected set, so the next goal starts
    /// from the right players. Shift times follow; TOI is best-effort anyway.
    func applyOnIceToLive(_ skaterIds: Set<PersistentIdentifier>) {
        for player in skaters {
            let id = player.persistentModelID
            let isOn = onIcePlayers.contains(id)
            if skaterIds.contains(id) && !isOn {
                putPlayerOnIce(player)
            } else if !skaterIds.contains(id) && isOn {
                takePlayerOffIce(player)
            }
        }
    }

    /// Skaters on the ice right now, excluding the goalie in net.
    func currentOnIce() -> OnIceSnapshot {
        let goalieId = activeGoalie?.persistentModelID
        let skaters = checkedInPlayers.filter {
            onIcePlayers.contains($0.persistentModelID) && $0.persistentModelID != goalieId
        }
        return OnIceSnapshot(skaters: skaters, storedIds: onIcePlayerIdString())
    }

    /// Who was on the ice when `gameEvent` was recorded, from its stored ids.
    /// The goalie in net at that moment is left out of the skaters, as live
    /// scoring did.
    func recordedOnIce(for gameEvent: GameEvent) -> OnIceSnapshot {
        let goalieId = goalieInNet(at: gameEvent)?.playerId
        let pool = checkedInPlayers + availablePlayers
        var seen = Set<String>()
        let skaters: [Player] = gameEvent.onIcePlayerIds
            .split(separator: ",").map(String.init)
            .filter { $0 != goalieId && seen.insert($0).inserted }
            .compactMap { pid in pool.first { $0.playerId == pid } }
        return OnIceSnapshot(skaters: skaters, storedIds: gameEvent.onIcePlayerIds)
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
        if activeGoalie == nil {
            activeGoalie = game.startingGoalie
        }
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
        scheduleLivePush()
        clockTask = Task { @MainActor in
            while !Task.isCancelled && clockRunning && clockSeconds > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, clockRunning else { break }
                clockSeconds -= 1
                if clockSeconds % 15 == 0 { scheduleLivePush() }
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
        scheduleLivePush()
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
        // Anything live scoring changes is newer than the server's copy until
        // it is sent.
        if modelContext.hasChanges { game.hasLocalEdits = true }
        try? modelContext.save()
        LiveSessionStore.save(exportState())
        scheduleLivePush()
    }

    // MARK: - Live Score Publishing

    private var livePeriodLabel: String {
        switch period {
        case .regulation: periodLabel
        case .overtime: "OT"
        case .shootout: "SO"
        }
    }

    func liveScorePayload() -> APIClient.LiveScorePayload {
        APIClient.LiveScorePayload(
            gameId: game.gameId,
            opponent: game.opponent,
            date: Season.apiDay(for: game.date),
            goalsFor: game.goalsFor,
            goalsAgainst: game.goalsAgainst,
            shotsFor: totalShotsFor,
            shotsAgainst: totalShotsAgainst,
            period: livePeriodLabel,
            clock: isClockSetUp ? clockDisplay : "",
            clockRunning: clockRunning
        )
    }

    /// Coalesces pushes: the first goes out immediately, later ones wait for
    /// the interval and send the latest state once.
    func scheduleLivePush() {
        guard publishesLiveScore, !livePublishingSuspended, !game.gameId.isEmpty else { return }
        livePushPending = true
        guard livePushTask == nil else { return }
        livePushTask = Task { @MainActor [weak self] in
            while let self, self.livePushPending, !self.livePublishingSuspended {
                self.livePushPending = false
                try? await APIClient.pushLiveScore(self.liveScorePayload())
                try? await Task.sleep(for: Self.livePushInterval)
            }
            self?.livePushTask = nil
        }
    }

    private func stopLivePublishing() {
        livePublishingSuspended = true
        livePushPending = false
        livePushTask?.cancel()
        livePushTask = nil
        guard publishesLiveScore, !game.gameId.isEmpty else { return }
        let gameId = game.gameId
        Task { try? await APIClient.clearLiveScore(gameId: gameId) }
    }

    private func fire() {
        haptic.impactOccurred()
        haptic.prepare()
    }

    func playerLabel(_ player: Player) -> String {
        "\(displayNumber(for: player)) \(player.lastName)"
    }

    /// Per-game jersey number for this player. Returns nil if no number applies (sub with no override).
    func effectiveNumber(for player: Player) -> Int? {
        if let stat = game.playerStats.first(where: { $0.player?.persistentModelID == player.persistentModelID }),
           let override = stat.gameJerseyNumber {
            return override
        }
        if player.isSubstitute { return nil }
        return player.number
    }

    /// Plain number text for compact tiles (no `#`). Returns "—" when no number applies.
    func jerseyText(for player: Player) -> String {
        guard let n = effectiveNumber(for: player), n >= 0 else { return "—" }
        if n == 0 { return "00" }
        return "\(n)"
    }

    /// `#NN` style text for headers/labels. Returns "—" when no number applies.
    func displayNumber(for player: Player) -> String {
        guard let n = effectiveNumber(for: player), n >= 0 else { return "—" }
        if n == 0 { return "#00" }
        return "#\(n)"
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
            playerId: player?.playerId ?? "",
            playerName: player?.name ?? "",
            playerNumber: player?.number ?? 0,
            assist1Id: assist1?.playerId ?? "",
            assist1Name: assist1?.name ?? "",
            assist1Number: assist1?.number ?? 0,
            assist2Id: assist2?.playerId ?? "",
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

    private func snapshot() -> LiveTransitionSnapshot {
        LiveTransitionSnapshot(
            period: period.rawValue,
            currentPeriod: currentPeriod,
            clockSeconds: clockSeconds,
            goalsFor: game.goalsFor,
            goalsAgainst: game.goalsAgainst,
            activePenalties: activePenalties.map(Self.penaltyState)
        )
    }

    private func restore(_ snap: LiveTransitionSnapshot) {
        stopClock()
        closeAllShifts()
        period = GamePeriod(rawValue: snap.period) ?? .regulation
        currentPeriod = snap.currentPeriod
        clockSeconds = snap.clockSeconds
        activePenalties = snap.activePenalties.compactMap(Self.penalty)
        game.goalsFor = snap.goalsFor
        game.goalsAgainst = snap.goalsAgainst
        // Leaving a shootout that has no attempts yet (it can only be undone
        // while it is the latest event) — nothing to tear down but the counters.
        shootoutAttempts.removeAll()
        recomputeShootout()
    }

    nonisolated private static func penaltyState(_ penalty: ActivePenalty) -> LiveSessionState.Penalty {
        LiveSessionState.Penalty(
            playerName: penalty.playerName,
            playerNumber: penalty.playerNumber,
            isOurs: penalty.isOurs,
            type: penalty.type.rawValue,
            totalSeconds: penalty.totalSeconds,
            remainingSeconds: penalty.remainingSeconds
        )
    }

    nonisolated private static func penalty(_ state: LiveSessionState.Penalty) -> ActivePenalty? {
        guard let type = PenaltyType(rawValue: state.type) else { return nil }
        return ActivePenalty(
            playerName: state.playerName,
            playerNumber: state.playerNumber,
            isOurs: state.isOurs,
            type: type,
            totalSeconds: state.totalSeconds,
            remainingSeconds: state.remainingSeconds
        )
    }

    /// Label for a period the way the scoreboard shows it: "1st Period", "Overtime", "Shootout".
    func label(for period: GamePeriod, number: Int) -> String {
        switch period {
        case .regulation:
            switch number {
            case 1: "1st Period"
            case 2: "2nd Period"
            case 3: "3rd Period"
            default: "Period \(number)"
            }
        case .overtime: "Overtime"
        case .shootout: "Shootout"
        }
    }

    private func appendTransition(emoji: String, description: String, from snap: LiveTransitionSnapshot) {
        events.append(transitionEvent(emoji: emoji, description: description, snapshot: snap))
    }

    private func transitionEvent(emoji: String, description: String, snapshot snap: LiveTransitionSnapshot) -> LiveEvent {
        let previous = GamePeriod(rawValue: snap.period) ?? .regulation
        return LiveEvent(
            emoji: emoji,
            description: description,
            undoClosure: { [weak self] in self?.restore(snap) },
            kind: .transition,
            goBackLabel: label(for: previous, number: snap.currentPeriod),
            transitionSnapshot: snap
        )
    }

    /// True when the latest thing that happened was a period change, so "go
    /// back" can reverse it without touching any recorded play.
    var canGoBack: Bool {
        lastUndoableEvent?.kind == .transition
    }

    var goBackLabel: String? {
        guard canGoBack else { return nil }
        return lastUndoableEvent?.goBackLabel
    }

    /// The most recent feed line that can be undone, skipping notes such as
    /// "Resumed" so they never hide the Undo or Go Back buttons.
    private var lastUndoableIndex: Int? {
        events.lastIndex { $0.kind != .note && $0.undoClosure != nil }
    }

    var lastUndoableEvent: LiveEvent? {
        lastUndoableIndex.map { events[$0] }
    }

    /// Reverse the most recent period change. Plays recorded since then would
    /// have to be deleted first; while any exist the transition is no longer
    /// the latest event and this does nothing.
    func goBack() {
        guard canGoBack else { return }
        undoLast()
    }

    func endPeriod() {
        let snap = snapshot()
        let skippedSeconds = clockSeconds
        stopClock()
        closeAllShifts()
        // Sync penalty timers: subtract remaining clock time
        for i in activePenalties.indices {
            activePenalties[i].remainingSeconds -= skippedSeconds
        }
        activePenalties.removeAll { $0.remainingSeconds <= 0 }
        appendTransition(emoji: "⏱️", description: "— End of \(periodLabel) Period —", from: snap)
        currentPeriod += 1
        if isClockSetUp {
            clockSeconds = periodLengthMinutes * 60
        }
        save()
        fire()
    }

    func goToOvertime() {
        let snap = snapshot()
        stopClock()
        closeAllShifts()
        period = .overtime
        currentPeriod = 4
        if isClockSetUp {
            clockSeconds = 5 * 60
        }
        appendTransition(emoji: "⏱️", description: "— OVERTIME —", from: snap)
        save()
        fire()
    }

    func goToShootout() {
        let snap = snapshot()
        stopClock()
        closeAllShifts()
        period = .shootout
        goalsBeforeShootout = (game.goalsFor, game.goalsAgainst)
        shootoutAttempts.removeAll()
        recomputeShootout()
        appendTransition(emoji: "🎯", description: "— SHOOTOUT —", from: snap)
        save()
        fire()
    }

    /// Jump straight to a regulation period or overtime, for when the wrong
    /// button was tapped a while ago and the plays since are fine. Recorded
    /// plays keep the period they were stamped with; fix those from the feed.
    /// Undoable like any other transition.
    func setPeriod(number: Int) {
        let target: GamePeriod = number >= 4 ? .overtime : .regulation
        let clamped = max(1, min(number, 4))
        guard period != .shootout, target != period || clamped != currentPeriod else { return }
        let snap = snapshot()
        stopClock()
        closeAllShifts()
        period = target
        currentPeriod = clamped
        appendTransition(emoji: "⏱️", description: "— Period set to \(label(for: target, number: clamped)) —", from: snap)
        save()
        fire()
    }

    // MARK: - Shootout

    func recordShootoutAttempt(player: Player, isGoal: Bool) {
        addShootoutAttempt(isOurs: true, player: player, isGoal: isGoal)
    }

    func recordShootoutAttemptAgainst(isGoal: Bool) {
        addShootoutAttempt(isOurs: false, player: nil, isGoal: isGoal)
    }

    private func addShootoutAttempt(isOurs: Bool, player: Player?, isGoal: Bool) {
        var attempt = ShootoutAttempt(isOurs: isOurs, player: player, isGoal: isGoal)
        if !isOurs, let goalie = activeGoalie {
            let round = ShootoutRound(roundNumber: shootoutRoundNumber, isGoal: isGoal)
            round.goalieStats = findOrCreateGoalieStats(for: goalie)
            modelContext.insert(round)
            attempt.round = round
        }
        shootoutAttempts.append(attempt)
        let id = attempt.id
        events.append(LiveEvent(
            emoji: "🎯",
            description: "",
            undoClosure: { [weak self] in self?.removeShootoutAttempt(id: id, removeEvent: false) },
            kind: .shootout,
            shootoutAttemptId: id
        ))
        recomputeShootout()
        save()
        fire()
    }

    func shootoutAttempt(id: UUID) -> ShootoutAttempt? {
        shootoutAttempts.first { $0.id == id }
    }

    /// Change the shooter and/or result of an attempt already recorded.
    func updateShootoutAttempt(id: UUID, player: Player?, isGoal: Bool) {
        guard let index = shootoutAttempts.firstIndex(where: { $0.id == id }) else { return }
        if shootoutAttempts[index].isOurs {
            shootoutAttempts[index].player = player
        }
        shootoutAttempts[index].isGoal = isGoal
        shootoutAttempts[index].round?.isGoal = isGoal
        recomputeShootout()
        save()
        fire()
    }

    /// Drop an attempt. `removeEvent` is false when called from an undo or a
    /// feed delete, which remove the feed line themselves.
    func removeShootoutAttempt(id: UUID, removeEvent: Bool) {
        guard let index = shootoutAttempts.firstIndex(where: { $0.id == id }) else { return }
        if let round = shootoutAttempts[index].round {
            modelContext.delete(round)
        }
        shootoutAttempts.remove(at: index)
        if removeEvent {
            events.removeAll { $0.shootoutAttemptId == id }
        }
        recomputeShootout()
        save()
    }

    /// Re-derive score, round numbers, whose turn it is, and the feed text
    /// from the attempt list.
    private func recomputeShootout() {
        var ours = 0
        var theirs = 0
        for index in shootoutAttempts.indices {
            if shootoutAttempts[index].isOurs {
                ours += 1
                shootoutAttempts[index].roundNumber = ours
            } else {
                theirs += 1
                shootoutAttempts[index].roundNumber = theirs
            }
            shootoutAttempts[index].round?.roundNumber = shootoutAttempts[index].roundNumber
        }

        ourShootoutGoals = shootoutAttempts.filter { $0.isOurs && $0.isGoal }.count
        theirShootoutGoals = shootoutAttempts.filter { !$0.isOurs && $0.isGoal }.count
        shootoutRoundNumber = min(ours, theirs) + 1
        isOurShootoutTurn = ours <= theirs

        if period == .shootout {
            game.goalsFor = goalsBeforeShootout.for + ourShootoutGoals
            game.goalsAgainst = goalsBeforeShootout.against + theirShootoutGoals
        }

        for attempt in shootoutAttempts {
            if let eventIndex = events.firstIndex(where: { $0.shootoutAttemptId == attempt.id }) {
                events[eventIndex].description = shootoutDescription(attempt)
            }
        }
    }

    private func shootoutDescription(_ attempt: ShootoutAttempt) -> String {
        let prefix = "SO Rd \(attempt.roundNumber): "
        if attempt.isOurs {
            let label = attempt.player.map { playerLabel($0) } ?? "Shooter"
            return prefix + label + (attempt.isGoal ? " — GOAL!" : " — Miss")
        }
        if attempt.isGoal {
            return prefix + "Opponent — GOAL"
        }
        let label = (attempt.round?.goalieStats?.player ?? activeGoalie).map { playerLabel($0) } ?? "Goalie"
        return prefix + label + " — SAVE!"
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

        let decided = goalieOfRecord(for: result)
        if let decided {
            findOrCreateGoalieStats(for: decided).result = result.rawValue
        }
        // Everyone else in goal gets no decision, and a goalie who never
        // faced a shot loses the empty line an accidental change left behind.
        for line in game.goalieStats where line.player?.persistentModelID != decided?.persistentModelID {
            line.result = ""
            if let goalie = line.player { pruneEmptyGoalieLine(for: goalie) }
        }

        closeAllShifts()
        persistTOI()
        stopLivePublishing()

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

    /// Hockey's goalie of record. On a win, the goalie in net when the winning
    /// goal was scored; on a loss, the goalie who allowed the deciding goal
    /// against; in a shootout, the goalie who faced it. Other goalies who
    /// appeared get no decision.
    func goalieOfRecord(for result: GameResult) -> Player? {
        let log = events.compactMap(\.gameEvent)

        func goalie(withId id: String) -> Player? {
            guard !id.isEmpty else { return nil }
            return (checkedInPlayers + availablePlayers).first { $0.playerId == id }
        }

        func goalieInNet(before index: Int) -> Player? {
            for event in log[..<index].reversed() where event.type == "goalieChange" {
                if let player = goalie(withId: event.playerId) { return player }
            }
            return game.startingGoalie ?? activeGoalie
        }

        switch result {
        case .shootoutWin, .shootoutLoss:
            return activeGoalie
        case .win:
            let deciding = game.goalsAgainst + 1
            var count = 0
            for (index, event) in log.enumerated() where event.type == "goal" {
                count += 1
                if count == deciding { return goalieInNet(before: index) }
            }
        case .loss, .overtimeLoss:
            let deciding = game.goalsFor + 1
            var count = 0
            for (index, event) in log.enumerated() where event.type == "goalAgainst" {
                count += 1
                if count == deciding {
                    return goalie(withId: event.playerId) ?? goalieInNet(before: index)
                }
            }
        }
        return activeGoalie
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

    /// `onIce` replays who was on the ice when an edited goal was scored —
    /// their stored ids — instead of whoever is on now. Nil means right now.
    func recordGoal(scorer: Player, primaryAssist: Player?, secondaryAssist: Player?, clockTime: String = "", isPowerPlay: Bool = false, isShortHanded: Bool = false, onIce: OnIceSnapshot? = nil) {
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
        let onIceNow = onIce ?? currentOnIce()
        var plusMinusPlayers: [Player] = []
        if !isPowerPlay {
            plusMinusPlayers = onIceNow.skaters
            for p in plusMinusPlayers {
                findOrCreatePlayerStats(for: p).plusMinus += 1
            }
        }

        let label = playerLabel(scorer)
        let timeStr = clockTime.isEmpty ? "" : " \(clockTime)"
        let strengthStr = isPowerPlay ? " PP" : isShortHanded ? " SH" : ""
        let event = createEvent(type: "goal", player: scorer, clockTime: clockTime, assist1: primaryAssist, assist2: secondaryAssist, isPowerPlay: isPowerPlay, isShortHanded: isShortHanded, onIcePlayerIds: onIceNow.storedIds)
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

    func recordShotAgainst(goalie inNet: Player? = nil) {
        guard let goalie = inNet ?? activeGoalie else { return }
        let stats = findOrCreateGoalieStats(for: goalie)
        stats.shotsAgainst += 1
        let label = playerLabel(goalie)
        // The goalie in net is stamped on the event so a relief goalie's shots
        // stay theirs when stats are rebuilt from the event log.
        let event = createEvent(type: "shotAgainst", player: goalie)
        events.append(LiveEvent(emoji: "🧤", description: "\(periodLabel) Shot Against (\(label))", undoClosure: {
            stats.shotsAgainst -= 1
            self.removeGameEvent(event)
        }, gameEvent: event))
        save()
        fire()
    }

    func recordGoalAgainst(clockTime: String = "", isPowerPlay: Bool = false, goalie inNet: Player? = nil, onIce: OnIceSnapshot? = nil) {
        guard let goalie = inNet ?? activeGoalie else { return }
        let stats = findOrCreateGoalieStats(for: goalie)
        stats.shotsAgainst += 1
        stats.goalsAgainst += 1
        game.goalsAgainst += 1

        // +/- applies on even-strength and short-handed goals, not power play
        let onIceNow = onIce ?? currentOnIce()
        var plusMinusPlayers: [Player] = []
        if !isPowerPlay {
            plusMinusPlayers = onIceNow.skaters
            for p in plusMinusPlayers {
                findOrCreatePlayerStats(for: p).plusMinus -= 1
            }
        }

        let label = playerLabel(goalie)
        let timeStr = clockTime.isEmpty ? "" : " \(clockTime)"
        let ppStr = isPowerPlay ? " PP" : ""
        let event = createEvent(type: "goalAgainst", player: goalie, clockTime: clockTime, isPowerPlay: isPowerPlay, onIcePlayerIds: onIceNow.storedIds)
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
        guard let index = lastUndoableIndex else { return }
        events[index].undoClosure?()
        events.remove(at: index)
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
        pendingOnIce = Set(currentOnIce().skaters.map(\.persistentModelID))
        pendingOnIceUpdatesLine = true
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
        let onIceIds = pendingOnIce.union(goalFlowRequiredOnIce)
        if pendingOnIceUpdatesLine {
            applyOnIceToLive(onIceIds)
        }
        recordGoal(
            scorer: scorer, primaryAssist: pendingPrimaryAssist, secondaryAssist: pendingSecondaryAssist,
            clockTime: pendingClockTime, isPowerPlay: pendingGoalStrength == 1, isShortHanded: pendingGoalStrength == 2,
            onIce: onIceSnapshot(skaterIds: onIceIds, goalie: activeGoalie)
        )
        pendingOnIce = []
        pendingGoalScorer = nil
        pendingPrimaryAssist = nil
        pendingSecondaryAssist = nil
        pendingClockTime = ""
        pendingGoalStrength = 0
        currentAction = nil
    }

    /// Scorer and assists picked so far — they were on the ice by definition.
    var goalFlowRequiredOnIce: Set<PersistentIdentifier> {
        Set([pendingGoalScorer, pendingPrimaryAssist, pendingSecondaryAssist].compactMap { $0?.persistentModelID })
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

    /// `onIce`, for goals and goals against, is a corrected list of the
    /// skaters who were on the ice. Nil keeps the list recorded with the goal.
    func replaceEvent(at index: Int, player: Player?, clockTime: String, isPowerPlay: Bool, isShortHanded: Bool, assist1: Player?, assist2: Player?, penaltyType: PenaltyType?, faceoffWon: Bool?, opponentNumber: String, period: Int, onIce: [Player]? = nil) {
        guard events.indices.contains(index), let gameEvent = events[index].gameEvent else { return }
        let eventType = gameEvent.type
        // Resolve before the undo below deletes the event: an edited shot or
        // goal against stays with the goalie who faced it, not whoever is in
        // net now.
        let originalGoalie = goalieInNet(at: gameEvent)
        // +/- belongs to whoever was on the ice for the goal, not whoever is
        // on the ice when the scorekeeper gets round to fixing it.
        let originalOnIce = onIce.map {
            onIceSnapshot(skaterIds: Set($0.map(\.persistentModelID)), goalie: originalGoalie)
        } ?? recordedOnIce(for: gameEvent)

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
                recordGoal(scorer: player, primaryAssist: assist1, secondaryAssist: assist2, clockTime: clockTime, isPowerPlay: isPowerPlay, isShortHanded: isShortHanded, onIce: originalOnIce)
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
            recordShotAgainst(goalie: originalGoalie)
        case "goalAgainst":
            recordGoalAgainst(clockTime: clockTime, isPowerPlay: isPowerPlay, goalie: originalGoalie, onIce: originalOnIce)
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

    // MARK: - Session Persistence (leave and resume, reopen after end)

    private func playerId(_ id: PersistentIdentifier) -> String? {
        let pid = checkedInPlayers.first { $0.persistentModelID == id }?.playerId
        return (pid?.isEmpty ?? true) ? nil : pid
    }

    private func stringKeyed<V>(_ dict: [PersistentIdentifier: V]) -> [String: V] {
        var out: [String: V] = [:]
        for (id, value) in dict {
            if let pid = playerId(id) { out[pid] = value }
        }
        return out
    }

    func exportState() -> LiveSessionState {
        let feed: [LiveSessionState.FeedLine] = events.map { event in
            var line = LiveSessionState.FeedLine(kind: "note", emoji: event.emoji, description: event.description)
            switch event.kind {
            case .action:
                if let gameEvent = event.gameEvent {
                    line.kind = "action"
                    line.eventCreatedAt = gameEvent.createdAt
                }
            case .transition:
                line.kind = "transition"
                line.transition = event.transitionSnapshot
                line.goBackLabel = event.goBackLabel
            case .shootout:
                line.kind = "shootout"
                line.attemptIndex = shootoutAttempts.firstIndex { $0.id == event.shootoutAttemptId }
            case .note:
                break
            }
            return line
        }

        return LiveSessionState(
            gameId: game.gameId,
            savedAt: Date(),
            period: period.rawValue,
            currentPeriod: currentPeriod,
            periodLengthMinutes: periodLengthMinutes,
            clockSeconds: clockSeconds,
            isClockSetUp: isClockSetUp,
            activePenalties: activePenalties.map(Self.penaltyState),
            checkedInPlayerIds: checkedInPlayers.map(\.playerId),
            activeGoalieId: activeGoalie?.playerId,
            onIcePlayerIds: onIcePlayers.compactMap(playerId),
            playerTOI: stringKeyed(playerTOI),
            currentShiftSeconds: stringKeyed(currentShiftSeconds),
            shiftStartClockTime: stringKeyed(shiftStartClockTime),
            playerLines: stringKeyed(playerLines),
            playerGamePosition: stringKeyed(playerGamePosition),
            playerGameRole: stringKeyed(playerGameRole),
            shootoutAttempts: shootoutAttempts.map {
                LiveSessionState.Attempt(
                    isOurs: $0.isOurs,
                    playerId: $0.player?.playerId,
                    isGoal: $0.isGoal,
                    roundNumber: $0.roundNumber,
                    goaliePlayerId: $0.round?.goalieStats?.player?.playerId
                )
            },
            goalsBeforeShootoutFor: goalsBeforeShootout.for,
            goalsBeforeShootoutAgainst: goalsBeforeShootout.against,
            feed: feed
        )
    }

    /// Rebuild a live session from its saved state. `lookup` resolves player
    /// ids (pass the whole roster); `eligible` is who may be added to the
    /// lineup or put in goal.
    static func resume(game: Game, modelContext: ModelContext, lookup: [Player], eligible: [Player], publishesLiveScore: Bool = true) -> LiveGameViewModel? {
        guard let state = LiveSessionStore.load(gameId: game.gameId) else { return nil }
        let vm = LiveGameViewModel(game: game, modelContext: modelContext)
        vm.publishesLiveScore = publishesLiveScore
        vm.availablePlayers = eligible
        vm.restoreState(state, lookup: lookup)
        return vm
    }

    private func restoreState(_ state: LiveSessionState, lookup pool: [Player]) {
        var lookup: [String: Player] = [:]
        for player in pool where !player.playerId.isEmpty { lookup[player.playerId] = player }
        for stat in game.playerStats {
            if let player = stat.player, !player.playerId.isEmpty { lookup[player.playerId] = player }
        }
        for stat in game.goalieStats {
            if let player = stat.player, !player.playerId.isEmpty { lookup[player.playerId] = player }
        }
        func keyed<V>(_ dict: [String: V]) -> [PersistentIdentifier: V] {
            var out: [PersistentIdentifier: V] = [:]
            for (pid, value) in dict {
                if let player = lookup[pid] { out[player.persistentModelID] = value }
            }
            return out
        }

        period = GamePeriod(rawValue: state.period) ?? .regulation
        currentPeriod = state.currentPeriod
        periodLengthMinutes = state.periodLengthMinutes
        clockSeconds = state.clockSeconds
        isClockSetUp = state.isClockSetUp
        activePenalties = state.activePenalties.compactMap(Self.penalty)

        checkedInPlayers = state.checkedInPlayerIds.compactMap { lookup[$0] }
        activeGoalie = state.activeGoalieId.flatMap { lookup[$0] } ?? game.startingGoalie
        onIcePlayers = Set(state.onIcePlayerIds.compactMap { lookup[$0]?.persistentModelID })
        playerTOI = keyed(state.playerTOI)
        currentShiftSeconds = keyed(state.currentShiftSeconds)
        shiftStartClockTime = keyed(state.shiftStartClockTime)
        playerLines = keyed(state.playerLines)
        playerGamePosition = keyed(state.playerGamePosition)
        playerGameRole = keyed(state.playerGameRole)
        goalsBeforeShootout = (state.goalsBeforeShootoutFor, state.goalsBeforeShootoutAgainst)

        // Shootout attempts. Opponent attempts re-attach to the persisted round
        // on the line of the goalie who faced them (a goalie can change mid-
        // shootout), matched by round number.
        var roundPools: [String: [ShootoutRound]] = [:]
        for line in game.goalieStats {
            roundPools[line.player?.playerId ?? "", default: []].append(contentsOf: line.shootoutRounds)
        }
        let fallbackGoalieId = activeGoalie?.playerId ?? ""
        shootoutAttempts = state.shootoutAttempts.map { saved in
            var attempt = ShootoutAttempt(isOurs: saved.isOurs, player: saved.playerId.flatMap { lookup[$0] }, isGoal: saved.isGoal)
            attempt.roundNumber = saved.roundNumber
            if !saved.isOurs {
                let key = saved.goaliePlayerId ?? fallbackGoalieId
                if let index = roundPools[key]?.firstIndex(where: { $0.roundNumber == saved.roundNumber }) {
                    attempt.round = roundPools[key]?.remove(at: index)
                }
            }
            return attempt
        }

        // The feed, with every recorded play wired back to an undo.
        var unclaimed = GameEvent.chronological(game.events)
        var rebuilt: [LiveEvent] = []
        for line in state.feed {
            switch line.kind {
            case "action":
                if let created = line.eventCreatedAt,
                   let index = unclaimed.firstIndex(where: { abs($0.createdAt.timeIntervalSince(created)) < 0.002 }) {
                    let gameEvent = unclaimed.remove(at: index)
                    rebuilt.append(LiveEvent(emoji: line.emoji, description: line.description, undoClosure: genericUndo(for: gameEvent), gameEvent: gameEvent))
                } else {
                    rebuilt.append(LiveEvent(emoji: line.emoji, description: line.description, undoClosure: nil))
                }
            case "transition":
                if let snap = line.transition {
                    rebuilt.append(transitionEvent(emoji: line.emoji, description: line.description, snapshot: snap))
                } else {
                    rebuilt.append(LiveEvent(emoji: line.emoji, description: line.description, undoClosure: nil))
                }
            case "shootout":
                if let index = line.attemptIndex, shootoutAttempts.indices.contains(index) {
                    let id = shootoutAttempts[index].id
                    rebuilt.append(LiveEvent(
                        emoji: line.emoji,
                        description: line.description,
                        undoClosure: { [weak self] in self?.removeShootoutAttempt(id: id, removeEvent: false) },
                        kind: .shootout,
                        shootoutAttemptId: id
                    ))
                }
            default:
                rebuilt.append(LiveEvent(emoji: line.emoji, description: line.description, undoClosure: nil, kind: .note))
            }
        }
        // A play the saved feed never mentioned still gets a line, so nothing
        // recorded is hidden from the scorekeeper.
        for gameEvent in unclaimed {
            rebuilt.append(LiveEvent(
                emoji: Self.emoji(forEventType: gameEvent.type),
                description: Self.describe(gameEvent),
                undoClosure: genericUndo(for: gameEvent),
                gameEvent: gameEvent
            ))
        }
        events = rebuilt
        recomputeShootout()
        events.append(LiveEvent(emoji: "▶️", description: "— Resumed —", undoClosure: nil, kind: .note))
        initializeStatsForCheckedInPlayers()
    }

    /// An undo for a play whose original closure was lost with the process:
    /// reverse its stat impact and delete it, the same way the post-game
    /// editor does, plus the score, plus/minus and penalty-timer effects the
    /// editor does not track.
    private func genericUndo(for gameEvent: GameEvent) -> () -> Void {
        { [weak self] in
            guard let self else { return }
            // Stats and +/- (from the skaters stored on the event) — the same
            // reversal the post-game editor uses.
            EventStatAdjuster.subtract(gameEvent, game: self.game)
            switch gameEvent.type {
            case "goal":
                self.game.goalsFor = max(0, self.game.goalsFor - 1)
            case "goalAgainst":
                self.game.goalsAgainst = max(0, self.game.goalsAgainst - 1)
            case "penalty":
                if let index = self.activePenalties.firstIndex(where: {
                    $0.isOurs && $0.playerNumber == gameEvent.playerNumber && $0.type.rawValue == gameEvent.penaltyType
                }) {
                    self.activePenalties.remove(at: index)
                }
            case "penaltyAgainst":
                if let index = self.activePenalties.firstIndex(where: {
                    !$0.isOurs && $0.playerNumber == (Int(gameEvent.opponentNumber) ?? 0) && $0.type.rawValue == gameEvent.penaltyType
                }) {
                    self.activePenalties.remove(at: index)
                }
            case "goalieChange":
                // Back to whoever was in net before this change.
                let log = self.events.compactMap(\.gameEvent)
                let earlier = log.prefix { $0 !== gameEvent }.last { $0.type == "goalieChange" }
                let previous = earlier.flatMap { change in
                    (self.checkedInPlayers + self.availablePlayers).first { $0.playerId == change.playerId }
                } ?? self.game.startingGoalie
                let removed = (self.checkedInPlayers + self.availablePlayers).first { $0.playerId == gameEvent.playerId }
                if let previous { self.applyGoalie(previous) }
                if let removed { self.pruneEmptyGoalieLine(for: removed) }
            default:
                break
            }
            self.removeGameEvent(gameEvent)
        }
    }

    private static func emoji(forEventType type: String) -> String {
        switch type {
        case "goal", "goalAgainst": "🚨"
        case "shot": "🏒"
        case "shotAgainst": "🧤"
        case "penalty", "penaltyAgainst": "🚫"
        case "faceoffWin", "faceoffLoss": "🏑"
        case "hit": "💥"
        case "block": "🛡️"
        default: "📝"
        }
    }

    private static func describe(_ event: GameEvent) -> String {
        let who = event.playerName.isEmpty ? "" : " #\(event.playerNumber) \(event.playerName)"
        let time = event.clockTime.isEmpty ? "" : " \(event.clockTime)"
        let what: String
        switch event.type {
        case "goal": what = "GOAL"
        case "goalAgainst": what = "GOAL AGAINST"
        case "shot": what = "Shot"
        case "shotAgainst": what = "Shot Against"
        case "penalty": what = "\(event.penaltyType) (\(event.penaltyMinutes) min)"
        case "penaltyAgainst": what = "OPP #\(event.opponentNumber) — \(event.penaltyType)"
        case "faceoffWin": what = "FO Won"
        case "faceoffLoss": what = "FO Lost"
        case "hit": what = "Hit"
        case "block": what = "Block"
        default: what = event.type
        }
        return "P\(event.period)\(time)\(who) — \(what)"
    }

    /// Take a game that was ended back to live scoring. Reverses what
    /// "End Game" derived — result, goalie decision, game-winning goal — so
    /// they are recomputed when the game is ended again.
    func reopenAfterEnd() {
        game.hasLocalEdits = true
        game.isComplete = false
        game.result = ""
        for stats in game.goalieStats { stats.result = "" }
        for stats in game.playerStats { stats.gameWinningGoals = 0 }
        events.append(LiveEvent(emoji: "🔓", description: "— Game reopened —", undoClosure: nil, kind: .note))
        livePublishingSuspended = false
        save()
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
