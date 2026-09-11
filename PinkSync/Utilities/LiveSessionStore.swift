import Foundation
import os

private let logger = Logger(subsystem: "PinkSync", category: "LiveSession")

/// Everything a period change touches, kept so it can be put back.
struct LiveTransitionSnapshot: Codable {
    var period: String
    var currentPeriod: Int
    var clockSeconds: Int
    var goalsFor: Int
    var goalsAgainst: Int
    var activePenalties: [LiveSessionState.Penalty]
}

/// A live game's in-memory state, written to disk after every change so the
/// scorekeeper can leave the live screen, switch apps, or survive a crash and
/// pick up exactly where they were. Also what lets an ended game be reopened.
///
/// Plays themselves are already in SwiftData (`GameEvent`, stat rows); this
/// holds only what lived in the view model: period, clock, penalty timers,
/// lineup, on-ice, shifts, shootout attempts, and the feed as displayed.
struct LiveSessionState: Codable {
    struct Penalty: Codable {
        var playerName: String
        var playerNumber: Int
        var isOurs: Bool
        var type: String
        var totalSeconds: Int
        var remainingSeconds: Int
    }

    struct Attempt: Codable {
        var isOurs: Bool
        var playerId: String?
        var isGoal: Bool
        var roundNumber: Int
        /// Opponent attempts: the goalie who faced it. Absent in sessions
        /// saved before goalie changes were tracked.
        var goaliePlayerId: String?
    }

    struct FeedLine: Codable {
        /// "action", "transition", "shootout" or "note".
        var kind: String
        var emoji: String
        var description: String
        /// For actions: the `GameEvent` this line describes.
        var eventCreatedAt: Date?
        /// For shootout lines: index into `shootoutAttempts`.
        var attemptIndex: Int?
        /// For transitions: what "go back" restores.
        var transition: LiveTransitionSnapshot?
        var goBackLabel: String?
    }

    var gameId: String
    var savedAt: Date

    var period: String
    var currentPeriod: Int
    var periodLengthMinutes: Int
    var clockSeconds: Int
    var isClockSetUp: Bool
    var activePenalties: [Penalty]

    var checkedInPlayerIds: [String]
    var activeGoalieId: String?
    var onIcePlayerIds: [String]
    var playerTOI: [String: Int]
    var currentShiftSeconds: [String: Int]
    var shiftStartClockTime: [String: String]
    var playerLines: [String: String]
    var playerGamePosition: [String: String]
    var playerGameRole: [String: String]

    var shootoutAttempts: [Attempt]
    var goalsBeforeShootoutFor: Int
    var goalsBeforeShootoutAgainst: Int

    var feed: [FeedLine]
}

/// One JSON file per game under Application Support.
enum LiveSessionStore {
    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("LiveSessions", isDirectory: true)
    }

    private static func url(for gameId: String) -> URL {
        directory.appendingPathComponent("\(gameId).json")
    }

    static func exists(gameId: String) -> Bool {
        !gameId.isEmpty && FileManager.default.fileExists(atPath: url(for: gameId).path)
    }

    static func save(_ state: LiveSessionState) {
        guard !state.gameId.isEmpty else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601WithFractionalSeconds
            let data = try encoder.encode(state)
            try data.write(to: url(for: state.gameId), options: .atomic)
        } catch {
            logger.error("Could not save live session: \(error.localizedDescription)")
        }
    }

    static func load(gameId: String) -> LiveSessionState? {
        guard exists(gameId: gameId) else { return nil }
        do {
            let data = try Data(contentsOf: url(for: gameId))
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601WithFractionalSeconds
            return try decoder.decode(LiveSessionState.self, from: data)
        } catch {
            logger.error("Could not load live session: \(error.localizedDescription)")
            return nil
        }
    }

    static func delete(gameId: String) {
        guard !gameId.isEmpty else { return }
        try? FileManager.default.removeItem(at: url(for: gameId))
    }
}

private extension JSONEncoder.DateEncodingStrategy {
    static var iso8601WithFractionalSeconds: JSONEncoder.DateEncodingStrategy {
        .custom { date, encoder in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
    }
}

private extension JSONDecoder.DateDecodingStrategy {
    static var iso8601WithFractionalSeconds: JSONDecoder.DateDecodingStrategy {
        .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: string) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: string) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Bad date: \(string)")
        }
    }
}
