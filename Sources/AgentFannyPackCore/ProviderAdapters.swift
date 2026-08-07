import Foundation

public struct ProviderRefresh: Equatable, Sendable {
    public var identity: String?
    public var connected: Bool
    public var snapshot: QuotaSnapshot?
    public var health: SourceHealth
    public var detail: String?

    public init(identity: String?, connected: Bool, snapshot: QuotaSnapshot?, health: SourceHealth, detail: String? = nil) {
        self.identity = identity
        self.connected = connected
        self.snapshot = snapshot
        self.health = health
        self.detail = detail
    }
}

public protocol ProviderRefreshing {
    var surface: ProviderSurface { get }
    func refresh(profile: AccountProfile, previousSnapshot: QuotaSnapshot?) throws -> ProviderRefresh
}

public struct CodexCLIAdapter: ProviderRefreshing {
    public let surface: ProviderSurface = .codexCLI
    private let runner: ProcessRunning
    private let now: () -> Date

    public init(runner: ProcessRunning = SystemProcessRunner(), now: @escaping () -> Date = Date.init) {
        self.runner = runner
        self.now = now
    }

    public func refresh(profile: AccountProfile, previousSnapshot: QuotaSnapshot?) throws -> ProviderRefresh {
        guard let home = profile.configurationHome else {
            throw FannyPackError.missingConfigurationHome(profile.id)
        }
        let messages = [
            #"{"method":"initialize","id":0,"params":{"clientInfo":{"name":"agent_fanny_pack","title":"Agent Fanny Pack","version":"0.1.2"}}}"#,
            #"{"method":"initialized","params":{}}"#,
            #"{"method":"account/read","id":1,"params":{"refreshToken":false}}"#,
            #"{"method":"account/rateLimits/read","id":2}"#
        ].joined(separator: "\n") + "\n"
        let result = try runner.run(
            CommandSpec(executable: "/usr/bin/env", arguments: ["codex", "app-server"], environment: ["CODEX_HOME": home]),
            standardInput: messages,
            timeout: 8
        )
        guard result.exitCode == 0 else {
            throw FannyPackError.commandFailed(Redactor.text(result.standardError))
        }
        return try Self.decode(profileID: profile.id, jsonLines: result.standardOutput, fetchedAt: now())
    }

    public static func decode(profileID: String, jsonLines: String, fetchedAt: Date) throws -> ProviderRefresh {
        let objects = jsonLines.split(whereSeparator: \.isNewline).compactMap { line -> [String: Any]? in
            guard let data = String(line).data(using: .utf8) else { return nil }
            return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        }
        let accountResponse = objects.first { ($0["id"] as? Int) == 1 }
        let rateResponse = objects.first { ($0["id"] as? Int) == 2 }
        guard let accountResult = accountResponse?["result"] as? [String: Any] else {
            throw FannyPackError.invalidProviderPayload("account/read")
        }
        let account = accountResult["account"] as? [String: Any]
        let identity = (account?["email"] as? String) ?? (account?["type"] as? String)
        let connected = account != nil

        var windows: [QuotaWindow] = []
        if let result = rateResponse?["result"] as? [String: Any] {
            if let buckets = result["rateLimitsByLimitId"] as? [String: Any] {
                for key in buckets.keys.sorted() {
                    guard let bucket = buckets[key] as? [String: Any] else { continue }
                    windows.append(contentsOf: decodeCodexBucket(bucket, fallbackID: key))
                }
            } else if let bucket = result["rateLimits"] as? [String: Any] {
                windows.append(contentsOf: decodeCodexBucket(bucket, fallbackID: "codex"))
            }
        }
        let snapshot = windows.isEmpty ? nil : QuotaSnapshot(
            profileID: profileID,
            windows: windows,
            fetchedAt: fetchedAt,
            source: .codexAppServer
        )
        return ProviderRefresh(
            identity: identity,
            connected: connected,
            snapshot: snapshot,
            health: connected && snapshot != nil ? .fresh : .unavailable,
            detail: connected && snapshot == nil ? "Signed in; first-party limits were not returned." : nil
        )
    }

