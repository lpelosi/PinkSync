import SwiftUI
import SwiftData

struct LiveGameView: View {
    @Bindable var vm: LiveGameViewModel
    let onEnd: () -> Void

    @State private var showingEndConfirm = false
    @State private var showingPlayerPicker = false
    @State private var showingGoalFlow = false
    @State private var showingPenaltyEntry = false
    @State private var showingOpponentPenalty = false
    @State private var showingShootoutPlayerPicker = false
    @State private var pendingAction: LiveAction?

    var body: some View {
        VStack(spacing: 0) {
            scoreboard

            switch vm.period {
            case .regulation, .overtime:
                actionButtons
                periodTransitionButton
            case .shootout:
                shootoutControls
            }

            eventFeed
            undoBar
        }
        .background(Color(.systemBackground))
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .alert("End Game?", isPresented: $showingEndConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("End Game", role: .destructive) {
                vm.computeResult()
                onEnd()
            }
        } message: {
            let result = autoResultLabel
            Text("Result: \(result). Stats have been saved.")
        }
        .sheet(isPresented: $showingPlayerPicker) {
            playerPickerSheet
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingGoalFlow) {
            GoalFlowSheet(vm: vm) {
                showingGoalFlow = false
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingPenaltyEntry) {
            PenaltyEntryView(
                isOurs: true,
                players: vm.skaters,
                excluded: []
            ) { player, _, type in
                if let player {
                    vm.recordPenalty(player: player, type: type)
                }
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showingOpponentPenalty) {
            PenaltyEntryView(
                isOurs: false,
                players: [],
                excluded: []
            ) { _, number, type in
                vm.recordOpponentPenalty(jerseyNumber: number, type: type)
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingShootoutPlayerPicker) {
            LivePlayerPickerView(
                players: vm.skaters,
                title: "Who's shooting?",
                skipLabel: nil,
                excluded: []
            ) { player in
                guard let player else { return }
                shootoutPlayerPicked = player
                showingShootoutResult = true
            }
            .presentationDetents([.medium])
        }
        .alert("Result?", isPresented: $showingShootoutResult) {
            Button("Goal") {
                if let player = shootoutPlayerPicked {
                    vm.recordShootoutAttempt(player: player, isGoal: true)
                }
                shootoutPlayerPicked = nil
            }
            Button("Miss") {
                if let player = shootoutPlayerPicked {
                    vm.recordShootoutAttempt(player: player, isGoal: false)
                }
                shootoutPlayerPicked = nil
            }
        } message: {
            if let player = shootoutPlayerPicked {
                Text("Did \(vm.playerLabel(player)) score?")
            }
        }
    }

    @State private var shootoutPlayerPicked: Player?
    @State private var showingShootoutResult = false

    // MARK: - Scoreboard

    private var scoreboard: some View {
        VStack(spacing: 8) {
            HStack {
                Text(vm.period.rawValue)
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(periodColor.opacity(0.2), in: Capsule())
                    .foregroundStyle(periodColor)

                Spacer()

                Button {
                    showingEndConfirm = true
                } label: {
                    Text("End Game")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.red.opacity(0.8), in: Capsule())
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)

            HStack(spacing: 20) {
                VStack {
                    Text("FF")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.pink)
                    Text("\(vm.game.goalsFor)")
                        .font(.system(size: 48, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppTheme.pink)
                }

                Text("—")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(.secondary)

                VStack {
                    Text(abbreviate(vm.game.opponent))
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.teal)
                    Text("\(vm.game.goalsAgainst)")
                        .font(.system(size: 48, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppTheme.teal)
                }
            }
            .padding(.bottom, 8)
        }
        .background(Color(.systemGray6))
    }

    private var periodColor: Color {
        switch vm.period {
        case .regulation: .secondary
        case .overtime: .orange
        case .shootout: .purple
        }
    }

    // MARK: - Action Buttons (Regulation & OT)

    private var actionButtons: some View {
        HStack(spacing: 12) {
            VStack(spacing: 8) {
                Text("Us")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.pink)
                actionButton("Shot", emoji: "🏒", color: AppTheme.pink) {
                    pendingAction = .shot
                    showingPlayerPicker = true
                }
                actionButton("Goal", emoji: "🚨", color: AppTheme.pink) {
                    vm.startGoalFlow()
                    showingGoalFlow = true
                }
                actionButton("Hit", emoji: "💥", color: AppTheme.pink) {
                    pendingAction = .hit
                    showingPlayerPicker = true
                }
                actionButton("Block", emoji: "🛡️", color: AppTheme.pink) {
                    pendingAction = .block
                    showingPlayerPicker = true
                }
                actionButton("Penalty", emoji: "🚫", color: AppTheme.pink) {
                    showingPenaltyEntry = true
                }
            }

            VStack(spacing: 8) {
                Text("Them")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.teal)
                actionButton("Shot", emoji: "🧤", color: AppTheme.teal) {
                    vm.recordShotAgainst()
                }
                actionButton("Goal", emoji: "🚨", color: AppTheme.teal) {
                    vm.recordGoalAgainst()
                }
                actionButton("Penalty", emoji: "🚫", color: AppTheme.teal) {
                    showingOpponentPenalty = true
                }
            }
        }
        .padding()
    }

    private func actionButton(_ label: String, emoji: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(emoji)
                    .font(.title3)
                Text(label)
                    .font(.system(size: 16, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(color, in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(.white)
        }
    }

    // MARK: - Period Transition

    @ViewBuilder
    private var periodTransitionButton: some View {
        if vm.period == .regulation {
            Button {
                vm.goToOvertime()
            } label: {
                Label("Going to Overtime", systemImage: "clock.badge.exclamationmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(.orange, in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal)
        } else if vm.period == .overtime {
            Button {
                vm.goToShootout()
            } label: {
                Label("Going to Shootout", systemImage: "target")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(.purple, in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Shootout Controls

    private var shootoutControls: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Round \(vm.shootoutRoundNumber)")
                    .font(.headline)
                Spacer()
                Text("SO: \(vm.ourShootoutGoals) – \(vm.theirShootoutGoals)")
                    .font(.system(.body, design: .monospaced, weight: .bold))
            }
            .padding(.horizontal)

            HStack(spacing: 12) {
                VStack(spacing: 8) {
                    Text("Our Shot")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.pink)
                    Button {
                        showingShootoutPlayerPicker = true
                    } label: {
                        HStack {
                            Text("🎯")
                                .font(.title3)
                            Text("Pick Shooter")
                                .font(.system(size: 16, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background(vm.isOurShootoutTurn ? AppTheme.pink : Color(.systemGray4), in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                    }
                    .disabled(!vm.isOurShootoutTurn)
                }

                VStack(spacing: 8) {
                    Text("Their Shot")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.teal)

                    HStack(spacing: 8) {
                        Button {
                            vm.recordShootoutAttemptAgainst(isGoal: true)
                        } label: {
                            Text("Goal")
                                .font(.system(size: 15, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 60)
                                .background(vm.isOurShootoutTurn ? Color(.systemGray4) : Color.red, in: RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(.white)
                        }
                        .disabled(vm.isOurShootoutTurn)

                        Button {
                            vm.recordShootoutAttemptAgainst(isGoal: false)
                        } label: {
                            Text("Save")
                                .font(.system(size: 15, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 60)
                                .background(vm.isOurShootoutTurn ? Color(.systemGray4) : Color.green, in: RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(.white)
                        }
                        .disabled(vm.isOurShootoutTurn)
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 12)
    }

    // MARK: - Event Feed

    private var eventFeed: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(vm.events) { event in
                        HStack(spacing: 8) {
                            Text(event.emoji)
                                .font(.body)
                            Text(event.description)
                                .font(.system(size: 14, weight: .medium))
                            Spacer()
                            Text(event.timestamp, style: .time)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                        .id(event.id)
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .background(Color(.systemBackground))
            .onChange(of: vm.events.count) {
                if let last = vm.events.last {
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Undo Bar

    private var undoBar: some View {
        HStack {
            if let last = vm.events.last, last.undoClosure != nil {
                Button {
                    vm.undoLast()
                } label: {
                    Label("Undo: \(last.description)", systemImage: "arrow.uturn.backward")
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(Color(.systemGray3), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    // MARK: - Player Picker Sheet

    @ViewBuilder
    private var playerPickerSheet: some View {
        LivePlayerPickerView(
            players: vm.skaters,
            title: pickerTitle,
            skipLabel: nil,
            excluded: []
        ) { player in
            guard let player else { return }
            switch pendingAction {
            case .shot: vm.recordShot(player: player)
            case .hit: vm.recordHit(player: player)
            case .block: vm.recordBlock(player: player)
            default: break
            }
            pendingAction = nil
        }
    }

    private var pickerTitle: String {
        switch pendingAction {
        case .shot: "Who took the shot?"
        case .hit: "Who made the hit?"
        case .block: "Who blocked?"
        default: "Select Player"
        }
    }

    // MARK: - Helpers

    private var autoResultLabel: String {
        if vm.game.goalsFor == vm.game.goalsAgainst {
            return "Tied — record overtime or shootout first"
        }
        let weWin = vm.game.goalsFor > vm.game.goalsAgainst
        switch vm.period {
        case .regulation: return weWin ? "Win" : "Loss"
        case .overtime: return weWin ? "Win" : "OT Loss"
        case .shootout: return weWin ? "SO Win" : "SO Loss"
        }
    }

    private func abbreviate(_ name: String) -> String {
        let words = name.components(separatedBy: " ")
        if words.count >= 2 {
            return String(words.prefix(2).compactMap(\.first))
        }
        return String(name.prefix(3)).uppercased()
    }
}

// MARK: - Goal Flow Sheet

private struct GoalFlowSheet: View {
    @Bindable var vm: LiveGameViewModel
    let onDone: () -> Void

    private var availablePlayers: [Player] {
        vm.skaters.filter { !vm.goalFlowExcludedPlayers.contains($0.persistentModelID) }
    }

    private let columns = [GridItem(.adaptive(minimum: 80), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(availablePlayers) { player in
                        Button {
                            pickPlayer(player)
                        } label: {
                            VStack(spacing: 4) {
                                Text(player.number > 0 ? "\(player.number)" : "—")
                                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.white)
                                Text(lastName(player.name))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.8))
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 80)
                            .background(AppTheme.pink, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                .padding()

                if vm.goalFlowStep == .pickPrimaryAssist {
                    skipButton("No Assist") {
                        vm.goalFlowPickPrimaryAssist(nil)
                        onDone()
                    }
                }

                if vm.goalFlowStep == .pickSecondaryAssist {
                    skipButton("No 2nd Assist") {
                        vm.goalFlowPickSecondaryAssist(nil)
                        onDone()
                    }
                }
            }
            .navigationTitle(stepTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        vm.currentAction = nil
                        onDone()
                    }
                }
            }
        }
    }

    private var stepTitle: String {
        switch vm.goalFlowStep {
        case .pickScorer: "Who scored?"
        case .pickPrimaryAssist: "Primary Assist?"
        case .pickSecondaryAssist: "Secondary Assist?"
        }
    }

    private func pickPlayer(_ player: Player) {
        switch vm.goalFlowStep {
        case .pickScorer:
            vm.goalFlowPickScorer(player)
        case .pickPrimaryAssist:
            vm.goalFlowPickPrimaryAssist(player)
            if vm.goalFlowStep == .pickSecondaryAssist {
                return
            }
            onDone()
        case .pickSecondaryAssist:
            vm.goalFlowPickSecondaryAssist(player)
            onDone()
        }
    }

    private func skipButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.headline)
                .foregroundStyle(AppTheme.teal)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .padding(.horizontal)
        .padding(.bottom)
    }

    private func lastName(_ name: String) -> String {
        name.components(separatedBy: " ").last ?? name
    }
}
