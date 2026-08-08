import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// `NSApplication.delegate` is a weak reference, so the local binding in `main()` is the
    /// only owner. Holding the delegate for the process lifetime keeps `controller` — and with
    /// it the `NSStatusItem` — from being released out from under the menu bar.
    static var shared: AppDelegate?

    private var controller: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        LoginItem.registerOnFirstLaunch()
        let model = AppModel(preview: ProcessInfo.processInfo.environment["AGENT_FANNY_PACK_PREVIEW"] == "1")
        controller = StatusBarController(model: model)
        if ProcessInfo.processInfo.environment["AGENT_FANNY_PACK_OPEN"] == "1" {
            controller?.showPopover()
        }
    }
}

@main
struct AgentFannyPackMain {
    @MainActor
    static func main() {
        if let exitCode = CommandLineMode.handle(arguments: CommandLine.arguments) {
            exit(exitCode)
        }

        let application = NSApplication.shared
        let delegate = AppDelegate()
        AppDelegate.shared = delegate
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}
