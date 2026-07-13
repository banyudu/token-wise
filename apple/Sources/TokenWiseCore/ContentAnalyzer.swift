import Foundation

/// Categorizes transcript content blocks by what consumed the tokens — file
/// reads, shell output, edits, thinking, prompts, etc. — and surfaces the
/// largest blocks plus heuristic suggestions. Port of the Rust `analyze_content`.
public enum ContentAnalyzer {
    struct Block {
        var category: String
        var subcategory: String?
        var toolName: String?
        var source: String?
        var byteSize: UInt64
        var preview: String
        var fullContent: String
        var turnIndex: UInt32
    }

    public static func analyze(_ messages: [ClaudeMessage]) -> ContentAnalysis {
        // Step A: tool_use_id -> (name, source)
        var toolUseMap: [String: (String, String?)] = [:]
        for msg in messages {
            guard let inner = msg.message, inner.role == "assistant",
                  case let .array(blocks)? = inner.content else { continue }
            for block in blocks where block["type"]?.stringValue == "tool_use" {
                if let id = block["id"]?.stringValue, let name = block["name"]?.stringValue {
                    toolUseMap[id] = (name, extractToolSource(name, block["input"]))
                }
            }
        }

        // Step B: classify + measure
        var blocks: [Block] = []
        var turnIndex: UInt32 = 0
        for msg in messages {
            guard let inner = msg.message, let content = inner.content else {
                if msg.type == "user" || msg.type == "assistant" { turnIndex += 1 }
                continue
            }
            let role = inner.role ?? ""
            switch content {
            case let .string(s):
                blocks.append(Block(category: role == "user" ? "User Prompts" : role == "assistant" ? "Assistant Text" : "Other",
                                    subcategory: nil, toolName: nil, source: nil,
                                    byteSize: UInt64(s.utf8.count), preview: preview(content, 80),
                                    fullContent: s, turnIndex: turnIndex))
            case let .array(arr):
                for block in arr {
                    let type = block["type"]?.stringValue ?? ""
                    let size = block.byteSize
                    switch type {
                    case "tool_result":
                        let id = block["tool_use_id"]?.stringValue ?? ""
                        let (name, source) = toolUseMap[id].map { ($0.0 as String?, $0.1) } ?? (nil, nil)
                        let (cat, sub) = name.map(classifyTool) ?? ("Other Tools", nil)
                        let resultContent = block["content"] ?? block
                        blocks.append(Block(category: cat, subcategory: sub, toolName: name, source: source,
                                            byteSize: size, preview: preview(resultContent, 80),
                                            fullContent: fullContent(resultContent), turnIndex: turnIndex))
                    case "tool_use":
                        let name = block["name"]?.stringValue ?? "unknown"
                        let (cat, sub) = classifyTool(name)
                        if cat == "File Edits" {
                            let input = block["input"] ?? block
                            let inputBytes = block["input"]?.byteSize ?? 0
                            if inputBytes > 0 {
                                blocks.append(Block(category: cat, subcategory: sub, toolName: name,
                                                    source: extractToolSource(name, block["input"]),
                                                    byteSize: inputBytes, preview: preview(input, 80),
                                                    fullContent: fullContent(input), turnIndex: turnIndex))
                            }
                        }
                    case "thinking":
                        blocks.append(Block(category: "Thinking", subcategory: nil, toolName: nil, source: nil,
                                            byteSize: size, preview: preview(block, 80),
                                            fullContent: fullContent(block), turnIndex: turnIndex))
                    case "text":
                        blocks.append(Block(category: role == "user" ? "User Prompts" : role == "assistant" ? "Assistant Text" : "Other",
                                            subcategory: nil, toolName: nil, source: nil,
                                            byteSize: size, preview: preview(block, 80),
                                            fullContent: fullContent(block), turnIndex: turnIndex))
                    default: break
                    }
                }
            default: break
            }
            if msg.type == "user" || msg.type == "assistant" { turnIndex += 1 }
        }

        // Step C: aggregate by category
        let totalBytes = blocks.reduce(UInt64(0)) { $0 + $1.byteSize }
        let totalTokens = totalBytes / 4
        var catMap: [String: (bytes: UInt64, count: UInt32, sub: String?)] = [:]
        for b in blocks {
            let key = b.subcategory.map { "\(b.category):\($0)" } ?? b.category
            var e = catMap[key] ?? (0, 0, b.subcategory)
            e.bytes += b.byteSize; e.count += 1
            catMap[key] = e
        }
        var categories = catMap.map { key, v -> ContentCategory in
            let category = key.split(separator: ":", maxSplits: 1).first.map(String.init) ?? key
            let est = v.bytes / 4
            let pct = totalTokens > 0 ? Double(est) / Double(totalTokens) * 100 : 0
            return ContentCategory(category: category, subcategory: v.sub, estimatedTokens: est,
                                   byteSize: v.bytes, count: v.count, percentage: pct)
        }
        categories.sort { $0.estimatedTokens > $1.estimatedTokens }

        let allItems = blocks.sorted { $0.byteSize > $1.byteSize }.map { b in
            ContentItem(category: b.category, toolName: b.toolName, source: b.source,
                        estimatedTokens: b.byteSize / 4, preview: b.preview,
                        fullContent: b.fullContent, turnIndex: b.turnIndex)
        }

        // Step D: suggestions
        var catPct: [String: Double] = [:]
        for c in categories { catPct[c.category, default: 0] += c.percentage }
        var suggestions: [String] = []
        if catPct["File Reads", default: 0] > 40 {
            suggestions.append("File Reads consume >40% of tokens. Consider targeted Grep/Glob instead of reading entire files.")
        }
        if catPct["Shell Commands", default: 0] > 30 {
            suggestions.append("Shell Commands consume >30% of tokens. Consider limiting output with head/tail or more specific commands.")
        }
        if catPct["Web Content", default: 0] > 25 {
            suggestions.append("Web Content consumes >25% of tokens. Consider targeted extraction instead of full page fetches.")
        }
        if catPct["External Tools", default: 0] > 20 {
            suggestions.append("External Tools (MCP) consume >20% of tokens. Consider requesting less data from MCP services.")
        }
        for item in allItems.prefix(10) where item.estimatedTokens > 50_000 {
            suggestions.append("Large block: \(item.category) (\(item.toolName ?? "unknown")) with ~\(item.estimatedTokens / 1000)K est. tokens at turn \(item.turnIndex + 1). Consider reducing its size.")
        }

        return ContentAnalysis(categories: categories, totalEstimatedTokens: totalTokens,
                               allItems: allItems, suggestions: suggestions)
    }

