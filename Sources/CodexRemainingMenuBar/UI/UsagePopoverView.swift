import AppKit
import SwiftUI

struct UsagePopoverView: View {
    @ObservedObject var viewModel: UsageViewModel
    @StateObject private var launchAtLogin = LaunchAtLoginManager()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if viewModel.needsSignIn {
                        signInState
                    } else {
                        if let snapshot = viewModel.snapshot {
                            quotaCard(snapshot)
                            ResetCreditsBanner(snapshot: snapshot)
                        } else if viewModel.isRefreshing {
                            loadingState
                        } else {
                            emptyState
                        }

                        TokenUsageCard(
                            snapshot: viewModel.tokenUsage,
                            isRefreshing: viewModel.isRefreshing,
                            errorMessage: viewModel.tokenUsageError
                        )
                    }

                    if let errorMessage = viewModel.errorMessage {
                        errorBanner(errorMessage)
                    }
                }
                .padding(.vertical, 1)
            }

            Divider()
            footer
        }
        .padding(14)
        .frame(width: 340)
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "gauge.with.dots.needle.33percent")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.tint)

            Text("Codex Usage")
                .font(.system(size: 17, weight: .semibold))

            if let plan = viewModel.snapshot?.limits.compactMap(\.planType).first {
                planBadge(plan)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 5) {
                    if viewModel.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Button {
                        Task { await viewModel.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .keyboardShortcut("r", modifiers: .command)
                    .help("刷新 (⌘R)")
                    .disabled(viewModel.isRefreshing)
                }

                if let fetchedAt = viewModel.snapshot?.fetchedAt {
                    Text("\(fetchedAt.formatted(date: .omitted, time: .shortened)) 更新")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func quotaCard(_ snapshot: UsageSnapshot) -> some View {
        let codex = snapshot.limits.first { $0.id == "codex" } ?? snapshot.limits.first
        let weekly = codex?.windows.first { $0.windowDurationMinutes == 10_080 }
        let featuredWindow = weekly ?? codex?.windows.first
        let otherWindows = codex?.windows.filter { $0.id != featuredWindow?.id } ?? []
        let otherLimits = snapshot.limits.filter { $0.id != codex?.id }

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(weekly == nil ? "\(codex?.displayName ?? "Codex") 剩余额度" : "\(codex?.displayName ?? "Codex") 7 天剩余窗口")
                    .font(.callout.weight(.semibold))
                Spacer()
                if codex?.spendControlReached == true || codex?.rateLimitReachedType != nil {
                    Text("额度已用尽")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.red)
                }
            }

            if let featuredWindow {
                windowRow(featuredWindow)
            } else {
                Text("当前没有额度窗口数据")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !otherWindows.isEmpty || !otherLimits.isEmpty {
                Divider()
                DisclosureGroup("其他额度窗口") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(otherWindows) { window in
                            windowRow(window)
                        }
                        ForEach(otherLimits) { limit in
                            HStack {
                                Text(limit.displayName)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if limit.spendControlReached == true || limit.rateLimitReachedType != nil {
                                    Text("额度已用尽")
                                        .foregroundStyle(.red)
                                }
                            }
                            .font(.caption.weight(.medium))
                            ForEach(limit.windows) { window in
                                windowRow(window)
                            }
                            if limit.hasCredits == true, let balance = limit.creditsBalance {
                                Label("余额 \(balance)", systemImage: "creditcard")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.top, 8)
                }
                .font(.caption)
            }

            if codex?.hasCredits == true, let balance = codex?.creditsBalance {
                Label("余额 \(balance)", systemImage: "creditcard")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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

    private func windowRow(_ window: UsageWindow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.durationDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("剩余 \(window.remainingPercent)%")
                    .font(.system(size: 16, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(color(for: window.remainingPercent))
            }

            ProgressView(value: Double(window.remainingPercent), total: 100)
                .tint(color(for: window.remainingPercent))

            Text("已使用 \(Int(window.usedPercent.rounded()))%")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("重置：\(resetDescription(window.resetsAt))（本机时间）")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var signInState: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            Text("登录后查看 Codex 使用额度")
                .font(.callout)
            Button("登录 ChatGPT") {
                Task { await viewModel.signIn() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 130)
    }

    private var loadingState: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text("正在读取使用额度…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 130)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "gauge.open.with.lines.needle.33percent")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("暂时没有 Usage 数据")
                .font(.callout)
            Button("重试") {
                Task { await viewModel.refresh() }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 130)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var footer: some View {
        VStack(spacing: 10) {
            HStack {
                Label("菜单栏显示", systemImage: "menubar.rectangle")
                    .font(.subheadline.weight(.medium))

                Spacer()

                Picker(
                    "菜单栏显示",
                    selection: $viewModel.menuBarDisplayMode
                ) {
                    ForEach(MenuBarDisplayMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(width: 118)
            }

            Toggle(
                "登录时启动",
                isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                )
            )
            .toggleStyle(.switch)
            .controlSize(.small)
            .font(.subheadline.weight(.medium))

            if let error = launchAtLogin.errorMessage {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }

            HStack {
                Button {
                    if let url = URL(string: "https://chatgpt.com/codex/settings/usage") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("完整 Usage", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.bordered)
                .keyboardShortcut("u", modifiers: .command)
                .help("打开完整 Usage (⌘U)")

                Spacer()

                Button(role: .destructive) {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("退出应用", systemImage: "power")
                }
                .buttonStyle(.bordered)
                .keyboardShortcut("q", modifiers: .command)
                .help("退出应用 (⌘Q)")
                .tint(.red)
            }
            .controlSize(.regular)
        }
    }

    private func planBadge(_ plan: String) -> some View {
        Text(plan.uppercased())
            .font(.system(size: 10, weight: .bold, design: .default))
            .tracking(0.25)
            .foregroundStyle(Color(nsColor: .systemPurple))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(Color(nsColor: .systemPurple), lineWidth: 1)
            }
            .accessibilityLabel("\(plan) 账户")
    }

    private func color(for remaining: Int) -> Color {
        if remaining <= 10 { return .red }
        if remaining <= 30 { return .orange }
        return .accentColor
    }

    private func resetDescription(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd EEE HH:mm"
        return formatter.string(from: date)
    }
}
