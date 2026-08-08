import AppKit
import SwiftUI
import AgentFannyPackCore

public enum AccountFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case active = "Active"
    case needsAttention = "Needs attention"
    public var id: String { rawValue }
}

/// Every tunable in the approved design lives here so visual QA can be closed
/// by adjusting numbers rather than restructuring the view tree.
enum Metrics {
    // Spec proportions, in points. Row columns sum exactly to the panel's inner width
    // (580 - 2*14 = 552) so a column can never silently overflow the card.
    static let width: CGFloat = 580
    static let height: CGFloat = 900
    static let gutter: CGFloat = 14
    static let cardRadius: CGFloat = 13
    static let rowRadius: CGFloat = 10
    static let sectionSpacing: CGFloat = 12

    static let colSelector: CGFloat = 36
    static let colName: CGFloat = 140
    static let colQuota: CGFloat = 74
    static let colReset: CGFloat = 100
    static let colHealth: CGFloat = 70
    static let colAction: CGFloat = 100
    static let colOverflow: CGFloat = 32
    static let rowTrailing: CGFloat = 0

    static let rowHeight: CGFloat = 88
    static let addRowHeight: CGFloat = 60
    static let sectionHeaderHeight: CGFloat = 70
    static let summaryHeight: CGFloat = 120
    static let footerHeight: CGFloat = 72

    static let buttonWidth: CGFloat = 100
    static let buttonHeight: CGFloat = 43
    static let filterButton: CGFloat = 53
    static let tabHeight: CGFloat = 46

    static let logoSize: CGFloat = 56
    static let titleSize: CGFloat = 28
    static let headerTop: CGFloat = 22
    static let headerBottom: CGFloat = 18
    static let blockGap: CGFloat = 16
}

struct PopoverView: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var filter: AccountFilter = .all

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar(model: model)
            SummaryCard(model: model)
                .padding(.horizontal, Metrics.gutter)
                .padding(.bottom, Metrics.blockGap)
            FilterBar(filter: $filter)
                .padding(.horizontal, Metrics.gutter)
                .padding(.bottom, Metrics.blockGap)
            ScrollView {
                VStack(spacing: Metrics.sectionSpacing) {
                    // Every supported provider is always listed, with or without accounts.
                    // The section is how you discover the provider exists and how you add
                    // your first account to it, so an empty one still has to be on screen.
                    ForEach(ProviderSurface.allCases, id: \.id) { surface in
                        ProviderSection(
                            surface: surface,
                            profiles: model.profiles(for: surface, filter: filter),
                            model: model
                        )
                    }
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.bottom, Metrics.blockGap)
            }
            FooterBar(model: model)
        }
        .frame(width: Metrics.width, height: Metrics.height)
        .background(Palette.canvas(colorScheme))
        .alert(item: $model.pendingPrompt) { prompt in
            switch prompt {
            case .switchProfile(let profile):
                return Alert(
                    title: Text(alertTitle(for: profile)),
                    message: Text(switchMessage(for: profile)),
                    primaryButton: .default(Text(actionTitle(for: profile)), action: model.confirmSwitch),
                    secondaryButton: .cancel()
                )
            case .removeProfile(let profile):
                return Alert(
                    title: Text("Remove \(profile.label)?"),
                    message: Text(model.deleteMessage(for: profile)),
                    primaryButton: .destructive(Text("Remove"), action: model.confirmDelete),
                    secondaryButton: .cancel()
                )
            }
        }
        .overlay(alignment: .bottom) {
            if let notice = model.notice {
                NoticeToast(text: notice) { model.notice = nil }
                    .padding(.bottom, 54)
                    .transition(reduceMotion ? .identity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
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
        return "Switch to \(profile.label)?"
    }

    private func actionTitle(for profile: AccountProfile) -> String {
        if profile.switchCapability == .guidedOnly { return "Open Codex" }
        return profile.connected ? "Switch launcher" : "Connect"
    }
}

// MARK: - Header

private struct HeaderBar: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 14) {
            PouchMark()
                .frame(width: Metrics.logoSize, height: Metrics.logoSize)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("AGENT FANNY PACK")
                    .font(.system(size: Metrics.titleSize, weight: .bold))
                    .tracking(0.3)
                    .foregroundStyle(Palette.title)
                Text("All your agent accounts. Always ready.")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Palette.subtitle)
            }
            Spacer(minLength: 6)
            Menu {
                Toggle(
                    "Show 5-hour and other quota windows",
                    isOn: Binding(get: { model.showAllQuotaWindows }, set: model.setShowAllQuotaWindows)
                )
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Palette.glyph)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Settings")
            Image(systemName: "chevron.down")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.glyph)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Metrics.gutter + 2)
        .padding(.top, Metrics.headerTop)
        .padding(.bottom, Metrics.headerBottom)
    }
}

