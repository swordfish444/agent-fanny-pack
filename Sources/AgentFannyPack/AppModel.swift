import AppKit
import Foundation
import AgentFannyPackCore

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var state: PersistedState
    @Published var pendingSwitch: AccountProfile?
    @Published var isRefreshing = false
    @Published var notice: String?
    @Published var showAllQuotaWindows: Bool

    let isPreview: Bool
    private let store: MetadataStore
    private var loginProcesses: [String: Process] = [:]

    init(preview: Bool = false, store: MetadataStore = MetadataStore()) {
        self.isPreview = preview
        self.store = store
        self.showAllQuotaWindows = preview ? false : UserDefaults.standard.bool(forKey: "showAllQuotaWindows")
        if preview {
            self.state = PreviewData.state(now: PreviewData.pinnedNow)
        } else {
            var loaded = (try? store.load()) ?? PersistedState()
            Self.mergeDefaultProfiles(into: &loaded)
            self.state = loaded
            try? store.save(loaded)
        }
    }

    /// Everything time-relative renders against this instant. Synthetic previews pin it so
    /// documentation screenshots and the design-QA comparison are reproducible.
    var referenceDate: Date { isPreview ? PreviewData.pinnedNow : Date() }

    var groupedProfiles: [(ProviderSurface, [AccountProfile])] {
        ProviderSurface.allCases.map { surface in
            (surface, state.profiles.filter { $0.surface == surface })
        }
    }

    /// Auto-discovered placeholders that exist only so a surface has something to point at.
    /// They carry no account, so showing one signed-out is just noise where an Add belongs.
    private static let discoveredDefaultIDs: Set<String> = [
        "codex-default", "claude-default", "codex-macos-guided", "cursor-deferred"
    ]

    func profiles(for surface: ProviderSurface, filter: AccountFilter) -> [AccountProfile] {
        state.profiles.filter { profile in
            guard profile.surface == surface, matches(profile, filter: filter) else { return false }
            // A profile the user created stays visible when signed out so it can be
            // reconnected; an untouched discovered default does not.
            if !profile.connected && Self.discoveredDefaultIDs.contains(profile.id) { return false }
            return true
        }
    }

    /// Only the isolated-profile surfaces can take a new account: the Codex macOS app owns
    /// its own session, and Cursor has no supported multi-profile contract.
    func canAddProfile(to surface: ProviderSurface) -> Bool {
        surface == .codexCLI || surface == .claudeCode
    }

    /// Creates an isolated profile and hands straight off to the provider's own login.
    /// Agent Fanny Pack never sees a credential; it only owns the directory pointer.
    func addProfile(to surface: ProviderSurface) {
        guard canAddProfile(to: surface) else { return }
        guard !isPreview else {
            notice = "Synthetic preview: no account is added."
            return
        }
        let existing = state.profiles.filter { $0.surface == surface }.count
        let slug = surface == .codexCLI ? "codex" : "claude"
        var index = existing + 1
        var id = "\(slug)-profile-\(index)"
        while state.profiles.contains(where: { $0.id == id }) {
            index += 1
            id = "\(slug)-profile-\(index)"
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".\(slug)-afp-\(index)")
            .path
        let profile = AccountProfile(
            id: id,
            surface: surface,
            label: "\(surface.displayName) \(index)",
            configurationHome: home,
            switchCapability: .isolatedProfile
        )
        do {
            state.profiles.append(profile)
            if state.activeProfileID(for: surface) == nil { try state.setActive(profileID: id) }
            try store.save(state)
            beginConnection(for: profile)
        } catch {
            notice = Redactor.text(error.localizedDescription)
        }
    }

    func matches(_ profile: AccountProfile, filter: AccountFilter) -> Bool {
        switch filter {
        case .all:
            return true
        case .active:
            return isActive(profile)
        case .needsAttention:
            return !profile.connected
                || profile.switchCapability == .unsupported
                || profile.switchCapability == .guidedOnly
                || QuotaFormatting.health(for: snapshot(for: profile), now: referenceDate) != .fresh
        }
    }

    var connectedAccountCount: Int {
        state.profiles.filter(\.connected).count
    }

    var activeProviderCount: Int {
        ProviderSurface.allCases.filter { surface in
            guard let id = state.activeProfileID(for: surface) else { return false }
            return state.profiles.contains { $0.id == id && $0.connected }
        }.count
    }

    var providerCount: Int { ProviderSurface.allCases.count }

    /// The soonest reset across every window the app currently holds.
    var nextReset: Date? {
        state.snapshots
            .flatMap { $0.displayWindows(showAll: showAllQuotaWindows) }
            .map(\.resetsAt)
            .filter { $0 > referenceDate }
            .min()
    }

    var lastUpdated: Date? {
        state.snapshots.map(\.fetchedAt).max()
    }

    /// Average remaining percentage across a surface's primary display window.
    func averageRemaining(for surface: ProviderSurface) -> Double? {
        let values = state.profiles
            .filter { $0.surface == surface && $0.connected }
            .compactMap { snapshot(for: $0)?.displayWindows(showAll: false).first?.remainingPercent }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    func launchActiveProfile() {
        guard let surface = ProviderSurface.allCases.first(where: { surface in
            guard let id = state.activeProfileID(for: surface),
                  let profile = state.profiles.first(where: { $0.id == id }) else { return false }
            return profile.switchCapability == .isolatedProfile && profile.connected
        }), let id = state.activeProfileID(for: surface),
           let profile = state.profiles.first(where: { $0.id == id }) else {
            notice = "No launchable active profile. Connect a Codex CLI or Claude Code account first."
            return
        }
        guard !isPreview else {
            notice = "Synthetic preview: no session is launched."
            return
        }
        do {
            let spec = try Switching.command(for: profile, passthrough: [])
            let process = Process()
            process.executableURL = URL(fileURLWithPath: spec.executable)
            process.arguments = spec.arguments
            process.environment = ProcessInfo.processInfo.environment.merging(spec.environment) { _, new in new }
            try process.run()
            notice = "Launched \(profile.label). Running sessions were not touched."
        } catch {
            notice = Redactor.text(error.localizedDescription)
        }
    }

    func isActive(_ profile: AccountProfile) -> Bool {
        state.activeProfileID(for: profile.surface) == profile.id
    }

    func snapshot(for profile: AccountProfile) -> QuotaSnapshot? {
        state.latestSnapshot(for: profile.id)
    }

    func requestSwitch(_ profile: AccountProfile) {
        pendingSwitch = profile
    }

    func setShowAllQuotaWindows(_ value: Bool) {
        showAllQuotaWindows = value
        if !isPreview { UserDefaults.standard.set(value, forKey: "showAllQuotaWindows") }
    }

    func confirmSwitch() {
        guard let profile = pendingSwitch else { return }
        defer { pendingSwitch = nil }
        switch profile.switchCapability {
        case .isolatedProfile:
            if !profile.connected {
                beginConnection(for: profile)
                return
            }
            do {
                try state.setActive(profileID: profile.id)
                if !isPreview { try store.save(state) }
                notice = "Launcher packed for \(profile.label). Running sessions were not touched."
            } catch {
                notice = error.localizedDescription
            }
        case .guidedOnly:
            let configuration = NSWorkspace.OpenConfiguration()
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") {
                NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in }
            }
            notice = "Open Codex, sign out and back in, then refresh here. Agent Fanny Pack will not claim a switch without app-owned readback."
        case .unsupported:
            notice = "That zipper is closed: this provider has no supported safe switch contract yet."
        }
    }

    private func beginConnection(for profile: AccountProfile) {
        guard loginProcesses[profile.id] == nil else {
            notice = "A sign-in is already open for \(profile.label)."
            return
        }
        do {
            let spec = try Switching.loginCommand(for: profile)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: spec.executable)
            process.arguments = spec.arguments
            process.environment = ProcessInfo.processInfo.environment.merging(spec.environment) { _, new in new }
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { [weak self] finished in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.loginProcesses[profile.id] = nil
                    if finished.terminationStatus == 0 {
                        self.notice = "Sign-in finished for \(profile.label). Refreshing its account state."
                        self.refresh()
                    } else {
                        self.notice = "Sign-in did not finish. Your existing sessions were not changed."
                    }
                }
            }
            try process.run()
            loginProcesses[profile.id] = process
            notice = "Opening the provider's sign-in for \(profile.label) in its isolated profile."
        } catch {
            notice = Redactor.text(error.localizedDescription)
        }
    }

    func refresh() {
        guard !isRefreshing else { return }
        if isPreview {
            notice = "Synthetic preview refreshed — no accounts or networks touched."
            return
        }

        isRefreshing = true
        let profiles = state.profiles
        let previous = state.snapshots
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var refreshes: [(String, Result<ProviderRefresh, Error>)] = []
            for profile in profiles {
                let old = previous
                    .filter { $0.profileID == profile.id }
                    .max(by: { $0.fetchedAt < $1.fetchedAt })
                let adapter: ProviderRefreshing
                switch profile.surface {
                case .codexCLI: adapter = CodexCLIAdapter()
                case .codexMacApp: adapter = GuidedCodexMacAdapter()
                case .claudeCode: adapter = ClaudeCodeAdapter()
                case .cursor: adapter = CursorDeferredAdapter()
                }
                refreshes.append((profile.id, Result { try adapter.refresh(profile: profile, previousSnapshot: old) }))
            }
            DispatchQueue.main.async {
                guard let self else { return }
                for (profileID, result) in refreshes {
                    guard let index = self.state.profiles.firstIndex(where: { $0.id == profileID }) else { continue }
                    switch result {
                    case .success(let refresh):
                        self.state.profiles[index].identity = refresh.identity
                        self.state.profiles[index].connected = refresh.connected
                        self.state.profiles[index].lastError = refresh.detail
                        if let snapshot = refresh.snapshot,
                           self.state.latestSnapshot(for: profileID)?.id != snapshot.id {
                            self.state.snapshots.append(snapshot)
                        }
                    case .failure(let error):
                        self.state.profiles[index].lastError = Redactor.text(error.localizedDescription)
                    }
                }
                self.state = MetadataStore.bounded(self.state)
                try? self.store.save(self.state)
                self.isRefreshing = false
            }
        }
    }

    private static func mergeDefaultProfiles(into state: inout PersistedState) {
        for profile in ProfileDiscovery().defaults() where !state.profiles.contains(where: { $0.id == profile.id }) {
            state.profiles.append(profile)
        }
        if !state.profiles.contains(where: { $0.surface == .codexMacApp }) {
            state.profiles.append(AccountProfile(
                id: "codex-macos-guided",
                surface: .codexMacApp,
                label: "Current app session",
                switchCapability: .guidedOnly
            ))
        }
        if !state.profiles.contains(where: { $0.surface == .cursor }) {
            state.profiles.append(AccountProfile(
                id: "cursor-deferred",
                surface: .cursor,
                label: "Cursor integration",
                switchCapability: .unsupported,
                lastError: "Deferred until Cursor exposes a supported personal quota and isolated-profile contract."
            ))
        }
        for surface in ProviderSurface.allCases {
            let candidates = state.profiles.filter { $0.surface == surface && $0.switchCapability != .unsupported }
            if state.activeProfileID(for: surface) == nil, let first = candidates.first {
                state.activeProfileBySurface[surface.rawValue] = first.id
            }
        }
    }
}

