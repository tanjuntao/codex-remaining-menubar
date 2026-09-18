import AppKit
import Foundation

@MainActor
final class UsageViewModel: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var tokenUsage: TokenUsageSnapshot?
    @Published private(set) var tokenUsageError: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var needsSignIn = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var codexExecutablePath: String?
    @Published var menuBarDisplayMode: MenuBarDisplayMode {
        didSet {
            UserDefaults.standard.set(menuBarDisplayMode.rawValue, forKey: Self.menuBarDisplayModeKey)
        }
    }

    private let client: any CodexUsageClient
    private let cache: UsageCache
    private var refreshLoop: Task<Void, Never>?
    private static let menuBarDisplayModeKey = "menuBarDisplayMode"

    init(client: any CodexUsageClient = CodexAppServerClient(), cache: UsageCache = UsageCache()) {
        self.client = client
        self.cache = cache
        let savedMode = UserDefaults.standard.string(forKey: Self.menuBarDisplayModeKey)
        menuBarDisplayMode = MenuBarDisplayMode(rawValue: savedMode ?? "") ?? .iconAndPercentage
        snapshot = cache.load()
        tokenUsage = cache.loadTokenUsage()

        client.notificationHandler = { [weak self] method, _ in
            guard let self else { return }
            switch method {
            case "account/updated":
                self.tokenUsage = nil
                self.cache.clearTokenUsage()
                Task { await self.refresh() }
            case "account/rateLimits/updated", "account/login/completed":
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
        tokenUsageError = nil
        defer { isRefreshing = false }

        do {
            try await client.startIfNeeded()
            codexExecutablePath = client.executableURL?.path

            let accountResult = try await client.readAccount()
            let account = accountResult.objectValue?["account"]
            let accountType = account?.objectValue?["type"]?.stringValue
            needsSignIn = account == .null || accountType == "apiKey" || accountType == "amazonBedrock"

            guard !needsSignIn else {
                tokenUsage = nil
                cache.clearTokenUsage()
                errorMessage = nil
                return
            }

            // Independent endpoints: either card can update even if the other request fails.
            async let limitsRefresh: Void = refreshLimits()
            async let tokensRefresh: Void = refreshTokenUsage()
            _ = await (limitsRefresh, tokensRefresh)
        } catch {
            errorMessage = error.localizedDescription
            tokenUsageError = "暂时无法刷新 Token 用量。"
        }
    }

    private func refreshLimits() async {
        do {
            let result = try await client.readRateLimits()
            let updatedSnapshot = try UsageSnapshot(appServerResult: result)
            snapshot = updatedSnapshot
            cache.save(updatedSnapshot)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshTokenUsage() async {
        do {
            let result = try await client.readTokenUsage()
            let updated = try TokenUsageSnapshot(appServerResult: result)
            tokenUsage = updated
            cache.saveTokenUsage(updated)
        } catch CodexAppServerClient.ClientError.rpc(let code, let message)
            where code == -32601 || (code == -32600 && message.contains("account/usage/read") && message.contains("unknown variant")) {
            tokenUsageError = "当前 Codex CLI 不支持 Token 统计，请升级后重试。"
        } catch {
            tokenUsageError = error.localizedDescription
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
