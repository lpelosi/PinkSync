import Foundation

/// Wins, losses and overtime losses over a set of games, counted the way the
/// NHL standings count them and the way `lib/teamRecord.js` does on the site:
/// a shootout win is a win, and a loss after regulation, in overtime or in a
/// shootout, is an OTL. Only a regulation loss is a loss. A game with no
/// result yet is not counted at all.
struct TeamRecord: Equatable {
    var gamesPlayed = 0
    var wins = 0
    var losses = 0
    var overtimeLosses = 0
    var goalsFor = 0
    var goalsAgainst = 0

    init() {}

    init(games: [Game]) {
        for game in games {
            guard let result = game.gameResult else { continue }
            switch result {
            case .win, .shootoutWin: wins += 1
            case .loss: losses += 1
            case .overtimeLoss, .shootoutLoss: overtimeLosses += 1
            }
            gamesPlayed += 1
            goalsFor += game.goalsFor
            goalsAgainst += game.goalsAgainst
        }
    }

    /// Two for a win, one for an overtime or shootout loss.
    var points: Int { wins * 2 + overtimeLosses }

    var pointsPercentage: Double {
        guard gamesPlayed > 0 else { return 0 }
        return Double(points) / Double(gamesPlayed * 2)
    }

    var goalDifferential: Int { goalsFor - goalsAgainst }

    /// "12-4-2"
    var display: String { "\(wins)-\(losses)-\(overtimeLosses)" }

    // MARK: - Streak

    /// The team's current run, newest game first: "W3", "L1", "OTL2", or nil
    /// with no decided game.
    static func streak(_ games: [Game]) -> String? {
        let decided = games
            .filter { $0.gameResult != nil }
            .sorted { $0.date > $1.date }
        guard let latest = decided.first?.gameResult else { return nil }
        let column = Self.column(latest)
        var run = 0
        for game in decided {
            guard let result = game.gameResult, Self.column(result) == column else { break }
            run += 1
        }
        return "\(column)\(run)"
    }

    private static func column(_ result: GameResult) -> String {
        switch result {
        case .win, .shootoutWin: "W"
        case .loss: "L"
        case .overtimeLoss, .shootoutLoss: "OTL"
        }
    }

    // MARK: - Scopes

    /// The games a roster-picker selection covers, the way the site's
    /// team-record view does: a season is league play only, regular season and
    /// playoffs together, with tournament games kept out; a tournament is its
    /// own games; "All Seasons" is every game ever played.
    static func games(_ games: [Game], selection: String, seasonStore: SeasonStore) -> [Game] {
        if selection == Season.allId { return games }
        let scope = seasonStore.scope(seasonId: selection, type: nil)
        if scope.tournamentId != nil { return games.filter { scope.includes($0) } }
        return games.filter { $0.tournamentId.isEmpty && scope.includes($0) }
    }
}
