import Foundation
import Testing
@testable import CodexRemainingMenuBar

private func response(_ json: String) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
}

private let tokenFixture = #"""
{
  "summary": {
    "lifetimeTokens": 12345678901,
    "peakDailyTokens": 1349710279,
    "longestRunningTurnSec": 27699,
    "currentStreakDays": 15,
    "longestStreakDays": 19
  },
  "dailyUsageBuckets": [
    {"startDate": "2026-09-14", "tokens": 73643060},
    {"startDate": "2026-09-12", "tokens": 0},
    {"startDate": "2026-09-13", "tokens": 65580616}
  ],
  "futureField": true
}
"""#

struct TokenUsageTests {
    @Test func parsesSummaryAndSortedDailyBuckets() throws {
        let snapshot = try TokenUsageSnapshot(appServerResult: response(tokenFixture))
        #expect(snapshot.summary.lifetimeTokens == 12_345_678_901)
        #expect(snapshot.summary.peakDailyTokens == 1_349_710_279)
        #expect(snapshot.summary.currentStreakDays == 15)
        #expect(snapshot.dailyUsageBuckets?.map(\.startDate) == ["2026-09-12", "2026-09-13", "2026-09-14"])
        #expect(TokenUsageSnapshot.formattedTokens(snapshot.summary.lifetimeTokens) == "12.3B")
    }

    @Test func preservesUnavailableMetricsAndDailyBuckets() throws {
        let snapshot = try TokenUsageSnapshot(appServerResult: response(#"{"summary":{"lifetimeTokens":null},"dailyUsageBuckets":null}"#))
        #expect(snapshot.summary.lifetimeTokens == nil)
        #expect(snapshot.summary.currentStreakDays == nil)
        #expect(snapshot.dailyUsageBuckets == nil)
        #expect(snapshot.recentDays().allSatisfy { $0.tokens == nil })
        #expect(TokenUsageSnapshot.formattedTokens(nil) == "—")
    }

    @Test func missingDaysAreUnknownAndExplicitZeroIsPreserved() throws {
        let snapshot = try TokenUsageSnapshot(appServerResult: response(tokenFixture))
        let now = try #require(ISO8601DateFormatter().date(from: "2026-09-15T08:00:00Z"))
        let days = snapshot.recentDays(now: now, timeZone: TimeZone(secondsFromGMT: 28_800)!)
        #expect(days.count == 7)
        #expect(days.last?.dateKey == "2026-09-15")
        #expect(days.last?.tokens == nil)
        #expect(days.first { $0.dateKey == "2026-09-12" }?.tokens == 0)
        #expect(days.first { $0.dateKey == "2026-09-14" }?.tokens == 73_643_060)
    }

    @Test func localMidnightChangesTodayWithoutShiftingServerDateLabels() throws {
        let snapshot = try TokenUsageSnapshot(appServerResult: response(tokenFixture))
        let now = try #require(ISO8601DateFormatter().date(from: "2026-09-14T17:00:00Z"))
        let shanghai = snapshot.recentDays(now: now, timeZone: TimeZone(secondsFromGMT: 28_800)!)
        let utc = snapshot.recentDays(now: now, timeZone: TimeZone(secondsFromGMT: 0)!)
        #expect(shanghai.last?.dateKey == "2026-09-15")
        #expect(shanghai.last?.tokens == nil)
        #expect(utc.last?.dateKey == "2026-09-14")
        #expect(utc.last?.tokens == 73_643_060)
    }

    @Test(arguments: [
        #"{"summary":{},"dailyUsageBuckets":[{"startDate":"2026-02-30","tokens":1}]}"#,
        #"{"summary":{},"dailyUsageBuckets":[{"startDate":"2026-09-14","tokens":-1}]}"#,
        #"{"summary":{},"dailyUsageBuckets":[{"startDate":"2026-09-14","tokens":1.5}]}"#,
        #"{"summary":{},"dailyUsageBuckets":[{"startDate":"2026-09-14","tokens":1},{"startDate":"2026-09-14","tokens":2}]}"#,
        #"{"summary":{"lifetimeTokens":-1},"dailyUsageBuckets":[]}"#,
        #"{}"#
    ])
    func rejectsInvalidDataWithoutPublishingPartialTotals(json: String) throws {
        let value = try response(json)
        #expect(throws: TokenUsageSnapshot.ParsingError.self) {
            try TokenUsageSnapshot(appServerResult: value)
        }
    }

    @Test func preservesInt64CountsThroughRPCParsingAndCaching() throws {
        // Above Double's exact-integer range; the App Server schema uses 64-bit integers.
        let value = try response(#"{"summary":{"lifetimeTokens":9007199254740993},"dailyUsageBuckets":[]}"#)
        let snapshot = try TokenUsageSnapshot(appServerResult: value)
        #expect(snapshot.summary.lifetimeTokens == 9_007_199_254_740_993)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = UsageCache(directory: directory)
        cache.saveTokenUsage(snapshot)
        #expect(cache.loadTokenUsage() == snapshot)
        #expect(cache.load() == nil)
        cache.clearTokenUsage()
        #expect(cache.loadTokenUsage() == nil)
    }
}

@MainActor
struct TokenUsageRefreshTests {
    @Test(arguments: [-32601, -32600])
    func unsupportedTokenEndpointDoesNotHideQuota(code: Int) async throws {
        let client = try FakeUsageClient()
        client.tokenError = .rpc(code: code, message: "unknown variant `account/usage/read`")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = UsageViewModel(client: client, cache: UsageCache(directory: directory))
        await model.refresh()
        #expect(model.snapshot?.mostConstrainedRemainingPercent == 80)
        #expect(model.errorMessage == nil)
        #expect(model.tokenUsage == nil)
        #expect(model.tokenUsageError?.contains("升级") == true)
        #expect(!model.isRefreshing)
    }

    @Test func quotaFailureDoesNotPreventTokenRefresh() async throws {
        let client = try FakeUsageClient()
        client.limitsError = .requestTimedOut
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = UsageViewModel(client: client, cache: UsageCache(directory: directory))
        await model.refresh()
        #expect(model.snapshot == nil)
        #expect(model.errorMessage != nil)
        #expect(model.tokenUsage?.summary.lifetimeTokens == 12_345_678_901)
        #expect(model.tokenUsageError == nil)
    }

    @Test func failedRefreshRetainsCacheAndSignOutClearsIt() async throws {
        let client = try FakeUsageClient()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = UsageCache(directory: directory)
        let previous = try TokenUsageSnapshot(appServerResult: response(tokenFixture), fetchedAt: .distantPast)
        cache.saveTokenUsage(previous)
        let model = UsageViewModel(client: client, cache: cache)
        #expect(model.tokenUsage == previous)
        client.tokenError = .requestTimedOut
        await model.refresh()
        #expect(model.tokenUsage == previous)
        #expect(model.tokenUsageError != nil)
        #expect(cache.loadTokenUsage() == previous)
        client.signedOut = true
        await model.refresh()
        #expect(model.needsSignIn)
        #expect(model.tokenUsage == nil)
        #expect(cache.loadTokenUsage() == nil)
    }
}

@MainActor
private final class FakeUsageClient: CodexUsageClient {
    var notificationHandler: CodexAppServerClient.NotificationHandler?
    var executableURL: URL?
    var tokenError: CodexAppServerClient.ClientError?
    var limitsError: CodexAppServerClient.ClientError?
    var signedOut = false
    let tokens: JSONValue
    let limits: JSONValue

    init() throws {
        tokens = try response(tokenFixture)
        limits = try response(#"{"rateLimits":{"primary":{"usedPercent":20,"windowDurationMins":300,"resetsAt":1800000000}}}"#)
    }

    func startIfNeeded() async throws {}
    func readAccount() async throws -> JSONValue {
        .object(["account": signedOut ? .null : .object(["type": .string("chatgpt")])])
    }
    func readRateLimits() async throws -> JSONValue {
        if let limitsError { throw limitsError }
        return limits
    }
    func readTokenUsage() async throws -> JSONValue {
        if let tokenError { throw tokenError }
        return tokens
    }
    func startChatGPTLogin() async throws -> URL { URL(string: "https://chatgpt.com")! }
    func stop() {}
}
