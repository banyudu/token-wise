import Foundation

/// One numbered recommendation from the analysis report.
public struct AnalysisFix: Identifiable, Equatable {
    /// Position in the report, 1-based — stable across a single report so the
    /// UI can track which fixes are selected.
    public let id: Int
    /// The number as the model wrote it, which is what the user sees.
    public let number: Int
    /// The item's markdown, without the `N.` marker.
    public let markdown: String
    /// Short label for the item — its leading bold run, else its first sentence.
    public let title: String
}

/// The analysis report broken into renderable blocks.
///
/// The model is asked for GitHub-flavored Markdown with an `## Actionable fixes`
/// list and an `## Narrative`. Rendering it through `AttributedString`'s inline
/// parser leaves `##` and list markers as literal text, and gives the UI nothing
/// to hang a per-item action on — so parse the block structure here.
public struct AnalysisDocument {
    public enum Block: Identifiable {
        case heading(id: Int, level: Int, text: String)
        case fix(AnalysisFix)
        case bullet(id: Int, markdown: String)
        case paragraph(id: Int, markdown: String)

        public var id: Int {
            switch self {
            case let .heading(id, _, _), let .bullet(id, _), let .paragraph(id, _): return id
            case let .fix(fix): return fix.id
            }
        }
    }

    public let blocks: [Block]
    public var fixes: [AnalysisFix] {
        blocks.compactMap { if case let .fix(f) = $0 { return f } else { return nil } }
    }

    public init(_ report: String) {
        var blocks: [Block] = []
        var pending: [String] = []
        var pendingFix: (number: Int, id: Int)?
        var nextID = 0

        func flush() {
            let text = pending.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            pending.removeAll()
            guard !text.isEmpty else { pendingFix = nil; return }
            if let fix = pendingFix {
                blocks.append(.fix(AnalysisFix(id: fix.id, number: fix.number,
                                               markdown: text, title: Self.title(of: text))))
                pendingFix = nil
            } else {
                blocks.append(.paragraph(id: nextID, markdown: text))
                nextID += 1
            }
        }

        for rawLine in report.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.isEmpty {
                flush()
                continue
            }
            if let heading = Self.heading(line) {
                flush()
                blocks.append(.heading(id: nextID, level: heading.level, text: heading.text))
                nextID += 1
                continue
            }
            if let item = Self.numberedItem(line) {
                flush()
                pendingFix = (item.number, nextID)
                nextID += 1
                pending.append(item.text)
                continue
            }
            if let bullet = Self.bulletItem(line) {
                flush()
                blocks.append(.bullet(id: nextID, markdown: bullet))
                nextID += 1
                continue
            }
            // A wrapped continuation of whatever block is open.
            pending.append(line)
        }
        flush()
        self.blocks = blocks
    }

    // MARK: Line classification

    private static func heading(_ line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return (hashes, String(line.dropFirst(hashes + 1)).trimmingCharacters(in: .whitespaces))
    }

    private static func numberedItem(_ line: String) -> (number: Int, text: String)? {
        let digits = line.prefix(while: \.isNumber)
        guard !digits.isEmpty, let number = Int(digits) else { return nil }
        var rest = line.dropFirst(digits.count)
        guard let marker = rest.first, marker == "." || marker == ")" else { return nil }
        rest = rest.dropFirst()
        guard rest.first == " " else { return nil }
        return (number, String(rest).trimmingCharacters(in: .whitespaces))
    }

    private static func bulletItem(_ line: String) -> String? {
        guard let marker = line.first, marker == "-" || marker == "*" || marker == "+",
              line.dropFirst().first == " "
        else { return nil }
        return String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
    }

    // MARK: Titles

    /// The item's leading `**bold**` run if it opens with one, else its first
    /// sentence, capped so a title stays a title.
    static func title(of markdown: String) -> String {
        if markdown.hasPrefix("**"), let close = markdown.range(of: "**", range: markdown.index(markdown.startIndex, offsetBy: 2)..<markdown.endIndex) {
            let inner = markdown[markdown.index(markdown.startIndex, offsetBy: 2)..<close.lowerBound]
            return plain(String(inner))
        }
        let sentence = markdown.prefix { $0 != "." } + "."
        return plain(String(sentence.count > 90 ? markdown.prefix(90) + "…" : sentence))
    }

    /// Strips the inline markers that would otherwise show up in a button label.
    private static func plain(_ text: String) -> String {
        text.replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
}
