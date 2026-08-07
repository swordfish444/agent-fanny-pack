import AppKit
import SwiftUI
import AgentFannyPackCore

struct PopoverView: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            PouchHeader(isRefreshing: model.isRefreshing)
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(model.groupedProfiles, id: \.0.id) { surface, profiles in
                        ProviderSection(
                            surface: surface,
                            profiles: profiles,
                            model: model
                        )
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            footer
        }
        .frame(width: 440, height: 690)
        .background(PouchPalette.background(for: colorScheme))
        .alert(item: $model.pendingSwitch) { profile in
            Alert(
                title: Text(alertTitle(for: profile)),
                message: Text(switchMessage(for: profile)),
                primaryButton: .default(Text(actionTitle(for: profile)), action: model.confirmSwitch),
                secondaryButton: .cancel()
            )
        }
        .overlay(alignment: .bottom) {
            if let notice = model.notice {
                NoticeToast(text: notice) { model.notice = nil }
                    .padding(.bottom, 54)
                    .transition(reduceMotion ? .identity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Local metadata · no transcripts · no telemetry")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Menu {
                Toggle(
                    "Show 5-hour and other quota windows",
                    isOn: Binding(
                        get: { model.showAllQuotaWindows },
                        set: model.setShowAllQuotaWindows
                    )
                )
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .frame(width: 20, height: 20)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Quota display settings")
            .accessibilityLabel("Quota display settings")
            Button(action: model.refresh) {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.borderless)
            .disabled(model.isRefreshing)
            .keyboardShortcut("r", modifiers: .command)
            .help("Refresh first-party account sources")
            .accessibilityLabel("Refresh accounts")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(PouchPalette.footer(for: colorScheme))
    }

    private func switchMessage(for profile: AccountProfile) -> String {
        if profile.switchCapability == .guidedOnly {
            return "Agent Fanny Pack cannot safely replace the app's credentials. It will open Codex so you can sign out and in yourself; the switch stays unconfirmed until you refresh."
        }
        if !profile.connected {
            return "This starts the provider's official sign-in in this isolated profile. It does not replace credentials or interrupt any running session."
        }
        return "Only the Agent Fanny Pack launcher changes. Existing Codex or Claude sessions keep their current account and credentials."
    }

    private func alertTitle(for profile: AccountProfile) -> String {
        if profile.switchCapability == .guidedOnly { return "Open the guided switch?" }
        if !profile.connected { return "Connect \(profile.label)?" }
        return "Zip over to \(profile.label)?"
    }

    private func actionTitle(for profile: AccountProfile) -> String {
        if profile.switchCapability == .guidedOnly { return "Open Codex" }
        return profile.connected ? "Switch launcher" : "Connect"
    }
}

private struct PouchHeader: View {
    let isRefreshing: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                PouchMark()
                    .frame(width: 46, height: 38)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("AGENT FANNY PACK")
                        .font(.system(size: 19, weight: .black, design: .rounded))
                        .tracking(0.8)
                    Text("what’s in the pouch?")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Refreshing accounts")
                } else {
                    Text("PACKED")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(PouchPalette.accent.opacity(0.20), in: Capsule())
                        .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal, 17)
            .padding(.top, 14)
            .padding(.bottom, 11)

            ZipperLine()
                .frame(height: 16)
                .accessibilityHidden(true)
        }
        .background(PouchPalette.header(for: colorScheme))
    }
}

private struct ZipperLine: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.18))
                    .frame(height: 3)
                    .padding(.horizontal, 12)
                HStack(spacing: 5) {
                    ForEach(0..<29, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.primary.opacity(0.38))
                            .frame(width: 8, height: 5)
                    }
                }
                .padding(.leading, 16)
                RoundedRectangle(cornerRadius: 3)
                    .fill(PouchPalette.accent)
                    .frame(width: 24, height: 11)
                    .overlay(
                        Capsule().stroke(Color.white.opacity(0.7), lineWidth: 1).padding(3)
                    )
                    .offset(x: geometry.size.width * 0.64)
            }
        }
    }
}

private struct PouchMark: View {
    var body: some View {
        ZStack {
            Capsule()
                .fill(PouchPalette.strap)
                .frame(height: 10)
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(PouchPalette.accent)
                .frame(width: 39, height: 30)
                .overlay(alignment: .top) {
                    Capsule().fill(Color.white.opacity(0.72)).frame(width: 25, height: 2).padding(.top, 7)
                }
            Circle()
                .fill(PouchPalette.ink)
                .frame(width: 5, height: 5)
                .offset(x: 13, y: -7)
        }
    }
}

