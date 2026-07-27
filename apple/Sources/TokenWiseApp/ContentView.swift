import SwiftUI
import TokenWiseCore

enum MainTab: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case sessions = "Sessions"
    case projects = "Projects"
    case analyze = "Analyze"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overview: return "chart.bar.xaxis"
        case .sessions: return "list.bullet.rectangle"
        case .projects: return "folder"
        case .analyze: return "sparkles"
        }
    }
}

// Sortable, non-optional accessors for Table comparators.
extension SessionSummary {
    var dateKey: String { firstTimestamp ?? "" }
    var titleText: String { title ?? "" }
    var branchText: String { gitBranch ?? "" }
    var durationMs: Double { Format.sessionDurationMs(self) }
}

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @State private var tab: MainTab? = .overview
    @State private var path: [SessionSummary] = []

    var body: some View {
        if model.needsOnboarding {
            OnboardingView()
        } else {
            NavigationSplitView {
                sidebar
            } detail: {
                NavigationStack(path: $path) {
                    tabRoot
                        .navigationDestination(for: SessionSummary.self) { session in
                            SessionDetailScreen(session: session)
                        }
                }
            }
        }
    }

    private var sidebar: some View {
        List(selection: $tab) {
            Section("Usage") {
                ForEach(MainTab.allCases) { t in
                    Label(t.rawValue, systemImage: t.icon)
                        .badge(t == .sessions ? model.sessions.count : 0)
                        .tag(t)
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 260)
    }

    @ViewBuilder
    private var tabRoot: some View {
        Group {
            if model.loading && model.overview == nil {
                ProgressView("Loading usage data…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = model.error {
                ContentUnavailableView("Couldn't load usage data", systemImage: "exclamationmark.triangle",
                                       description: Text(error))
            } else if let overview = model.overview {
                switch tab ?? .overview {
                case .overview:
                    OverviewTab(overview: overview, sessions: model.sessions,
                                showHourly: model.showHourly)
                case .sessions:
                    SessionsTab(sessions: model.sessions) { path.append($0) }
                case .projects:
                    ProjectsTab(projects: overview.projectSummaries) { project in
                        model.projectFilter = project
                        tab = .sessions
                    }
                case .analyze:
                    AnalyzeTab()
                }
            }
        }
        .navigationTitle(tab?.rawValue ?? "Token Wise")
        .navigationSubtitle(subtitle)
        .toolbar { toolbarContent }
        .safeAreaInset(edge: .top, spacing: 0) { activeFilterBar }
    }

    private var subtitle: String {
        guard let overview = model.overview else { return "" }
        return "\(Format.cost(overview.totalCostUsd)) · \(overview.totalSessions) sessions"
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            if model.loading { ProgressView().controlSize(.small) }

            Picker(selection: $model.sourceFilter) {
                ForEach(SourceFilter.allCases) { s in Text(s.rawValue).tag(s) }
            } label: {
                Label("Source", systemImage: "square.stack.3d.up")
            }
            .pickerStyle(.menu)

            Picker(selection: $model.dateRange) {
                ForEach(DateRange.allCases) { r in Text(r.rawValue).tag(r) }
            } label: {
                Label("Range", systemImage: "calendar")
            }
            .pickerStyle(.menu)

            Button {
                model.load(force: true)
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(model.loading)
            .keyboardShortcut("r")

            SettingsLink {
                Label("Settings", systemImage: "gearshape")
            }
        }
    }

    /// Secondary bar shown only when a custom date range or project filter is active.
    @ViewBuilder
    private var activeFilterBar: some View {
        if model.dateRange == .custom || model.projectFilter != nil {
            HStack(spacing: 12) {
                if model.dateRange == .custom {
                    DatePicker("From", selection: $model.customFrom, displayedComponents: .date)
                        .datePickerStyle(.compact).fixedSize()
                    DatePicker("To", selection: $model.customTo, displayedComponents: .date)
                        .datePickerStyle(.compact).fixedSize()
                }
                if let project = model.projectFilter {
                    HStack(spacing: 5) {
                        Image(systemName: "folder")
                        Text(Format.path(project)).lineLimit(1).truncationMode(.middle)
                        Button {
                            model.projectFilter = nil
                        } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain)
                    }
                    .font(.caption)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.selection.opacity(0.5), in: Capsule())
                }
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(.bar)
            .overlay(alignment: .bottom) { Divider() }
        }
    }
}

// MARK: - Session detail (native push)

struct SessionDetailScreen: View {
    let session: SessionSummary
    @State private var detail: SessionDetail?
    @State private var failed = false

    var body: some View {
        Group {
            if let detail {
                SessionDetailView(detail: detail)
            } else if failed {
                ContentUnavailableView("No detail available", systemImage: "doc.questionmark",
                                       description: Text("Turn-level detail exists only for Claude transcripts."))
            } else {
                ProgressView("Loading session detail…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(session.title ?? Format.path(session.project))
        .task(id: session.sessionId) {
            let id = session.sessionId
            let loaded = await Task.detached(priority: .userInitiated) {
                ClaudeParser.sessionDetail(id: id, pricing: PricingTable.load())
            }.value
            detail = loaded
            failed = loaded == nil
        }
    }
}

// MARK: - Overview

struct OverviewTab: View {
    let overview: OverviewMetrics
    let sessions: [SessionSummary]
    let showHourly: Bool

    private var fallbackCount: Int { sessions.filter { $0.pricedByFallback }.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                metricCards

                CostBreakdownBar(breakdown: overview.costBreakdown)

                if fallbackCount > 0 {
                    Label("\(fallbackCount) session\(fallbackCount == 1 ? "" : "s") priced with the default Sonnet-class fallback (model not in the pricing table) — those totals are approximate.",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }

                ContextComposition(overview: overview)

                DailyCostChart(dailyCosts: overview.dailyCosts,
                               hourlyCosts: overview.hourlyCosts,
                               showHourly: showHourly)

                RecommendationsView(sessions: sessions, overview: overview)

                SavingsPotentialView(overview: overview, sessions: sessions)

                GroupBox("Top Sessions by Cost") {
                    VStack(spacing: 0) {
                        ForEach(overview.topSessions) { s in
                            NavigationLink(value: s) {
                                HStack {
                                    Text(Format.path(s.project)).lineLimit(1).truncationMode(.middle)
                                        .frame(width: 200, alignment: .leading)
                                    Text(s.title ?? "—").lineLimit(1).foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    sourceBadge(s.source)
                                    Text(Format.percent(s.cacheHitRate)).monospacedDigit()
                                        .foregroundStyle(.secondary).frame(width: 60, alignment: .trailing)
                                    Text(Format.cost(s.estimatedCostUsd)).monospacedDigit().bold()
                                        .frame(width: 80, alignment: .trailing)
                                    Image(systemName: "chevron.right")
                                        .font(.caption2).foregroundStyle(.tertiary)
                                }
                                .font(.callout)
                                .padding(.vertical, 5)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    private var metricCards: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
            let totalMs = sessions.reduce(0.0) { $0 + Format.sessionDurationMs($1) }
            MetricCard(label: "Total Cost", value: Format.cost(overview.totalCostUsd),
                       sub: overview.totalSessions > 0 ? "\(Format.cost(overview.totalCostUsd / Double(overview.totalSessions))) avg/session" : nil)
            MetricCard(label: "Sessions", value: String(overview.totalSessions),
                       sub: totalMs > 0 ? "\(Format.duration(totalMs)) total" : nil)
            MetricCard(label: "Cache Hit Rate", value: Format.percent(overview.avgCacheHitRate), sub: "higher is better")
            MetricCard(label: "System Overhead", value: Format.tokens(overview.estimatedSystemOverheadTokens), sub: "median/session")
            MetricCard(label: "Input", value: Format.tokens(overview.totalInputTokens), sub: Format.cost(overview.costBreakdown.inputCost))
            MetricCard(label: "Output", value: Format.tokens(overview.totalOutputTokens), sub: Format.cost(overview.costBreakdown.outputCost))
            MetricCard(label: "Cache Read", value: Format.tokens(overview.totalCacheReadTokens), sub: Format.cost(overview.costBreakdown.cacheReadCost))
            MetricCard(label: "Cache Write", value: Format.tokens(overview.totalCacheWriteTokens), sub: Format.cost(overview.costBreakdown.cacheWriteCost))
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
        [("Output", breakdown.outputCost, CostColors.output),
         ("Cache Write", breakdown.cacheWriteCost, CostColors.cacheWrite),
         ("Input", breakdown.inputCost, CostColors.input),
         ("Cache Read", breakdown.cacheReadCost, CostColors.cacheRead)]
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
                            Text("\(seg.0): \(Format.cost(seg.1)) (\(Format.percent(seg.1 / total)))").font(.caption)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Sessions

struct SessionsTab: View {
    let sessions: [SessionSummary]
    let onSelectSession: (SessionSummary) -> Void

    @State private var filter = ""
    @State private var sortOrder = [KeyPathComparator(\SessionSummary.dateKey, order: .reverse)]
    @State private var selection: SessionSummary.ID?

    private var filtered: [SessionSummary] {
        var result = sessions
        if !filter.isEmpty {
            let q = filter.lowercased()
            result = result.filter {
                $0.project.lowercased().contains(q) || ($0.title ?? "").lowercased().contains(q)
                    || $0.source.lowercased().contains(q) || ($0.gitBranch ?? "").lowercased().contains(q)
            }
        }
        return result.sorted(using: sortOrder)
    }

    var body: some View {
        Table(filtered, selection: $selection, sortOrder: $sortOrder) {
            Group {
                TableColumn("Project", value: \SessionSummary.project) {
                    Text(Format.path($0.project)).lineLimit(1).truncationMode(.middle)
                }
                .width(min: 140, ideal: 200)
                TableColumn("Title", value: \SessionSummary.titleText) { Text($0.title ?? "—").lineLimit(1) }
                    .width(min: 120, ideal: 240)
                TableColumn("Branch", value: \SessionSummary.branchText) { Text($0.gitBranch ?? "—").lineLimit(1) }
                    .width(min: 70, ideal: 110)
                TableColumn("Msgs", value: \SessionSummary.messageCount) { Text(String($0.messageCount)).monospacedDigit() }
                    .width(48)
                TableColumn("Duration", value: \SessionSummary.durationMs) { Text(Format.duration($0.durationMs)).monospacedDigit() }
                    .width(70)
                TableColumn("Cost", value: \SessionSummary.estimatedCostUsd) {
                    Text(Format.cost($0.estimatedCostUsd)).monospacedDigit().bold()
                }
                .width(70)
                TableColumn("Cache Hit", value: \SessionSummary.cacheHitRate) { Text(Format.percent($0.cacheHitRate)).monospacedDigit() }
                    .width(66)
            }
            Group {
                TableColumn("Input", value: \SessionSummary.totalInputTokens) { Text(Format.tokens($0.totalInputTokens)).monospacedDigit() }
                    .width(60)
                TableColumn("Output", value: \SessionSummary.totalOutputTokens) { Text(Format.tokens($0.totalOutputTokens)).monospacedDigit() }
                    .width(60)
                TableColumn("Cache W", value: \SessionSummary.totalCacheWriteTokens) { Text(Format.tokens($0.totalCacheWriteTokens)).monospacedDigit() }
                    .width(64)
                TableColumn("Cache R", value: \SessionSummary.totalCacheReadTokens) { Text(Format.tokens($0.totalCacheReadTokens)).monospacedDigit() }
                    .width(64)
                TableColumn("Subagents") { s in
                    Text(s.subagentCount > 0 ? "\(s.subagentCount) (\(Format.cost(s.subagentCostUsd)))" : "—")
                        .monospacedDigit()
                }
                .width(80)
                TableColumn("Source") { s in
                    HStack(spacing: 5) {
                        sourceBadge(s.source)
                        if let model = displayModel(s.model) {
                            Text(model).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                .width(min: 90, ideal: 150)
                TableColumn("Date", value: \SessionSummary.dateKey) { s in
                    Text(Format.parseDate(s.firstTimestamp).map {
                        $0.formatted(.dateTime.month(.abbreviated).day().hour().minute())
                    } ?? "—")
                }
                .width(110)
            }
        }
        .searchable(text: $filter, placement: .toolbar,
                    prompt: "Project, branch, title, or source")
        .onChange(of: selection) { _, newValue in
            guard let id = newValue,
                  let session = sessions.first(where: { $0.sessionId == id }) else { return }
            selection = nil
            onSelectSession(session)
        }
    }
}

// MARK: - Projects

struct ProjectsTab: View {
    let projects: [ProjectSummary]
    let onSelectProject: (String) -> Void

    @State private var sortOrder = [KeyPathComparator(\ProjectSummary.totalCostUsd, order: .reverse)]
    @State private var selection: ProjectSummary.ID?

    var body: some View {
        Table(projects.sorted(using: sortOrder), selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Project", value: \ProjectSummary.project) {
                Text(Format.path($0.project)).lineLimit(1).truncationMode(.middle)
            }
            .width(min: 200, ideal: 340)
            TableColumn("Sessions", value: \ProjectSummary.sessionCount) { Text(String($0.sessionCount)).monospacedDigit() }
            TableColumn("Total Cost", value: \ProjectSummary.totalCostUsd) {
                Text(Format.cost($0.totalCostUsd)).monospacedDigit().bold()
            }
            TableColumn("Cache Hit", value: \ProjectSummary.avgCacheHitRate) { Text(Format.percent($0.avgCacheHitRate)).monospacedDigit() }
            TableColumn("Input", value: \ProjectSummary.totalInputTokens) { Text(Format.tokens($0.totalInputTokens)).monospacedDigit() }
            TableColumn("Output", value: \ProjectSummary.totalOutputTokens) { Text(Format.tokens($0.totalOutputTokens)).monospacedDigit() }
            TableColumn("Cache W", value: \ProjectSummary.totalCacheWriteTokens) { Text(Format.tokens($0.totalCacheWriteTokens)).monospacedDigit() }
            TableColumn("Cache R", value: \ProjectSummary.totalCacheReadTokens) { Text(Format.tokens($0.totalCacheReadTokens)).monospacedDigit() }
        }
        .onChange(of: selection) { _, newValue in
            guard let project = newValue else { return }
            selection = nil
            onSelectProject(project)
        }
    }
}
