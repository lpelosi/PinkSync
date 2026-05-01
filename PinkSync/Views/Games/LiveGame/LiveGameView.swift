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
    @State private var showingGoalAgainstTime = false
    @State private var showingFaceoffPicker = false
    @State private var showingLineSetup = false
    @State private var showingPeriodSummary = false
    @State private var goalAgainstClockTime = ""
    @State private var pendingAction: LiveAction?
    @State private var eventToDelete: Int?

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                scoreboard

                switch vm.period {
                case .regulation, .overtime:
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
        .alert("Delete Event?", isPresented: Binding(
            get: { eventToDelete != nil },
            set: { if !$0 { eventToDelete = nil } }
        )) {
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
        .sheet(isPresented: $showingPlayerPicker) {
            LivePlayerPickerView(
                players: vm.filteredSkaters,
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
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingGoalFlow) {
            GoalFlowSheet(vm: vm) {
                showingGoalFlow = false
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingPenaltyEntry) {
            PenaltyEntryView(
                isOurs: true,
                players: vm.filteredSkaters,
                excluded: []
            ) { player, _, type, clockTime in
                if let player {
                    vm.recordPenalty(player: player, type: type, clockTime: clockTime)
                }
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showingOpponentPenalty) {
            PenaltyEntryView(
                isOurs: false,
                players: [],
                excluded: []
            ) { _, number, type, clockTime in
                vm.recordOpponentPenalty(jerseyNumber: number, type: type, clockTime: clockTime)
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingGoalAgainstTime) {
            GoalAgainstTimeSheet(clockTime: $goalAgainstClockTime) { isPowerPlay in
                vm.recordGoalAgainst(clockTime: goalAgainstClockTime, isPowerPlay: isPowerPlay)
                goalAgainstClockTime = ""
                showingGoalAgainstTime = false
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingFaceoffPicker) {
            FaceoffPickerSheet(vm: vm)
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
        .sheet(isPresented: $showingLineSetup) {
            LineSetupSheet(vm: vm)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showingPeriodSummary) {
            PeriodSummarySheet(summary: vm.currentPeriodSummary()) {
                showingPeriodSummary = false
                vm.endPeriod()
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
        VStack(spacing: 8) {
            HStack {
                Text(periodDisplayLabel)
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(periodColor.opacity(0.2), in: Capsule())
                    .foregroundStyle(periodColor)

                Spacer()

                Button {
                    showingLineSetup = true
                } label: {
                    Image(systemName: "person.3.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .background(Color(.systemGray5), in: Circle())
                }

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

    // MARK: - Line Filter Bar

    @ViewBuilder
    private var lineFilterBar: some View {
        let lines = vm.configuredLineNumbers
        if !lines.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    lineFilterPill("All", isActive: vm.activeLineFilter == nil) {
                        vm.activeLineFilter = nil
                    }
                    ForEach(lines, id: \.self) { line in
                        lineFilterPill("L\(line)", isActive: vm.activeLineFilter == line) {
                            vm.activeLineFilter = (vm.activeLineFilter == line) ? nil : line
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
            }
            .background(Color(.systemGray6).opacity(0.5))
        }
    }

    private func lineFilterPill(_ label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(isActive ? .white : .secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(isActive ? AppTheme.pink : Color(.systemGray5), in: Capsule())
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
                actionButton("Faceoff", emoji: "🏑", color: AppTheme.pink) {
                    showingFaceoffPicker = true
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
                    goalAgainstClockTime = ""
                    showingGoalAgainstTime = true
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
                showingPeriodSummary = true
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

    // MARK: - Event Feed (tap to delete)

    private var eventFeed: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(vm.events.enumerated()), id: \.element.id) { index, event in
                        Button {
                            if event.undoClosure != nil {
                                eventToDelete = index
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Text(event.emoji)
                                    .font(.body)
                                Text(event.description)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.primary)
                                Spacer()
                                if event.undoClosure != nil {
                                    Image(systemName: "xmark.circle.fill")
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

    private var players: [Player] { vm.filteredSkaters }
    private let columns = [GridItem(.adaptive(minimum: 80), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                Text("Won or Lost?")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(players) { player in
                        VStack(spacing: 0) {
                            VStack(spacing: 4) {
                                Text(player.number > 0 ? "\(player.number)" : "—")
                                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.white)
                                Text(lastName(player.name))
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

    private func lastName(_ name: String) -> String {
        name.components(separatedBy: " ").last ?? name
    }
}

// MARK: - Line Setup Sheet

private struct LineSetupSheet: View {
    @Bindable var vm: LiveGameViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Assign players to lines for quick filtering.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(vm.skaters) { player in
                    HStack {
                        Text(player.number > 0 ? "#\(player.number)" : "--")
                            .font(.system(.body, design: .monospaced, weight: .bold))
                            .frame(width: 40)
                        Text(player.name)
                            .lineLimit(1)
                        Spacer()
                        Picker("Line", selection: lineBinding(for: player)) {
                            Text("—").tag(0)
                            Text("L1").tag(1)
                            Text("L2").tag(2)
                            Text("L3").tag(3)
                            Text("L4").tag(4)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 200)
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

    private func lineBinding(for player: Player) -> Binding<Int> {
        Binding(
            get: { vm.playerLines[player.persistentModelID] ?? 0 },
            set: { newValue in
                if newValue == 0 {
                    vm.playerLines.removeValue(forKey: player.persistentModelID)
                } else {
                    vm.playerLines[player.persistentModelID] = newValue
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

    private var availablePlayers: [Player] {
        vm.filteredSkaters.filter { !vm.goalFlowExcludedPlayers.contains($0.persistentModelID) }
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
        }
    }

    private var timeEntryView: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("When did the goal happen?")
                .font(.headline)

            ClockTimeField(time: Bindable(vm).pendingClockTime)

            Toggle(isOn: Bindable(vm).pendingIsPowerPlay) {
                Label("Power Play Goal", systemImage: "bolt.fill")
                    .font(.subheadline.bold())
            }
            .tint(AppTheme.pink)
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

    private func lastName(_ name: String) -> String {
        name.components(separatedBy: " ").last ?? name
    }
}