private struct ProviderSection: View {
    let surface: ProviderSurface
    let profiles: [AccountProfile]
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                ProviderBadge(surface: surface)
                Text(surface.displayName)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Spacer()
                Text(countLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            ForEach(profiles) { profile in
                AccountCard(
                    profile: profile,
                    snapshot: model.snapshot(for: profile),
                    isActive: model.isActive(profile),
                    showAllQuotaWindows: model.showAllQuotaWindows,
                    switchAction: { model.requestSwitch(profile) }
                )
            }
        }
    }

    private var countLabel: String {
        let connected = profiles.filter(\.connected).count
        if surface == .cursor { return "DEFERRED" }
        return connected == 1 ? "1 CONNECTED" : "\(connected) CONNECTED"
    }
}

private struct ProviderBadge: View {
    let surface: ProviderSurface
    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(color)
            .frame(width: 23, height: 23)
            .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 7))
            .accessibilityHidden(true)
    }

    private var icon: String {
        switch surface {
        case .codexCLI: return "terminal.fill"
        case .codexMacApp: return "macwindow"
        case .claudeCode: return "sparkles"
        case .cursor: return "cursorarrow.rays"
        }
    }

    private var color: Color {
        switch surface {
        case .codexCLI: return Color(red: 0.08, green: 0.52, blue: 0.42)
        case .codexMacApp: return Color(red: 0.25, green: 0.42, blue: 0.78)
        case .claudeCode: return Color(red: 0.72, green: 0.34, blue: 0.19)
        case .cursor: return Color(red: 0.45, green: 0.43, blue: 0.52)
        }
    }
}

private struct AccountCard: View {
    let profile: AccountProfile
    let snapshot: QuotaSnapshot?
    let isActive: Bool
    let showAllQuotaWindows: Bool
    let switchAction: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.label)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    Text(profile.identity ?? identityFallback)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    if isActive { AnimatedActiveBadge() }
                    if shouldShowAction { actionButton }
                }
            }

            if let snapshot {
                let windows = snapshot.displayWindows(showAll: showAllQuotaWindows)
                if windows.isEmpty {
                    compactUnavailable
                } else {
                    ForEach(Array(windows.enumerated()), id: \.element.id) { index, window in
                        CompactQuotaRow(
                            window: window,
                            health: index == 0 ? QuotaFormatting.health(for: snapshot) : nil,
                            age: index == 0 ? QuotaFormatting.age(snapshot.fetchedAt) : nil
                        )
                    }
                }
            } else {
                compactUnavailable
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(PouchPalette.card(for: colorScheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.15 : 0.08), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private var shouldShowAction: Bool {
        profile.switchCapability == .unsupported ||
            profile.switchCapability == .guidedOnly ||
            !profile.connected ||
            !isActive
    }

    @ViewBuilder private var actionButton: some View {
        if profile.switchCapability == .unsupported {
            StatusPill(text: "ROADMAP", icon: "road.lanes", tint: .secondary)
        } else {
            Button(actionLabel, action: switchAction)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel(actionAccessibilityLabel)
        }
    }

    private var compactUnavailable: some View {
        HStack(spacing: 6) {
            HealthDot(health: profile.switchCapability == .unsupported ? .unsupported : .unavailable)
            Text(profile.lastError ?? "No authoritative quota snapshot yet.")
                .lineLimit(1)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .help(profile.lastError ?? "No authoritative quota snapshot yet.")
    }

    private var actionLabel: String {
        if profile.switchCapability == .guidedOnly { return "Guide" }
        return profile.connected ? "Switch" : "Connect"
    }

    private var actionAccessibilityLabel: String {
        if profile.switchCapability == .guidedOnly { return "Open guided switch for \(profile.label)" }
        if !profile.connected { return "Connect \(profile.label)" }
        return "Switch launcher to \(profile.label)"
    }

    private var identityFallback: String {
        profile.connected ? "Connected account" : "Not connected"
    }
}

private struct CompactQuotaRow: View {
    let window: QuotaWindow
    let health: SourceHealth?
    let age: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(window.label)
                    .font(.caption.weight(.semibold))
                Text(QuotaFormatting.percentRemaining(window.remainingPercent))
                    .font(.caption2.weight(.bold))
                Spacer(minLength: 6)
                if let health, let age {
                    HealthDot(health: health)
                    Text("· \(age)")
                        .foregroundStyle(.secondary)
                }
                Text("\(QuotaFormatting.countdown(to: window.resetsAt)) · \(QuotaFormatting.compactAbsoluteReset(window.resetsAt))")
                    .foregroundStyle(.secondary)
            }
            .font(.caption2)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.10))
                    Capsule()
                        .fill(barColor)
                        .frame(width: max(4, geometry.size.width * window.remainingPercent / 100))
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(window.label) quota")
        .accessibilityValue("\(QuotaFormatting.percentRemaining(window.remainingPercent)); \(QuotaFormatting.countdown(to: window.resetsAt)); \(QuotaFormatting.absoluteReset(window.resetsAt))")
    }

    private var barColor: Color {
        if window.remainingPercent < 20 { return PouchPalette.danger }
        if window.remainingPercent < 40 { return PouchPalette.warning }
        return PouchPalette.success
    }
}

