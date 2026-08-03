import AppKit

@main
enum CodexRemainingMenuBarApp {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let viewModel = UsageViewModel()
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarController = MenuBarController(viewModel: viewModel)
        Task { await viewModel.start() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        viewModel.stop()
    }
}
