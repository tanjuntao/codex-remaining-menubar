import Foundation

struct UsageCache {
    private let fileManager: FileManager
    private let directory: URL?

    init(fileManager: FileManager = .default, directory: URL? = nil) {
        self.fileManager = fileManager
        self.directory = directory
    }

    func load() -> UsageSnapshot? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(UsageSnapshot.self, from: data)
    }

    func save(_ snapshot: UsageSnapshot) {
        do {
            let directory = cacheURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: cacheURL, options: .atomic)
        } catch {
            // Usage remains visible even if the optional cache cannot be written.
        }
    }

    func loadTokenUsage() -> TokenUsageSnapshot? {
        guard let data = try? Data(contentsOf: tokenUsageURL) else { return nil }
        return try? JSONDecoder().decode(TokenUsageSnapshot.self, from: data)
    }

    func saveTokenUsage(_ snapshot: TokenUsageSnapshot) {
        do {
            try fileManager.createDirectory(at: tokenUsageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: tokenUsageURL, options: .atomic)
        } catch {
            // A cache write failure must not hide a successful response.
        }
    }

    func clearTokenUsage() {
        try? fileManager.removeItem(at: tokenUsageURL)
    }

    private var tokenUsageURL: URL {
        cacheURL.deletingLastPathComponent().appendingPathComponent("token-usage-cache.json")
    }

    private var cacheURL: URL {
        if let directory { return directory.appendingPathComponent("usage-cache.json") }
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base
            .appendingPathComponent("CodexRemainingMenuBar", isDirectory: true)
            .appendingPathComponent("usage-cache.json")
    }
}