/// The pouch mark: a rounded bag with a strap arch, side gussets, and a zipper pull.
private struct PouchMark: View {
    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            ZStack {
                // Side gussets peeking out behind the body.
                HStack(spacing: size * 0.44) {
                    Circle().fill(Palette.pouchDark).frame(width: size * 0.30, height: size * 0.40)
                    Circle().fill(Palette.pouchDark).frame(width: size * 0.30, height: size * 0.40)
                }
                .offset(y: size * 0.06)
                // Strap arch over the top.
                RoundedRectangle(cornerRadius: size * 0.10, style: .continuous)
                    .stroke(Palette.pouchStrap, lineWidth: size * 0.075)
                    .frame(width: size * 0.60, height: size * 0.42)
                    .offset(y: -size * 0.20)
                // Main body.
                RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Palette.pouchLight, Palette.pouchBody],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size * 0.80, height: size * 0.62)
                    .offset(y: size * 0.10)
                // Zipper track and pull.
                Capsule()
                    .fill(Palette.pouchZip)
                    .frame(width: size * 0.42, height: size * 0.045)
                    .offset(x: -size * 0.04, y: -size * 0.02)
                Circle()
                    .fill(Palette.pouchDark)
                    .frame(width: size * 0.10, height: size * 0.10)
                    .offset(x: size * 0.20, y: -size * 0.02)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

// MARK: - Summary

private struct SummaryCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            SummaryCell(
                dot: Palette.good,
                title: "Connected accounts",
                value: "\(model.connectedAccountCount)"
            )
            Divider().frame(height: 72).overlay(Palette.hairline)
            SummaryCell(
                dot: Palette.good,
                title: "Active providers",
                value: "\(model.activeProviderCount)",
                suffix: " / \(model.providerCount)"
            )
            Divider().frame(height: 72).overlay(Palette.hairline)
            SummaryCell(
                icon: "clock",
                title: "Next reset",
                value: model.nextReset.map {
                    QuotaFormatting.compactCountdown(to: $0, now: model.referenceDate, includeMinutes: true)
                } ?? "—",
                caption: model.nextReset.map { QuotaFormatting.compactAbsoluteReset($0) }
            )
        }
        .frame(height: Metrics.summaryHeight)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .stroke(Palette.hairline, lineWidth: 1)
        }
    }
}

