import Charts
import SwiftUI
import TokenWiseCore

/// Shared cost-component colors (match the web app's palette).
enum CostColors {
    static let output = Color(red: 0.90, green: 0.30, blue: 0.24)      // #e74c3c
    static let cacheWrite = Color(red: 0.95, green: 0.61, blue: 0.07)  // #f39c12
    static let input = Color(red: 0.15, green: 0.68, blue: 0.38)       // #27ae60
    static let cacheRead = Color(red: 0.10, green: 0.74, blue: 0.61)   // #1abc9c
    static let primary = Color(red: 0.29, green: 0.56, blue: 0.85)     // #4a90d9

    static let scale: KeyValuePairs<String, Color> = [
        "Output": output, "Cache Write": cacheWrite, "Input": input, "Cache Read": cacheRead,
    ]
}

// MARK: - Daily / hourly stacked cost chart

struct DailyCostChart: View {
    let dailyCosts: [DailyCost]
    let hourlyCosts: [HourlyCost]
    let showHourly: Bool

    private struct Slice: Identifiable {
        let bucket: String
        let component: String
        let cost: Double
        var id: String { "\(bucket)-\(component)" }
    }

    private var slices: [Slice] {
        if showHourly {
            return hourlyCosts.flatMap { h -> [Slice] in
                let label = String(h.hour.suffix(2)) + ":00"
                return sliceBreakdown(bucket: label, h.costBreakdown)
            }
        }
        return dailyCosts.flatMap { d -> [Slice] in
            sliceBreakdown(bucket: String(d.date.dropFirst(5)), d.costBreakdown)
        }
    }

    private func sliceBreakdown(bucket: String, _ bd: CostBreakdown) -> [Slice] {
        [Slice(bucket: bucket, component: "Output", cost: bd.outputCost),
         Slice(bucket: bucket, component: "Cache Write", cost: bd.cacheWriteCost),
         Slice(bucket: bucket, component: "Input", cost: bd.inputCost),
         Slice(bucket: bucket, component: "Cache Read", cost: bd.cacheReadCost)]
    }

    var body: some View {
        let items = slices
        let count = showHourly ? hourlyCosts.count : dailyCosts.count
        if count > 0 {
            GroupBox("\(showHourly ? "Hourly" : "Daily") Cost (\(count) \(showHourly ? "hours" : "days"))") {
                Chart(items) { s in
                    BarMark(x: .value(showHourly ? "Hour" : "Date", s.bucket),
                            y: .value("Cost", s.cost))
                        .foregroundStyle(by: .value("Component", s.component))
                }
                .chartForegroundStyleScale(CostColors.scale)
                .chartXAxis {
                    AxisMarks { value in
                        // Thin the labels when many buckets are shown.
                        let stride = max(1, count / 16)
                        if value.index % stride == 0 {
                            AxisValueLabel(orientation: count > 40 ? .verticalReversed : .horizontal)
                                .font(.system(size: 9))
                        }
                    }
                }
                .frame(height: 160)
                .padding(.top, 6)
            }
        }
    }
}

// MARK: - Session context growth chart (per-turn / cumulative / cost)

enum GrowthMode: String, CaseIterable, Identifiable {
    case perTurn = "Per Turn"
    case cumulative = "Cumulative"
    case cost = "Cost"
    case cumulativeCost = "Cum. Cost"
    var id: String { rawValue }
}

struct ContextGrowthChart: View {
    let turns: [TurnMetrics]
    @State private var mode: GrowthMode = .perTurn

    private var cumulativeCosts: [Double] {
        var sum = 0.0
        return turns.map { sum += $0.costUsd; return sum }
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Context Growth").font(.headline)
                    Spacer()
                    Picker("", selection: $mode) {
                        ForEach(GrowthMode.allCases) { m in Text(m.rawValue).tag(m) }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 360)
                }

                summaryLine