enum PreviewData {
    /// Synthetic previews and the design-QA render must be byte-identical between runs,
    /// so the fixture is pinned to a fixed instant rather than the wall clock.
    static let pinnedNow: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 10
        components.hour = 23
        components.minute = 6
        return Calendar.current.date(from: components) ?? Date(timeIntervalSince1970: 1_786_000_000)
    }()

    /// The weekly window resets on a wall-clock boundary, which is what produces the
    /// "3d 6h 54m · Aug 14, 6:00 AM" pairing in the approved design.
    static let pinnedWeeklyReset: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 14
        components.hour = 6
        components.minute = 0
        return Calendar.current.date(from: components) ?? pinnedNow.addingTimeInterval(3 * 86_400)
    }()

    static func state(now: Date) -> PersistedState {
        let profiles = [
            AccountProfile(id: "codex-weekend", surface: .codexCLI, label: "Weekend Build", identity: "dev@sample.test", configurationHome: "/tmp/demo-codex-a", switchCapability: .isolatedProfile, connected: true),
            AccountProfile(id: "codex-studio", surface: .codexCLI, label: "Studio Bench", identity: "studio@sample.test", configurationHome: "/tmp/demo-codex-b", switchCapability: .isolatedProfile, connected: true),
            AccountProfile(id: "codex-app", surface: .codexMacApp, label: "Desktop Session", identity: "maker@sample.test", switchCapability: .guidedOnly, connected: true, lastError: "App-owned session · guided sign-out/sign-in only."),
            AccountProfile(id: "claude-side", surface: .claudeCode, label: "Side Project", identity: "builder@sample.test", configurationHome: "/tmp/demo-claude-a", switchCapability: .isolatedProfile, connected: true),
            AccountProfile(id: "claude-lab", surface: .claudeCode, label: "Research Lab", identity: "lab@sample.test", configurationHome: "/tmp/demo-claude-b", switchCapability: .isolatedProfile, connected: true),
            AccountProfile(id: "cursor-deferred", surface: .cursor, label: "Personal Workspace", identity: "me@sample.test", switchCapability: .unsupported, lastError: "Deferred — safe personal quota and profile switching are not documented."),
        ]
        let values: [(String, QuotaSource, Double, Double?)] = [
            ("codex-weekend", .codexAppServer, 26, 42),
            ("codex-studio", .codexAppServer, 72, 81),
            ("claude-side", .claudeStatusLine, 53, 68),
            ("claude-lab", .claudeStatusLine, 18, 31),
        ]
        let snapshots = values.map { profileID, source, primary, secondary in
            QuotaSnapshot(
                profileID: profileID,
                windows: [
                    QuotaWindow(id: "\(profileID)-primary", label: source == .claudeStatusLine ? "5h" : "Session", usedPercent: primary, resetsAt: now.addingTimeInterval(2 * 3600 + 26 * 60)),
                    QuotaWindow(id: "\(profileID)-secondary", label: source == .claudeStatusLine ? "7d" : "Weekly", usedPercent: secondary ?? 0, resetsAt: pinnedWeeklyReset),
                ],
                fetchedAt: now.addingTimeInterval(-94),
                source: .syntheticPreview
            )
        }
        return PersistedState(
            profiles: profiles,
            activeProfileBySurface: [
                ProviderSurface.codexCLI.rawValue: "codex-weekend",
                ProviderSurface.codexMacApp.rawValue: "codex-app",
                ProviderSurface.claudeCode.rawValue: "claude-side"
            ],
            snapshots: snapshots
        )
    }
}
