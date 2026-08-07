import Foundation

public enum Switching {
    public static func command(for profile: AccountProfile, passthrough: [String] = []) throws -> CommandSpec {
        guard let home = profile.configurationHome else {
            throw FannyPackError.missingConfigurationHome(profile.id)
        }
        switch profile.surface {
        case .codexCLI:
            return CommandSpec(executable: "/usr/bin/env", arguments: ["codex"] + passthrough, environment: ["CODEX_HOME": home])
        case .claudeCode:
            return CommandSpec(executable: "/usr/bin/env", arguments: ["claude"] + passthrough, environment: ["CLAUDE_CONFIG_DIR": home])
        case .codexMacApp, .cursor:
            throw FannyPackError.unsupportedSwitch(profile.surface)
        }
    }

    public static func loginCommand(for profile: AccountProfile) throws -> CommandSpec {
        switch profile.surface {
        case .codexCLI:
            var spec = try command(for: profile)
            spec.arguments += ["login"]
            return spec
        case .claudeCode:
            var spec = try command(for: profile)
            spec.arguments += ["auth", "login"]
            return spec
        case .codexMacApp, .cursor:
            throw FannyPackError.unsupportedSwitch(profile.surface)
        }
    }

    public static func displayCommand(for profile: AccountProfile, passthrough: [String] = []) throws -> String {
        let spec = try command(for: profile, passthrough: passthrough)
        let assignments = spec.environment.keys.sorted().map { key in
            "\(key)=\(shellQuote(spec.environment[key] ?? ""))"
        }
        return (assignments + spec.arguments.map(shellQuote)).joined(separator: " ")
    }

    public static func shellQuote(_ value: String) -> String {
        if value.range(of: #"^[A-Za-z0-9_./:-]+$"#, options: .regularExpression) != nil {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

public struct ProfileDiscovery {
    public let fileManager: FileManager
    public let homeDirectory: URL

    public init(fileManager: FileManager = .default, homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory
    }

    public func defaults() -> [AccountProfile] {
        var profiles: [AccountProfile] = []
        let codexHome = homeDirectory.appendingPathComponent(".codex", isDirectory: true)
        if fileManager.fileExists(atPath: codexHome.path) {
            profiles.append(AccountProfile(
                id: "codex-default",
                surface: .codexCLI,
                label: "Default Codex",
                configurationHome: codexHome.path,
                switchCapability: .isolatedProfile
            ))
        }
        let claudeHome = homeDirectory.appendingPathComponent(".claude", isDirectory: true)
        if fileManager.fileExists(atPath: claudeHome.path) {
            profiles.append(AccountProfile(
                id: "claude-default",
                surface: .claudeCode,
                label: "Default Claude",
                configurationHome: claudeHome.path,
                switchCapability: .isolatedProfile
            ))
        }
        return profiles
    }
}
