import Foundation
import SwiftData
import UIKit
import os

/// Keeps team logos in step with the server, which is the source of truth.
///
/// A device pulls every logo the server has and keeps a copy. It pushes one
/// only when the logo was changed on this device, or when the server has none
/// for a team this device does. It never overwrites the server's logo just
/// because it holds a different one.
@MainActor
enum TeamLogoSync {
    private static let logger = Logger(subsystem: "PinkSync", category: "TeamLogoSync")
    private static var isRunning = false

    enum Action: Equatable {
        /// Send this device's logo to the server.
        case upload
        /// Replace this device's copy with the server's, at this path.
        case download(String)
        case none
    }

    /// A team name reduced to what identifies it, the same way the server
    /// does: "WOLVES " and "Wolves" are one team.
    static func teamKey(_ name: String) -> String {
        name.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }

    /// What one team needs, given what the server holds for it.
    ///
    /// - hasLocalLogo: the device holds image data for the team.
    /// - hasBundledLogo: the team has a logo shipped inside the app.
    /// - needsUpload: the logo was changed on this device and not yet sent.
    /// - localVersion: the server path the local copy was taken from.
    /// - serverPath: the server's current path, nil when it has no logo.
    static func action(hasLocalLogo: Bool, hasBundledLogo: Bool, needsUpload: Bool, localVersion: String?, serverPath: String?) -> Action {
        if needsUpload && hasLocalLogo { return .upload }
        if let serverPath {
            return hasLocalLogo && localVersion == serverPath ? .none : .download(serverPath)
        }
        // The server has nothing for this team. Give it what this device has.
        return hasLocalLogo || hasBundledLogo ? .upload : .none
    }

    /// Bring every team's logo in step with the server. Safe to call often;
    /// a team already in step costs nothing beyond the one list request.
    static func sync(modelContext: ModelContext) async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        let serverLogos: [String: String]
        do {
            serverLogos = try await APIClient.fetchTeamLogos()
        } catch {
            logger.warning("Team logo list unavailable: \(error.localizedDescription)")
            return
        }
        var serverByKey: [String: (name: String, path: String)] = [:]
        for (name, path) in serverLogos { serverByKey[teamKey(name)] = (name, path) }

        var teams = (try? modelContext.fetch(FetchDescriptor<OpponentTeam>())) ?? []

        // A team the server has a logo for and this device has never heard
        // of, e.g. a tournament opponent added from another phone.
        let known = Set(teams.map { teamKey($0.name) })
        for (key, entry) in serverByKey where !known.contains(key) {
            let team = OpponentTeam(name: entry.name)
            modelContext.insert(team)
            teams.append(team)
        }

        for team in teams {
            let bundled = team.logoAsset.flatMap { UIImage(named: $0) }
            let step = action(
                hasLocalLogo: team.logoData != nil,
                hasBundledLogo: bundled != nil,
                needsUpload: team.logoNeedsUpload,
                localVersion: team.logoVersion,
                serverPath: serverByKey[teamKey(team.name)]?.path
            )
            switch step {
            case .upload:
                guard let data = team.logoData ?? bundled?.pngData() else { continue }
                await upload(data, for: team)
            case .download(let path):
                do {
                    team.logoData = try await APIClient.downloadImage(path: path)
                    team.logoVersion = path
                } catch {
                    logger.warning("Logo download failed for \(team.name): \(error.localizedDescription)")
                }
            case .none:
                break
            }
        }
        try? modelContext.save()
    }

    /// Replace a team's logo from this device. Shown straight away and sent
    /// to the server; if the upload fails it is sent on the next sync.
    /// Returns whether the server has it.
    @discardableResult
    static func setLogo(_ data: Data, for team: OpponentTeam, modelContext: ModelContext) async -> Bool {
        team.logoData = data
        team.logoNeedsUpload = true
        try? modelContext.save()
        let sent = await upload(data, for: team)
        try? modelContext.save()
        return sent
    }

    @discardableResult
    private static func upload(_ data: Data, for team: OpponentTeam) async -> Bool {
        guard let path = await APIClient.sendTeamLogo(teamName: team.name, logoData: data) else { return false }
        team.logoVersion = path
        team.logoNeedsUpload = false
        return true
    }
}
