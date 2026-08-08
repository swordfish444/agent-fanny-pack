import Foundation
import AgentFannyPackCore

struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

@discardableResult
func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws -> Bool {
    guard condition() else { throw TestFailure(description: message) }
    return true
}

func expectThrows(_ message: String, _ operation: () throws -> Void) throws {
    do {
        try operation()
        throw TestFailure(description: message)
    } catch is TestFailure {
        throw TestFailure(description: message)
    } catch {
        return
    }
}

final class FakeRunner: ProcessRunning {
    let result: CommandResult
    var lastSpec: CommandSpec?

    init(result: CommandResult) { self.result = result }

    func run(_ spec: CommandSpec, standardInput: String?, timeout: TimeInterval) throws -> CommandResult {
        lastSpec = spec
        return result
    }
}

let tests: [(String, () throws -> Void)] = [
    ("Codex quota decoding", {
        let payload = """
        {"id":0,"result":{"userAgent":"test"}}
        {"id":1,"result":{"account":{"type":"chatgpt","email":"dev@sample.test","planType":"plus"},"requiresOpenaiAuth":true}}
        {"id":2,"result":{"rateLimitsByLimitId":{"codex":{"limitId":"codex","limitName":null,"primary":{"usedPercent":25.0,"windowDurationMins":300.0,"resetsAt":1800007200.0},"secondary":{"usedPercent":40.0,"windowDurationMins":10080.0,"resetsAt":1800604800.0}}}}}
        """
        let refresh = try CodexCLIAdapter.decode(profileID: "codex-a", jsonLines: payload, fetchedAt: Date(timeIntervalSince1970: 1_800_000_000))
        try expect(refresh.connected, "Codex account should be connected")
        try expect(refresh.identity == "dev@sample.test", "Codex identity was not decoded")
        try expect(refresh.snapshot?.source == .codexAppServer, "Codex source must be authoritative app-server")
        try expect(refresh.snapshot?.windows.count == 2, "Codex should decode both windows")
        try expect(refresh.snapshot?.windows[0].remainingPercent == 75, "Codex remaining percentage is wrong")
        try expect(refresh.snapshot?.windows[1].label == "1w", "Codex window duration label is wrong")
    }),
    ("Codex signed-out state", {
        let payload = """
        {"id":1,"result":{"account":null,"requiresOpenaiAuth":true}}
        {"id":2,"result":{"rateLimits":null}}
        """
        let refresh = try CodexCLIAdapter.decode(profileID: "codex-a", jsonLines: payload, fetchedAt: Date())
        try expect(!refresh.connected, "Signed-out Codex account cannot be connected")
        try expect(refresh.snapshot == nil, "Signed-out Codex must not invent quota")
    }),
    ("Codex malformed response", {
        try expectThrows("Malformed Codex response should fail") {
            _ = try CodexCLIAdapter.decode(profileID: "x", jsonLines: "{\"id\":2,\"result\":{}}", fetchedAt: Date())
        }
    }),
    ("Claude first-party status-line decoding", {
        let payload = Data("""
        {"context_window":{"used_percentage":99},"rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":1800007200.0},"seven_day":{"used_percentage":41.2,"resets_at":1800604800.0}}}
        """.utf8)
        let snapshot = try ClaudeStatusLineDecoder.decode(profileID: "claude-a", data: payload, fetchedAt: Date(timeIntervalSince1970: 1_800_000_000))
        try expect(snapshot.source == .claudeStatusLine, "Claude source must be the official status line")
        try expect(snapshot.windows.map(\.label) == ["5h", "7d"], "Claude windows are wrong")
        try expect(snapshot.windows[0].remainingPercent == 76.5, "Claude remaining percentage is wrong")
        try expect(!snapshot.windows.contains(where: { $0.usedPercent == 99 }), "Context estimate leaked into quota")
    }),
    ("Claude rejects local estimates", {
        try expectThrows("Claude context estimates must not be treated as quota") {
            _ = try ClaudeStatusLineDecoder.decode(profileID: "claude-a", data: Data(#"{"context_window":{"remaining_percentage":90}}"#.utf8))
        }
    }),
    ("Claude auth status preserves quota snapshot", {
        let previous = QuotaSnapshot(profileID: "claude-a", windows: [QuotaWindow(id: "5h", label: "5h", usedPercent: 10, resetsAt: Date().addingTimeInterval(1000))], fetchedAt: Date().addingTimeInterval(-1800), source: .claudeStatusLine)
        let runner = FakeRunner(result: CommandResult(exitCode: 0, standardOutput: #"{"loggedIn":true,"email":"dev@sample.test"}"#, standardError: ""))
        let adapter = ClaudeCodeAdapter(runner: runner)
        let profile = AccountProfile(id: "claude-a", surface: .claudeCode, label: "Claude", configurationHome: "/tmp/claude-fixture", switchCapability: .isolatedProfile)
        let refresh = try adapter.refresh(profile: profile, previousSnapshot: previous)
        try expect(refresh.connected, "Claude auth status was not decoded")
        try expect(refresh.snapshot == previous, "Claude auth refresh should preserve the first-party snapshot")
        try expect(runner.lastSpec?.environment["CLAUDE_CONFIG_DIR"] == "/tmp/claude-fixture", "Claude isolated home was not used")
    }),
    ("Independent active account per surface", {
        let profiles = [
            AccountProfile(id: "codex-a", surface: .codexCLI, label: "A", configurationHome: "/tmp/a", switchCapability: .isolatedProfile),
            AccountProfile(id: "codex-b", surface: .codexCLI, label: "B", configurationHome: "/tmp/b", switchCapability: .isolatedProfile),
            AccountProfile(id: "claude-a", surface: .claudeCode, label: "C", configurationHome: "/tmp/c", switchCapability: .isolatedProfile)
        ]
        var state = PersistedState(profiles: profiles)
        try state.setActive(profileID: "codex-a")
        try state.setActive(profileID: "claude-a")
        try state.setActive(profileID: "codex-b")
        try expect(state.activeProfileID(for: .codexCLI) == "codex-b", "Codex active account is wrong")
        try expect(state.activeProfileID(for: .claudeCode) == "claude-a", "Claude active account should be independent")
    }),
    ("Unsupported switch fails closed", {
        var state = PersistedState(profiles: [AccountProfile(id: "cursor", surface: .cursor, label: "Cursor", switchCapability: .unsupported)])
        try expectThrows("Unsupported provider should not become active") { try state.setActive(profileID: "cursor") }
        try expect(state.activeProfileID(for: .cursor) == nil, "Cursor became active")
    }),
    ("Switch command construction", {
        let codex = AccountProfile(id: "codex", surface: .codexCLI, label: "Codex", configurationHome: "/tmp/codex profile", switchCapability: .isolatedProfile)
        let claude = AccountProfile(id: "claude", surface: .claudeCode, label: "Claude", configurationHome: "/tmp/claude", switchCapability: .isolatedProfile)
        let codexSpec = try Switching.command(for: codex, passthrough: ["--version"])
        let codexLogin = try Switching.loginCommand(for: codex)
        let claudeSpec = try Switching.loginCommand(for: claude)
        try expect(codexSpec.environment == ["CODEX_HOME": "/tmp/codex profile"], "Codex home is wrong")
        try expect(codexSpec.arguments == ["codex", "--version"], "Codex arguments are wrong")
        try expect(codexLogin.arguments == ["codex", "login"], "Codex login arguments are wrong")
        try expect(claudeSpec.environment == ["CLAUDE_CONFIG_DIR": "/tmp/claude"], "Claude home is wrong")
        try expect(claudeSpec.arguments == ["claude", "auth", "login"], "Claude login command is wrong")
        let displayed = try Switching.displayCommand(for: codex)
        try expect(displayed == "CODEX_HOME='/tmp/codex profile' codex", "Displayed shell command is unsafe")
    }),
    ("Shell quoting", {
        try expect(Switching.shellQuote("a'b") == "'a'\\''b'", "Apostrophe shell quoting is wrong")
    }),
    ("Bounded profile discovery", {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".codex"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("unrelated-private-data"), withIntermediateDirectories: true)
        let profiles = ProfileDiscovery(homeDirectory: root).defaults()
        try expect(Set(profiles.map(\.surface)) == Set([.codexCLI, .claudeCode]), "Discovery included an unexpected surface")
        try expect(!profiles.contains(where: { $0.configurationHome?.contains("unrelated") == true }), "Discovery escaped known config homes")
    }),
    ("Fake executable isolation", {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let executable = root.appendingPathComponent("fake-provider")
        try Data("#!/bin/sh\nprintf '%s|%s' \"$CODEX_HOME\" \"$1\"\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let isolated = root.appendingPathComponent("profile").path
        let result = try SystemProcessRunner().run(CommandSpec(executable: executable.path, arguments: ["status"], environment: ["CODEX_HOME": isolated]), standardInput: nil, timeout: 2)
        try expect(result.exitCode == 0, "Fake executable failed")
        try expect(result.standardOutput == "\(isolated)|status", "Fake executable did not receive isolated home")
    }),
    ("Redaction", {
        let input = "failed for person@private.example at /home/example/.codex with oauth-secretvalue123456"
        let output = Redactor.text(input, homeDirectory: "/home/example")
        try expect(!output.contains("person@private.example"), "Email was not redacted")
        try expect(!output.contains("/home/example"), "Home path was not redacted")
        try expect(!output.contains("secretvalue"), "Token was not redacted")
        try expect(output.count <= 240, "Redacted output is unbounded")
    }),
    ("Persistence bounds", {
        let profiles = (0..<40).map { index in
            AccountProfile(id: "profile-\(index)", surface: .codexCLI, label: "Profile \(index)", configurationHome: "/tmp/profile-\(index)", switchCapability: .isolatedProfile)
        }
        var snapshots: [QuotaSnapshot] = []
        for profile in profiles.prefix(4) {
            for index in 0..<20 {
                snapshots.append(QuotaSnapshot(profileID: profile.id, windows: [QuotaWindow(id: "w", label: "5h", usedPercent: Double(index), resetsAt: Date(timeIntervalSince1970: 2_000_000_000))], fetchedAt: Date(timeIntervalSince1970: Double(index)), source: .codexAppServer))
            }
            snapshots.append(QuotaSnapshot(profileID: profile.id, windows: [], fetchedAt: Date(), source: .syntheticPreview))
        }
        let bounded = MetadataStore.bounded(PersistedState(profiles: profiles, activeProfileBySurface: [ProviderSurface.codexCLI.rawValue: "profile-39"], snapshots: snapshots))
        try expect(bounded.profiles.count == MetadataStore.maximumProfiles, "Profile bound failed")
        try expect(bounded.activeProfileID(for: .codexCLI) == nil, "Invalid active profile was retained")
        try expect(!bounded.snapshots.contains(where: { $0.source == .syntheticPreview }), "Synthetic preview was persisted")
        try expect(bounded.snapshots.allSatisfy { snapshot in bounded.snapshots.filter { $0.profileID == snapshot.profileID }.count <= MetadataStore.maximumSnapshotsPerProfile }, "Per-profile snapshot bound failed")
    }),
    ("Metadata store round-trip", {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MetadataStore(fileURL: root.appendingPathComponent("state.json"))
        let state = PersistedState(profiles: [AccountProfile(id: "codex-a", surface: .codexCLI, label: "Sample", identity: "dev@sample.test", configurationHome: "/tmp/codex-a", switchCapability: .isolatedProfile, connected: true)])
        try store.save(state)
        let raw = try String(contentsOf: store.fileURL, encoding: .utf8)
        let loaded = try store.load()
        try expect(loaded == state, "Metadata did not round-trip")
        try expect(!raw.lowercased().contains("access_token") && !raw.contains("sk-"), "Credential-shaped data entered metadata")
    }),
    ("Reset formatting", {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let reset = now.addingTimeInterval(2 * 3600 + 26 * 60)
        try expect(QuotaFormatting.countdown(to: reset, now: now) == "resets in 2h 26m", "Countdown is wrong")
        try expect(QuotaFormatting.absoluteReset(reset, timeZone: TimeZone(secondsFromGMT: 0)!).contains("2027"), "Absolute reset is wrong")
        try expect(QuotaFormatting.compactAbsoluteReset(reset, timeZone: TimeZone(secondsFromGMT: 0)!).contains("Jan"), "Compact absolute reset is wrong")
    }),
    ("Weekly quota is the compact default", {
        let windows = [
            QuotaWindow(id: "primary", label: "5h", usedPercent: 20, resetsAt: Date()),
            QuotaWindow(id: "secondary", label: "7d", usedPercent: 40, resetsAt: Date())
        ]
        let snapshot = QuotaSnapshot(profileID: "x", windows: windows, fetchedAt: Date(), source: .codexAppServer)
        try expect(snapshot.displayWindows(showAll: false).map(\.label) == ["7d"], "Compact mode did not prefer the weekly window")
        try expect(snapshot.displayWindows(showAll: true) == windows, "Expanded mode did not preserve every quota window")
    }),
    ("Existing sessions are found so Connect can skip a login", {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("afp-sessions-\(UUID().uuidString)")
        let fm = FileManager.default
        // Two isolated Codex homes, only one of which holds a session.
        for name in [".codex", ".codex-work", ".codex-empty"] {
            try fm.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        try Data("{}".utf8).write(to: root.appendingPathComponent(".codex/auth.json"))
        try Data("{}".utf8).write(to: root.appendingPathComponent(".codex-work/auth.json"))
        let discovery = ProfileDiscovery(homeDirectory: root)

        let sessions = discovery.existingSessions(for: .codexCLI).map(\.lastPathComponent)
        try expect(sessions == [".codex", ".codex-work"], "Expected both signed-in homes, got \(sessions)")
        try expect(!sessions.contains(".codex-empty"), "A home with no credential was offered as a session")

        // The desktop app shares CODEX_HOME, so it sees the same live sessions.
        try expect(discovery.existingSessions(for: .codexMacApp).count == 2, "Codex desktop did not see the shared sessions")

        // The Claude keychain is not per-home, so it must not vouch for isolated homes.
        try fm.createDirectory(at: root.appendingPathComponent(".claude-lab"), withIntermediateDirectories: true)
        try expect(discovery.isSignedIn(surface: .claudeCode, home: root.appendingPathComponent(".claude-lab")) == false,
                   "An isolated Claude home claimed the keychain session")
        try? fm.removeItem(at: root)
    }),
    ("Discovery reports signed-in only when a credential exists", {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("afp-signin-\(UUID().uuidString)")
        let codex = root.appendingPathComponent(".codex")
        try FileManager.default.createDirectory(at: codex, withIntermediateDirectories: true)
        let discovery = ProfileDiscovery(homeDirectory: root)

        // A home that merely exists is not a signed-in account.
        try expect(discovery.isSignedIn(surface: .codexCLI, home: codex) == false, "An empty Codex home reported signed in")
        try expect(discovery.defaults().first(where: { $0.id == "codex-default" })?.connected == false, "Empty Codex home was marked connected")

        try Data("{}".utf8).write(to: codex.appendingPathComponent("auth.json"))
        try expect(discovery.isSignedIn(surface: .codexCLI, home: codex), "auth.json was not treated as a session")
        try expect(discovery.defaults().first(where: { $0.id == "codex-default" })?.connected == true, "Signed-in Codex home was not marked connected")

        // App-owned and unsupported surfaces never claim a session.
        try expect(discovery.isSignedIn(surface: .codexMacApp, home: codex) == false, "Codex macOS claimed a readable session")
        try expect(discovery.isSignedIn(surface: .cursor, home: codex) == false, "Cursor claimed a readable session")
        try? FileManager.default.removeItem(at: root)
    }),
    ("Removing a profile keeps credentials and reassigns active", {
        var state = PersistedState(
            profiles: [
                AccountProfile(id: "a", surface: .codexCLI, label: "A", configurationHome: "/tmp/a", switchCapability: .isolatedProfile, connected: true),
                AccountProfile(id: "b", surface: .codexCLI, label: "B", configurationHome: "/tmp/b", switchCapability: .isolatedProfile, connected: true)
            ],
            activeProfileBySurface: [ProviderSurface.codexCLI.rawValue: "a"],
            snapshots: [QuotaSnapshot(profileID: "a", windows: [], fetchedAt: Date(), source: .codexAppServer)]
        )
        state.removeProfile(id: "a")
        try expect(state.profiles.count == 1, "Profile was not removed")
        try expect(state.snapshots.isEmpty, "Snapshots for the removed profile survived")
        try expect(state.activeProfileID(for: .codexCLI) == "b", "Active did not fall back to the remaining profile")

        state.removeProfile(id: "b")
        try expect(state.activeProfileID(for: .codexCLI) == nil, "Active should be cleared when nothing is left")
        try expect(state.profiles.isEmpty, "Last profile was not removed")
    }),
    ("Popover stays on screen", {
        let screen = CGRect(x: 0, y: 0, width: 2056, height: 1329)
        // Anchored near the right edge, as a status item at x=1760 would leave it.
        let overflowing = CGRect(x: 1758, y: 600, width: 539, height: 648)
        let pulledBack = ScreenPlacement.constrainedOriginX(panel: overflowing, within: screen)
        try expect(pulledBack + 539 <= 2056 - 8 + 0.001, "Panel still runs off the right edge")
        try expect(pulledBack == 2056 - 8 - 539, "Panel did not hug the right edge")

        let offLeft = CGRect(x: -120, y: 600, width: 539, height: 648)
        try expect(ScreenPlacement.constrainedOriginX(panel: offLeft, within: screen) == 8, "Panel did not hug the left edge")

        let comfortable = CGRect(x: 900, y: 600, width: 539, height: 648)
        try expect(ScreenPlacement.constrainedOriginX(panel: comfortable, within: screen) == 900, "A panel already on screen was moved")

        let tooWide = CGRect(x: 400, y: 0, width: 4000, height: 648)
        try expect(ScreenPlacement.constrainedOriginX(panel: tooWide, within: screen) == 8, "An oversized panel did not pin to the leading edge")
    }),
    ("Freshness transitions", {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func snapshot(age: TimeInterval) -> QuotaSnapshot {
            QuotaSnapshot(profileID: "x", windows: [], fetchedAt: now.addingTimeInterval(-age), source: .codexAppServer)
        }
        try expect(QuotaFormatting.health(for: snapshot(age: 60), now: now) == .fresh, "Fresh state is wrong")
        try expect(QuotaFormatting.health(for: snapshot(age: 3600), now: now) == .stale, "Stale state is wrong")
        try expect(QuotaFormatting.health(for: snapshot(age: 86_400), now: now) == .offline, "Offline state is wrong")
    })
]

var failures = 0
for (name, test) in tests {
    do {
        try test()
        print("PASS \(name)")
    } catch {
        failures += 1
        print("FAIL \(name): \(error)")
    }
}
print("\n\(tests.count - failures)/\(tests.count) tests passed")
exit(failures == 0 ? 0 : 1)