private struct SummaryCell: View {
    var dot: Color?
    var icon: String?
    let title: String
    let value: String
    var suffix: String?
    var caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let dot {
                    Circle().fill(dot).frame(width: 6, height: 6)
                } else if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 10.5, weight: .regular))
                        .foregroundStyle(Palette.subtitle)
                }
                Text(title)
                    .font(.system(size: 13))
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(Palette.subtitle)
            }
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(value)
                    .font(.system(size: caption == nil ? 34 : 22, weight: .bold))
                    .foregroundStyle(Palette.title)
                if let suffix {
                    Text(suffix)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Palette.subtitle)
                }
            }
            if let caption {
                Text(caption)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.subtitle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Filter bar

private struct FilterBar: View {
    @Binding var filter: AccountFilter

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 0) {
                ForEach(AccountFilter.allCases) { option in
                    Button {
                        filter = option
                    } label: {
                        Text(option.rawValue)
                            .font(.system(size: 14, weight: filter == option ? .semibold : .regular))
                            .foregroundStyle(filter == option ? Palette.title : Palette.subtitle)
                            .frame(maxWidth: .infinity)
                            .frame(height: Metrics.tabHeight - 8)
                            .background {
                                if filter == option {
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(Palette.panel)
                                        .shadow(color: .black.opacity(0.06), radius: 1.5, y: 1)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(filter == option ? [.isSelected] : [])
                }
            }
            .padding(2)
            .background(Palette.track, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Palette.hairline, lineWidth: 1)
            }

            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Palette.glyph)
                .frame(width: Metrics.filterButton, height: Metrics.filterButton)
                .background(Palette.panel, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Palette.hairline, lineWidth: 1)
                }
                .accessibilityLabel("Display options")
        }
    }
}

// MARK: - Provider section

private struct ProviderSection: View {
    let surface: ProviderSurface
    let profiles: [AccountProfile]
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ProviderBadge(surface: surface)
                Text(surface.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Palette.title)
                Spacer(minLength: 8)
                // The design's average-remaining dropdown was dropped; the connected
                // count takes the trailing slot instead.
                HStack(spacing: 6) {
                    Text(countLabel)
                        .font(.system(size: 13.5))
                        .foregroundStyle(Palette.subtitle)
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.horizontal, 18)
            .frame(height: Metrics.sectionHeaderHeight)

            ForEach(profiles) { profile in
                Divider().overlay(Palette.hairline)
                AccountRow(
                    profile: profile,
                    snapshot: model.snapshot(for: profile),
                    isActive: model.isActive(profile),
                    referenceDate: model.referenceDate,
                    showAllQuotaWindows: model.showAllQuotaWindows,
                    switchAction: { model.requestSwitch(profile) },
                    canDelete: model.canDelete(profile),
                    deleteAction: { model.requestDelete(profile) },
                    renameAction: { model.renameProfile(profile) },
                    setActiveAction: { model.requestSwitch(profile) }
                )
            }

            if model.canAddProfile(to: surface) || profiles.isEmpty {
                Divider().overlay(Palette.hairline)
            }
            if model.canAddProfile(to: surface) {
                AddAccountRow(surface: surface) { model.addProfile(to: surface) }
            } else if profiles.isEmpty {
                EmptySurfaceRow(surface: surface, action: model.guidedAction(for: surface))
            }
        }
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .stroke(Palette.hairline, lineWidth: 1)
        }
    }

    private var connectedCount: Int { profiles.filter(\.connected).count }

    private var countLabel: String {
        if surface == .cursor { return "\(profiles.count) configured" }
        return "\(connectedCount) connected"
    }

    private var statusColor: Color {
        switch surface {
        case .cursor: return Palette.muted
        case .codexMacApp: return Palette.warn
        default: return connectedCount > 0 ? Palette.good : Palette.muted
        }
    }
}

/// Always present on an addable surface, so a signed-out provider offers the next step
/// instead of a placeholder row that does nothing.
private struct AddAccountRow: View {
    let surface: ProviderSurface
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(Palette.good)
                    .frame(width: Metrics.colSelector)
                Text("Add \(surface.displayName) account")
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(Palette.good)
                Spacer(minLength: 0)
                Text("Opens provider sign-in")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.subtitle)
                    .padding(.trailing, Metrics.rowTrailing)
            }
            .frame(height: Metrics.addRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add \(surface.displayName) account")
    }
}

