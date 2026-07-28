import SwiftUI
import TokenWiseCore

/// Strip the dated suffix and `claude-`/`anthropic.` prefix for display.
func displayModel(_ model: String?) -> String? {
    guard var m = model, !m.isEmpty else { return nil }
    for prefix in ["claude-", "anthropic."] where m.lowercased().hasPrefix(prefix) {
        m = String(m.dropFirst(prefix.count))
    }
    // Drop trailing -YYYYMMDD
    if m.count > 9 {
        let suffix = m.suffix(9)
        if suffix.first == "-", suffix.dropFirst().allSatisfy(\.isNumber) {
            m = String(m.dropLast(9))
        }
    }
    return m
}

struct SessionDetailView: View {
    let detail: SessionDetail

    private var summary: SessionSummary { detail.summary }
    private var turns: [TurnMetrics] { detail.turns }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                metricCards

                if let analysis = detail.contentAnalysis {
                    ContentAnalysisView(analysis: analysis)
                }
                if let savings = detail.cacheSavings {
                    CacheSavingsSection(report: savings)
                }
                ContextGrowthChart(turns: turns)
                TurnByTurnTable(turns: turns, contentItems: detail.contentAnalysis?.allItems ?? [])
            }
            .padding(20)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Format.path(summary.project)).font(.title2.bold())
            HStack(spacing: 10) {
                Text(summary.gitBranch ?? "no branch")
                sourceBadge(summary.source, model: summary.model)
                if let model = displayModel(summary.model) {
                    Text(model).font(.caption)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
                }
                if let ts = summary.firstTimestamp, let d = Format.parseDate(ts) {
                    Text(d.formatted(date: .abbreviated, time: .shortened))
                }
                Text(Format.duration(Format.sessionDurationMs(summary)))
            }
            .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var metricCards: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
            let hours = Format.sessionDurationMs(summary) / 3_600_000
            MetricCard(label: "Total Cost", value: Format.cost(summary.estimatedCostUsd),
                       sub: hours > 0.01 ? "\(Format.cost(summary.estimatedCostUsd / hours))/hr" : nil)
            MetricCard(label: "Turns", value: String(turns.count), sub: "\(summary.messageCount) messages")
            MetricCard(label: "Cache Hit Rate", value: Format.percent(summary.cacheHitRate), sub: nil)
            MetricCard(label: "System Overhead (est.)",
                       value: Format.tokens(turns.first?.cacheWriteTokens ?? 0),
                       sub: "first turn cache write")
            if summary.subagentCount > 0 {
                MetricCard(label: "Subagents", value: String(summary.subagentCount),
                           sub: Format.cost(summary.subagentCostUsd))
            }
            if summary.ephemeral5mTokens > 0 || summary.ephemeral1hTokens > 0 {
                MetricCard(label: "Ephemeral Cache",
                           value: Format.tokens(summary.ephemeral5mTokens + summary.ephemeral1hTokens),
                           sub: "5m: \(Format.tokens(summary.ephemeral5mTokens)) / 1h: \(Format.tokens(summary.ephemeral1hTokens))")
            }
        }
    }
}

func sourceBadge(_ source: String, model: String? = nil) -> some View {
    BrandBadge(mark: .resolve(source: source, model: model))
}

// MARK: - Content analysis

struct ContentAnalysisView: View {
    let analysis: ContentAnalysis
    @State private var showTopItems = false
    @State private var categoryFilter: String?
    @State private var previewItem: ContentItem?

    private var mergedCategories: [(name: String, tokens: UInt64, count: UInt32, pct: Double)] {
        var map: [String: (UInt64, UInt32, Double)] = [:]
        for c in analysis.categories {
            var e = map[c.category] ?? (0, 0, 0)
            e.0 += c.estimatedTokens; e.1 += c.count; e.2 += c.percentage
            map[c.category] = e
        }
        return map.map { (name: $0.key, tokens: $0.value.0, count: $0.value.1, pct: $0.value.2) }
            .sorted { $0.tokens > $1.tokens }
    }

