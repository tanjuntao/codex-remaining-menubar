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
        let days = snapshot.recentDays()
        let today = days.last
        let yesterday = days.dropLast().last
        let selected = days.first { $0.dateKey == selectedDate }
            ?? days.last { $0.tokens != nil }
            ?? today

        HStack(alignment: .firstTextBaseline, spacing: 8) {
            metric("今日", tokens: today?.tokens)
            metric("昨日", tokens: yesterday?.tokens)
            metric("累计", tokens: snapshot.summary.lifetimeTokens)
        }

        if snapshot.dailyUsageBuckets != nil {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("近 7 天")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let selected {
                        Text("\(selected.shortLabel) · \(selected.tokens == nil ? "尚未返回" : TokenUsageSnapshot.formattedTokens(selected.tokens))")
                            .monospacedDigit()
                    }
                }
                .font(.caption)

                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(days) { day in
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

        if let buckets = snapshot.dailyUsageBuckets, !buckets.isEmpty {
            DisclosureGroup("每日明细") {
                LazyVStack(spacing: 6) {
                    ForEach(buckets.reversed()) { bucket in
                        HStack {
                            Text(bucket.startDate)
                            Spacer()
                            Text("\(Double(bucket.tokens) / 1_000_000, specifier: "%.1f")M")
                                .textSelection(.enabled)
                        }
                        .font(.caption.monospacedDigit())
                    }
                }
                .padding(.top, 6)
            }
            .font(.caption)
        }
    }

    private func metric(_ title: String, tokens: Int64?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(TokenUsageSnapshot.formattedTokens(tokens))
                .font(.system(size: 19, weight: .semibold, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(tokens.map { "\(title)：\($0.formatted()) tokens" } ?? "\(title)：服务端尚未返回数据")
    }

    private func dayBar(_ day: TokenUsageSnapshot.Day, maximum: Int64, selected: Bool) -> some View {
        let height = maximum > 0 ? max(3, 48 * Double(day.tokens ?? 0) / Double(maximum)) : 3
        return Button {
            selectedDate = day.dateKey
        } label: {
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(day.tokens == nil ? Color.secondary.opacity(0.15) : Color.accentColor.opacity(selected ? 1 : 0.4))
                    .frame(height: height)
                    .frame(height: 48, alignment: .bottom)
                Text(day.shortLabel)
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(selected ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(day.dateKey)：\(day.tokens.map { "\($0.formatted()) tokens" } ?? "尚未返回")")
        .accessibilityLabel("\(day.dateKey)，\(day.tokens.map { "\($0) tokens" } ?? "尚未返回")")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