/// A surface that cannot take an isolated profile still gets a next step where one
/// exists. Cursor genuinely has none, so it says why rather than offering a dead button.
private struct EmptySurfaceRow: View {
    let surface: ProviderSurface
    let action: (() -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: surface == .cursor ? "clock.badge.questionmark" : "arrow.up.forward.app")
                .font(.system(size: 14))
                .foregroundStyle(surface == .cursor ? Palette.subtitle : Palette.good)
                .frame(width: Metrics.colSelector)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Palette.subtitle)
                .lineLimit(2)
            Spacer(minLength: 8)
            if let action {
                Button(action: action) {
                    Text("Sign in")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Palette.title)
                        .frame(width: Metrics.buttonWidth, height: Metrics.buttonHeight)
                        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(Palette.hairline, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .padding(.trailing, Metrics.rowTrailing)
            }
        }
        .frame(height: Metrics.addRowHeight)
    }

    private var message: String {
        switch surface {
        case .cursor:
            return "Deferred until Cursor documents safe profile switching"
        case .codexMacApp:
            return "The Codex app owns its own session"
        default:
            return "No accounts yet"
        }
    }
}

private struct ProviderBadge: View {
    let surface: ProviderSurface

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: 34, height: 34)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityHidden(true)
    }

    private var icon: String {
        switch surface {
        case .codexCLI: return "chevron.left.forwardslash.chevron.right"
        case .codexMacApp: return "macwindow"
        case .claudeCode: return "sparkle"
        case .cursor: return "cursorarrow.rays"
        }
    }

    private var tint: Color {
        switch surface {
        case .codexCLI: return Palette.good
        case .codexMacApp: return Color(red: 0.29, green: 0.45, blue: 0.85)
        case .claudeCode: return Color(red: 0.85, green: 0.42, blue: 0.22)
        case .cursor: return Palette.title
        }
    }
}

// MARK: - Account row

private struct AccountRow: View {
    let profile: AccountProfile
    let snapshot: QuotaSnapshot?
    let isActive: Bool
    let referenceDate: Date
    let showAllQuotaWindows: Bool
    let switchAction: () -> Void
    let canDelete: Bool
    let deleteAction: () -> Void
    let renameAction: () -> Void
    let setActiveAction: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            selector
                .frame(width: Metrics.colSelector)

