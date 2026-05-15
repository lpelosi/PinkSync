import CryptoKit
import Foundation
import UIKit

actor PhotoCache {
    static let shared = PhotoCache()

    private let cacheDir: URL
    private var memory = NSCache<NSString, UIImage>()
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDir = caches.appendingPathComponent("player-photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        memory.countLimit = 50
    }

    func image(for url: URL) async -> UIImage? {
        let key = cacheKey(for: url)

        if let cached = memory.object(forKey: key as NSString) {
            return cached
        }

        let file = cacheDir.appendingPathComponent(key)
        if let data = try? Data(contentsOf: file), let img = UIImage(data: data) {
            memory.setObject(img, forKey: key as NSString)
            return img
        }

        if let existing = inFlight[url] {
            return await existing.value
        }

        let task = Task<UIImage?, Never> { [cacheDir] in
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  let img = UIImage(data: data) else {
                return nil
            }
            try? data.write(to: cacheDir.appendingPathComponent(key), options: .atomic)
            return img
        }
        inFlight[url] = task
        let result = await task.value
        inFlight[url] = nil
        if let result {
            memory.setObject(result, forKey: key as NSString)
        }
        return result
    }

    func clearCache() {
        memory.removeAllObjects()
        try? FileManager.default.removeItem(at: cacheDir)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    private func cacheKey(for url: URL) -> String {
        let hash = SHA256.hash(data: Data(url.absoluteString.utf8))
        let hex = hash.compactMap { String(format: "%02x", $0) }.joined()
        let ext = url.pathExtension.isEmpty ? "img" : url.pathExtension
        return "\(hex).\(ext)"
    }
}
