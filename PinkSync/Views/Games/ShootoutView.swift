import SwiftUI
import SwiftData

struct ShootoutView: View {
    @Bindable var goalieStats: GameGoalieStats
    @Environment(\.modelContext) private var modelContext

    private var sortedRounds: [ShootoutRound] {
        goalieStats.shootoutRounds.sorted { $0.roundNumber < $1.roundNumber }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SHOOTOUT ROUNDS")
                .font(AppTheme.statLabel)
                .foregroundStyle(.secondary)

            ForEach(sortedRounds) { round in
                HStack {
                    Text("Round \(round.roundNumber)")
                        .font(.headline)

                    Spacer()

                    Button {
                        round.isGoal.toggle()
                        try? modelContext.save()
                    } label: {
                        Text(round.isGoal ? "Goal" : "Save")
                            .font(.subheadline.bold())
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(round.isGoal ? Color.red.opacity(0.15) : Color.green.opacity(0.15))
                            .foregroundStyle(round.isGoal ? .red : .green)
                            .clipShape(Capsule())
                    }

                    Button(role: .destructive) {
                        modelContext.delete(round)
                        try? modelContext.save()
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 4)
            }

            Button {
                addRound()
            } label: {
                Label("Add Round", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .foregroundStyle(AppTheme.pink)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(AppTheme.pink.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            // Summary
            let saves = sortedRounds.filter { !$0.isGoal }.count
            let goals = sortedRounds.filter { $0.isGoal }.count
            HStack {
                Text("Saves: \(saves)")
                    .foregroundStyle(.green)
                Spacer()
                Text("Goals: \(goals)")
                    .foregroundStyle(.red)
            }
            .font(.subheadline.bold())
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func addRound() {
        let nextNumber = (sortedRounds.last?.roundNumber ?? 0) + 1
        let round = ShootoutRound(roundNumber: nextNumber, isGoal: false)
        round.goalieStats = goalieStats
        modelContext.insert(round)
        try? modelContext.save()
    }
}
