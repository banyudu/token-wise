import Foundation

// MARK: - Raw transcript decode types (Claude JSONL)

public struct CacheCreationDetail: Decodable {
    public var ephemeral_5m_input_tokens: UInt64?
    public var ephemeral_1h_input_tokens: UInt64?
}

public struct TokenUsage: Decodable {
    public var input_tokens: UInt64?
    public var cache_creation_input_tokens: UInt64?
    public var cache_read_input_tokens: UInt64?
    public var output_tokens: UInt64?
    public var service_tier: String?
    public var cache_creation: CacheCreationDetail?
}

public struct ClaudeMessageInner: Decodable {
    public var id: String?
    public var usage: TokenUsage?
    public var role: String?
    public var content: JSONValue?
    public var model: String?
}

public struct ClaudeMessage: Decodable {
    public var type: String?
    public var message: ClaudeMessageInner?
    public var timestamp: String?
    public var cwd: String?
    public var sessionId: String?
    public var gitBranch: String?
    public var requestId: String?

    /// Streaming writes one JSONL line per content block, each repeating the
    /// SAME API response usage. This key identifies the underlying response so
    /// usage is only counted once (nil = no id, count it).
    public var usageDedupeKey: String? { message?.id ?? requestId }
}

// MARK: - Output types

public struct CostBreakdown: Codable, Equatable {
    public var inputCost: Double = 0
    public var outputCost: Double = 0
    public var cacheWriteCost: Double = 0
    public var cacheReadCost: Double = 0
    public var totalCost: Double = 0

    public init(inputCost: Double = 0, outputCost: Double = 0,
                cacheWriteCost: Double = 0, cacheReadCost: Double = 0,
                totalCost: Double = 0) {
        self.inputCost = inputCost
        self.outputCost = outputCost
        self.cacheWriteCost = cacheWriteCost
        self.cacheReadCost = cacheReadCost
        self.totalCost = totalCost
    }

    public mutating func add(_ other: CostBreakdown) {
        inputCost += other.inputCost
        outputCost += other.outputCost
        cacheWriteCost += other.cacheWriteCost
        cacheReadCost += other.cacheReadCost
        totalCost += other.totalCost
    }
}

public struct SessionSummary: Codable, Identifiable, Hashable {
    public static func == (lhs: SessionSummary, rhs: SessionSummary) -> Bool {
        lhs.sessionId == rhs.sessionId && lhs.lastTimestamp == rhs.lastTimestamp
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(sessionId)
    }

    public var sessionId: String
    public var project: String
    public var gitBranch: String?
    public var title: String?
    public var messageCount: UInt32
    public var totalInputTokens: UInt64
    public var totalOutputTokens: UInt64
    public var totalCacheWriteTokens: UInt64
    public var totalCacheReadTokens: UInt64
    public var cacheHitRate: Double
    public var estimatedCostUsd: Double
    public var costBreakdown: CostBreakdown
    public var firstTimestamp: String?
    public var lastTimestamp: String?
    public var firstTurnCacheWrite: UInt64
    public var subagentCount: UInt32
    public var subagentCostUsd: Double
    public var source: String
    public var model: String?
    public var pricedByFallback: Bool
    public var ephemeral5mTokens: UInt64
    public var ephemeral1hTokens: UInt64
    /// Cost attributed to each local-timezone day ("yyyy-MM-dd") the session
    /// actually ran, from per-response timestamps. Long sessions no longer
    /// dump their whole cost on the day they ended. Nil for sources without
    /// per-response data (Codex).
    public var dailyCostUsd: [String: Double]? = nil

    public var id: String { sessionId }
}

public struct TurnMetrics: Codable, Identifiable {
    public var turnIndex: UInt32
    public var role: String
    public var inputTokens: UInt64
    public var outputTokens: UInt64
    public var cacheWriteTokens: UInt64
    public var cacheReadTokens: UInt64
    public var cumulativeContext: UInt64
    public var cacheHitRate: Double
    public var costUsd: Double
    public var timestamp: String?

    public var id: UInt32 { turnIndex }
}

public struct ContentCategory: Codable, Identifiable {
    public var category: String
    public var subcategory: String?
    public var estimatedTokens: UInt64
    public var byteSize: UInt64
    public var count: UInt32
    public var percentage: Double

    public var id: String { subcategory.map { "\(category):\($0)" } ?? category }
}

public struct ContentItem: Codable, Identifiable {
    public var category: String
    public var toolName: String?
    public var source: String?
    public var estimatedTokens: UInt64
    public var preview: String
    public var fullContent: String
    public var turnIndex: UInt32

    public var id: String { "\(turnIndex)-\(category)-\(source ?? preview)" }
}

public struct ContentAnalysis: Codable {
    public var categories: [ContentCategory]
    public var totalEstimatedTokens: UInt64
    public var allItems: [ContentItem]
    public var suggestions: [String]
}

public struct SessionDetail: Codable {
    public var summary: SessionSummary
    public var turns: [TurnMetrics]
    public var contentAnalysis: ContentAnalysis?
    public var cacheSavings: CacheSavingsReport?
}

public struct ProjectSummary: Codable, Identifiable {
    public var project: String
    public var sessionCount: UInt32
    public var totalCostUsd: Double
    public var totalInputTokens: UInt64
    public var totalOutputTokens: UInt64
    public var totalCacheWriteTokens: UInt64
    public var totalCacheReadTokens: UInt64
    public var avgCacheHitRate: Double

    public var id: String { project }
}

public struct DailyCost: Codable, Identifiable {
    public var date: String
    public var costUsd: Double
    public var costBreakdown: CostBreakdown
    public var inputTokens: UInt64
    public var outputTokens: UInt64
    public var cacheWriteTokens: UInt64
    public var cacheReadTokens: UInt64
    public var source: String

    public var id: String { date }
}

public struct HourlyCost: Codable, Identifiable {
    public var hour: String
    public var costUsd: Double
    public var costBreakdown: CostBreakdown
    public var inputTokens: UInt64
    public var outputTokens: UInt64
    public var cacheWriteTokens: UInt64
    public var cacheReadTokens: UInt64
    public var source: String

    public var id: String { hour }
}

public struct OverviewMetrics: Codable {
    public var totalSessions: UInt32
    public var totalCostUsd: Double
    public var totalInputTokens: UInt64
    public var totalOutputTokens: UInt64
    public var totalCacheWriteTokens: UInt64
    public var totalCacheReadTokens: UInt64
    public var avgCacheHitRate: Double
    public var costBreakdown: CostBreakdown
    public var estimatedSystemOverheadTokens: UInt64
    public var dailyCosts: [DailyCost]
    public var hourlyCosts: [HourlyCost]
    public var projectSummaries: [ProjectSummary]
    public var topSessions: [SessionSummary]
}
