import SwiftUI

struct ResetCreditsBanner: View {
    let snapshot: UsageSnapshot

    var body: some View {
        let credits = snapshot.availableResetCredits
        let count = snapshot.resetCreditsAvailable
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Label("可重置次数", systemImage: "arrow.counterclockwise.circle.fill")
                    .font(.callout.weight(.semibold))
                Spacer()
                Text(count.map { "\($0) 次" } ?? "—")
                    .font(.system(size: 19, weight: .bold, design: .rounded).monospacedDigit())
            }
            .accessibilityElement(children: .combine)

            if count == 0 {
                Text("暂无可用重置次数")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if credits.isEmpty {
                Text("到期时间暂不可用")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("到期时间（本机时区）")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .help(TimeZone.current.identifier)

                if credits.count > 5 {
                    ScrollView {
                        expirationRows(credits)
                    }
                    .frame(height: 140)
                } else {
                    expirationRows(credits)
                }

                if !snapshot.hasCompleteResetCreditExpirations {
                    Text("部分重置卡的期限尚未返回。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .foregroundStyle(.primary)
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private func expirationRows(_ credits: [UsageResetCredit]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(credits.enumerated()), id: \.element.id) { index, credit in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("重置卡 \(index + 1)")
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(credit.expirationDescription)
                            .monospacedDigit()
                        if let expiresAt = credit.expiresAt, expiresAt <= Date() {
                            Text("已到期，待刷新")
                                .foregroundStyle(.orange)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
