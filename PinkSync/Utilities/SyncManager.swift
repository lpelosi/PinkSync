import Foundation
import Network
import SwiftData

/// Manages background retry of games whose `Save & Send` failed, plus live network reachability.
/// One instance is created at app launch and passed into the view tree via `.environment`.
@Observable
@MainActor
final class SyncManager {
    /// Number of games currently waiting to be re-sent.
    private(set) var pendingCount: Int = 0

    /// True while a retry pass is in flight.
    private(set) var isRetrying: Bool = false

    /// True when the device currently has a network path. Used for the offline indicator.
    private(set) var isOnline: Bool = true

    private let container: ModelContainer
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "PinkSync.SyncManager.NWPathMonitor")
    private var retryTask: Task<Void, Never>?

    private static let retryInterval: Duration = .seconds(60)

    init(container: ModelContainer) {
        self.container = container
        startNetworkMonitoring()
        refreshPendingCount()
        startRetryLoop()
    }


    /// Recount pending games. Call after any local change that might affect the queue.
    func refreshPendingCount() {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<Game>(
            predicate: #Predicate { $0.pendingSync == true }
        )
        pendingCount = (try? context.fetchCount(descriptor)) ?? 0
    }

    /// Mark a game as needing retry and bump the pending count.
    func enqueue(game: Game, error: Error) {
        game.pendingSync = true
        game.lastSyncError = error.localizedDescription
        try? game.modelContext?.save()
        refreshPendingCount()
    }

    /// Clear pending state after a successful send.
    func markSent(game: Game) {
        game.pendingSync = false
        game.lastSyncError = nil
        try? game.modelContext?.save()
        refreshPendingCount()
    }

    /// Immediately try to flush the queue. Safe to call any time.
    func retryNow() async {
        guard !isRetrying else { return }
        guard isOnline else { return }
        isRetrying = true
        defer {
            isRetrying = false
            refreshPendingCount()
        }

        let context = ModelContext(container)
        let descriptor = FetchDescriptor<Game>(
            predicate: #Predicate { $0.pendingSync == true }
        )
        guard let pending = try? context.fetch(descriptor), !pending.isEmpty else { return }

        for game in pending {
            do {
                try await APIClient.sendGameStats(game: game)
                game.pendingSync = false
                game.isSynced = true
                game.lastSyncError = nil
                try? context.save()
            } catch {
                game.lastSyncError = error.localizedDescription
                try? context.save()
            }
        }
    }

    // MARK: - Private

    private func startNetworkMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self else { return }
                let wasOffline = !self.isOnline
                self.isOnline = online
                if online && wasOffline {
                    // Just came back online — flush the queue.
                    await self.retryNow()
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }

    private func startRetryLoop() {
        retryTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.retryInterval)
                if Task.isCancelled { break }
                guard let self else { break }
                if self.pendingCount > 0 {
                    await self.retryNow()
                }
            }
        }
    }
}