    var body: some View {
        GroupBox("Content Analysis") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 24) {
                    DonutChart(categories: analysis.categories, total: analysis.totalEstimatedTokens)

                    VStack(spacing: 0) {
                        gridHeader(["Category", "Est. Tokens", "Count", "%"])
                        ForEach(mergedCategories, id: \.name) { c in
                            Button {
                                categoryFilter = categoryFilter == c.name ? nil : c.name
                                showTopItems = true
                            } label: {
                                HStack {
                                    HStack(spacing: 6) {
                                        Circle().fill(CategoryColors.color(c.name)).frame(width: 8, height: 8)
                                        Text(c.name)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(Format.tokens(c.tokens)).monospacedDigit().frame(width: 80, alignment: .trailing)
                                    Text(String(c.count)).monospacedDigit().frame(width: 60, alignment: .trailing)
                                    Text(String(format: "%.1f%%", c.pct)).monospacedDigit().frame(width: 60, alignment: .trailing)
                                }
                                .font(.callout)
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .background(categoryFilter == c.name ? CostColors.primary.opacity(0.08) : .clear)
                            Divider()
                        }
                    }
                }

                let subcats = analysis.categories.filter { $0.subcategory != nil }
                if !subcats.isEmpty {
                    DisclosureGroup("Subcategories") {
                        VStack(spacing: 0) {
                            ForEach(subcats) { c in
                                HStack {
                                    HStack(spacing: 6) {
                                        Circle().fill(CategoryColors.color(c.category)).frame(width: 7, height: 7)
                                        Text("\(c.category) / \(c.subcategory ?? "")")
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(Format.tokens(c.estimatedTokens)).monospacedDigit().frame(width: 80, alignment: .trailing)
                                    Text(String(c.count)).monospacedDigit().frame(width: 60, alignment: .trailing)
                                    Text(String(format: "%.1f%%", c.percentage)).monospacedDigit().frame(width: 60, alignment: .trailing)
                                }
                                .font(.caption)
                                .padding(.vertical, 3)
                            }
                        }
                    }
                    .font(.caption.bold())
                }

                if !analysis.allItems.isEmpty {
                    topItemsSection
                }

                if !analysis.suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Optimization Suggestions").font(.caption.bold()).foregroundStyle(CostColors.primary)
                        ForEach(analysis.suggestions, id: \.self) { s in
                            Text("• \(s)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(CostColors.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(.vertical, 4)
        }
        .sheet(item: $previewItem) { item in ContentPreviewSheet(item: item) }
    }

    private var topItemsSection: some View {
        let filtered = (categoryFilter.map { f in analysis.allItems.filter { $0.category == f } } ?? analysis.allItems)
            .prefix(10)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    showTopItems.toggle()
                } label: {
                    Label("Top \(filtered.count) Largest Content Blocks",
                          systemImage: showTopItems ? "chevron.down" : "chevron.right")
                        .font(.callout.bold())
                }
                .buttonStyle(.plain).foregroundStyle(CostColors.primary)
                if let f = categoryFilter {
                    Button {
                        categoryFilter = nil
                    } label: {
                        Label(f, systemImage: "xmark.circle.fill").font(.caption)
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }
            }
            if showTopItems {
                VStack(spacing: 0) {
                    gridHeader(["Turn", "Category", "Tool", "Source", "Est. Tokens", ""])
                    ForEach(Array(filtered.enumerated()), id: \.offset) { _, item in
                        HStack {
                            Text(String(item.turnIndex + 1)).frame(width: 40, alignment: .leading)
                            HStack(spacing: 6) {
                                Circle().fill(CategoryColors.color(item.category)).frame(width: 7, height: 7)
                                Text(item.category)
                            }
                            .frame(width: 130, alignment: .leading)
                            Text(item.toolName ?? "—").frame(width: 90, alignment: .leading)
                            Text(item.source.map { Format.path($0) } ?? "—")
                                .lineLimit(1).truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(Format.tokens(item.estimatedTokens)).monospacedDigit().frame(width: 80, alignment: .trailing)
                            Button("View") { previewItem = item }
                                .buttonStyle(.bordered).controlSize(.small)
                                .disabled(item.fullContent.isEmpty)
                        }
                        .font(.caption)
                        .padding(.vertical, 3)
                        Divider()
                    }
                }
            }
        }
    }
}

private func gridHeader(_ labels: [String]) -> some View {
    HStack {
        ForEach(Array(labels.enumerated()), id: \.offset) { i, l in
            Text(l.uppercased()).font(.caption2.bold()).foregroundStyle(.secondary)
                .frame(maxWidth: i == 0 ? nil : .infinity,
                       alignment: i == 0 ? .leading : .leading)
        }
    }
    .padding(.vertical, 4)
}

struct ContentPreviewSheet: View {
    let item: ContentItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Content Preview").font(.headline)
                if let source = item.source {
                    Text(Format.path(source)).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(14)
            Divider()
            ScrollView {
                Text(item.fullContent)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
        }
        .frame(minWidth: 640, minHeight: 420, idealHeight: 560)
    }
}

// MARK: - Cache savings section

struct CacheSavingsSection: View {
    let report: CacheSavingsReport