    private static func decodeCodexBucket(_ bucket: [String: Any], fallbackID: String) -> [QuotaWindow] {
        let bucketID = (bucket["limitId"] as? String) ?? fallbackID
        let name = (bucket["limitName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        var result: [QuotaWindow] = []
        for (key, suffix) in [("primary", "primary"), ("secondary", "secondary")] {
            guard let window = bucket[key] as? [String: Any],
                  let used = window["usedPercent"] as? Double,
                  let reset = window["resetsAt"] as? Double else { continue }
            let duration = (window["windowDurationMins"] as? Double).map(Int.init)
            let durationLabel: String
            if let duration, duration % 10_080 == 0 { durationLabel = "\(duration / 10_080)w" }
            else if let duration, duration % 1_440 == 0 { durationLabel = "\(duration / 1_440)d" }
            else if let duration, duration % 60 == 0 { durationLabel = "\(duration / 60)h" }
            else if let duration { durationLabel = "\(duration)m" }
            else { durationLabel = suffix.capitalized }
            result.append(QuotaWindow(
                id: "\(bucketID)-\(suffix)",
                label: name ?? durationLabel,
                usedPercent: used,
                resetsAt: Date(timeIntervalSince1970: reset)
            ))
        }
        return result
    }
}

public struct ClaudeCodeAdapter: ProviderRefreshing {
    public let surface: ProviderSurface = .claudeCode
    private let runner: ProcessRunning

    public init(runner: ProcessRunning = SystemProcessRunner()) {
        self.runner = runner
    }

    public func refresh(profile: AccountProfile, previousSnapshot: QuotaSnapshot?) throws -> ProviderRefresh {
        guard let home = profile.configurationHome else {
            throw FannyPackError.missingConfigurationHome(profile.id)
        }
        let result = try runner.run(
            CommandSpec(executable: "/usr/bin/env", arguments: ["claude", "auth", "status"], environment: ["CLAUDE_CONFIG_DIR": home]),
            standardInput: nil,
            timeout: 5
        )
        guard let data = result.standardOutput.data(using: .utf8),
              let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            if result.exitCode == 1 {
                return ProviderRefresh(identity: nil, connected: false, snapshot: previousSnapshot, health: .unavailable, detail: "Not signed in.")
            }
            throw FannyPackError.invalidProviderPayload("claude auth status")
        }
        let connected = (payload["loggedIn"] as? Bool)
            ?? (payload["authenticated"] as? Bool)
            ?? (result.exitCode == 0)
        let identity = (payload["email"] as? String)
            ?? (payload["account"] as? [String: Any])?["email"] as? String
            ?? (payload["authMethod"] as? String)
        let health = connected ? QuotaFormatting.health(for: previousSnapshot) : .unavailable
        return ProviderRefresh(
            identity: identity,
            connected: connected,
            snapshot: previousSnapshot,
            health: health,
            detail: previousSnapshot == nil ? "Connect the first-party status-line bridge to show quota." : nil
        )
    }
}

public enum ClaudeStatusLineDecoder {
    public static func decode(profileID: String, data: Data, fetchedAt: Date = Date()) throws -> QuotaSnapshot {
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let limits = payload["rate_limits"] as? [String: Any] else {
            throw FannyPackError.invalidProviderPayload("Claude rate_limits")
        }
        let definitions = [("five_hour", "5h"), ("seven_day", "7d")]
        let windows = definitions.compactMap { key, label -> QuotaWindow? in
            guard let item = limits[key] as? [String: Any],
                  let used = item["used_percentage"] as? Double,
                  let reset = item["resets_at"] as? Double else { return nil }
            return QuotaWindow(
                id: "claude-\(key)",
                label: label,
                usedPercent: used,
                resetsAt: Date(timeIntervalSince1970: reset)
            )
        }
        guard !windows.isEmpty else {
            throw FannyPackError.invalidProviderPayload("Claude rate limit windows")
        }
        return QuotaSnapshot(
            profileID: profileID,
            windows: windows,
            fetchedAt: fetchedAt,
            source: .claudeStatusLine
        )
    }
}

public struct GuidedCodexMacAdapter: ProviderRefreshing {
    public let surface: ProviderSurface = .codexMacApp
    public init() {}
    public func refresh(profile: AccountProfile, previousSnapshot: QuotaSnapshot?) throws -> ProviderRefresh {
        ProviderRefresh(
            identity: profile.identity,
            connected: profile.connected,
            snapshot: previousSnapshot,
            health: previousSnapshot.map { QuotaFormatting.health(for: $0) } ?? .unavailable,
            detail: "Guided sign-out/sign-in only; the app owns its session."
        )
    }
}

public struct CursorDeferredAdapter: ProviderRefreshing {
    public let surface: ProviderSurface = .cursor
    public init() {}
    public func refresh(profile: AccountProfile, previousSnapshot: QuotaSnapshot?) throws -> ProviderRefresh {
        ProviderRefresh(
            identity: nil,
            connected: false,
            snapshot: nil,
            health: .unsupported,
            detail: "Deferred: no supported personal quota plus isolated-profile switching contract."
        )
    }
}
