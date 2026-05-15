import SwiftUI
import SwiftData

struct LiveGameView: View {
    @Bindable var vm: LiveGameViewModel
    let onEnd: () -> Void

    private enum ActiveSheet: Identifiable {
        case playerPicker
        case goalFlow
        case penaltyEntry
        case opponentPenalty
        case goalAgainstTime
        case faceoffPicker
        case shootoutPlayerPicker
        case lineSetup
        case periodSummary
        case editEvent(Int)
        case clockEdit
        case benchPicker
        case onIceManager

        var id: String {
            switch self {
            case .editEvent(let idx): return "editEvent_\(idx)"
            default: return String(describing: self)
            }
        }
    }

    @State private var activeSheet: ActiveSheet?
    @State private var showingEndConfirm = false
    @State private var showingDeleteConfirm = false
    @State private var goalAgainstClockTime = ""
    @State private var pendingAction: LiveAction?
    @State private var eventToDelete: Int?
    @State private var editClockMinutes = 0
    @State private var editClockSeconds = 0
    @State private var playerToSub: Player?

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                scoreboard

                switch vm.period {
                case .regulation, .overtime:
                    onIcePanel
                    lineFilterBar
                    actionButtons
                    quickRepeatBar
                    periodTransitionButton
                case .shootout:
                    shootoutControls
                }

