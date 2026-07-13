import Foundation

/// Display formatters shared by the CLI and GUI.
public enum Format {
    public static func tokens(_ n: UInt64) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return String(n)
    }

    public static func cost(_ n: Double) -> String {
        String(format: "$%.2f", n)
    }

    public static func percent(_ n: Double) -> String {
        String(format: "%.1f%%", n * 100)
    }

    public static func duration(_ ms: Double) -> String {
        if ms <= 0 { return "—" }
        let mins = Int(ms / 60_000)
        if mins < 1 { return "<1m" }
        if mins < 60 { return "\(mins)m" }
        let hours = mins / 60
        let remain = mins % 60
        if hours < 24 { return "\(hours)h \(remain)m" }
        let days = hours / 24
        return "\(days)d \(hours % 24)h"
    }

    /// Milliseconds between a session's first and last timestamp.
    public static func sessionDurationMs(_ s: SessionSummary) -> Double {
        guard let first = parseDate(s.firstTimestamp), let last = parseDate(s.lastTimestamp) else { return 0 }
        return max(0, last.timeIntervalSince(first) * 1000)
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoNoFrac = ISO8601DateFormatter()

    public static func parseDate(_ s: String?) -> Date? {
        guard let s else { return nil }
        return iso.date(from: s) ?? isoNoFrac.date(from: s)
    }

    /// Shorten a path with `~` for home and a trailing-segment cap.
    public static func path(_ path: String, maxSegments: Int = 3) -> String {
        var result = path
        let home = Paths.home.path
        if result.hasPrefix(home) { result = "~" + result.dropFirst(home.count) }
        let parts = result.split(separator: "/", omittingEmptySubsequences: false)
        if parts.count > maxSegments {
            return ".../" + parts.suffix(maxSegments - 1).joined(separator: "/")
        }
        return result
    }
}
