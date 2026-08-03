import AppKit
import Foundation

@MainActor
final class UsageViewModel: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var needsSignIn = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var codexExecutablePath: String?
    @Published var menuBarDisplayMode: MenuBarDisplayMode {
        didSet {
            UserDefaults.standard.set(menuBarDisplayMode.rawValue, forKey: Self.menuBarDisplayModeKey)
        }
    }

    private let client: CodexAppServerClient
    private let cache: UsageCache
    private var refreshLoop: Task<Void, Never>?
    private static let menuBarDisplayModeKey = "menuBarDisplayMode"

    init(client: CodexAppServerClient = CodexAppServerClient(), cache: UsageCache = UsageCache()) {
        self.client = client
        self.cache = cache
        let savedMode = UserDefaults.standard.string(forKey: Self.menuBarDisplayModeKey)
        menuBarDisplayMode = MenuBarDisplayMode(rawValue: savedMode ?? "") ?? .iconAndPercentage
        snapshot = cache.load()

        client.notificationHandler = { [weak self] method, _ in
            guard let self else { return }
            switch method {
            case "account/rateLimits/updated", "account/login/completed", "account/updated":
                Task { await self.refresh() }
            default:
                break
            }
        }
    }

    func start() async {
        await refresh()
        refreshLoop?.cancel()
        refreshLoop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                guard !Task.isCancelled else { return }
                await self?.refresh()
            }
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        errorMessage = nil
        defer { isRefreshing = false }

        do {
            try await client.startIfNeeded()
            codexExecutablePath = client.executableURL?.path

            let accountResult = try await client.readAccount()
            let account = accountResult.objectValue?["account"]
            let accountType = account?.objectValue?["type"]?.stringValue
            needsSignIn = account == .null || accountType == "apiKey" || accountType == "amazonBedrock"

            guard !needsSignIn else {
                errorMessage = nil
                return
            }

            let result = try await client.readRateLimits()
            let updatedSnapshot = try UsageSnapshot(appServerResult: result)
            snapshot = updatedSnapshot
            cache.save(updatedSnapshot)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signIn() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            try await client.startIfNeeded()
            let url = try await client.startChatGPTLogin()
            NSWorkspace.shared.open(url)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stop() {
        refreshLoop?.cancel()
        refreshLoop = nil
        client.stop()
    }
}
