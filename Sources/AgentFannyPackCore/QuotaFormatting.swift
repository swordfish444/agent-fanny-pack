import Foundation

public enum QuotaFormatting {
    public static func percentRemaining(_ value: Double) -> String {
        "\(Int(value.rounded()))% left"
    }

    public static func countdown(to reset: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(reset.timeIntervalSince(now)))
        if seconds < 60 { return "resets in <1m" }
        let minutes = seconds / 60
        if minutes < 60 { return "resets in \(minutes)m" }
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours < 48 { return "resets in \(hours)h \(remainder)m" }
        return "resets in \(hours / 24)d \(hours % 24)h"
    }

    /// Bare duration for the compact layout, where a surrounding label already says
    /// what the number means: "3d 6h" in a row, "3d 6h 54m" in the summary.
    public static func compactCountdown(to reset: Date, now: Date = Date(), includeMinutes: Bool = false) -> String {
        let seconds = max(0, Int(reset.timeIntervalSince(now)))
        let minutes = seconds / 60
        let hours = minutes / 60
        let days = hours / 24
        if days > 0 {
            let base = "\(days)d \(hours % 24)h"
            return includeMinutes ? base + " \(minutes % 60)m" : base
        }
        if hours > 0 {
            let base = "\(hours)h"
            return includeMinutes ? base + " \(minutes % 60)m" : base
        }
        return "\(minutes)m"
    }

    public static func absoluteReset(_ reset: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: reset)
    }

    public static func compactAbsoluteReset(_ reset: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: reset)
    }

    public static func health(for snapshot: QuotaSnapshot?, now: Date = Date()) -> SourceHealth {
        guard let snapshot else { return .unavailable }
        let age = now.timeIntervalSince(snapshot.fetchedAt)
        if age <= 15 * 60 { return .fresh }
        if age <= 6 * 60 * 60 { return .stale }
        return .offline
    }

    public static func age(_ date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        if seconds < 86_400 { return "\(seconds / 3600)h ago" }
        return "\(seconds / 86_400)d ago"
    }
}
