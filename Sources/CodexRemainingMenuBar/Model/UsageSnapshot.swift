import Foundation

struct UsageSnapshot: Codable, Equatable, Sendable {
    let limits: [UsageLimit]
    let resetCreditsAvailable: Int?
    let fetchedAt: Date

    init(limits: [UsageLimit], resetCreditsAvailable: Int?, fetchedAt: Date = Date()) {
        self.limits = limits
        self.resetCreditsAvailable = resetCreditsAvailable
        self.fetchedAt = fetchedAt
    }

    init(appServerResult result: JSONValue, fetchedAt: Date = Date()) throws {
        guard let root = result.objectValue else {
            throw UsageParsingError.invalidRoot
        }

        var parsedLimits: [UsageLimit] = []
        if let buckets = root["rateLimitsByLimitId"]?.objectValue, !buckets.isEmpty {
            parsedLimits = try buckets.map { key, value in
                try UsageLimit(idHint: key, value: value)
            }
        } else if let fallback = root["rateLimits"] {
            parsedLimits = [try UsageLimit(idHint: "codex", value: fallback)]
        }

        guard !parsedLimits.isEmpty else {
            throw UsageParsingError.noLimits
        }

        let credits = root["rateLimitResetCredits"]?.objectValue?["availableCount"]?.intValue
        self.limits = parsedLimits.sorted {
            if $0.id == "codex" { return true }
            if $1.id == "codex" { return false }
            return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
        self.resetCreditsAvailable = credits
        self.fetchedAt = fetchedAt
    }

    var mostConstrainedRemainingPercent: Int? {
        limits
            .flatMap(\.windows)
            .map(\.remainingPercent)
            .min()
    }
}

struct UsageLimit: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let planType: String?
    let windows: [UsageWindow]
    let creditsBalance: String?
    let hasCredits: Bool?
    let isUnlimited: Bool?
    let spendControlReached: Bool?
    let rateLimitReachedType: String?

    fileprivate init(idHint: String, value: JSONValue) throws {
        guard let object = value.objectValue else {
            throw UsageParsingError.invalidLimit(idHint)
        }

        id = object["limitId"]?.stringValue ?? idHint
        let suppliedName = object["limitName"]?.stringValue
        displayName = suppliedName?.isEmpty == false ? suppliedName! : Self.fallbackName(for: id)
        planType = object["planType"]?.stringValue
        creditsBalance = object["credits"]?.objectValue?["balance"]?.stringValue
        hasCredits = object["credits"]?.objectValue?["hasCredits"]?.boolValue
        isUnlimited = object["credits"]?.objectValue?["unlimited"]?.boolValue
        spendControlReached = object["spendControlReached"]?.boolValue
        rateLimitReachedType = object["rateLimitReachedType"]?.stringValue

        var parsedWindows: [UsageWindow] = []
        if let primary = object["primary"], primary != .null {
            parsedWindows.append(try UsageWindow(role: .primary, value: primary, limitID: id))
        }
        if let secondary = object["secondary"], secondary != .null {
            parsedWindows.append(try UsageWindow(role: .secondary, value: secondary, limitID: id))
        }
        windows = parsedWindows
    }

    private static func fallbackName(for id: String) -> String {
        switch id {
        case "codex": return "Codex"
        default:
            return id
                .split(separator: "_")
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
        }
    }
}

struct UsageWindow: Codable, Identifiable, Equatable, Sendable {
    enum Role: String, Codable, Sendable {
        case primary
        case secondary

        var localizedName: String {
            switch self {
            case .primary: return "主要额度"
            case .secondary: return "次要额度"
            }
        }
    }

    let id: String
    let role: Role
    let usedPercent: Double
    let windowDurationMinutes: Int
    let resetsAt: Date

    fileprivate init(role: Role, value: JSONValue, limitID: String) throws {
        guard let object = value.objectValue,
              let usedPercent = object["usedPercent"]?.doubleValue,
              let duration = object["windowDurationMins"]?.intValue,
              let resetsAt = object["resetsAt"]?.doubleValue else {
            throw UsageParsingError.invalidWindow(limitID, role.rawValue)
        }

        id = "\(limitID)-\(role.rawValue)"
        self.role = role
        self.usedPercent = min(100, max(0, usedPercent))
        windowDurationMinutes = duration
        self.resetsAt = Date(timeIntervalSince1970: resetsAt)
    }

    var remainingPercent: Int {
        Int((100 - usedPercent).rounded())
    }

    var durationDescription: String {
        if windowDurationMinutes >= 1_440, windowDurationMinutes.isMultiple(of: 1_440) {
            return "\(windowDurationMinutes / 1_440) 天窗口"
        }
        if windowDurationMinutes >= 60, windowDurationMinutes.isMultiple(of: 60) {
            return "\(windowDurationMinutes / 60) 小时窗口"
        }
        return "\(windowDurationMinutes) 分钟窗口"
    }
}

enum UsageParsingError: LocalizedError, Equatable {
    case invalidRoot
    case noLimits
    case invalidLimit(String)
    case invalidWindow(String, String)

    var errorDescription: String? {
        switch self {
        case .invalidRoot: return "App Server 返回了无法识别的数据。"
        case .noLimits: return "App Server 没有返回可展示的额度。"
        case let .invalidLimit(id): return "额度 \(id) 的数据格式无法识别。"
        case let .invalidWindow(id, role): return "额度 \(id) 的 \(role) 窗口格式无法识别。"
        }
    }
}
