import Foundation
import AgentFannyPackCore

/// Named states the UI has to handle. Every one of these gets rendered and looked at, because
/// shipping a layout that was only ever seen with a full, healthy account list is how rows end
/// up claiming "Connected", "Needs login" and "Active" at the same time.
enum StateFixtures {
    static let names = ["empty", "one-connected", "no-quota", "needs-login", "mixed", "error"]

    static func state(_ name: String) -> PersistedState {
        let now = PreviewData.pinnedNow
        switch name {
        case "empty":
            return PersistedState()

        case "one-connected":
            let profile = codex(id: "c1", label: "Personal", identity: "dev@sample.test")
            return PersistedState(
                profiles: [profile],
                activeProfileBySurface: [ProviderSurface.codexCLI.rawValue: "c1"],
                snapshots: [snapshot(id: "c1", used: 42, now: now)]
            )

        case "no-quota":
            // Connected, but nothing has reported usage yet. This must not read as an error.
            let profile = codex(id: "c1", label: "Personal", identity: "dev@sample.test")
            return PersistedState(
                profiles: [profile],
                activeProfileBySurface: [ProviderSurface.codexCLI.rawValue: "c1"],
                snapshots: []
            )

        case "needs-login":
            var profile = codex(id: "c1", label: "Work", identity: nil)
            profile.connected = false
            return PersistedState(profiles: [profile], activeProfileBySurface: [:], snapshots: [])

        case "error":
            var profile = codex(id: "c1", label: "Broken", identity: "dev@sample.test")
            profile.lastError = "Sign-in expired. Reconnect to continue."
            profile.connected = false
            return PersistedState(profiles: [profile], activeProfileBySurface: [:], snapshots: [])

        default:
            return PreviewData.state(now: now)
        }
    }

    private static func codex(id: String, label: String, identity: String?) -> AccountProfile {
        AccountProfile(
            id: id,
            surface: .codexCLI,
            label: label,
            identity: identity,
            configurationHome: "/tmp/demo-\(id)",
            switchCapability: .isolatedProfile,
            connected: true
        )
    }

    private static func snapshot(id: String, used: Double, now: Date) -> QuotaSnapshot {
        QuotaSnapshot(
            profileID: id,
            windows: [QuotaWindow(id: "\(id)-w", label: "Weekly", usedPercent: used, resetsAt: PreviewData.pinnedWeeklyReset)],
            fetchedAt: now.addingTimeInterval(-94),
            source: .syntheticPreview
        )
    }
}
