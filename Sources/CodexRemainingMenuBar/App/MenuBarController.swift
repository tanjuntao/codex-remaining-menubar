import AppKit
import Combine
import SwiftUI

@MainActor
final class MenuBarController: NSObject {
    private static let panelSize = NSSize(width: 312, height: 438)
    private static let panelSpacing: CGFloat = 6

    private let statusItem: NSStatusItem
    private let panel: MenuBarPanel
    private let viewModel: UsageViewModel
    private var cancellables: Set<AnyCancellable> = []
    private var outsideClickMonitor: Any?
    private var escapeKeyMonitor: Any?

    init(viewModel: UsageViewModel) {
        self.viewModel = viewModel
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        panel = MenuBarPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
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

        configurePanel()

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
        if panel.isVisible {
            closePanel()
        } else {
            showPanel(relativeTo: button)
            Task { await viewModel.refresh() }
        }
    }

    private func configurePanel() {
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.level = .popUpMenu
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]

        let backgroundView = NSVisualEffectView()
        backgroundView.material = .popover
        backgroundView.blendingMode = .behindWindow
        backgroundView.state = .active
        backgroundView.wantsLayer = true
        backgroundView.layer?.cornerRadius = 14
        backgroundView.layer?.masksToBounds = true

        let hostingView = NSHostingView(rootView: UsagePopoverView(viewModel: viewModel))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: backgroundView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor)
        ])
        panel.contentView = backgroundView
    }

    private func installDismissalMonitors() {
        guard outsideClickMonitor == nil, escapeKeyMonitor == nil else { return }

        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.closePanel()
            }
        }

        escapeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard event.keyCode == 53, self?.panel.isVisible == true else {
                return event
            }
            self?.closePanel()
            return nil
        }
    }

    private func showPanel(relativeTo button: NSStatusBarButton) {
        guard let buttonWindow = button.window else { return }

        let buttonRectInWindow = button.convert(button.bounds, to: nil)
        let buttonRectOnScreen = buttonWindow.convertToScreen(buttonRectInWindow)
        let visibleFrame = buttonWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame

        let origin = MenuBarPanelPositioner.origin(
            anchorRect: buttonRectOnScreen,
            panelSize: Self.panelSize,
            visibleFrame: visibleFrame,
            verticalSpacing: Self.panelSpacing
        )
        panel.setFrame(NSRect(origin: origin, size: Self.panelSize), display: false)
        panel.makeKeyAndOrderFront(nil)
        installDismissalMonitors()
    }

    private func closePanel() {
        panel.orderOut(nil)

        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        if let escapeKeyMonitor {
            NSEvent.removeMonitor(escapeKeyMonitor)
            self.escapeKeyMonitor = nil
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

final class MenuBarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

enum MenuBarPanelPositioner {
    static func origin(
        anchorRect: CGRect,
        panelSize: CGSize,
        visibleFrame: CGRect?,
        verticalSpacing: CGFloat = 0
    ) -> CGPoint {
        var x = anchorRect.midX - panelSize.width / 2
        var panelTop = anchorRect.minY

        if let visibleFrame {
            let maximumX = max(visibleFrame.minX, visibleFrame.maxX - panelSize.width)
            x = min(max(x, visibleFrame.minX), maximumX)
            panelTop = min(panelTop, visibleFrame.maxY)
        }

        var y = panelTop - max(0, verticalSpacing) - panelSize.height
        if let visibleFrame {
            y = max(y, visibleFrame.minY)
        }

        return CGPoint(x: x.rounded(), y: y.rounded())
    }
}
