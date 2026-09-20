import SwiftUI

struct TokenUsageCalendar: View {
    let snapshot: TokenUsageSnapshot
    @State private var hoveredDay: TokenUsageSnapshot.Day?
    private let cellSize: CGFloat = 12
    private let cellSpacing: CGFloat = 3

    var body: some View {
        let weeks = snapshot.calendarWeeks()
        let maximum = snapshot.dailyUsageBuckets?.map(\.tokens).max() ?? 0

        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("每日用量")
                    .font(.caption.weight(.medium))
                Spacer()
                Text("悬停查看消耗")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: cellSpacing) {
                VStack(spacing: cellSpacing) {
                    Color.clear.frame(width: cellSize, height: 14)
                    ForEach(0..<7) { weekday in
                        Text(["一", "", "三", "", "五", "", "日"][weekday])
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .frame(width: cellSize, height: cellSize)
                    }
                }
                .frame(height: 134)

                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: cellSpacing) {
                            ForEach(weeks) { week in
                                VStack(spacing: cellSpacing) {
                                    Color.clear
                                        .frame(width: cellSize, height: 14)
                                        .overlay(alignment: .leading) {
                                            Text(monthLabel(for: week, isFirstWeek: week.id == weeks.first?.id))
                                                .font(.system(size: 9))
                                                .foregroundStyle(.secondary)
                                                .fixedSize()
                                        }
                                    ForEach(0..<7) { weekday in
                                        if let day = week.days[weekday] {
                                            calendarCell(day, maximum: maximum)
                                        } else {
                                            Color.clear.frame(width: cellSize, height: cellSize)
                                        }
                                    }
                                }
                                .id(week.id)
                            }
                        }
                        .padding(.trailing, 18)
                    }
                    .frame(height: 134)
                    // Eighteen week columns fit at the popover's current width. Shorter
                    // histories stay left aligned instead of scrolling to a trailing anchor.
                    .onAppear {
                        if weeks.count > 18, let last = weeks.last { proxy.scrollTo(last.id, anchor: .trailing) }
                    }
                    .onChange(of: weeks.last?.id) { last in
                        if weeks.count > 18, let last { proxy.scrollTo(last, anchor: .trailing) }
                    }
                }
            }

            Text(hoveredDay.map(dayDescription) ?? "将鼠标移到某一天，查看该日的 M 用量")
                .font(.caption.monospacedDigit())
                .foregroundStyle(hoveredDay == nil ? .secondary : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            HStack(spacing: 4) {
                Text("少")
                ForEach(0..<5) { level in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(level == 0 ? Color.secondary.opacity(0.12) : Color.green.opacity(Double(level) / 4))
                        .frame(width: 10, height: 10)
                }
                Text("多")
                Spacer()
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
                    .frame(width: 10, height: 10)
                Text("尚未返回")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private func calendarCell(_ day: TokenUsageSnapshot.Day, maximum: Int64) -> some View {
        let color: Color
        if let tokens = day.tokens {
            let level = maximum > 0 ? max(1, min(4, Int(ceil(Double(tokens) / Double(maximum) * 4)))) : 0
            color = tokens == 0 ? Color.secondary.opacity(0.12) : Color.green.opacity(Double(level) / 4)
        } else {
            color = .clear
        }
        return Button {
            // Also expose the value to keyboard users and pointer devices that do not hover.
            hoveredDay = day
        } label: {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .overlay {
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(hoveredDay?.id == day.id ? Color.primary : Color.secondary.opacity(day.tokens == nil ? 0.3 : 0), lineWidth: 1)
                }
                .frame(width: cellSize, height: cellSize)
        }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .onHover { hovering in
                updateHover(hovering, day: day)
            }
            .onContinuousHover { phase in
                switch phase {
                case .active: updateHover(true, day: day)
                case .ended: updateHover(false, day: day)
                }
            }
            .help(dayDescription(day))
            .accessibilityLabel(dayDescription(day))
    }

    private func updateHover(_ hovering: Bool, day: TokenUsageSnapshot.Day) {
        if hovering {
            if hoveredDay?.id != day.id { hoveredDay = day }
        } else if hoveredDay?.id == day.id {
            hoveredDay = nil
        }
    }

    private func dayDescription(_ day: TokenUsageSnapshot.Day) -> String {
        "\(day.dateKey) · \(day.tokens.map { TokenUsageSnapshot.formattedTokens($0) } ?? "尚未返回")"
    }

    private func monthLabel(for week: TokenUsageSnapshot.CalendarWeek, isFirstWeek: Bool) -> String {
        let days = week.days.compactMap { $0 }
        guard let day = days.first(where: { $0.dateKey.hasSuffix("-01") }) ?? (isFirstWeek ? days.first : nil) else { return "" }
        return "\(Int(day.dateKey.dropFirst(5).prefix(2)) ?? 0)月"
    }
}