            VStack(alignment: .leading, spacing: 3) {
                Text(profile.label)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.title)
                Text(profile.identity ?? (profile.connected ? "Connected account" : "Not connected"))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.subtitle)
                    .lineLimit(1)
            }
            .frame(width: Metrics.colName, alignment: .leading)

            quotaColumn.frame(width: Metrics.colQuota, alignment: .leading)
            resetColumn.frame(width: Metrics.colReset, alignment: .leading)
            healthColumn.frame(width: Metrics.colHealth, alignment: .leading)

            Spacer(minLength: 0)
            action
            overflowMenu
        }
        .frame(height: Metrics.rowHeight)
        .background {
            if showsActive {
                RoundedRectangle(cornerRadius: Metrics.rowRadius, style: .continuous)
                    .fill(Palette.activeFill)
                    .overlay {
                        RoundedRectangle(cornerRadius: Metrics.rowRadius, style: .continuous)
                            .stroke(Palette.good.opacity(0.55), lineWidth: 1)
                    }
                    .overlay(alignment: .leading) {
                        // A 4pt accent strip carries the "active" signal so the row itself
                        // can stay near-white instead of shouting in green.
                        UnevenRoundedRectangle(
                            topLeadingRadius: Metrics.rowRadius,
                            bottomLeadingRadius: Metrics.rowRadius,
                            bottomTrailingRadius: 0,
                            topTrailingRadius: 0,
                            style: .continuous
                        )
                        .fill(Palette.good)
                        .frame(width: 4)
                    }
                    .padding(.horizontal, 1)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var window: QuotaWindow? {
        snapshot?.displayWindows(showAll: showAllQuotaWindows).first
    }

    /// Guided-only surfaces never wear the active treatment: the app cannot confirm
    /// that switch, so claiming it in the UI would be a lie.
    private var showsActive: Bool { isActive && profile.switchCapability == .isolatedProfile }

    @ViewBuilder private var selector: some View {
        if showsActive {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(Palette.good)
                .accessibilityLabel("Active account")
        } else {
            Circle()
                .stroke(Palette.selectorRing, lineWidth: 1.5)
                .frame(width: 20, height: 20)
                .accessibilityLabel("Inactive account")
        }
    }

    @ViewBuilder private var quotaColumn: some View {
        if let window {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(Int(window.remainingPercent.rounded()))%")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Palette.title)
                    Text("left")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.subtitle)
                }
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.track).frame(height: 6)
                    Capsule()
                        .fill(barColor(window.remainingPercent))
                        .frame(width: max(4, 66 * window.remainingPercent / 100), height: 6)
                }
                .frame(width: 66)
            }
        } else {
            VStack(alignment: .leading, spacing: 3) {
                Text("—").font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.subtitle)
                Text("No quota").font(.system(size: 11)).foregroundStyle(Palette.subtitle)
            }
        }
    }

    @ViewBuilder private var resetColumn: some View {
        if let window {
            VStack(alignment: .leading, spacing: 3) {
                Text(QuotaFormatting.compactCountdown(to: window.resetsAt, now: referenceDate))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Palette.title)
                Text(QuotaFormatting.compactAbsoluteReset(window.resetsAt))
                    .font(.system(size: 12))
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(Palette.subtitle)
            }
        } else {
            VStack(alignment: .leading, spacing: 3) {
                Text("—").font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.subtitle)
                Text("No reset").font(.system(size: 11)).foregroundStyle(Palette.subtitle)
            }
        }
    }

    private var healthColumn: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Circle().fill(healthTint).frame(width: 7, height: 7)
                Text(healthLabel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(healthTint == Palette.good ? Palette.good : Palette.subtitle)
            }
            if snapshot != nil {
                Text(QuotaFormatting.age(snapshot?.fetchedAt ?? referenceDate, now: referenceDate))
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.subtitle)
            }
        }
    }

    private var healthLabel: String {
        if profile.switchCapability == .unsupported { return "Deferred" }
        if snapshot == nil { return "Needs login" }
        return QuotaFormatting.health(for: snapshot, now: referenceDate).label
    }

    private var healthTint: Color {
        if profile.switchCapability == .unsupported { return Palette.muted }
        if snapshot == nil { return Palette.warn }
        return QuotaFormatting.health(for: snapshot, now: referenceDate) == .fresh ? Palette.good : Palette.warn
    }

    @ViewBuilder private var action: some View {
        if showsActive {
            // No chevron: this reports the current state, it is not a menu. Row actions
            // live in the overflow control beside it.
            Text("Active")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.good)
                .frame(width: Metrics.buttonWidth, height: Metrics.buttonHeight)
            .background(Palette.panel, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Palette.good.opacity(0.45), lineWidth: 1)
            }
        } else {
            Button(action: switchAction) {
                Text(actionLabel)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Palette.title)
                    .frame(width: Metrics.buttonWidth, height: Metrics.buttonHeight)
                    .background(Palette.panel, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Palette.hairline, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(actionAccessibilityLabel)
        }
    }

    private var actionLabel: String {
        if profile.switchCapability == .unsupported { return "Enable" }
        if profile.switchCapability == .guidedOnly { return "Guide" }
        return profile.connected ? "Switch" : "Connect"
    }

    private var actionAccessibilityLabel: String {
        if profile.switchCapability == .unsupported { return "Cursor support is deferred" }
        if profile.switchCapability == .guidedOnly { return "Open guided switch for \(profile.label)" }
        if !profile.connected { return "Connect \(profile.label)" }
        return "Switch launcher to \(profile.label)"
    }

    /// Row actions live behind one quiet trailing control rather than competing with the
    /// row's content, and destructive removal is never a bare button in the row itself.
    @ViewBuilder private var overflowMenu: some View {
        if canDelete {
            Menu {
                if !showsActive && profile.switchCapability == .isolatedProfile && profile.connected {
                    Button("Set active", action: setActiveAction)
                }
                Button("Rename\u{2026}", action: renameAction)
                Divider()
                Button("Remove account", action: deleteAction)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.glyph)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(width: Metrics.colOverflow, height: Metrics.rowHeight)
            .accessibilityLabel("Actions for \(profile.label)")
        } else {
            Color.clear.frame(width: Metrics.colOverflow, height: 1)
        }
    }

    private func barColor(_ remaining: Double) -> Color {
        if remaining < 20 { return Palette.bad }
        if remaining < 40 { return Palette.warn }
        return Palette.good
    }
}

