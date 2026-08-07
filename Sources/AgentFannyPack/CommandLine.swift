import AppKit
import Foundation
import AgentFannyPackCore

enum CommandLineMode {
    @MainActor
    static func handle(arguments: [String]) -> Int32? {
        guard arguments.count > 1 else { return nil }
        let command = arguments[1]
        do {
            switch command {
            case "--render-screenshot":
                guard arguments.count >= 3 else { return usage("Missing screenshot path") }
                let dark = arguments.contains("--dark")
                let showAllQuotas = arguments.contains("--all-quotas")
                try ScreenshotRenderer.render(to: URL(fileURLWithPath: arguments[2]), dark: dark, showAllQuotas: showAllQuotas)
                print("Rendered synthetic UI to \(arguments[2])")
                return 0
            case "--ui-smoke-test":
                return uiSmokeTest()
            case "ingest-claude-status":
                return try ingestClaude(arguments: arguments)
            case "profile":
                return try profileCommand(arguments: arguments)
            case "run":
                return try runActive(arguments: arguments)
            case "doctor":
                print("Codex CLI: isolated profiles + first-party app-server quota")
                print("Claude Code: isolated profiles + first-party status-line quota")
                print("Codex macOS: guided switch only")
                print("Cursor: deferred; no supported personal quota/profile contract")
                return 0
            case "--help", "help":
                return usage(nil)
            default:
                return usage("Unknown command: \(command)")
            }
        } catch {
            FileHandle.standardError.write(Data("Agent Fanny Pack: \(Redactor.text(error.localizedDescription))\n".utf8))
            return 1
        }
    }

    @MainActor
    private static func uiSmokeTest() -> Int32 {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        let controller = StatusBarController(model: AppModel(preview: true))
        controller.showPopover()
        RunLoop.current.run(until: Date().addingTimeInterval(0.45))
        let result: [String: Any] = [
            "statusItem": controller.statusItem.button != nil,
            "popoverShown": controller.popover.isShown,
            "synthetic": true
        ]
        let data = try! JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(data: data, encoding: .utf8)!)
        controller.popover.performClose(nil)
        return (result["statusItem"] as? Bool == true && result["popoverShown"] as? Bool == true) ? 0 : 1
    }

    private static func ingestClaude(arguments: [String]) throws -> Int32 {
        guard let marker = arguments.firstIndex(of: "--profile-id"), arguments.indices.contains(marker + 1) else {
            return usage("ingest-claude-status requires --profile-id")
        }
        let profileID = arguments[marker + 1]
        let input = FileHandle.standardInput.readDataToEndOfFile()
        let snapshot = try ClaudeStatusLineDecoder.decode(profileID: profileID, data: input)
        let store = MetadataStore()
        var state = try store.load()
        guard state.profiles.contains(where: { $0.id == profileID && $0.surface == .claudeCode }) else {
            throw FannyPackError.unknownProfile(profileID)
        }
        state.snapshots.append(snapshot)
        try store.save(state)
        let summary = snapshot.windows.map { "\($0.label) \(Int($0.usedPercent.rounded()))% used" }.joined(separator: " · ")
        print("AFP · \(summary)")
        return 0
    }

    private static func profileCommand(arguments: [String]) throws -> Int32 {
        guard arguments.count >= 3 else { return usage("profile requires add or list") }
        let store = MetadataStore()
        var state = try store.load()
        switch arguments[2] {
        case "list":
            for profile in state.profiles {
                let active = state.activeProfileID(for: profile.surface) == profile.id ? "active" : "inactive"
                print("\(profile.id)\t\(profile.surface.rawValue)\t\(active)\t\(profile.label)")
            }
            return 0
        case "add":
            guard arguments.count >= 4, let surface = ProviderSurface(rawValue: arguments[3]) else {
                return usage("profile add requires codex-cli or claude-code")
            }
            guard surface == .codexCLI || surface == .claudeCode else {
                throw FannyPackError.unsupportedSwitch(surface)
            }
            guard let id = option("--id", in: arguments),
                  let label = option("--label", in: arguments),
                  let home = option("--home", in: arguments) else {
                return usage("profile add requires --id, --label, and --home")
            }
            guard id.range(of: #"^[a-z0-9][a-z0-9-]{1,39}$"#, options: .regularExpression) != nil else {
                return usage("Profile id must be 2-40 lowercase letters, digits, or hyphens")
            }
            let expandedHome = NSString(string: home).expandingTildeInPath
            let profile = AccountProfile(
                id: id,
                surface: surface,
                label: String(label.prefix(60)),
                configurationHome: expandedHome,
                switchCapability: .isolatedProfile
            )
            state.profiles.removeAll { $0.id == id }
            state.profiles.append(profile)
            if state.activeProfileID(for: surface) == nil { try state.setActive(profileID: id) }
            try store.save(state)
            print("Packed \(label) for \(surface.displayName). Credentials stay in \(expandedHome).")
            return 0
        default:
            return usage("Unknown profile command")
        }
    }

    private static func runActive(arguments: [String]) throws -> Int32 {
        guard arguments.count >= 3 else { return usage("run requires codex or claude") }
        let surface: ProviderSurface
        switch arguments[2] {
        case "codex": surface = .codexCLI
        case "claude": surface = .claudeCode
        default: return usage("run supports codex or claude")
        }
        let state = try MetadataStore().load()
        guard let activeID = state.activeProfileID(for: surface),
              let profile = state.profiles.first(where: { $0.id == activeID }) else {
            throw FannyPackError.unknownProfile(surface.rawValue)
        }
        let passthrough = Array(arguments.dropFirst(3))
        let spec = try Switching.command(for: profile, passthrough: passthrough)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: spec.executable)
        process.arguments = spec.arguments
        process.environment = ProcessInfo.processInfo.environment.merging(spec.environment) { _, new in new }
        process.standardInput = FileHandle.standardInput
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    private static func option(_ name: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    @discardableResult
    private static func usage(_ error: String?) -> Int32 {
        if let error { FileHandle.standardError.write(Data("\(error)\n".utf8)) }
        print("""
        Usage:
          agent-fanny-pack profile add <codex-cli|claude-code> --id ID --label LABEL --home PATH
          agent-fanny-pack profile list
          agent-fanny-pack run <codex|claude> [arguments...]
          agent-fanny-pack ingest-claude-status --profile-id ID
          agent-fanny-pack doctor
        """)
        return error == nil ? 0 : 2
    }
}