                eventFeed
                undoBar
            }
            .background(Color(.systemBackground))

            goalFlashOverlay
        }
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
        .alert("Delete Event?", isPresented: $showingDeleteConfirm) {
            Button("Cancel", role: .cancel) { eventToDelete = nil }
            Button("Delete", role: .destructive) {
                if let idx = eventToDelete {
                    vm.deleteEvent(at: idx)
                }
                eventToDelete = nil
            }
        } message: {
            if let idx = eventToDelete, vm.events.indices.contains(idx) {
                Text(vm.events[idx].description)
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .playerPicker:
                LivePlayerPickerView(
                    players: vm.onIceSkatersSorted,
                    title: pickerTitle,
                    skipLabel: nil,
                    excluded: [],
                    onPick: { player in
                        guard let player else { return }
                        switch pendingAction {
                        case .shot: vm.recordShot(player: player)
                        case .hit: vm.recordHit(player: player)
                        case .block: vm.recordBlock(player: player)
                        default: break
                        }
                        pendingAction = nil
                    },
                    benchPlayers: vm.skaters
                )
                .presentationDetents([.medium, .large])
            case .goalFlow:
                GoalFlowSheet(vm: vm) {
                    activeSheet = nil
                }
                .presentationDetents([.medium, .large])
            case .penaltyEntry:
                PenaltyEntryView(
                    isOurs: true,
                    players: vm.onIceSkatersSorted,
                    excluded: [],
                    benchPlayers: vm.skaters
                ) { player, _, type, clockTime in
                    if let player {
                        vm.recordPenalty(player: player, type: type, clockTime: clockTime)
                    }
                }
                .presentationDetents([.large])
            case .opponentPenalty:
                PenaltyEntryView(
                    isOurs: false,
                    players: [],
                    excluded: []
                ) { _, number, type, clockTime in
                    vm.recordOpponentPenalty(jerseyNumber: number, type: type, clockTime: clockTime)
                }
                .presentationDetents([.medium])
            case .goalAgainstTime:
                GoalAgainstTimeSheet(clockTime: $goalAgainstClockTime, defaultPowerPlay: vm.shortHanded) { isPowerPlay in
                    vm.recordGoalAgainst(clockTime: goalAgainstClockTime, isPowerPlay: isPowerPlay)
                    goalAgainstClockTime = ""
                    activeSheet = nil
                }
                .presentationDetents([.medium])
            case .faceoffPicker:
                FaceoffPickerSheet(vm: vm)
                    .presentationDetents([.medium])
            case .shootoutPlayerPicker:
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
            case .lineSetup:
                LineSetupSheet(vm: vm)
                    .presentationDetents([.large])
            case .periodSummary:
                PeriodSummarySheet(summary: vm.currentPeriodSummary()) {
                    activeSheet = nil
                    vm.endPeriod()
                }
                .presentationDetents([.medium])
            case .editEvent(let index):
                EventEditSheet(vm: vm, eventIndex: index) {
                    activeSheet = nil
                } onDelete: {
                    activeSheet = nil
                    eventToDelete = index
                    showingDeleteConfirm = true
                }
                .presentationDetents([.medium, .large])
            case .clockEdit:
                ClockEditSheet(minutes: $editClockMinutes, seconds: $editClockSeconds) {
                    vm.setClockTime(minutes: editClockMinutes, seconds: editClockSeconds)
                    activeSheet = nil
                }
                .presentationDetents([.medium])
            case .benchPicker:
                BenchPickerSheet(vm: vm, subOutPlayer: playerToSub) {
                    activeSheet = nil
                    playerToSub = nil
                }
                .presentationDetents([.medium])
            case .onIceManager:
                OnIceManagerSheet(vm: vm)
                    .presentationDetents([.medium, .large])
            }
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

    // MARK: - Goal Flash Overlay

    @ViewBuilder
    private var goalFlashOverlay: some View {
        if let color = vm.goalFlashColor {
            (color == .pink ? AppTheme.pink : AppTheme.teal)
                .opacity(0.3)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .transition(.opacity)
                .animation(.easeOut(duration: 0.5), value: vm.goalFlashColor == nil)
        }
    }

    // MARK: - Scoreboard

    private var scoreboard: some View {
        VStack(spacing: 4) {
            // Top bar: period + clock + controls
            HStack(spacing: 8) {
                Text(periodDisplayLabel)
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(periodColor.opacity(0.2), in: Capsule())
                    .foregroundStyle(periodColor)

                if vm.isClockSetUp {
                    Button {
                        editClockMinutes = vm.clockSeconds / 60
                        editClockSeconds = vm.clockSeconds % 60
                        activeSheet = .clockEdit
                    } label: {
                        Text(vm.clockDisplay)
                            .font(.system(size: 28, weight: .bold, design: .monospaced))
                            .foregroundStyle(vm.clockRunning ? .primary : .secondary)
                            .contentTransition(.numericText())
                    }

                    Button {
                        vm.toggleClock()
                    } label: {
                        Image(systemName: vm.clockRunning ? "pause.fill" : "play.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(vm.clockRunning ? .orange : .green, in: Circle())
                    }
                } else {
                    clockSetupMenu
                }

                Spacer()

                Button {
                    activeSheet = .lineSetup
                } label: {
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .background(Color(.systemGray5), in: Circle())
                }

                Button {
                    showingEndConfirm = true
                } label: {
                    Text("End")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.red.opacity(0.8), in: Capsule())
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)

            // Score
            HStack(spacing: 20) {
                VStack(spacing: 2) {
                    Text("FF")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.pink)
                    Text("\(vm.game.goalsFor)")
                        .font(.system(size: 44, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppTheme.pink)
                    Text("SOG: \(vm.totalShotsFor)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Text("—")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.secondary)

                VStack(spacing: 2) {
                    Text(abbreviate(vm.game.opponent))
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.teal)
                    Text("\(vm.game.goalsAgainst)")
                        .font(.system(size: 44, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppTheme.teal)
                    Text("SOG: \(vm.totalShotsAgainst)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            // Penalty timers
            if !vm.activePenalties.isEmpty {
                penaltyTimersBar
            }
        }
        .padding(.bottom, 6)
        .background(Color(.systemGray6))
    }

    private var clockSetupMenu: some View {
        Menu {
            Button("12:00 (12 min)") { vm.setupClock(minutes: 12) }
            Button("15:00 (15 min)") { vm.setupClock(minutes: 15) }
            Button("20:00 (20 min)") { vm.setupClock(minutes: 20) }
            Button("25:00 (25 min)") { vm.setupClock(minutes: 25) }
        } label: {
            Label("Set Clock", systemImage: "clock")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(AppTheme.teal, in: Capsule())
        }
    }

    private var penaltyTimersBar: some View {
        HStack(spacing: 0) {
            // Our penalties (left side)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(vm.ourPenalties) { penalty in
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                        Text(penalty.display)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                    }
                    .foregroundStyle(AppTheme.pink)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Their penalties (right side)
            VStack(alignment: .trailing, spacing: 2) {
                ForEach(vm.theirPenalties) { penalty in
                    HStack(spacing: 4) {
                        Text(penalty.display)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(AppTheme.teal)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.3))
    }

    private var periodDisplayLabel: String {
        switch vm.period {
        case .regulation: vm.periodLabel
        case .overtime: "OT"
        case .shootout: "SO"
        }
    }

    private var periodColor: Color {
        switch vm.period {
        case .regulation: .secondary
        case .overtime: .orange
        case .shootout: .purple
        }
    }

    // MARK: - On Ice Panel

    @ViewBuilder
    private var onIcePanel: some View {
        VStack(spacing: 4) {
            if vm.onIceSkatersSorted.isEmpty {
                HStack {
                    Text("ON ICE")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        activeSheet = .onIceManager
                    } label: {
                        Text("Set Players")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(AppTheme.teal, in: Capsule())
                    }
                }
                .padding(.horizontal)
            } else {
                HStack(spacing: 0) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(vm.onIceSkatersSorted) { player in
                                let pos = vm.positionLabel(for: player)
                                Button {
                                    playerToSub = player
                                    activeSheet = .benchPicker
                                } label: {
                                    VStack(spacing: 0) {
                                        if !pos.isEmpty {
                                            Text(pos)
                                                .font(.system(size: 8, weight: .heavy))
                                                .foregroundStyle(.white.opacity(0.7))
                                        }
                                        Text("\(player.number)")
                                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                                            .foregroundStyle(.white)
                                        Text(vm.formatTOI(vm.currentShiftSeconds[player.persistentModelID] ?? 0))
                                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                                            .foregroundStyle(.white.opacity(0.7))
                                    }
                                    .frame(width: 42, height: pos.isEmpty ? 36 : 42)
                                    .background(
                                        vm.isForwardPosition(player.position) ? AppTheme.pink : AppTheme.teal,
                                        in: RoundedRectangle(cornerRadius: 6)
                                    )
                                }
                            }
                        }
                        .padding(.leading)
                    }

                    Button {
                        activeSheet = .onIceManager
                    } label: {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 36)
                            .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .padding(.trailing)
                }
            }

        }
        .padding(.vertical, 4)
        .background(Color(.systemGray6).opacity(0.3))
    }

    // MARK: - Line Filter Bar

    @ViewBuilder
    private var lineFilterBar: some View {
        let fwdLines = vm.configuredForwardLines
        let defPairings = vm.configuredDefensePairings
        if !fwdLines.isEmpty || !defPairings.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    lineFilterPill("All", isActive: vm.activeLineFilter == nil) {
                        vm.activeLineFilter = nil
                    }
                    ForEach(fwdLines, id: \.self) { line in
                        lineFilterPill(line, color: AppTheme.pink, isActive: vm.activeLineFilter == line) {
                            vm.activeLineFilter = (vm.activeLineFilter == line) ? nil : line
                            vm.sendLineOn(line)
                        }
                    }
                    if !fwdLines.isEmpty && !defPairings.isEmpty {
                        Divider().frame(height: 20)
                    }
                    ForEach(defPairings, id: \.self) { pair in
                        lineFilterPill(pair, color: AppTheme.teal, isActive: vm.activeLineFilter == pair) {
                            vm.activeLineFilter = (vm.activeLineFilter == pair) ? nil : pair
                            vm.sendLineOn(pair)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
            }
            .background(Color(.systemGray6).opacity(0.5))
        }
    }

    private func lineFilterPill(_ label: String, color: Color = AppTheme.pink, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(isActive ? .white : .secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(isActive ? color : Color(.systemGray5), in: Capsule())
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
                    activeSheet = .playerPicker
                }
                actionButton("Goal", emoji: "🚨", color: AppTheme.pink) {
                    vm.startGoalFlow()
                    activeSheet = .goalFlow
                }
                actionButton("Hit", emoji: "💥", color: AppTheme.pink) {
                    pendingAction = .hit
                    activeSheet = .playerPicker
                }
                actionButton("Block", emoji: "🛡️", color: AppTheme.pink) {
                    pendingAction = .block
                    activeSheet = .playerPicker
                }
                actionButton("Faceoff", emoji: "🏑", color: AppTheme.pink) {
                    activeSheet = .faceoffPicker
                }
                actionButton("Penalty", emoji: "🚫", color: AppTheme.pink) {
                    activeSheet = .penaltyEntry
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
                    goalAgainstClockTime = ""
                    activeSheet = .goalAgainstTime
                }
                actionButton("Penalty", emoji: "🚫", color: AppTheme.teal) {
                    activeSheet = .opponentPenalty
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
            .frame(height: 48)
            .background(color, in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(.white)
        }
    }

    // MARK: - Quick Repeat

    @ViewBuilder
    private var quickRepeatBar: some View {
        if let label = vm.quickRepeatLabel {
            Button {
                vm.executeQuickRepeat()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.counterclockwise")
                    Text(label)
                }
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(AppTheme.pink.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(.horizontal)
            .padding(.bottom, 4)
        }
    }

    // MARK: - Period Transition

    @ViewBuilder
    private var periodTransitionButton: some View {
        if vm.period == .regulation && vm.currentPeriod < 3 {
            Button {
                activeSheet = .periodSummary
            } label: {
                Label("End \(vm.periodLabel) Period", systemImage: "forward.end.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(.systemGray2), in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal)
        } else if vm.period == .regulation && vm.currentPeriod == 3 {
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
                        activeSheet = .shootoutPlayerPicker
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

    // MARK: - Event Feed (tap to delete)

    private var eventFeed: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(vm.events.enumerated()), id: \.element.id) { index, event in
                        Button {
                            if event.gameEvent != nil {
                                activeSheet = .editEvent(index)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Text(event.emoji)
                                    .font(.body)
                                Text(event.description)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.primary)
                                Spacer()
                                if event.gameEvent != nil {
                                    Image(systemName: "pencil.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.secondary.opacity(0.4))
                                }
                                Text(event.timestamp, style: .time)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
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

    // MARK: - Helpers

    private var pickerTitle: String {
        switch pendingAction {
        case .shot: "Who took the shot?"
        case .hit: "Who made the hit?"
        case .block: "Who blocked?"
        default: "Select Player"
        }
    }

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

// MARK: - Goal Against Time Entry

private struct GoalAgainstTimeSheet: View {
    @Binding var clockTime: String
    let defaultPowerPlay: Bool
    let onRecord: (Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isPowerPlay = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Goal Against")
                    .font(.headline)

                ClockTimeField(time: $clockTime)

                Toggle(isOn: $isPowerPlay) {
                    Label("Power Play Goal", systemImage: "bolt.fill")
                        .font(.subheadline.bold())
                }
                .tint(AppTheme.teal)
                .padding(.horizontal)

                HStack(spacing: 16) {
                    Button("Skip Time") {
                        clockTime = ""
                        onRecord(isPowerPlay)
                    }
                    .foregroundStyle(.secondary)
                    Button("Record") {
                        onRecord(isPowerPlay)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.teal)
                }
            }
            .padding()
            .onAppear { isPowerPlay = defaultPowerPlay }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Faceoff Picker

private struct FaceoffPickerSheet: View {
    @Bindable var vm: LiveGameViewModel
    @Environment(\.dismiss) private var dismiss

    private var players: [Player] { vm.onIceSkatersSorted }
    private let columns = [GridItem(.adaptive(minimum: 80), spacing: 12)]

    private var centerPlayer: Player? {
        players.first { vm.playerGamePosition[$0.persistentModelID] == "C" }
    }

    private var otherPlayers: [Player] {
        guard let center = centerPlayer else { return players }
        return players.filter { $0.persistentModelID != center.persistentModelID }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let center = centerPlayer {
                    VStack(spacing: 0) {
                        VStack(spacing: 4) {
                            Text(center.number > 0 ? "\(center.number)" : "—")
                                .font(.system(size: 40, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
                            Text(center.lastName)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white.opacity(0.8))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 90)
                        .background(AppTheme.pink, in: UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16))

                        HStack(spacing: 0) {
                            Button {
                                vm.recordFaceoff(player: center, won: true)
                                dismiss()
                            } label: {
                                Text("WON")
                                    .font(.system(size: 18, weight: .heavy))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 52)
                                    .background(.green)
                            }

                            Button {
                                vm.recordFaceoff(player: center, won: false)
                                dismiss()
                            } label: {
                                Text("LOST")
                                    .font(.system(size: 18, weight: .heavy))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 52)
                                    .background(.red)
                            }
                        }
                        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 16, bottomTrailingRadius: 16))
                    }
                    .padding(.horizontal)
                    .padding(.top, 12)

                    if !otherPlayers.isEmpty {
                        Text("OTHER PLAYERS")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1)
                            .foregroundStyle(.secondary)
                            .padding(.top, 16)
                    }
                }

                if centerPlayer == nil {
                    Text("Won or Lost?")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(centerPlayer == nil ? players : otherPlayers) { player in
                        faceoffPlayerCard(player)
                    }
                }
                .padding()
            }
            .navigationTitle("Faceoff")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func faceoffPlayerCard(_ player: Player) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Text(player.number > 0 ? "\(player.number)" : "—")
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                Text(player.lastName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 55)
            .background(AppTheme.pink, in: UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12))

            HStack(spacing: 0) {
                Button {
                    vm.recordFaceoff(player: player, won: true)
                    dismiss()
                } label: {
                    Text("W")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(.green)
                }

                Button {
                    vm.recordFaceoff(player: player, won: false)
                    dismiss()
                } label: {
                    Text("L")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(.red)
                }
            }
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12))
        }
    }

}

// MARK: - Line Setup Sheet

private struct LineSetupSheet: View {
    @Bindable var vm: LiveGameViewModel
    @Environment(\.dismiss) private var dismiss

    private var forwards: [Player] {
        vm.skaters.filter { $0.position == "Forward" || $0.position == "Center" || $0.position == "Left Wing" || $0.position == "Right Wing" }
    }

    private var defensemen: [Player] {
        vm.skaters.filter { $0.position == "Defense" || $0.position == "Left Defense" || $0.position == "Right Defense" }
    }

    private var unassigned: [Player] {
        vm.skaters.filter { p in !forwards.contains(where: { $0.id == p.id }) && !defensemen.contains(where: { $0.id == p.id }) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Assign positions, then lines. Players without a line will stay on ice during line changes (rolling).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Forwards") {
                    ForEach(forwards) { player in
                        VStack(spacing: 6) {
                            HStack {
                                Text(player.number > 0 ? "#\(player.number)" : "--")
                                    .font(.system(.body, design: .monospaced, weight: .bold))
                                    .frame(width: 40)
                                Text(player.name)
                                    .lineLimit(1)
                                Spacer()
                            }
                            HStack(spacing: 8) {
                                Picker("Pos", selection: positionBinding(for: player)) {
                                    Text("—").tag("")
                                    Text("C").tag("C")
                                    Text("LW").tag("LW")
                                    Text("RW").tag("RW")
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 150)

                                Picker("Line", selection: lineBinding(for: player)) {
                                    Text("—").tag("")
                                    Text("F1").tag("F1")
                                    Text("F2").tag("F2")
                                    Text("F3").tag("F3")
                                    Text("F4").tag("F4")
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 200)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                Section("Defense") {
                    ForEach(defensemen) { player in
                        VStack(spacing: 6) {
                            HStack {
                                Text(player.number > 0 ? "#\(player.number)" : "--")
                                    .font(.system(.body, design: .monospaced, weight: .bold))
                                    .frame(width: 40)
                                Text(player.name)
                                    .lineLimit(1)
                                Spacer()
                            }
                            HStack(spacing: 8) {
                                Picker("Pos", selection: positionBinding(for: player)) {
                                    Text("—").tag("")
                                    Text("LD").tag("LD")
                                    Text("RD").tag("RD")
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 120)

                                Picker("Pairing", selection: lineBinding(for: player)) {
                                    Text("—").tag("")
                                    Text("D1").tag("D1")
                                    Text("D2").tag("D2")
                                    Text("D3").tag("D3")
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 160)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                if !unassigned.isEmpty {
                    Section("Other") {
                        ForEach(unassigned) { player in
                            VStack(spacing: 6) {
                                HStack {
                                    Text(player.number > 0 ? "#\(player.number)" : "--")
                                        .font(.system(.body, design: .monospaced, weight: .bold))
                                        .frame(width: 40)
                                    Text(player.name)
                                        .lineLimit(1)
                                    Spacer()
                                }
                                HStack(spacing: 8) {
                                    Picker("Pos", selection: positionBinding(for: player)) {
                                        Text("—").tag("")
                                        Text("C").tag("C")
                                        Text("LW").tag("LW")
                                        Text("RW").tag("RW")
                                        Text("LD").tag("LD")
                                        Text("RD").tag("RD")
                                    }
                                    .pickerStyle(.menu)

                                    Picker("Line", selection: lineBinding(for: player)) {
                                        Text("—").tag("")
                                        Text("F1").tag("F1")
                                        Text("F2").tag("F2")
                                        Text("F3").tag("F3")
                                        Text("F4").tag("F4")
                                        Text("D1").tag("D1")
                                        Text("D2").tag("D2")
                                        Text("D3").tag("D3")
                                    }
                                    .pickerStyle(.menu)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .navigationTitle("Set Up Lines")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.bold)
                }
            }
        }
    }

    private func lineBinding(for player: Player) -> Binding<String> {
        Binding(
            get: { vm.playerLines[player.persistentModelID] ?? "" },
            set: { newValue in
                if newValue.isEmpty {
                    vm.playerLines.removeValue(forKey: player.persistentModelID)
                } else {
                    vm.playerLines[player.persistentModelID] = newValue
                }
            }
        )
    }

    private func positionBinding(for player: Player) -> Binding<String> {
        Binding(
            get: { vm.playerGamePosition[player.persistentModelID] ?? "" },
            set: { newValue in
                if newValue.isEmpty {
                    vm.playerGamePosition.removeValue(forKey: player.persistentModelID)
                } else {
                    vm.playerGamePosition[player.persistentModelID] = newValue
                }
            }
        )
    }
}

// MARK: - Period Summary Sheet

private struct PeriodSummarySheet: View {
    let summary: LiveGameViewModel.PeriodSummaryData
    let onContinue: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("\(summary.period) Period Summary")
                    .font(.title2.bold())

                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.fixed(50)),
                    GridItem(.fixed(50))
                ], spacing: 12) {
                    Text("").frame(maxWidth: .infinity, alignment: .leading)
                    Text("FF").font(.caption.bold()).foregroundStyle(AppTheme.pink)
                    Text("OPP").font(.caption.bold()).foregroundStyle(AppTheme.teal)

                    Text("Goals").frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(summary.goalsFor)").font(.system(.title3, design: .monospaced, weight: .bold))
                    Text("\(summary.goalsAgainst)").font(.system(.title3, design: .monospaced, weight: .bold))

                    Text("Shots").frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(summary.shotsFor)").font(.system(.body, design: .monospaced))
                    Text("\(summary.shotsAgainst)").font(.system(.body, design: .monospaced))

                    Text("Faceoffs").frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(summary.faceoffWins)").font(.system(.body, design: .monospaced))
                    Text("\(summary.faceoffLosses)").font(.system(.body, design: .monospaced))
                }
                .padding(.horizontal)

                if summary.penalties > 0 {
                    Text("\(summary.penalties) penalty/penalties")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    onContinue()
                } label: {
                    Text("Continue to Next Period")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AppTheme.pink, in: RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal)
            }
            .padding(.top, 20)
            .padding(.bottom)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Goal Flow Sheet

private struct GoalFlowSheet: View {
    @Bindable var vm: LiveGameViewModel
    let onDone: () -> Void

    @State private var showAll = false

    private var excluded: Set<PersistentIdentifier> { vm.goalFlowExcludedPlayers }

    private var onIcePlayers: [Player] {
        vm.onIceSkatersSorted.filter { !excluded.contains($0.persistentModelID) }
    }

    private var benchPlayers: [Player] {
        vm.skaters
            .filter { !excluded.contains($0.persistentModelID) }
            .filter { p in !vm.onIcePlayers.contains(p.persistentModelID) }
            .sorted { $0.number < $1.number }
    }

    private let columns = [GridItem(.adaptive(minimum: 80), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                if vm.goalFlowStep == .enterTime {
                    timeEntryView
                } else {
                    playerGrid
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

    private var playerGrid: some View {
        VStack(spacing: 0) {
            if vm.goalFlowStep == .pickPrimaryAssist {
                skipButton("No Assist") {
                    vm.goalFlowPickPrimaryAssist(nil)
                }
            }

            if vm.goalFlowStep == .pickSecondaryAssist {
                skipButton("No 2nd Assist") {
                    vm.goalFlowPickSecondaryAssist(nil)
                }
            }

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(onIcePlayers) { player in
                    goalPlayerButton(player, color: AppTheme.pink)
                }
            }
            .padding()

            if !benchPlayers.isEmpty {
                if showAll {
                    Text("ALL PLAYERS")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(benchPlayers) { player in
                            goalPlayerButton(player, color: Color(.systemGray3))
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                } else {
                    Button {
                        showAll = true
                    } label: {
                        Text("Show All Players")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(AppTheme.teal)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                }
            }
        }
    }

    private func goalPlayerButton(_ player: Player, color: Color) -> some View {
        Button {
            pickPlayer(player)
        } label: {
            VStack(spacing: 4) {
                Text(player.number > 0 ? "\(player.number)" : "—")
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                Text(player.lastName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 80)
            .background(color, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var timeEntryView: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("When did the goal happen?")
                .font(.headline)

            ClockTimeField(time: Bindable(vm).pendingClockTime)

            Picker("Strength", selection: Bindable(vm).pendingGoalStrength) {
                Text("Even").tag(0)
                Text("PP").tag(1)
                Text("SH").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            HStack(spacing: 16) {
                Button("Skip Time") {
                    vm.pendingClockTime = ""
                    vm.finalizeGoalWithTime()
                    onDone()
                }
                .foregroundStyle(.secondary)
                Button("Record Goal") {
                    vm.finalizeGoalWithTime()
                    onDone()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.pink)
            }
            Spacer()
        }
        .padding()
    }

    private var stepTitle: String {
        switch vm.goalFlowStep {
        case .pickScorer: "Who scored?"
        case .pickPrimaryAssist: "Primary Assist?"
        case .pickSecondaryAssist: "Secondary Assist?"
        case .enterTime: "Goal Time"
        }
    }

    private func pickPlayer(_ player: Player) {
        switch vm.goalFlowStep {
        case .pickScorer:
            vm.goalFlowPickScorer(player)
        case .pickPrimaryAssist:
            vm.goalFlowPickPrimaryAssist(player)
        case .pickSecondaryAssist:
            vm.goalFlowPickSecondaryAssist(player)
        case .enterTime:
            break
        }
    }

    private func skipButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AppTheme.teal, in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

}

// MARK: - Event Edit Sheet

private struct EventEditSheet: View {
    @Bindable var vm: LiveGameViewModel
    let eventIndex: Int
    let onSave: () -> Void
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPlayer: Player?
    @State private var selectedAssist1: Player?
    @State private var selectedAssist2: Player?
    @State private var clockTime: String = ""
    @State private var goalStrength: Int = 0 // 0=ES, 1=PP, 2=SH
    @State private var selectedPenaltyType: PenaltyType = .minor
    @State private var faceoffWon: Bool = true
    @State private var opponentNumber: String = ""
    @State private var period: Int = 1

    private var gameEvent: GameEvent? {
        guard vm.events.indices.contains(eventIndex) else { return nil }
        return vm.events[eventIndex].gameEvent
    }

    private var eventType: String {
        gameEvent?.type ?? ""
    }

    private var isGoal: Bool { eventType == "goal" }
    private var isPenalty: Bool { eventType == "penalty" }
    private var isGoalAgainst: Bool { eventType == "goalAgainst" }
    private var isPenaltyAgainst: Bool { eventType == "penaltyAgainst" }
    private var isFaceoff: Bool { eventType == "faceoffWin" || eventType == "faceoffLoss" }
    private var isPlayerEvent: Bool { ["shot", "goal", "hit", "block", "faceoffWin", "faceoffLoss", "penalty"].contains(eventType) }

    private var eventLabel: String {
        switch eventType {
        case "shot": "Shot"
        case "goal": "Goal"
        case "hit": "Hit"
        case "block": "Block"
        case "faceoffWin", "faceoffLoss": "Faceoff"
        case "penalty": "Penalty"
        case "shotAgainst": "Shot Against"
        case "goalAgainst": "Goal Against"
        case "penaltyAgainst": "Opponent Penalty"
        default: "Event"
        }
    }

    private let columns = [GridItem(.adaptive(minimum: 80), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text(eventLabel)
                        .font(.title2.bold())
                        .foregroundStyle(isGoalAgainst || isPenaltyAgainst ? AppTheme.teal : AppTheme.pink)

                    Picker("Period", selection: $period) {
                        Text("1st").tag(1)
                        Text("2nd").tag(2)
                        Text("3rd").tag(3)
                        Text("OT").tag(4)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    if isPlayerEvent {
                        playerPickerSection
                    }

                    if isGoal {
                        assistPickerSection
                    }

                    if isGoal || isGoalAgainst || isPenalty || isPenaltyAgainst {
                        VStack(spacing: 8) {
                            Text("Clock Time")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            ClockTimeField(time: $clockTime)
                        }
                    }

                    if isGoal {
                        Picker("Strength", selection: $goalStrength) {
                            Text("Even").tag(0)
                            Text("PP").tag(1)
                            Text("SH").tag(2)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                    }

                    if isGoalAgainst {
                        Toggle(isOn: Binding(
                            get: { goalStrength == 1 },
                            set: { goalStrength = $0 ? 1 : 0 }
                        )) {
                            Label("Power Play Goal", systemImage: "bolt.fill")
                                .font(.subheadline.bold())
                        }
                        .tint(AppTheme.teal)
                        .padding(.horizontal)
                    }

                    if isPenalty || isPenaltyAgainst {
                        Picker("Penalty Type", selection: $selectedPenaltyType) {
                            ForEach(PenaltyType.allCases) { type in
                                Text(type.rawValue).tag(type)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                    }

                    if isPenaltyAgainst {
                        HStack {
                            Text("Opponent #")
                                .font(.subheadline.bold())
                            TextField("Jersey #", text: $opponentNumber)
                                .keyboardType(.numberPad)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                        }
                        .padding(.horizontal)
                    }

                    if isFaceoff {
                        Picker("Result", selection: $faceoffWon) {
                            Text("Won").tag(true)
                            Text("Lost").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                    }

                    HStack(spacing: 16) {
                        Button(role: .destructive) {
                            onDelete()
                        } label: {
                            Label("Delete", systemImage: "trash")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(.red, in: RoundedRectangle(cornerRadius: 12))
                        }

                        Button {
                            saveEdits()
                        } label: {
                            Text("Save")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(AppTheme.pink, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
                .padding(.top, 16)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { loadFromEvent() }
        }
    }

    private var playerPickerSection: some View {
        VStack(spacing: 8) {
            Text("Player")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(vm.skaters) { player in
                    Button {
                        selectedPlayer = player
                    } label: {
                        VStack(spacing: 2) {
                            Text(player.number > 0 ? "\(player.number)" : "—")
                                .font(.system(size: 22, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
                            Text(player.name.components(separatedBy: " ").last ?? player.name)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.8))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 55)
                        .background(selectedPlayer?.persistentModelID == player.persistentModelID ? AppTheme.pink : Color(.systemGray3), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var assistPickerSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Primary Assist")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                if selectedAssist1 != nil {
                    Button("Clear") { selectedAssist1 = nil }
                        .font(.caption)
                        .foregroundStyle(AppTheme.teal)
                }
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(vm.skaters.filter { $0.persistentModelID != selectedPlayer?.persistentModelID && $0.persistentModelID != selectedAssist2?.persistentModelID }) { player in
                        Button {
                            selectedAssist1 = player
                        } label: {
                            Text(player.number > 0 ? "#\(player.number)" : "—")
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
                                .frame(width: 50, height: 36)
                                .background(selectedAssist1?.persistentModelID == player.persistentModelID ? AppTheme.pink : Color(.systemGray3), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .padding(.horizontal)
            }
        }

        VStack(spacing: 8) {
            HStack {
                Text("Secondary Assist")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                if selectedAssist2 != nil {
                    Button("Clear") { selectedAssist2 = nil }
                        .font(.caption)
                        .foregroundStyle(AppTheme.teal)
                }
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(vm.skaters.filter { $0.persistentModelID != selectedPlayer?.persistentModelID && $0.persistentModelID != selectedAssist1?.persistentModelID }) { player in
                        Button {
                            selectedAssist2 = player
                        } label: {
                            Text(player.number > 0 ? "#\(player.number)" : "—")
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
                                .frame(width: 50, height: 36)
                                .background(selectedAssist2?.persistentModelID == player.persistentModelID ? AppTheme.pink : Color(.systemGray3), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func loadFromEvent() {
        guard let event = gameEvent else { return }
        period = event.period
        clockTime = event.clockTime
        if event.isPowerPlay { goalStrength = 1 }
        else if event.isShortHanded { goalStrength = 2 }
        else { goalStrength = 0 }
        opponentNumber = event.opponentNumber
        faceoffWon = event.type == "faceoffWin"

        if let pType = PenaltyType(rawValue: event.penaltyType) {
            selectedPenaltyType = pType
        }

        selectedPlayer = vm.findPlayer(named: event.playerName, number: event.playerNumber)

        if !event.assist1Name.isEmpty {
            selectedAssist1 = vm.findPlayer(named: event.assist1Name, number: event.assist1Number)
        }
        if !event.assist2Name.isEmpty {
            selectedAssist2 = vm.findPlayer(named: event.assist2Name, number: event.assist2Number)
        }
    }

    private func saveEdits() {
        vm.replaceEvent(
            at: eventIndex,
            player: selectedPlayer,
            clockTime: clockTime,
            isPowerPlay: goalStrength == 1,
            isShortHanded: goalStrength == 2,
            assist1: selectedAssist1,
            assist2: selectedAssist2,
            penaltyType: (isPenalty || isPenaltyAgainst) ? selectedPenaltyType : nil,
            faceoffWon: isFaceoff ? faceoffWon : nil,
            opponentNumber: opponentNumber,
            period: period
        )
        onSave()
    }
}

// MARK: - Bench Picker Sheet

private struct BenchPickerSheet: View {
    @Bindable var vm: LiveGameViewModel
    let subOutPlayer: Player?
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 72), spacing: 10)]

    var body: some View {
        NavigationStack {
            ScrollView {
                if let player = subOutPlayer {
                    Text("Replacing #\(player.number) \(player.lastName)")
                        .font(.headline)
                        .padding(.top, 12)
                }

                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(vm.benchPlayers) { player in
                        Button {
                            if let outPlayer = subOutPlayer {
                                vm.swapPlayer(on: player, off: outPlayer)
                            }
                            onDone()
                        } label: {
                            VStack(spacing: 2) {
                                Text(player.number > 0 ? "\(player.number)" : "—")
                                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.white)
                                Text(player.lastName)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.8))
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 60)
                            .background(
                                vm.isForwardPosition(player.position) ? AppTheme.pink : AppTheme.teal,
                                in: RoundedRectangle(cornerRadius: 10)
                            )
                        }
                    }
                }
                .padding()

                Button {
                    if let outPlayer = subOutPlayer {
                        vm.takePlayerOffIce(outPlayer)
                    }
                    onDone()
                } label: {
                    Label("Take Off Ice", systemImage: "arrow.down.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(.systemGray3), in: RoundedRectangle(cornerRadius: 10))
                }
                .padding(.horizontal)
            }
            .navigationTitle("Sub Player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

}

// MARK: - On Ice Manager Sheet

private struct OnIceManagerSheet: View {
    @Bindable var vm: LiveGameViewModel
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 72), spacing: 10)]

    var body: some View {
        NavigationStack {
            ScrollView {
                Text("Tap players to toggle on/off ice")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)

                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(vm.skaters) { player in
                        Button {
                            vm.togglePlayerOnIce(player)
                        } label: {
                            let isOnIce = vm.onIcePlayers.contains(player.persistentModelID)
                            VStack(spacing: 2) {
                                Text(player.number > 0 ? "\(player.number)" : "—")
                                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.white)
                                Text(player.lastName)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.8))
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 60)
                            .background(
                                isOnIce
                                    ? (vm.isForwardPosition(player.position) ? AppTheme.pink : AppTheme.teal)
                                    : Color(.systemGray4),
                                in: RoundedRectangle(cornerRadius: 10)
                            )
                            .overlay(
                                isOnIce
                                    ? RoundedRectangle(cornerRadius: 10).stroke(.white, lineWidth: 2)
                                    : nil
                            )
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Manage On Ice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.bold)
                }
            }
        }
    }

}

// MARK: - Clock Edit Sheet

private struct ClockEditSheet: View {
    @Binding var minutes: Int
    @Binding var seconds: Int
    let onSet: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Edit Clock")
                    .font(.title2.bold())

                HStack(spacing: 0) {
                    Picker("Minutes", selection: $minutes) {
                        ForEach(0...25, id: \.self) { m in
                            Text(String(format: "%02d", m)).tag(m)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 80)
                    .clipped()

                    Text(":")
                        .font(.system(size: 32, weight: .bold, design: .monospaced))

                    Picker("Seconds", selection: $seconds) {
                        ForEach(0...59, id: \.self) { s in
                            Text(String(format: "%02d", s)).tag(s)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 80)
                    .clipped()
                }
                .frame(height: 150)

                Button {
                    onSet()
                } label: {
                    Text("Set Clock")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AppTheme.pink, in: RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal)
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
