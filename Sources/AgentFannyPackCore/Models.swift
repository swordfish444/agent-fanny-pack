import Foundation

public enum ProviderSurface: String, Codable, CaseIterable, Identifiable, Sendable {
    case codexCLI = "codex-cli"
    case codexMacApp = "codex-macos"
    case claudeCode = "claude-code"
    case cursor = "cursor"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .codexCLI: return "OpenAI Codex CLI"
        case .codexMacApp: return "Codex macOS app"
        case .claudeCode: return "Claude Code"
        case .cursor: return "Cursor"
        }
    }

    public var shortName: String {
        switch self {
        case .codexCLI: return "Codex CLI"
        case .codexMacApp: return "Codex app"
        case .claudeCode: return "Claude Code"
        case .cursor: return "Cursor"
        }
    }
}

public enum SwitchCapability: String, Codable, Sendable {
    case isolatedProfile
    case guidedOnly
    case unsupported
}

public enum SourceHealth: String, Codable, Sendable {
    case fresh
    case stale
    case offline
    case error
    case unavailable
    case unsupported

    public var label: String {
        switch self {
        case .fresh: return "Fresh"
        case .stale: return "Stale"
        case .offline: return "Offline"
        case .error: return "Needs attention"
        case .unavailable: return "No snapshot"
        case .unsupported: return "Unsupported"
        }
    }
}

public enum QuotaSource: String, Codable, Sendable {
    case codexAppServer = "Codex app-server"
    case claudeStatusLine = "Claude status line"
    case unavailable = "Unavailable"
    case syntheticPreview = "Synthetic preview"

    public var isAuthoritative: Bool {
        self == .codexAppServer || self == .claudeStatusLine
    }
}

public struct QuotaWindow: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var label: String
    public var usedPercent: Double
    public var resetsAt: Date

    public init(id: String, label: String, usedPercent: Double, resetsAt: Date) {
        self.id = id
        self.label = label
        self.usedPercent = min(100, max(0, usedPercent))
        self.resetsAt = resetsAt
    }

    public var remainingPercent: Double { 100 - usedPercent }
}

public struct QuotaSnapshot: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var profileID: String
    public var windows: [QuotaWindow]
    public var fetchedAt: Date
    public var source: QuotaSource

    public init(
        id: UUID = UUID(),
        profileID: String,
        windows: [QuotaWindow],
        fetchedAt: Date,
        source: QuotaSource
    ) {
        self.id = id
        self.profileID = profileID
        self.windows = windows
        self.fetchedAt = fetchedAt
        self.source = source
    }

    public func displayWindows(showAll: Bool) -> [QuotaWindow] {
        guard !showAll else { return windows }
        guard let preferred = windows.first(where: { window in
            let label = window.label.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            return label == "week" || label == "weekly" || label == "1w" ||
                label == "7d" || label.contains("seven day")
        }) ?? windows.last else { return [] }
        return [preferred]
    }
}

public struct AccountProfile: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var surface: ProviderSurface
    public var label: String
    public var identity: String?
    public var configurationHome: String?
    public var switchCapability: SwitchCapability
    public var connected: Bool
    public var lastError: String?

    public init(
        id: String,
        surface: ProviderSurface,
        label: String,
        identity: String? = nil,
        configurationHome: String? = nil,
        switchCapability: SwitchCapability,
        connected: Bool = false,
        lastError: String? = nil
    ) {
        self.id = id
        self.surface = surface
        self.label = label
        self.identity = identity
        self.configurationHome = configurationHome
        self.switchCapability = switchCapability
        self.connected = connected
        self.lastError = lastError
    }
}

public struct PersistedState: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public var schemaVersion: Int
    public var profiles: [AccountProfile]
    public var activeProfileBySurface: [String: String]
    public var snapshots: [QuotaSnapshot]

    public init(
        schemaVersion: Int = PersistedState.currentSchemaVersion,
        profiles: [AccountProfile] = [],
        activeProfileBySurface: [String: String] = [:],
        snapshots: [QuotaSnapshot] = []
    ) {
        self.schemaVersion = schemaVersion
        self.profiles = profiles
        self.activeProfileBySurface = activeProfileBySurface
        self.snapshots = snapshots
    }

    public func activeProfileID(for surface: ProviderSurface) -> String? {
        activeProfileBySurface[surface.rawValue]
    }

    public mutating func setActive(profileID: String) throws {
        guard let profile = profiles.first(where: { $0.id == profileID }) else {
            throw FannyPackError.unknownProfile(profileID)
        }
        guard profile.switchCapability != .unsupported else {
            throw FannyPackError.unsupportedSwitch(profile.surface)
        }
        activeProfileBySurface[profile.surface.rawValue] = profile.id
    }

    public func latestSnapshot(for profileID: String) -> QuotaSnapshot? {
        snapshots
            .filter { $0.profileID == profileID }
            .max(by: { $0.fetchedAt < $1.fetchedAt })
    }
}

public enum FannyPackError: Error, Equatable, LocalizedError {
    case unknownProfile(String)
    case unsupportedSwitch(ProviderSurface)
    case missingConfigurationHome(String)
    case commandFailed(String)
    case invalidProviderPayload(String)
    case timedOut(String)

    public var errorDescription: String? {
        switch self {
        case .unknownProfile: return "That packed account is no longer available."
        case .unsupportedSwitch(let surface): return "Safe switching is not supported for \(surface.displayName)."
        case .missingConfigurationHome: return "This account is missing its isolated configuration home."
        case .commandFailed(let message): return message
        case .invalidProviderPayload: return "The provider returned an unreadable account response."
        case .timedOut: return "The provider did not respond in time."
        }
    }
}
