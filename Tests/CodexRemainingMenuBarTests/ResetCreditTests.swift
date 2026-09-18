import Foundation
import Testing
@testable import CodexRemainingMenuBar

struct ResetCreditTests {
    @Test func parsesAndSortsOnlyAvailableCardExpirations() throws {
        let snapshot = try parseCredits(#"""
        [
          {"id":"used","status":"redeemed","expiresAt":100},
          {"id":"later","status":"available","expiresAt":1800000600},
          {"id":"earlier","status":"available","expiresAt":1800000000}
        ]
        """#, count: 2)

        #expect(snapshot.availableResetCredits.map(\.id) == ["earlier", "later"])
        #expect(snapshot.availableResetCredits.first?.expiresAt == Date(timeIntervalSince1970: 1_800_000_000))
        #expect(snapshot.hasCompleteResetCreditExpirations)
        #expect(snapshot.resetCreditsAvailable == 2)
    }

    @Test func distinguishesNonExpiringFromMissingOrInvalidExpiration() throws {
        let snapshot = try parseCredits(#"""
        [
          {"id":"forever","status":"available","expiresAt":null},
          {"id":"missing","status":"available"},
          {"id":"invalid","status":"available","expiresAt":"tomorrow"}
        ]
        """#, count: 3)

        #expect(snapshot.resetCredits?.first { $0.id == "forever" }?.expiration == .never)
        #expect(snapshot.resetCredits?.first { $0.id == "missing" }?.expiration == .unknown)
        #expect(snapshot.resetCredits?.first { $0.id == "invalid" }?.expiration == .unknown)
        #expect(!snapshot.hasCompleteResetCreditExpirations)

        let nonExpiring = try parseCredits(#"[{"id":"forever","status":"available","expiresAt":null}]"#, count: 1)
        #expect(nonExpiring.hasCompleteResetCreditExpirations)
        #expect(nonExpiring.availableResetCredits.first?.expirationDescription == "无到期限制")
    }

    @Test(arguments: ["null", "[]", #"[{"id":"only-one","status":"available","expiresAt":1800000000}]"#])
    func incompleteDetailsKeepAuthoritativeCount(details: String) throws {
        let snapshot = try parseCredits(details, count: 2)
        #expect(snapshot.resetCreditsAvailable == 2)
        #expect(!snapshot.hasCompleteResetCreditExpirations)
        #expect(snapshot.mostConstrainedRemainingPercent == 80)
    }

    @Test func duplicateAndMalformedRowsCannotMakePartialDetailsLookComplete() throws {
        let snapshot = try parseCredits(#"""
        [
          {"id":"same","status":"available","expiresAt":1800000000},
          {"id":"same","status":"available","expiresAt":1800000000},
          {"status":"available","expiresAt":1800000000}
        ]
        """#, count: 2)
        #expect(snapshot.availableResetCredits.count == 1)
        #expect(!snapshot.hasCompleteResetCreditExpirations)
    }

    @Test func cachedExpirationsRoundTripAndOldCacheStillLoads() throws {
        let snapshot = try parseCredits(#"[{"id":"card","status":"available","expiresAt":1800000000}]"#, count: 1)
        let encoded = try JSONEncoder().encode(snapshot)
        #expect(try JSONDecoder().decode(UsageSnapshot.self, from: encoded) == snapshot)

        var oldCache = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        oldCache.removeValue(forKey: "resetCredits")
        let oldData = try JSONSerialization.data(withJSONObject: oldCache)
        let restored = try JSONDecoder().decode(UsageSnapshot.self, from: oldData)
        #expect(restored.resetCreditsAvailable == 1)
        #expect(restored.resetCredits == nil)
        #expect(!restored.hasCompleteResetCreditExpirations)
        #expect(restored.limits == snapshot.limits)
    }

    private func parseCredits(_ credits: String, count: Int) throws -> UsageSnapshot {
        let json = """
        {
          "rateLimits": {"primary": {"usedPercent":20,"windowDurationMins":300,"resetsAt":1800000000}},
          "rateLimitResetCredits": {"availableCount":\(count),"credits":\(credits)}
        }
        """
        let result = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        return try UsageSnapshot(appServerResult: result)
    }
}