    private var hasAny: Bool {
        !report.wastedCacheWrites.isEmpty || !report.invalidationEvents.isEmpty
            || !report.unreferencedBlocks.isEmpty || !report.repeatedBlocks.isEmpty
    }

    var body: some View {
        GroupBox("Savings Opportunities") {
            if !hasAny {
                Text("No savings opportunities detected — this session looks well-cached.")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Text("TOTAL POTENTIAL SAVINGS").font(.caption2.bold()).foregroundStyle(.secondary)
                        Text(Format.cost(report.totalPotentialSavingsUsd)).font(.headline).foregroundStyle(CostColors.output)
                        Text("(heuristic estimate)").font(.caption2).foregroundStyle(.tertiary)
                    }

                    if !report.wastedCacheWrites.isEmpty {
                        savingsGroup("Wasted Cache Writes (\(report.wastedCacheWrites.count)) — \(Format.cost(report.wastedCacheWrites.reduce(0) { $0 + $1.wastedCostUsd }))",
                                     note: "Cache written but never read back before session ended.") {
                            ForEach(Array(report.wastedCacheWrites.enumerated()), id: \.offset) { _, w in
                                HStack(alignment: .top) {
                                    Text("Turn \(w.turnIndex + 1)").frame(width: 70, alignment: .leading)
                                    Text(Format.tokens(w.wastedTokens)).monospacedDigit().frame(width: 70, alignment: .trailing)
                                    Text(Format.cost(w.wastedCostUsd)).monospacedDigit().bold()
                                        .foregroundStyle(CostColors.output).frame(width: 70, alignment: .trailing)
                                    Text(w.reason).foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .font(.caption)
                            }
                        }
                    }

                    if !report.invalidationEvents.isEmpty {
                        savingsGroup("Cache Prefix Invalidations (\(report.invalidationEvents.count)) — \(Format.cost(report.invalidationEvents.reduce(0) { $0 + $1.rewriteCostUsd }))",
                                     note: "Turns where the cached prefix was suddenly invalidated and re-written.") {
                            ForEach(Array(report.invalidationEvents.enumerated()), id: \.offset) { _, e in
                                HStack(alignment: .top) {
                                    Text("Turn \(e.turnIndex + 1)").frame(width: 70, alignment: .leading)
                                    Text(Format.tokens(e.droppedTokens)).monospacedDigit().frame(width: 70, alignment: .trailing)
                                    Text(Format.cost(e.rewriteCostUsd)).monospacedDigit().bold()
                                        .foregroundStyle(CostColors.output).frame(width: 70, alignment: .trailing)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(e.suspectedCause ?? "—")
                                        if let preview = e.suspectedPreview {
                                            Text(preview).foregroundStyle(.tertiary).lineLimit(1)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .font(.caption)
                            }
                        }
                    }

                    if !report.unreferencedBlocks.isEmpty {
                        savingsGroup("Unreferenced Context Blocks (\(report.unreferencedBlocks.count)) — \(Format.cost(report.unreferencedBlocks.reduce(0) { $0 + $1.wastedCostUsd }))",
                                     note: "Large CLAUDE.md / system-reminder blocks loaded into context but seemingly never referenced downstream. May yield false positives when content influences behavior indirectly.") {
                            ForEach(Array(report.unreferencedBlocks.enumerated()), id: \.offset) { _, b in
                                HStack(alignment: .top) {
                                    Text("Turn \(b.turnIndex + 1)").frame(width: 70, alignment: .leading)
                                    Text(b.label).frame(width: 120, alignment: .leading)
                                    Text(Format.tokens(b.estimatedTokens)).monospacedDigit().frame(width: 70, alignment: .trailing)
                                    Text("\(b.carriedTurns) turns").frame(width: 70, alignment: .trailing)
                                    Text(Format.cost(b.wastedCostUsd)).monospacedDigit().bold()
                                        .foregroundStyle(CostColors.output).frame(width: 70, alignment: .trailing)
                                    Text(b.preview).foregroundStyle(.tertiary).lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .font(.caption)
                            }
                        }
                    }

                    if !report.repeatedBlocks.isEmpty {
                        savingsGroup("Repeated Content Blocks (\(report.repeatedBlocks.count)) — \(Format.cost(report.repeatedBlocks.reduce(0) { $0 + $1.wastedCostUsd }))",
                                     note: "Same content appearing in multiple turns. Could indicate re-reads of the same file or duplicated tool results.",
                                     expanded: false) {
                            ForEach(Array(report.repeatedBlocks.enumerated()), id: \.offset) { _, b in
                                HStack(alignment: .top) {
                                    Text("\(b.occurrences)×").frame(width: 40, alignment: .leading)
                                    Text(b.firstTurn == b.lastTurn ? "turn \(b.firstTurn + 1)" : "turns \(b.firstTurn + 1) → \(b.lastTurn + 1)")
                                        .frame(width: 110, alignment: .leading)
                                    Text(Format.tokens(b.estimatedTokensEach)).monospacedDigit().frame(width: 70, alignment: .trailing)
                                    Text(Format.tokens(b.totalWastedTokens)).monospacedDigit().frame(width: 70, alignment: .trailing)
                                    Text(Format.cost(b.wastedCostUsd)).monospacedDigit().bold()
                                        .foregroundStyle(CostColors.output).frame(width: 70, alignment: .trailing)
                                    Text(b.preview).foregroundStyle(.tertiary).lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .font(.caption)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func savingsGroup<Content: View>(_ title: String, note: String, expanded: Bool = true,
                                             @ViewBuilder content: @escaping () -> Content) -> some View {
        DisclosureGroup(isExpanded: .constant(expanded).animation()) {
            VStack(alignment: .leading, spacing: 5) {
                Text(note).font(.caption2).foregroundStyle(.tertiary)
                content()
            }
            .padding(.top, 4)
        } label: {
            Text(title).font(.callout.bold())
        }
    }
}

// MARK: - Turn-by-turn table

struct TurnByTurnTable: View {
    let turns: [TurnMetrics]
    let contentItems: [ContentItem]
    @State private var expandedTurn: UInt32?

    private var itemsByTurn: [UInt32: [ContentItem]] {
        Dictionary(grouping: contentItems, by: \.turnIndex)
    }

    private var maxTurnCost: Double { turns.map(\.costUsd).max() ?? 0 }

    var body: some View {
        GroupBox("Turn-by-Turn Metrics") {
            VStack(spacing: 0) {
                header
                Divider()
                LazyVStack(spacing: 0) {
                    ForEach(turns) { t in
                        row(t)
                        if expandedTurn == t.turnIndex {
                            expansion(t)
                        }
                        Divider()
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var header: some View {
        HStack {
            Text("#").frame(width: 40, alignment: .leading)
            Text("INPUT").frame(width: 65, alignment: .trailing)
            Text("OUTPUT").frame(width: 65, alignment: .trailing)
            Text("CACHE W").frame(width: 70, alignment: .trailing)
            Text("CACHE R").frame(width: 70, alignment: .trailing)
            Text("HIT").frame(width: 60, alignment: .trailing)
            Text("CUMULATIVE").frame(width: 90, alignment: .trailing)
            Text("COST").frame(width: 70, alignment: .trailing)
            Spacer()
            Text("TIME").frame(width: 120, alignment: .trailing)
        }
        .font(.caption2.bold()).foregroundStyle(.secondary)
        .padding(.vertical, 5)
    }

    private func costColor(_ cost: Double) -> Color {
        guard maxTurnCost > 0 else { return CostColors.cacheRead }
        let ratio = cost / maxTurnCost
        if ratio >= 0.66 { return CostColors.output }
        if ratio >= 0.33 { return CostColors.cacheWrite }
        return CostColors.cacheRead
    }

    private func row(_ t: TurnMetrics) -> some View {
        Button {
            expandedTurn = expandedTurn == t.turnIndex ? nil : t.turnIndex
        } label: {
            HStack {
                Text(String(t.turnIndex + 1)).frame(width: 40, alignment: .leading)
                Text(Format.tokens(t.inputTokens)).frame(width: 65, alignment: .trailing)
                Text(Format.tokens(t.outputTokens)).frame(width: 65, alignment: .trailing)
                Text(Format.tokens(t.cacheWriteTokens)).frame(width: 70, alignment: .trailing)
                Text(Format.tokens(t.cacheReadTokens)).frame(width: 70, alignment: .trailing)
                Text(Format.percent(t.cacheHitRate)).frame(width: 60, alignment: .trailing)
                Text(Format.tokens(t.cumulativeContext)).frame(width: 90, alignment: .trailing)
                Text(Format.cost(t.costUsd)).bold().foregroundStyle(costColor(t.costUsd))
                    .frame(width: 70, alignment: .trailing)
                Spacer()
                Text(Format.parseDate(t.timestamp).map { $0.formatted(date: .omitted, time: .shortened) } ?? "—")
                    .frame(width: 120, alignment: .trailing).foregroundStyle(.secondary)
            }
            .font(.caption).monospacedDigit()
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(t.cacheHitRate < 0.3 ? CostColors.output.opacity(0.04) : .clear)
        .background(expandedTurn == t.turnIndex ? CostColors.primary.opacity(0.06) : .clear)
    }

    @ViewBuilder
    private func expansion(_ t: TurnMetrics) -> some View {
        let items = itemsByTurn[t.turnIndex] ?? []
        VStack(alignment: .leading, spacing: 3) {
            if items.isEmpty {
                Text("No content details available for this turn.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 8) {
                        Circle().fill(CategoryColors.color(item.category)).frame(width: 7, height: 7)
                        Text(item.category).frame(width: 110, alignment: .leading)
                        Text(item.toolName ?? "—").frame(width: 90, alignment: .leading)
                        Text(item.source.map { Format.path($0) } ?? item.preview)
                            .lineLimit(1).truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(.secondary)
                        Text(Format.tokens(item.estimatedTokens)).monospacedDigit()
                            .frame(width: 70, alignment: .trailing)
                    }
                    .font(.caption)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CostColors.primary.opacity(0.03))
    }
}
