import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
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
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}
