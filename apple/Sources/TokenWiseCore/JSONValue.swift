import Foundation

/// A lightweight, fully-decoded JSON value. Mirrors the role `serde_json::Value`
/// played in the Rust implementation: session transcripts carry arbitrarily
/// shaped `content` blocks that we walk to classify tool use, measure sizes,
/// and extract previews.
public enum JSONValue: Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? container.decode(Double.self) {
            self = .number(n)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let a = try? container.decode([JSONValue].self) {
            self = .array(a)
        } else if let o = try? container.decode([String: JSONValue].self) {
            self = .object(o)
        } else {
            self = .null
        }
    }

    // MARK: Accessors

    public var stringValue: String? {
        if case let .string(s) = self { return s }
        return nil
    }

    public var arrayValue: [JSONValue]? {
        if case let .array(a) = self { return a }
        return nil
    }

    public var objectValue: [String: JSONValue]? {
        if case let .object(o) = self { return o }
        return nil
    }

    public subscript(_ key: String) -> JSONValue? {
        objectValue?[key]
    }

    /// Approximate byte size, mirroring the Rust `measure_content_bytes`.
    public var byteSize: UInt64 {
        switch self {
        case let .string(s): return UInt64(s.utf8.count)
        case let .array(a): return a.reduce(0) { $0 + $1.byteSize }
        case let .object(o): return o.values.reduce(0) { $0 + $1.byteSize }
        case let .number(n): return UInt64(String(n).utf8.count)
        case .bool: return 5
        case .null: return 4
        }
    }
}
