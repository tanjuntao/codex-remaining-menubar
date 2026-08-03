import Foundation

enum CodexExecutableLocator {
    static func locate(fileManager: FileManager = .default) -> URL? {
        let environment = ProcessInfo.processInfo.environment
        let home = fileManager.homeDirectoryForCurrentUser
        var candidates: [URL] = []

        if let override = environment["CODEX_EXECUTABLE"], !override.isEmpty {
            candidates.append(URL(fileURLWithPath: override))
        }

        if let path = environment["PATH"] {
            candidates.append(contentsOf: path.split(separator: ":").map {
                URL(fileURLWithPath: String($0), isDirectory: true).appendingPathComponent("codex")
            })
        }

        candidates.append(contentsOf: [
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex"),
            home.appendingPathComponent(".local/bin/codex"),
            home.appendingPathComponent(".volta/bin/codex"),
            home.appendingPathComponent("Library/pnpm/codex")
        ])

        let nvmVersions = home.appendingPathComponent(".nvm/versions/node", isDirectory: true)
        if let versions = try? fileManager.contentsOfDirectory(
            at: nvmVersions,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            candidates.append(contentsOf: versions.sorted { $0.lastPathComponent > $1.lastPathComponent }.map {
                $0.appendingPathComponent("bin/codex")
            })
        }

        return candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    static func launchEnvironment(
        for executable: URL,
        baseEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var environment = baseEnvironment
        let executableDirectory = executable.deletingLastPathComponent().path
        let existingDirectories = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)

        var seen: Set<String> = []
        let pathDirectories = ([executableDirectory] + existingDirectories).filter {
            seen.insert($0).inserted
        }
        environment["PATH"] = pathDirectories.joined(separator: ":")
        return environment
    }
}
