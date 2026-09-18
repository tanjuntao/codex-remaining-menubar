import SwiftUI

struct TokenUsageCard: View {
    let snapshot: TokenUsageSnapshot?
    let isRefreshing: Bool
    let errorMessage: String?
    @State private var selectedDate: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Token 消耗")
                    .font(.callout.weight(.semibold))
                Spacer()
                if let fetchedAt = snapshot?.fetchedAt {
                    Text("\(fetchedAt.formatted(date: .omitted, time: .shortened)) 更新")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .help("最近成功获取：\(fetchedAt.formatted())。服务端统计可能延迟。")
                }
            }

            if let snapshot {
                activity(snapshot)
            } else if isRefreshing {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在读取 Token 用量…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if errorMessage == nil {
                Text("暂时没有 Token 用量数据")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Label {
                    Text((snapshot == nil ? "" : "显示缓存 · ") + errorMessage)
                        .lineLimit(3)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .font(.caption)
                .foregroundStyle(.orange)
                .help(errorMessage)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func activity(_ snapshot: TokenUsageSnapshot) -> some View {
        let days = snapshot.recentDays(count: 10)
        let today = days.last
        let selected = days.first { $0.dateKey == selectedDate }
            ?? days.last { $0.tokens != nil }
            ?? today

        metric("总消耗", tokens: snapshot.summary.lifetimeTokens)

        if snapshot.dailyUsageBuckets != nil {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("近 10 天 · 由近及远")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let selected {
                        Text("\(selected.shortLabel) · \(selected.tokens == nil ? "尚未返回" : TokenUsageSnapshot.formattedTokens(selected.tokens))")
                            .monospacedDigit()
                    }
                }
                .font(.caption)

                VStack(spacing: 9) {
                    ForEach(Array(days.reversed())) { day in
                        dayBar(day, maximum: days.compactMap(\.tokens).max() ?? 0, selected: day.dateKey == selected?.dateKey)
                    }
                }
            }
        }

        HStack {
            Text("单日峰值 \(TokenUsageSnapshot.formattedTokens(snapshot.summary.peakDailyTokens))")
            Spacer()
            Text("连续 \(snapshot.summary.currentStreakDays.map(String.init) ?? "—") 天")
                .help("最长连续使用：\(snapshot.summary.longestStreakDays.map(String.init) ?? "—") 天")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)

        if snapshot.dailyUsageBuckets == nil {
            Text("服务端尚未返回每日明细。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else if today?.tokens == nil {
            Text("今日数据尚未返回\(snapshot.dailyUsageBuckets?.last.map { " · 最新 \($0.startDate)" } ?? "")")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }

        if snapshot.dailyUsageBuckets?.isEmpty == false {
            Divider()
            TokenUsageCalendar(snapshot: snapshot)
        }
    }

    private func metric(_ title: String, tokens: Int64?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(TokenUsageSnapshot.formattedTokens(tokens))
                .font(.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(tokens.map { "\(title)：\(TokenUsageSnapshot.formattedTokens($0))" } ?? "\(title)：服务端尚未返回数据")
    }

    private func dayBar(_ day: TokenUsageSnapshot.Day, maximum: Int64, selected: Bool) -> some View {
        let ratio = maximum > 0 ? Double(day.tokens ?? 0) / Double(maximum) : 0
        return Button {
            selectedDate = day.dateKey
        } label: {
            VStack(spacing: 4) {
                HStack {
                    Text(day.shortLabel)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(day.tokens == nil ? "尚未返回" : TokenUsageSnapshot.formattedTokens(day.tokens))
                        .fontWeight(.medium)
                        .foregroundStyle(day.tokens == nil ? .secondary : .primary)
                }
                .font(.caption.monospacedDigit())

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.12))
                        Capsule()
                            .fill(Color.accentColor.opacity(selected ? 1 : 0.5))
                            .frame(width: ratio > 0 ? max(2, geometry.size.width * ratio) : 0)
                    }
                }
                .frame(height: 7)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(day.dateKey)：\(day.tokens.map { TokenUsageSnapshot.formattedTokens($0) } ?? "尚未返回")")
        .accessibilityLabel("\(day.dateKey)，\(day.tokens.map { TokenUsageSnapshot.formattedTokens($0) } ?? "尚未返回")")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