// MARK: - Footer

private struct FooterBar: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 9) {
            Button(action: model.refresh) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.glyph)
            }
            .buttonStyle(.plain)
            .disabled(model.isRefreshing)
            .keyboardShortcut("r", modifiers: .command)
            .accessibilityLabel("Refresh accounts")

            Text(model.lastUpdated.map { "Updated \(QuotaFormatting.age($0, now: model.referenceDate))" } ?? "Not refreshed yet")
                .font(.system(size: 13))
                .foregroundStyle(Palette.subtitle)

            Spacer(minLength: 8)

            Button(action: model.launchActiveProfile) {
                HStack(spacing: 7) {
                    Image(systemName: "play.fill").font(.system(size: 11))
                    Text("Launch with active profile").font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(height: 46)
                .background(Palette.good, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)

            Menu {
                Button("Refresh", action: model.refresh)
                Toggle(
                    "Show 5-hour and other quota windows",
                    isOn: Binding(get: { model.showAllQuotaWindows }, set: model.setShowAllQuotaWindows)
                )
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.glyph)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(width: 46, height: 46)
            .background(Palette.panel, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Palette.hairline, lineWidth: 1)
            }
            .accessibilityLabel("More actions")
        }
        .padding(.horizontal, Metrics.gutter + 2)
        .frame(height: Metrics.footerHeight)
        .background(Palette.footer)
        .overlay(alignment: .top) { Rectangle().fill(Palette.hairline).frame(height: 1) }
    }
}

private struct NoticeToast: View {
    let text: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill").foregroundStyle(Palette.good)
            Text(text)
                .font(.caption.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(action: dismiss) { Image(systemName: "xmark") }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss notice")
        }
        .padding(10)
        .frame(maxWidth: 380)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.16), radius: 12, y: 4)
    }
}

// MARK: - Palette

enum Palette {
    // Sampled directly from the approved design reference rather than guessed. The
    // design is deliberately low-contrast: panels sit only a few levels above the
    // canvas, separated by hairlines rather than by fill.
    static let good = rgb(58, 132, 100)
    static let warn = rgb(214, 152, 47)
    static let bad = rgb(198, 58, 48)
    static let muted = rgb(158, 156, 150)

    static let title = rgb(32, 31, 29)
    static let subtitle = rgb(122, 119, 113)
    static let glyph = rgb(104, 101, 96)

    static let panel = rgb(250, 250, 248)
    static let track = rgb(232, 230, 226)
    static let hairline = rgb(233, 231, 227)
    static let footer = rgb(247, 244, 240)
    static let activeFill = rgb(250, 252, 250)
    static let selectorRing = rgb(203, 201, 196)

    static let pouchBody = rgb(196, 90, 48)
    static let pouchLight = rgb(214, 108, 64)
    static let pouchDark = rgb(44, 42, 41)
    static let pouchStrap = rgb(228, 164, 74)
    static let pouchZip = rgb(246, 243, 239)

    static func canvas(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? rgb(28, 28, 30) : rgb(247, 245, 241)
    }

    private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color {
        Color(red: r / 255, green: g / 255, blue: b / 255)
    }
}
