import SwiftUI
import TokenWiseCore

enum MainTab: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case sessions = "Sessions"
    case projects = "Projects"
    case analyze = "Analyze"
    var id: String { rawValue }
}

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @State private var tab: MainTab = .overview

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Group {
                if model.loading && model.overview == nil {
                    ProgressView("Loading usage data…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = model.error {
                    Text("Error: \(error)").foregroundStyle(.red).padding()
                } else if let overview = model.overview {
                    switch tab {
                    case .overview: OverviewTab(overview: overview, sessions: model.sessions)
                    case .sessions: SessionsTab(sessions: model.sessions)
                    case .projects: ProjectsTab(projects: overview.projectSummaries)
                    case .analyze: AnalyzeTab()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Text("Token Wise").font(.title2.bold())
            Picker("", selection: $tab) {
                ForEach(MainTab.allCases) { t in
                    Text(t == .sessions ? "Sessions (\(model.sessions.count))" : t.rawValue).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 460)
            Spacer()
            if model.loading { ProgressView().controlSize(.small) }
            Button { model.load(force: true) } label: { Image(systemName: "arrow.clockwise") }
                .disabled(model.loading)
                .keyboardShortcut("r")
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }
}

// MARK: - Overview

struct OverviewTab: View {
    let overview: OverviewMetrics
    let sessions: [SessionSummary]

    private var fallbackCount: Int { sessions.filter { $0.pricedByFallback }.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                    MetricCard(label: "Total Cost", value: Format.cost(overview.totalCostUsd),
                               sub: overview.totalSessions > 0 ? "\(Format.cost(overview.totalCostUsd / Double(overview.totalSessions))) avg/session" : nil)
                    MetricCard(label: "Sessions", value: String(overview.totalSessions), sub: nil)
                    MetricCard(label: "Cache Hit Rate", value: Format.percent(overview.avgCacheHitRate), sub: "higher is better")
                    MetricCard(label: "System Overhead", value: Format.tokens(overview.estimatedSystemOverheadTokens), sub: "median/session")
                    MetricCard(label: "Input", value: Format.tokens(overview.totalInputTokens), sub: Format.cost(overview.costBreakdown.inputCost))
                    MetricCard(label: "Output", value: Format.tokens(overview.totalOutputTokens), sub: Format.cost(overview.costBreakdown.outputCost))
                    MetricCard(label: "Cache Read", value: Format.tokens(overview.totalCacheReadTokens), sub: Format.cost(overview.costBreakdown.cacheReadCost))
                    MetricCard(label: "Cache Write", value: Format.tokens(overview.totalCacheWriteTokens), sub: Format.cost(overview.costBreakdown.cacheWriteCost))
                }

                CostBreakdownBar(breakdown: overview.costBreakdown)

                if fallbackCount > 0 {
                    Label("\(fallbackCount) session\(fallbackCount == 1 ? "" : "s") priced with the default Sonnet-class fallback (model not in the pricing table) — those totals are approximate.",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }

                GroupBox("Top Projects by Cost") {
                    VStack(spacing: 0) {
                        ForEach(overview.projectSummaries.prefix(10)) { p in
                            HStack {
                                Text(Format.path(p.project)).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Text("\(p.sessionCount) sessions").foregroundStyle(.secondary).font(.caption)
                                Text(Format.cost(p.totalCostUsd)).monospacedDigit().bold().frame(width: 90, alignment: .trailing)
                            }
                            .padding(.vertical, 5)
                            Divider()
                        }
                    }
                }
            }
            .padding(20)
        }
    }
}

struct MetricCard: View {
    let label: String
    let value: String
    let sub: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.title.bold()).minimumScaleFactor(0.6).lineLimit(1)
            Text(label.uppercased()).font(.caption2).foregroundStyle(.secondary)
            Text(sub ?? " ").font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct CostBreakdownBar: View {
    let breakdown: CostBreakdown
    private var segments: [(String, Double, Color)] {
        [("Output", breakdown.outputCost, .blue),
         ("Cache Write", breakdown.cacheWriteCost, .orange),
         ("Input", breakdown.inputCost, .green),
         ("Cache Read", breakdown.cacheReadCost, .teal)]
    }
    var body: some View {
        let total = max(breakdown.totalCost, 0.0001)
        GroupBox("Cost Breakdown") {
            VStack(alignment: .leading, spacing: 10) {
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        ForEach(segments, id: \.0) { seg in
                            Rectangle().fill(seg.2).frame(width: geo.size.width * (seg.1 / total))
                        }
                    }
                }
                .frame(height: 22).clipShape(RoundedRectangle(cornerRadius: 5))
                HStack(spacing: 16) {
                    ForEach(segments, id: \.0) { seg in
                        HStack(spacing: 5) {
                            Circle().fill(seg.2).frame(width: 9, height: 9)
                            Text("\(seg.0): \(Format.cost(seg.1))").font(.caption)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Sessions / Projects

struct SessionsTab: View {
    let sessions: [SessionSummary]
    @State private var filter = ""

    private var filtered: [SessionSummary] {
        guard !filter.isEmpty else { return sessions }
        let q = filter.lowercased()
        return sessions.filter {
            $0.project.lowercased().contains(q) || ($0.title ?? "").lowercased().contains(q)
                || $0.source.lowercased().contains(q) || ($0.gitBranch ?? "").lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Filter by project, branch, title, or source…", text: $filter)
                    .textFieldStyle(.roundedBorder).frame(maxWidth: 400)
                Text("\(filtered.count) sessions").foregroundStyle(.secondary).font(.caption)
                Spacer()
            }.padding(12)
            Table(filtered) {
                TableColumn("Project") { Text(Format.path($0.project)).lineLimit(1).truncationMode(.middle) }
                TableColumn("Title") { Text($0.title ?? "—").lineLimit(1) }
                TableColumn("Cost") { Text(Format.cost($0.estimatedCostUsd)).monospacedDigit() }
                TableColumn("Cache Hit") { Text(Format.percent($0.cacheHitRate)).monospacedDigit() }
                TableColumn("Input") { Text(Format.tokens($0.totalInputTokens)).monospacedDigit() }
                TableColumn("Output") { Text(Format.tokens($0.totalOutputTokens)).monospacedDigit() }
                TableColumn("Msgs") { Text(String($0.messageCount)).monospacedDigit() }
                TableColumn("Source") { Text($0.source) }
            }
        }
    }
}

struct ProjectsTab: View {
    let projects: [ProjectSummary]
    var body: some View {
        Table(projects) {
            TableColumn("Project") { Text(Format.path($0.project)).lineLimit(1).truncationMode(.middle) }
            TableColumn("Sessions") { Text(String($0.sessionCount)).monospacedDigit() }
            TableColumn("Total Cost") { Text(Format.cost($0.totalCostUsd)).monospacedDigit() }
            TableColumn("Cache Hit") { Text(Format.percent($0.avgCacheHitRate)).monospacedDigit() }
            TableColumn("Input") { Text(Format.tokens($0.totalInputTokens)).monospacedDigit() }
            TableColumn("Output") { Text(Format.tokens($0.totalOutputTokens)).monospacedDigit() }
        }
    }
}
