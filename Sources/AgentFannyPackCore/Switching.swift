import Foundation
import Security

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
                switchCapability: .isolatedProfile,
                connected: isSignedIn(surface: .codexCLI, home: codexHome)
            ))
        }
        let claudeHome = homeDirectory.appendingPathComponent(".claude", isDirectory: true)
        if fileManager.fileExists(atPath: claudeHome.path) {
            profiles.append(AccountProfile(
                id: "claude-default",
                surface: .claudeCode,
                label: "Default Claude",
                configurationHome: claudeHome.path,
                switchCapability: .isolatedProfile,
                connected: isSignedIn(surface: .claudeCode, home: claudeHome)
            ))
        }
        return profiles
    }

    /// Whether a configuration home already holds a session, decided without launching a
    /// provider process and without reading a single secret. A home that exists is not the
    /// same as a home that is signed in, and treating it as such made a signed-in account
    /// look disconnected.
    public func isSignedIn(surface: ProviderSurface, home: URL) -> Bool {
        switch surface {
        case .codexCLI:
            // OpenAI documents auth.json as the credential file inside CODEX_HOME.
            return fileManager.fileExists(atPath: home.appendingPathComponent("auth.json").path)
        case .claudeCode:
            // Claude Code stores credentials in the login keychain, with a file fallback
            // inside the config directory for non-keychain setups.
            if fileManager.fileExists(atPath: home.appendingPathComponent(".credentials.json").path) {
                return true
            }
            // The keychain item is not per-home, so it only evidences the default home.
            // Letting it vouch for every isolated home would mark them all signed in.
            return home.lastPathComponent == ".claude" && Self.keychainHoldsClaudeCredentials()
        case .codexMacApp, .cursor:
            // App-owned or unsupported: there is no readable local signal, and guessing
            // one would be a claim this app cannot stand behind.
            return false
        }
    }

    /// Every configuration home on this machine that already holds a session. Connect adopts
    /// one of these instead of sending the user through a login they do not need: a session is
    /// just a directory, so pointing at it copies no credential and disturbs no running app.
    public func existingSessions(for surface: ProviderSurface) -> [URL] {
        let prefix: String
        switch surface {
        case .codexCLI, .codexMacApp: prefix = ".codex"
        case .claudeCode: prefix = ".claude"
        case .cursor: return []
        }
        let credentialSurface: ProviderSurface = surface == .codexMacApp ? .codexCLI : surface
        let names = ((try? fileManager.contentsOfDirectory(atPath: homeDirectory.path)) ?? [])
            .filter { $0 == prefix || $0.hasPrefix(prefix + "-") }
            .sorted()
        return names
            .map { homeDirectory.appendingPathComponent($0, isDirectory: true) }
            .filter { isSignedIn(surface: credentialSurface, home: $0) }
    }

    /// Probes for the presence of the item only. `kSecReturnAttributes` keeps the secret out
    /// of the process entirely, which also means macOS does not prompt for access.
    static func keychainHoldsClaudeCredentials() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnAttributes as String: true,
            kSecReturnData as String: false,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }
}
