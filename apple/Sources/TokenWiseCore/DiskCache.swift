import Foundation

/// A persistent per-file summary cache so cold starts only re-parse changed
/// session files. Stored as one JSON blob under the user's Caches directory.
enum DiskCache {
    struct Entry: Codable {
        var mtime: Double
        var size: UInt64
        var summary: SessionSummary
    }

    private static func url(_ name: String) -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? Paths.home.appendingPathComponent("Library/Caches")
        let dir = base.appendingPathComponent("token-wise", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(name).json")
    }

    static func load(_ name: String) -> [String: Entry] {
        guard let data = try? Data(contentsOf: url(name)),
              let map = try? JSONDecoder().decode([String: Entry].self, from: data) else { return [:] }
        return map
    }

    static func save(_ name: String, _ map: [String: Entry]) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        try? data.write(to: url(name), options: .atomic)
    }
}