                chart.frame(height: 180)
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var summaryLine: some View {
        let totalCost = turns.reduce(0.0) { $0 + $1.costUsd }
        switch mode {
        case .perTurn:
            let maxPerTurn = turns.map { $0.inputTokens + $0.cacheWriteTokens + $0.cacheReadTokens }.max() ?? 0
            let maxCumulative = turns.map(\.cumulativeContext).max() ?? 0
            Text("Max per turn: \(Format.tokens(maxPerTurn))  ·  Total cumulative: \(Format.tokens(maxCumulative))")
                .font(.caption).foregroundStyle(.secondary)
        case .cost:
            let maxCost = turns.map(\.costUsd).max() ?? 0
            Text("Total cost: \(Format.cost(totalCost))  ·  Max per turn: \(Format.cost(maxCost))")
                .font(.caption).foregroundStyle(.secondary)
        case .cumulative, .cumulativeCost:
            Text("Total cost: \(Format.cost(totalCost))")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var chart: some View {
        switch mode {
        case .perTurn:
            Chart(turns) { t in
                BarMark(x: .value("Turn", Int(t.turnIndex) + 1),
                        y: .value("Tokens", Double(t.cacheWriteTokens)))
                    .foregroundStyle(by: .value("Component", "Cache Write"))
                BarMark(x: .value("Turn", Int(t.turnIndex) + 1),
                        y: .value("Tokens", Double(t.inputTokens)))
                    .foregroundStyle(by: .value("Component", "Input"))
                BarMark(x: .value("Turn", Int(t.turnIndex) + 1),
                        y: .value("Tokens", Double(t.cacheReadTokens)))
                    .foregroundStyle(by: .value("Component", "Cache Read"))
            }
            .chartForegroundStyleScale(["Cache Write": CostColors.cacheWrite,
                                        "Input": CostColors.input,
                                        "Cache Read": CostColors.cacheRead])
        case .cumulative:
            Chart(turns) { t in
                AreaMark(x: .value("Turn", Int(t.turnIndex) + 1),
                         y: .value("Tokens", Double(t.cumulativeContext)))
                    .foregroundStyle(CostColors.primary.opacity(0.25))
                LineMark(x: .value("Turn", Int(t.turnIndex) + 1),
                         y: .value("Tokens", Double(t.cumulativeContext)))
                    .foregroundStyle(CostColors.primary)
            }
        case .cost:
            Chart(turns) { t in
                BarMark(x: .value("Turn", Int(t.turnIndex) + 1),
                        y: .value("Cost", t.costUsd))
                    .foregroundStyle(CostColors.output)
            }
        case .cumulativeCost:
            let cum = cumulativeCosts
            Chart(Array(turns.enumerated()), id: \.element.turnIndex) { i, t in
                AreaMark(x: .value("Turn", Int(t.turnIndex) + 1),
                         y: .value("Cost", cum[i]))
                    .foregroundStyle(CostColors.output.opacity(0.2))
                LineMark(x: .value("Turn", Int(t.turnIndex) + 1),
                         y: .value("Cost", cum[i]))
                    .foregroundStyle(CostColors.output)
            }
        }
    }
}

// MARK: - Content-category donut

enum CategoryColors {
    static let map: [String: Color] = [
        "File Reads": Color(red: 0.29, green: 0.56, blue: 0.85),
        "Code Search": Color(red: 0.48, green: 0.41, blue: 0.93),
        "Shell Commands": Color(red: 0.90, green: 0.30, blue: 0.24),
        "File Edits": Color(red: 0.95, green: 0.61, blue: 0.07),
        "Web Content": Color(red: 0.10, green: 0.74, blue: 0.61),
        "Subagents": Color(red: 0.61, green: 0.35, blue: 0.71),
        "External Tools": Color(red: 0.15, green: 0.68, blue: 0.38),
        "Thinking": Color(red: 0.58, green: 0.65, blue: 0.65),
        "Assistant Text": Color(red: 0.20, green: 0.60, blue: 0.86),
        "User Prompts": Color(red: 0.90, green: 0.49, blue: 0.13),
        "Other Tools": Color(red: 0.74, green: 0.76, blue: 0.78),
        "Other": Color(red: 0.74, green: 0.76, blue: 0.78),
    ]

    static func color(_ category: String) -> Color {
        map[category] ?? Color(red: 0.74, green: 0.76, blue: 0.78)
    }
}

struct DonutChart: View {
    let categories: [ContentCategory]
    let total: UInt64

    private struct Segment: Identifiable {
        let category: String
        let tokens: UInt64
        var id: String { category }
    }

    private var segments: [Segment] {
        var merged: [String: UInt64] = [:]
        for c in categories { merged[c.category, default: 0] += c.estimatedTokens }
        return merged.map { Segment(category: $0.key, tokens: $0.value) }
            .filter { total > 0 && Double($0.tokens) / Double(total) >= 0.005 }
            .sorted { $0.tokens > $1.tokens }
    }

    var body: some View {
        if total > 0 {
            Chart(segments) { seg in
                SectorMark(angle: .value("Tokens", Double(seg.tokens)),
                           innerRadius: .ratio(0.6), angularInset: 1)
                    .foregroundStyle(CategoryColors.color(seg.category))
            }
            .chartBackground { _ in
                VStack(spacing: 2) {
                    Text(Format.tokens(total)).font(.headline)
                    Text("est. tokens").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 180, height: 180)
        }
    }
}
