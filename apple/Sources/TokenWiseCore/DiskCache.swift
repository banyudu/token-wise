import Foundation

/// A persistent per-file summary cache so cold starts only re-parse changed
/// session files. Stored as one JSON blob under the user's Caches directory.
enum DiskCache {
    struct Entry: Codable {
        var mtime: Double
        var size: UInt64
        var summary: SessionSummary
    }

    /// Cached summaries carry baked-in costs, so the file records which pricing
    /// produced them; a rate change invalidates the whole cache instead of
    /// leaving stale money on screen until a session file happens to change.
    private struct Snapshot: Codable {
        var pricing: String
        var entries: [String: Entry]
    }

    private static func url(_ name: String) -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? Paths.home.appendingPathComponent("Library/Caches")
        let dir = base.appendingPathComponent("token-wise", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(name).json")
    }

    static func load(_ name: String, pricing: String) -> [String: Entry] {
        guard let data = try? Data(contentsOf: url(name)),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
              snapshot.pricing == pricing
        else { return [:] }
        return snapshot.entries
    }

    static func save(_ name: String, pricing: String, _ map: [String: Entry]) {
        guard let data = try? JSONEncoder().encode(Snapshot(pricing: pricing, entries: map)) else { return }
        try? data.write(to: url(name), options: .atomic)
    }
}
