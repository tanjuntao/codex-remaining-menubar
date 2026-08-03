import Foundation
import Testing
@testable import CodexRemainingMenuBar

struct UsageSnapshotTests {
    @Test
    func launchEnvironmentPrependsCodexDirectoryForFinderLaunches() {
        let executable = URL(fileURLWithPath: "/Users/example/.nvm/versions/node/v24/bin/codex")
        let environment = CodexExecutableLocator.launchEnvironment(
            for: executable,
            baseEnvironment: ["PATH": "/usr/bin:/bin", "PRESERVED": "yes"]
        )

        #expect(environment["PATH"] == "/Users/example/.nvm/versions/node/v24/bin:/usr/bin:/bin")
        #expect(environment["PRESERVED"] == "yes")
    }

    @Test
    func launchEnvironmentDoesNotDuplicateCodexDirectory() {
        let executable = URL(fileURLWithPath: "/opt/homebrew/bin/codex")
        let environment = CodexExecutableLocator.launchEnvironment(
            for: executable,
            baseEnvironment: ["PATH": "/opt/homebrew/bin:/usr/bin:/bin"]
        )

        #expect(environment["PATH"] == "/opt/homebrew/bin:/usr/bin:/bin")
    }

    @Test
    func parsesMultiBucketRateLimits() throws {
        let data = Data(sampleResponse.utf8)
        let envelope = try JSONDecoder().decode(RPCEnvelope.self, from: data)
        let result = try #require(envelope.result)
        let snapshot = try UsageSnapshot(
            appServerResult: result,
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        #expect(snapshot.limits.map(\.id) == ["codex", "codex_spark"])
        #expect(snapshot.limits[0].displayName == "Codex")
        #expect(snapshot.limits[0].windows[0].remainingPercent == 75)
        #expect(snapshot.limits[0].windows[0].durationDescription == "5 小时窗口")
        #expect(snapshot.limits[1].displayName == "Codex Spark")
        #expect(snapshot.mostConstrainedRemainingPercent == 58)
        #expect(snapshot.resetCreditsAvailable == 2)
    }

    @Test
    func fallsBackToSingleRateLimitShape() throws {
        let value: JSONValue = .object([
            "rateLimits": .object([
                "limitId": .string("codex"),
                "primary": window(used: 10, minutes: 10_080, reset: 1_800_000_000),
                "secondary": .null
            ]),
            "rateLimitResetCredits": .null
        ])

        let snapshot = try UsageSnapshot(appServerResult: value)

        #expect(snapshot.limits.count == 1)
        #expect(snapshot.limits[0].windows[0].durationDescription == "7 天窗口")
        #expect(snapshot.mostConstrainedRemainingPercent == 90)
    }

    @Test
    func rejectsResponseWithoutLimits() {
        do {
            _ = try UsageSnapshot(appServerResult: .object([:]))
            Issue.record("Expected UsageParsingError.noLimits")
        } catch {
            #expect(error as? UsageParsingError == .noLimits)
        }
    }

    private func window(used: Double, minutes: Int, reset: Double) -> JSONValue {
        .object([
            "usedPercent": .number(used),
            "windowDurationMins": .number(Double(minutes)),
            "resetsAt": .number(reset)
        ])
    }

    private let sampleResponse = #"""
    {
      "id": 6,
      "result": {
        "rateLimits": {
          "limitId": "codex",
          "primary": {
            "usedPercent": 25,
            "windowDurationMins": 300,
            "resetsAt": 1730947200
          },
          "secondary": null
        },
        "rateLimitsByLimitId": {
          "codex_spark": {
            "limitId": "codex_spark",
            "limitName": "Codex Spark",
            "primary": {
              "usedPercent": 42,
              "windowDurationMins": 60,
              "resetsAt": 1730950800
            },
            "secondary": null,
            "planType": "pro"
          },
          "codex": {
            "limitId": "codex",
            "limitName": null,
            "primary": {
              "usedPercent": 25,
              "windowDurationMins": 300,
              "resetsAt": 1730947200
            },
            "secondary": null,
            "planType": "pro"
          }
        },
        "rateLimitResetCredits": {
          "availableCount": 2,
          "credits": []
        }
      }
    }
    """#
}
