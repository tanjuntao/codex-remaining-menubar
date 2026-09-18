import Foundation

struct UsageResetCredit: Codable, Equatable, Identifiable, Sendable {
    enum Expiration: Codable, Equatable, Sendable {
        case at(Date)
        case never
        case unknown
    }

    let id: String
    let status: String
    let expiration: Expiration

    init?(value: JSONValue) {
        guard let object = value.objectValue,
              let id = object["id"]?.stringValue, !id.isEmpty,
              let status = object["status"]?.stringValue else { return nil }
        self.id = id
        self.status = status

        if object["expiresAt"] == .null {
            // An explicit null means non-expiring; an absent/invalid field is unknown.
            expiration = .never
        } else if let seconds = object["expiresAt"]?.doubleValue,
                  seconds.isFinite, seconds >= 0, seconds <= 253_402_300_799 {
            expiration = .at(Date(timeIntervalSince1970: seconds))
        } else {
            expiration = .unknown
        }
    }

    var expiresAt: Date? {
        guard case let .at(date) = expiration else { return nil }
        return date
    }

    var expirationDescription: String {
        switch expiration {
        case let .at(date): return Self.formattedExpiration(date)
        case .never: return "无到期限制"
        case .unknown: return "到期时间暂不可用"
        }
    }

    static func formattedExpiration(_ date: Date) -> String {
        date.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).hour().minute())
    }
}