    static func classifyTool(_ name: String) -> (String, String?) {
        switch name {
        case "Read": return ("File Reads", nil)
        case "Grep", "Glob": return ("Code Search", nil)
        case "Bash": return ("Shell Commands", nil)
        case "WebFetch", "WebSearch": return ("Web Content", nil)
        case "Edit", "Write": return ("File Edits", nil)
        case "Agent": return ("Subagents", nil)
        default:
            if name.hasPrefix("Task") { return ("Subagents", nil) }
            if name.hasPrefix("mcp__") {
                let rest = String(name.dropFirst(5))
                let service = rest.range(of: "__").map { String(rest[..<$0.lowerBound]) } ?? rest
                return ("External Tools", service)
            }
            return ("Other Tools", nil)
        }
    }

    static func preview(_ value: JSONValue, _ maxLen: Int) -> String {
        let text: String
        switch value {
        case let .string(s): text = s
        case let .array(arr):
            text = arr.first { $0["type"]?.stringValue == "text" }?["text"]?.stringValue
                ?? arr.first { $0["content"]?.stringValue != nil }?["content"]?.stringValue
                ?? ""
        default: text = jsonString(value)
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
        if trimmed.count > maxLen { return String(trimmed.prefix(maxLen - 3)) + "..." }
        return trimmed
    }

    static func fullContent(_ value: JSONValue) -> String {
        switch value {
        case let .string(s): return s
        case let .array(arr):
            var parts: [String] = []
            for item in arr {
                if item["type"]?.stringValue == "text", let s = item["text"]?.stringValue { parts.append(s) }
                else if let s = item["content"]?.stringValue { parts.append(s) }
            }
            return parts.isEmpty ? jsonString(value) : parts.joined(separator: "\n")
        default: return jsonString(value)
        }
    }

    static func extractToolSource(_ toolName: String, _ input: JSONValue?) -> String? {
        guard let obj = input?.objectValue else { return nil }
        func s(_ keys: [String]) -> String? {
            for k in keys { if let v = obj[k]?.stringValue { return v } }
            return nil
        }
        let n = toolName.lowercased()
        let source: String?
        if n.contains("read") { source = s(["file_path", "path"]) }
        else if n.contains("write") || n.contains("edit") { source = s(["file_path", "path"]) }
        else if n.contains("bash") || n.contains("terminal") { source = s(["command", "cmd"]) }
        else if n.contains("fetch") || n.contains("web") || n.contains("browse") { source = s(["url", "uri"]) }
        else if n.contains("glob") { source = s(["pattern"]) }
        else if n.contains("grep") || n.contains("search") { source = s(["pattern", "query"]) }
        else { source = s(["file_path", "path", "url", "command"]) }
        guard let source else { return nil }
        return source.count > 120 ? String(source.prefix(117)) + "..." : source
    }

    private static func jsonString(_ value: JSONValue) -> String {
        func toAny(_ v: JSONValue) -> Any {
            switch v {
            case let .string(s): return s
            case let .number(n): return n
            case let .bool(b): return b
            case .null: return NSNull()
            case let .array(a): return a.map(toAny)
            case let .object(o): return o.mapValues(toAny)
            }
        }
        let any = toAny(value)
        guard JSONSerialization.isValidJSONObject(any),
              let data = try? JSONSerialization.data(withJSONObject: any, options: [.prettyPrinted]),
              let str = String(data: data, encoding: .utf8) else {
            if case let .string(s) = value { return s }
            return ""
        }
        return str
    }
}
