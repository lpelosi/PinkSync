import SwiftUI
import SwiftData

struct GameEventEditorView: View {
    @Bindable var game: Game
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var editingEvent: GameEvent?
    @State private var didModify = false

    private var enrolledPlayers: [Player] {
        game.playerStats.compactMap { $0.player }
            .sorted { $0.number < $1.number }
    }

    private var sortedEvents: [GameEvent] {
        game.events.sorted { a, b in
            if a.period != b.period { return a.period < b.period }
            return a.clockTime > b.clockTime
        }
    }

    private var groupedEvents: [(period: Int, events: [GameEvent])] {
        Dictionary(grouping: sortedEvents, by: \.period)
            .map { (period: $0.key, events: $0.value) }
            .sorted { $0.period < $1.period }
    }

    var body: some View {
        List {
            if didModify && game.isSynced {
                Section {
                    Label("Modified — re-send stats to update the server.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            if game.events.isEmpty {
                Section {
                    Text("No events recorded for this game.")
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(groupedEvents, id: \.period) { group in
                Section(periodName(group.period)) {
                    ForEach(group.events, id: \.persistentModelID) { event in
                        Button {
                            if isEditable(event) {
                                editingEvent = event
                            }
                        } label: {
                            eventRow(event)
                        }
                        .tint(.primary)
                        .disabled(!isEditable(event))
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                deleteEvent(event)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Edit Events")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
                    .fontWeight(.bold)
            }
        }
        .sheet(isPresented: Binding(
            get: { editingEvent != nil },
            set: { if !$0 { editingEvent = nil } }
        )) {
            if let event = editingEvent {
                NavigationStack {
                    EditEventSheet(
                        event: event,
                        game: game,
                        enrolledPlayers: enrolledPlayers,
                        onSave: {
                            didModify = true
                            if game.isSynced {
                                // Clear synced flag so the user knows to re-send
                                game.isSynced = false
                            }
                            try? modelContext.save()
                        }
                    )
                }
            }
        }
    }

    // MARK: - Helpers

    private func isEditable(_ event: GameEvent) -> Bool {
        switch event.type {
        case "penalty", "penaltyAgainst", "goal", "shot", "hit", "block", "faceoffWin", "faceoffLoss":
            return true
        default:
            return false
        }
    }

    private func periodName(_ period: Int) -> String {
        switch period {
        case 1: "1st"
        case 2: "2nd"
        case 3: "3rd"
        case 4: "OT"
        default: "Shootout"
        }
    }

    @ViewBuilder
    private func eventRow(_ event: GameEvent) -> some View {
        HStack(spacing: 8) {
            Image(systemName: iconForType(event.type))
                .foregroundStyle(colorForType(event.type))
                .frame(width: 18)

            if !event.clockTime.isEmpty {
                Text(event.clockTime)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(primaryText(for: event))
                    .font(.subheadline.weight(.semibold))
                if let detail = detailText(for: event) {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if isEditable(event) {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func primaryText(for event: GameEvent) -> String {
        switch event.type {
        case "goal":
            return "🚨 GOAL — \(playerLabel(event)) \(strengthSuffix(event))"
        case "shot":
            return "Shot — \(playerLabel(event))"
        case "hit":
            return "Hit — \(playerLabel(event))"
        case "block":
            return "Block — \(playerLabel(event))"
        case "faceoffWin":
            return "FO Won — \(playerLabel(event))"
        case "faceoffLoss":
            return "FO Lost — \(playerLabel(event))"
        case "penalty":
            return "Penalty — \(playerLabel(event))"
        case "penaltyAgainst":
            let num = event.opponentNumber.isEmpty ? "?" : event.opponentNumber
            return "Penalty — OPP #\(num)"
        case "goalAgainst":
            return "Goal Against \(strengthSuffix(event))"
        case "shotAgainst":
            return "Shot Against"
        default:
            return event.type
        }
    }

    private func detailText(for event: GameEvent) -> String? {
        switch event.type {
        case "penalty", "penaltyAgainst":
            guard !event.penaltyType.isEmpty else { return nil }
            return "\(event.penaltyType) (\(event.penaltyMinutes) min)"
        case "goal":
            var parts: [String] = []
            if event.assist1Number > 0 || !event.assist1Name.isEmpty {
                parts.append("A: #\(event.assist1Number) \(event.assist1Name)")
            }
            if event.assist2Number > 0 || !event.assist2Name.isEmpty {
                parts.append("#\(event.assist2Number) \(event.assist2Name)")
            }
            return parts.isEmpty ? nil : parts.joined(separator: ", ")
        default:
            return nil
        }
    }

    private func playerLabel(_ event: GameEvent) -> String {
        let num = event.playerNumber > 0 ? "#\(event.playerNumber)" : ""
        return "\(num) \(event.playerName)".trimmingCharacters(in: .whitespaces)
    }

    private func strengthSuffix(_ event: GameEvent) -> String {
        if event.isPowerPlay { return "(PP)" }
        if event.isShortHanded { return "(SH)" }
        return ""
    }

    private func iconForType(_ type: String) -> String {
        switch type {
        case "goal", "goalAgainst": "circle.fill"
        case "shot", "shotAgainst": "hockey.puck"
        case "hit": "figure.american.football"
        case "block": "shield.fill"
        case "faceoffWin", "faceoffLoss": "circle.dotted"
        case "penalty", "penaltyAgainst": "exclamationmark.octagon.fill"
        default: "questionmark.circle"
        }
    }

    private func colorForType(_ type: String) -> Color {
        switch type {
        case "goal": AppTheme.pink
        case "goalAgainst": AppTheme.teal
        case "penalty", "penaltyAgainst": .red
        default: .secondary
        }
    }

    private func deleteEvent(_ event: GameEvent) {
        EventStatAdjuster.subtract(event, game: game)
        modelContext.delete(event)
        didModify = true
        if game.isSynced { game.isSynced = false }
        try? modelContext.save()
    }
}

// MARK: - Edit Event Sheet

private struct EditEventSheet: View {
    @Bindable var event: GameEvent
    let game: Game
    let enrolledPlayers: [Player]
    let onSave: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPlayerId: PersistentIdentifier?
    @State private var assist1Id: PersistentIdentifier?
    @State private var assist2Id: PersistentIdentifier?
    @State private var clockTime: String = ""
    @State private var period: Int = 1
    @State private var penaltyType: PenaltyType = .minor
    @State private var opponentNumber: String = ""
    @State private var isPowerPlay: Bool = false
    @State private var isShortHanded: Bool = false

    private var isPenalty: Bool { event.type == "penalty" || event.type == "penaltyAgainst" }
    private var isOurEventWithPlayer: Bool {
        ["penalty", "goal", "shot", "hit", "block", "faceoffWin", "faceoffLoss"].contains(event.type)
    }
    private var isGoal: Bool { event.type == "goal" }

    var body: some View {
        Form {
            Section("Period") {
                Picker("Period", selection: $period) {
                    Text("1st").tag(1)
                    Text("2nd").tag(2)
                    Text("3rd").tag(3)
                    Text("OT").tag(4)
                }
                .pickerStyle(.segmented)
            }

            Section("Time") {
                ClockTimeField(time: $clockTime)
            }

            if isOurEventWithPlayer {
                Section("Player") {
                    Picker("Player", selection: $selectedPlayerId) {
                        Text("—").tag(PersistentIdentifier?.none)
                        ForEach(enrolledPlayers) { player in
                            Text("#\(player.number) \(player.name)")
                                .tag(Optional(player.persistentModelID))
                        }
                    }
                }
            }

            if event.type == "penaltyAgainst" {
                Section("Opponent Jersey #") {
                    TextField("#", text: $opponentNumber)
                        .keyboardType(.numberPad)
                }
            }

            if isPenalty {
                Section("Penalty Type") {
                    Picker("Type", selection: $penaltyType) {
                        ForEach(PenaltyType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                }
            }

            if isGoal {
                Section("Assists") {
                    Picker("Primary Assist", selection: $assist1Id) {
                        Text("—").tag(PersistentIdentifier?.none)
                        ForEach(enrolledPlayers) { player in
                            Text("#\(player.number) \(player.name)")
                                .tag(Optional(player.persistentModelID))
                        }
                    }
                    Picker("Secondary Assist", selection: $assist2Id) {
                        Text("—").tag(PersistentIdentifier?.none)
                        ForEach(enrolledPlayers) { player in
                            Text("#\(player.number) \(player.name)")
                                .tag(Optional(player.persistentModelID))
                        }
                    }
                }

                Section("Strength") {
                    Toggle("Power Play", isOn: $isPowerPlay)
                    Toggle("Short-Handed", isOn: $isShortHanded)
                }
            }
        }
        .navigationTitle("Edit Event")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    applyChanges()
                    dismiss()
                }
                .fontWeight(.bold)
            }
        }
        .onAppear { loadInitialState() }
    }

    private func loadInitialState() {
        period = event.period
        clockTime = event.clockTime
        opponentNumber = event.opponentNumber
        isPowerPlay = event.isPowerPlay
        isShortHanded = event.isShortHanded
        selectedPlayerId = enrolledPlayers.first { $0.number == event.playerNumber && $0.name == event.playerName }?.persistentModelID
        assist1Id = enrolledPlayers.first { $0.number == event.assist1Number && $0.name == event.assist1Name }?.persistentModelID
        assist2Id = enrolledPlayers.first { $0.number == event.assist2Number && $0.name == event.assist2Name }?.persistentModelID
        if !event.penaltyType.isEmpty,
           let type = PenaltyType.allCases.first(where: { $0.rawValue == event.penaltyType }) {
            penaltyType = type
        }
    }

    private func applyChanges() {
        // Reverse old stat impact
        EventStatAdjuster.subtract(event, game: game)

        // Mutate event
        event.period = period
        event.clockTime = clockTime
        event.opponentNumber = opponentNumber
        event.isPowerPlay = isPowerPlay
        event.isShortHanded = isShortHanded

        if isOurEventWithPlayer, let id = selectedPlayerId,
           let player = enrolledPlayers.first(where: { $0.persistentModelID == id }) {
            event.playerName = player.name
            event.playerNumber = player.number
        }

        if isPenalty {
            event.penaltyType = penaltyType.rawValue
            event.penaltyMinutes = penaltyType.minutes
        }

        if isGoal {
            if let id = assist1Id, let p = enrolledPlayers.first(where: { $0.persistentModelID == id }) {
                event.assist1Name = p.name
                event.assist1Number = p.number
            } else {
                event.assist1Name = ""
                event.assist1Number = 0
            }
            if let id = assist2Id, let p = enrolledPlayers.first(where: { $0.persistentModelID == id }) {
                event.assist2Name = p.name
                event.assist2Number = p.number
            } else {
                event.assist2Name = ""
                event.assist2Number = 0
            }
        }

        // Apply new stat impact
        EventStatAdjuster.add(event, game: game)

        try? modelContext.save()
        onSave()
    }
}

// MARK: - Stat Adjuster

/// Applies or reverses the GamePlayerStats / GameGoalieStats impact of a single event.
/// Players on events are matched by (name, number) since GameEvent does not store playerId.
enum EventStatAdjuster {
    static func add(_ event: GameEvent, game: Game) {
        apply(event, game: game, sign: 1)
    }

    static func subtract(_ event: GameEvent, game: Game) {
        apply(event, game: game, sign: -1)
    }

    private static func apply(_ event: GameEvent, game: Game, sign: Int) {
        switch event.type {
        case "goal":
            adjustPlayer(game: game, id: event.playerId, name: event.playerName, number: event.playerNumber) { s in
                s.goals += sign
                if event.isPowerPlay { s.powerPlayGoals += sign }
                if event.isShortHanded { s.shortHandedGoals += sign }
            }
            if event.assist1Number > 0 || !event.assist1Name.isEmpty {
                adjustPlayer(game: game, id: event.assist1Id, name: event.assist1Name, number: event.assist1Number) { s in
                    s.assists += sign
                    if event.isPowerPlay { s.powerPlayAssists += sign }
                    if event.isShortHanded { s.shortHandedAssists += sign }
                }
            }
            if event.assist2Number > 0 || !event.assist2Name.isEmpty {
                adjustPlayer(game: game, id: event.assist2Id, name: event.assist2Name, number: event.assist2Number) { s in
                    s.assists += sign
                    if event.isPowerPlay { s.powerPlayAssists += sign }
                    if event.isShortHanded { s.shortHandedAssists += sign }
                }
            }
        case "shot":
            adjustPlayer(game: game, id: event.playerId, name: event.playerName, number: event.playerNumber) { $0.shots += sign }
        case "hit":
            adjustPlayer(game: game, id: event.playerId, name: event.playerName, number: event.playerNumber) { $0.hits += sign }
        case "block":
            adjustPlayer(game: game, id: event.playerId, name: event.playerName, number: event.playerNumber) { $0.blocks += sign }
        case "faceoffWin":
            adjustPlayer(game: game, id: event.playerId, name: event.playerName, number: event.playerNumber) { $0.faceoffWins += sign }
        case "faceoffLoss":
            adjustPlayer(game: game, id: event.playerId, name: event.playerName, number: event.playerNumber) { $0.faceoffLosses += sign }
        case "penalty":
            adjustPlayer(game: game, id: event.playerId, name: event.playerName, number: event.playerNumber) {
                $0.penaltyMinutes += sign * event.penaltyMinutes
            }
        case "shotAgainst":
            adjustGoalie(game: game) { $0.shotsAgainst += sign }
        case "goalAgainst":
            adjustGoalie(game: game) {
                $0.shotsAgainst += sign
                $0.goalsAgainst += sign
            }
        default:
            break
        }
    }

    /// Find the GamePlayerStats for this event participant. Prefers stable playerId;
    /// only falls back to name+number for legacy events that pre-date playerId on GameEvent.
    private static func adjustPlayer(game: Game, id: String, name: String, number: Int, _ change: (GamePlayerStats) -> Void) {
        if !id.isEmpty,
           let stat = game.playerStats.first(where: { $0.player?.playerId == id }) {
            change(stat)
            return
        }
        if let stat = game.playerStats.first(where: { $0.player?.name == name && $0.player?.number == number }) {
            change(stat)
        }
    }

    private static func adjustGoalie(game: Game, _ change: (GameGoalieStats) -> Void) {
        guard let stat = game.goalieStats.first else { return }
        change(stat)
    }
}
