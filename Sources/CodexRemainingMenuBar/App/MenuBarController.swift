import AppKit
import Combine
import SwiftUI

@MainActor
final class MenuBarController: NSObject {
    private static let panelSize = NSSize(width: 340, height: 820)
    private static let panelSpacing: CGFloat = 6
    private static let fullUsageURL = URL(string: "https://chatgpt.com/codex/settings/usage")!

    private let statusItem: NSStatusItem
    private let panel: MenuBarPanel
    private let viewModel: UsageViewModel
    private var cancellables: Set<AnyCancellable> = []
    private var outsideClickMonitor: Any?
    private var keyboardMonitor: Any?

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
            .combineLatest(viewModel.$hasFreshQuotaData)
            .sink { [weak self] values, hasFreshQuotaData in
                let (snapshot, isRefreshing, errorMessage, displayMode) = values
                self?.updateStatusItem(
                    snapshot: snapshot,
                    isRefreshing: isRefreshing,
                    errorMessage: errorMessage,
                    displayMode: displayMode,
                    hasFreshQuotaData: hasFreshQuotaData
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
        panel.acceptsMouseMovedEvents = true
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
        guard outsideClickMonitor == nil, keyboardMonitor == nil else { return }

        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.closePanel()
            }
        }

        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard let self, self.panel.isVisible else {
                return event
            }
            return self.handleKeyboardShortcut(event) ? nil : event
        }
    }

    private func handleKeyboardShortcut(_ event: NSEvent) -> Bool {
        if event.keyCode == 53 {
            closePanel()
            return true
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.contains(.command),
              modifiers.intersection([.control, .option, .shift]).isEmpty,
              let key = event.charactersIgnoringModifiers?.lowercased() else {
            return false
        }

        switch key {
        case "q":
            NSApplication.shared.terminate(nil)
        case "w":
            closePanel()
        case "r":
            Task { await viewModel.refresh() }
        case "u":
            NSWorkspace.shared.open(Self.fullUsageURL)
        default:
            return false
        }
        return true
    }

    private func showPanel(relativeTo button: NSStatusBarButton) {
        guard let buttonWindow = button.window else { return }

        let buttonRectInWindow = button.convert(button.bounds, to: nil)
        let buttonRectOnScreen = buttonWindow.convertToScreen(buttonRectInWindow)
        let visibleFrame = buttonWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        var panelSize = Self.panelSize
        if let visibleFrame {
            panelSize.height = min(panelSize.height, max(1, min(buttonRectOnScreen.minY, visibleFrame.maxY) - visibleFrame.minY - Self.panelSpacing))
        }

        let origin = MenuBarPanelPositioner.origin(
            anchorRect: buttonRectOnScreen,
            panelSize: panelSize,
            visibleFrame: visibleFrame,
            verticalSpacing: Self.panelSpacing
        )
        panel.setFrame(NSRect(origin: origin, size: panelSize), display: false)
        panel.makeKeyAndOrderFront(nil)
        installDismissalMonitors()
    }

    private func closePanel() {
        panel.orderOut(nil)

        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        if let keyboardMonitor {
            NSEvent.removeMonitor(keyboardMonitor)
            self.keyboardMonitor = nil
        }
    }

    private func updateStatusItem(
        snapshot: UsageSnapshot?,
        isRefreshing: Bool,
        errorMessage: String?,
        displayMode: MenuBarDisplayMode,
        hasFreshQuotaData: Bool
    ) {
        guard let button = statusItem.button else { return }
        let presentation = MenuBarStatusPresentation.make(
            snapshot: snapshot,
            isRefreshing: isRefreshing,
            errorMessage: errorMessage,
            displayMode: displayMode,
            hasFreshQuotaData: hasFreshQuotaData
        )

        if let iconName = presentation.iconName {
            button.image = NSImage(
                systemSymbolName: iconName,
                accessibilityDescription: "Codex Usage"
            )
            button.imagePosition = .imageLeading
        } else {
            button.image = nil
        }

        button.title = presentation.title
        button.toolTip = presentation.toolTip
    }
}

struct MenuBarStatusPresentation: Equatable {
    let iconName: String?
    let title: String
    let toolTip: String

    static func make(
        snapshot: UsageSnapshot?,
        isRefreshing: Bool,
        errorMessage: String?,
        displayMode: MenuBarDisplayMode,
        hasFreshQuotaData: Bool
    ) -> Self {
        let iconName: String?
        if displayMode == .percentageOnly {
            iconName = nil
        } else if errorMessage != nil {
            iconName = "exclamationmark.triangle"
        } else if !hasFreshQuotaData, isRefreshing {
            iconName = "arrow.triangle.2.circlepath"
        } else {
            iconName = "gauge.with.dots.needle.33percent"
        }

        if let errorMessage {
            return Self(
                iconName: iconName,
                title: displayMode == .iconOnly ? "" : " !",
                toolTip: errorMessage
            )
        } else if hasFreshQuotaData, let remaining = snapshot?.mostConstrainedRemainingPercent {
            return Self(
                iconName: iconName,
                title: displayMode == .iconOnly ? "" : " \(remaining)%",
                toolTip: "Codex 剩余额度 \(remaining)%"
            )
        } else if isRefreshing {
            return Self(
                iconName: iconName,
                title: displayMode == .iconOnly ? "" : " …",
                toolTip: "正在读取 Codex Usage"
            )
        } else {
            return Self(
                iconName: iconName,
                title: displayMode == .iconOnly ? "" : " —",
                toolTip: "Codex Usage"
            )
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
