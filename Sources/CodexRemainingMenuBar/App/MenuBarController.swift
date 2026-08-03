import AppKit
import Combine
import SwiftUI

@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let viewModel: UsageViewModel
    private var cancellables: Set<AnyCancellable> = []

    init(viewModel: UsageViewModel) {
        self.viewModel = viewModel
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "gauge.with.dots.needle.33percent",
                accessibilityDescription: "Codex Usage"
            )
            button.imagePosition = .imageLeading
            button.title = " —"
            button.target = self
            button.action = #selector(togglePopover)
            button.sendAction(on: [.leftMouseUp])
        }

        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 312, height: 438)
        popover.contentViewController = NSHostingController(
            rootView: UsagePopoverView(viewModel: viewModel)
        )

        viewModel.$snapshot
            .combineLatest(
                viewModel.$isRefreshing,
                viewModel.$errorMessage,
                viewModel.$menuBarDisplayMode
            )
            .sink { [weak self] snapshot, isRefreshing, errorMessage, displayMode in
                self?.updateStatusItem(
                    snapshot: snapshot,
                    isRefreshing: isRefreshing,
                    errorMessage: errorMessage,
                    displayMode: displayMode
                )
            }
            .store(in: &cancellables)
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            Task { await viewModel.refresh() }
        }
    }

    private func updateStatusItem(
        snapshot: UsageSnapshot?,
        isRefreshing: Bool,
        errorMessage: String?,
        displayMode: MenuBarDisplayMode
    ) {
        guard let button = statusItem.button else { return }

        let iconName: String
        if snapshot == nil, errorMessage != nil {
            iconName = "exclamationmark.triangle"
        } else if snapshot == nil, isRefreshing {
            iconName = "arrow.triangle.2.circlepath"
        } else {
            iconName = "gauge.with.dots.needle.33percent"
        }

        if displayMode == .percentageOnly {
            button.image = nil
        } else {
            button.image = NSImage(
                systemSymbolName: iconName,
                accessibilityDescription: "Codex Usage"
            )
            button.imagePosition = .imageLeading
        }

        if let remaining = snapshot?.mostConstrainedRemainingPercent {
            button.title = displayMode == .iconOnly ? "" : " \(remaining)%"
            button.toolTip = "Codex 剩余额度 \(remaining)%"
        } else if isRefreshing {
            button.title = displayMode == .iconOnly ? "" : " …"
            button.toolTip = "正在读取 Codex Usage"
        } else if errorMessage != nil {
            button.title = displayMode == .iconOnly ? "" : " !"
            button.toolTip = errorMessage
        } else {
            button.title = displayMode == .iconOnly ? "" : " —"
            button.toolTip = "Codex Usage"
        }
    }
}
