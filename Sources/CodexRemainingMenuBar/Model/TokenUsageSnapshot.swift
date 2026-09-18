import Foundation

struct TokenUsageSnapshot: Codable, Equatable, Sendable {
    struct Summary: Codable, Equatable, Sendable {
        let lifetimeTokens: Int64?
        let peakDailyTokens: Int64?
        let longestRunningTurnSec: Int64?
        let currentStreakDays: Int64?
        let longestStreakDays: Int64?
    }

    struct DailyBucket: Codable, Equatable, Identifiable, Sendable {
        let startDate: String
        let tokens: Int64
        var id: String { startDate }
    }

    struct Day: Identifiable {
        let dateKey: String
        let tokens: Int64?
        var id: String { dateKey }
        var shortLabel: String { String(dateKey.suffix(5)).replacingOccurrences(of: "-", with: "/") }
    }

    struct CalendarWeek: Identifiable {
        let startDateKey: String
        let days: [Day?]
        var id: String { startDateKey }
    }

    let summary: Summary
    let dailyUsageBuckets: [DailyBucket]?
    let fetchedAt: Date

    init(appServerResult: JSONValue, fetchedAt: Date = Date()) throws {
        struct Response: Decodable {
            let summary: Summary
            let dailyUsageBuckets: [DailyBucket]?
        }

        do {
            let data = try JSONEncoder().encode(appServerResult)
            let response = try JSONDecoder().decode(Response.self, from: data)
            let metrics = [
                response.summary.lifetimeTokens, response.summary.peakDailyTokens,
                response.summary.longestRunningTurnSec, response.summary.currentStreakDays,
                response.summary.longestStreakDays
            ]
            guard metrics.compactMap({ $0 }).allSatisfy({ $0 >= 0 }) else {
                throw ParsingError.invalidResponse
            }

            if let buckets = response.dailyUsageBuckets {
                let formatter = Self.dateFormatter(timeZone: TimeZone(secondsFromGMT: 0)!)
                guard Set(buckets.map(\.startDate)).count == buckets.count,
                      buckets.allSatisfy({ bucket in
                          guard bucket.tokens >= 0,
                                let date = formatter.date(from: bucket.startDate) else { return false }
                          return formatter.string(from: date) == bucket.startDate
                      }) else {
                    throw ParsingError.invalidResponse
                }
            }

            summary = response.summary
            dailyUsageBuckets = response.dailyUsageBuckets?.sorted { $0.startDate < $1.startDate }
            self.fetchedAt = fetchedAt
        } catch {
            throw ParsingError.invalidResponse
        }
    }

    // Keep the service's YYYY-MM-DD labels intact. The API provides no bucket time zone.
    // Local calendar dates select "today"; missing buckets stay unknown, never inferred as zero.
    func recentDays(count: Int = 7, now: Date = Date(), timeZone: TimeZone = .current) -> [Day] {
        guard count > 0 else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let formatter = Self.dateFormatter(timeZone: timeZone)
        let byDate = Dictionary((dailyUsageBuckets ?? []).map { ($0.startDate, $0.tokens) }, uniquingKeysWith: { _, last in last })
        return (0..<count).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: now) else { return nil }
            let key = formatter.string(from: date)
            return Day(dateKey: key, tokens: byDate[key])
        }
    }

    // Arrange every returned date in Monday-to-Sunday columns. Missing dates within the
    // covered range remain unknown; only an explicit server bucket represents zero usage.
    func calendarWeeks(now: Date = Date(), timeZone: TimeZone = .current) -> [CalendarWeek] {
        guard let buckets = dailyUsageBuckets, let firstBucket = buckets.first else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.firstWeekday = 2
        let formatter = Self.dateFormatter(timeZone: timeZone)
        guard let firstDate = formatter.date(from: firstBucket.startDate),
              let firstWeek = calendar.dateInterval(of: .weekOfYear, for: firstDate)?.start else { return [] }

        let lastBucketDate = buckets.last.flatMap { formatter.date(from: $0.startDate) } ?? now
        let lastDate = max(calendar.startOfDay(for: now), lastBucketDate)
        let byDate = Dictionary(buckets.map { ($0.startDate, $0.tokens) }, uniquingKeysWith: { _, last in last })
        var weeks: [CalendarWeek] = []
        var weekStart = firstWeek
        while weekStart <= lastDate {
            let days = (0..<7).map { offset -> Day? in
                guard let date = calendar.date(byAdding: .day, value: offset, to: weekStart),
                      date >= firstDate, date <= lastDate else { return nil }
                let key = formatter.string(from: date)
                return Day(dateKey: key, tokens: byDate[key])
            }
            weeks.append(CalendarWeek(startDateKey: formatter.string(from: weekStart), days: days))
            guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: weekStart) else { break }
            weekStart = next
        }
        return weeks
    }

    static func formattedTokens(_ tokens: Int64?) -> String {
        guard let tokens else { return "—" }
        if tokens > 0 && tokens < 1_000 { return "<0.001M" }
        let millions = Double(tokens) / 1_000_000
        let digits = millions < 1 ? 3 : 1
        return millions.formatted(.number.precision(.fractionLength(0...digits)).locale(Locale(identifier: "en_US"))) + "M"
    }

    private static func dateFormatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }

    enum ParsingError: LocalizedError {
        case invalidResponse

        var errorDescription: String? { "Token 用量数据格式无法识别，请更新 Codex CLI 后重试。" }
    }
}