private struct AnimatedActiveBadge: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false
    private let pulseTimer = Timer.publish(every: 5, tolerance: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 5) {
            ZStack {
                Circle()
                    .stroke(PouchPalette.success.opacity(0.42), lineWidth: 1.5)
                    .frame(width: 9, height: 9)
                    .scaleEffect(pulsing ? 1.7 : 1)
                    .opacity(pulsing ? 0 : 0.8)
                Circle()
                    .fill(PouchPalette.success)
                    .frame(width: 7, height: 7)
            }
            Text("ACTIVE")
                .font(.system(size: 9, weight: .bold, design: .rounded))
        }
        .foregroundStyle(PouchPalette.success)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(PouchPalette.success.opacity(0.13), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Active account")
        .onAppear(perform: triggerPulse)
        .onReceive(pulseTimer) { _ in triggerPulse() }
        .onChange(of: reduceMotion) { reduced in
            if reduced { pulsing = false }
        }
    }

    private func triggerPulse() {
        guard !reduceMotion, !pulsing else { return }
        withAnimation(.easeOut(duration: 0.65)) { pulsing = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            pulsing = false
        }
    }
}

private struct HealthDot: View {
    let health: SourceHealth
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(health.label)
        }
        .foregroundStyle(color)
        .accessibilityElement(children: .combine)
    }
    private var icon: String {
        switch health {
        case .fresh: return "checkmark.circle.fill"
        case .stale: return "clock.badge.exclamationmark"
        case .offline: return "wifi.slash"
        case .error: return "exclamationmark.triangle.fill"
        case .unavailable: return "questionmark.circle"
        case .unsupported: return "nosign"
        }
    }
    private var color: Color {
        switch health {
        case .fresh: return PouchPalette.success
        case .stale: return PouchPalette.warning
        case .offline, .error: return PouchPalette.danger
        case .unavailable, .unsupported: return .secondary
        }
    }
}

private struct StatusPill: View {
    let text: String
    let icon: String
    let tint: Color
    var body: some View {
        Label(text, systemImage: icon)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(tint.opacity(0.13), in: Capsule())
            .accessibilityElement(children: .combine)
    }
}

private struct NoticeToast: View {
    let text: String
    let dismiss: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(PouchPalette.success)
            Text(text)
                .font(.caption.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(action: dismiss) { Image(systemName: "xmark") }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss notice")
        }
        .padding(10)
        .frame(maxWidth: 400)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.16), radius: 12, y: 4)
    }
}

enum PouchPalette {
    static let accent = Color(red: 0.91, green: 0.36, blue: 0.17)
    static let strap = Color(red: 0.19, green: 0.25, blue: 0.27)
    static let ink = Color(red: 0.10, green: 0.13, blue: 0.14)
    static let success = dynamicColor(
        light: NSColor(calibratedRed: 0.05, green: 0.48, blue: 0.34, alpha: 1),
        dark: NSColor(calibratedRed: 0.24, green: 0.84, blue: 0.62, alpha: 1)
    )
    static let warning = dynamicColor(
        light: NSColor(calibratedRed: 0.72, green: 0.40, blue: 0.02, alpha: 1),
        dark: NSColor(calibratedRed: 1.00, green: 0.68, blue: 0.22, alpha: 1)
    )
    static let danger = dynamicColor(
        light: NSColor(calibratedRed: 0.72, green: 0.16, blue: 0.18, alpha: 1),
        dark: NSColor(calibratedRed: 1.00, green: 0.45, blue: 0.48, alpha: 1)
    )

    static func background(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.09, green: 0.10, blue: 0.11) : Color(red: 0.96, green: 0.94, blue: 0.89)
    }
    static func header(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.14, green: 0.15, blue: 0.16) : Color(red: 0.91, green: 0.84, blue: 0.70)
    }
    static func footer(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.12, green: 0.13, blue: 0.14) : Color(red: 0.91, green: 0.89, blue: 0.84)
    }
    static func card(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.15, green: 0.16, blue: 0.17) : Color.white.opacity(0.88)
    }

    private static func dynamicColor(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}
