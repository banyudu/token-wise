use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct TokenUsage {
    #[serde(default)]
    pub input_tokens: u64,
    #[serde(default)]
    pub cache_creation_input_tokens: u64,
    #[serde(default)]
    pub cache_read_input_tokens: u64,
    #[serde(default)]
    pub output_tokens: u64,
    #[serde(default)]
    pub service_tier: Option<String>,
    #[serde(default)]
    pub cache_creation: Option<CacheCreationDetail>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct CacheCreationDetail {
    #[serde(default)]
    pub ephemeral_5m_input_tokens: u64,
    #[serde(default)]
    pub ephemeral_1h_input_tokens: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClaudeMessageInner {
    #[serde(default)]
    pub usage: Option<TokenUsage>,
    #[serde(default)]
    pub role: Option<String>,
    #[serde(default)]
    pub content: Option<serde_json::Value>,
    #[serde(default)]
    pub model: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClaudeMessage {
    #[serde(default)]
    pub r#type: String,
    #[serde(default)]
    pub message: Option<ClaudeMessageInner>,
    #[serde(default)]
    pub timestamp: Option<String>,
    #[serde(default)]
    pub cwd: Option<String>,
    #[serde(default, rename = "sessionId")]
    pub session_id: Option<String>,
    #[serde(default, rename = "gitBranch")]
    pub git_branch: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionSummary {
    pub session_id: String,
    pub project: String,
    pub git_branch: Option<String>,
    pub title: Option<String>,
    pub message_count: u32,
    pub total_input_tokens: u64,
    pub total_output_tokens: u64,
    pub total_cache_write_tokens: u64,
    pub total_cache_read_tokens: u64,
    pub cache_hit_rate: f64,
    pub estimated_cost_usd: f64,
    pub cost_breakdown: CostBreakdown,
    pub first_timestamp: Option<String>,
    pub last_timestamp: Option<String>,
    pub subagent_count: u32,
    pub subagent_cost_usd: f64,
    pub source: String,
    pub model: Option<String>,
    pub ephemeral_5m_tokens: u64,
    pub ephemeral_1h_tokens: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TurnMetrics {
    pub turn_index: u32,
    pub role: String,
    pub input_tokens: u64,
    pub output_tokens: u64,
    pub cache_write_tokens: u64,
    pub cache_read_tokens: u64,
    pub cumulative_context: u64,
    pub cache_hit_rate: f64,
    pub cost_usd: f64,
    pub timestamp: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ContentCategory {
    pub category: String,
    pub subcategory: Option<String>,
    pub estimated_tokens: u64,
    pub byte_size: u64,
    pub count: u32,
    pub percentage: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ContentItem {
    pub category: String,
    pub tool_name: Option<String>,
    pub source: Option<String>,
    pub estimated_tokens: u64,
    pub preview: String,
    pub full_content: String,
    pub turn_index: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ContentAnalysis {
    pub categories: Vec<ContentCategory>,
    pub total_estimated_tokens: u64,
    pub all_items: Vec<ContentItem>,
    pub suggestions: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WastedWrite {
    pub turn_index: u32,
    pub wasted_tokens: u64,
    pub wasted_cost_usd: f64,
    pub reason: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InvalidationEvent {
    pub turn_index: u32,
    pub dropped_tokens: u64,
    pub rewrite_cost_usd: f64,
    pub suspected_cause: Option<String>,
    pub suspected_preview: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UnreferencedBlock {
    pub turn_index: u32,
    pub label: String,
    pub estimated_tokens: u64,
    pub carried_turns: u32,
    pub wasted_cost_usd: f64,
    pub preview: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RepeatedBlock {
    pub occurrences: u32,
    pub first_turn: u32,
    pub last_turn: u32,
    pub estimated_tokens_each: u64,
    pub total_wasted_tokens: u64,
    pub wasted_cost_usd: f64,
    pub category: String,
    pub preview: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CacheSavingsReport {
    pub wasted_cache_writes: Vec<WastedWrite>,
    pub invalidation_events: Vec<InvalidationEvent>,
    pub unreferenced_blocks: Vec<UnreferencedBlock>,
    pub repeated_blocks: Vec<RepeatedBlock>,
    pub total_potential_savings_usd: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionDetail {
    pub summary: SessionSummary,
    pub turns: Vec<TurnMetrics>,
    pub content_analysis: Option<ContentAnalysis>,
    pub cache_savings: Option<CacheSavingsReport>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectSummary {
    pub project: String,
    pub session_count: u32,
    pub total_cost_usd: f64,
    pub total_input_tokens: u64,
    pub total_output_tokens: u64,
    pub total_cache_write_tokens: u64,
    pub total_cache_read_tokens: u64,
    pub avg_cache_hit_rate: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DailyCost {
    pub date: String,
    pub cost_usd: f64,
    pub cost_breakdown: CostBreakdown,
    pub input_tokens: u64,
    pub output_tokens: u64,
    pub cache_write_tokens: u64,
    pub cache_read_tokens: u64,
    pub source: String,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct CostBreakdown {
    pub input_cost: f64,
    pub output_cost: f64,
    pub cache_write_cost: f64,
    pub cache_read_cost: f64,
    pub total_cost: f64,
}

impl CostBreakdown {
    pub fn add(&mut self, other: &CostBreakdown) {
        self.input_cost += other.input_cost;
        self.output_cost += other.output_cost;
        self.cache_write_cost += other.cache_write_cost;
        self.cache_read_cost += other.cache_read_cost;
        self.total_cost += other.total_cost;
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OverviewMetrics {
    pub total_sessions: u32,
    pub total_cost_usd: f64,
    pub total_input_tokens: u64,
    pub total_output_tokens: u64,
    pub total_cache_write_tokens: u64,
    pub total_cache_read_tokens: u64,
    pub avg_cache_hit_rate: f64,
    pub cost_breakdown: CostBreakdown,
    pub estimated_system_overhead_tokens: u64,
    pub daily_costs: Vec<DailyCost>,
    pub project_summaries: Vec<ProjectSummary>,
    pub top_sessions: Vec<SessionSummary>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PricingInfo {
    pub input_per_mtok: f64,
    pub cache_write_per_mtok: f64,
    pub cache_read_per_mtok: f64,
    pub output_per_mtok: f64,
}

impl Default for PricingInfo {
    fn default() -> Self {
        // Sonnet 4.6 — used when a model name is unrecognized.
        Self {
            input_per_mtok: 3.0,
            cache_write_per_mtok: 3.75,
            cache_read_per_mtok: 0.30,
            output_per_mtok: 15.0,
        }
    }
}

impl PricingInfo {
    pub fn calculate_cost(
        &self,
        input: u64,
        cache_write: u64,
        cache_read: u64,
        output: u64,
    ) -> CostBreakdown {
        let input_cost = (input as f64 / 1_000_000.0) * self.input_per_mtok;
        let cache_write_cost = (cache_write as f64 / 1_000_000.0) * self.cache_write_per_mtok;
        let cache_read_cost = (cache_read as f64 / 1_000_000.0) * self.cache_read_per_mtok;
        let output_cost = (output as f64 / 1_000_000.0) * self.output_per_mtok;
        CostBreakdown {
            input_cost,
            output_cost,
            cache_write_cost,
            cache_read_cost,
            total_cost: input_cost + cache_write_cost + cache_read_cost + output_cost,
        }
    }
}

/// Resolves any model name to a `PricingInfo`. Holds explicit entries from
/// `~/.claude/readout-pricing.json` plus built-in defaults for both Anthropic
/// and OpenAI/Codex models so the UI never has to pick a model manually.
#[derive(Debug, Clone)]
pub struct PricingTable {
    explicit: std::collections::HashMap<String, PricingInfo>,
    fallback: PricingInfo,
}

impl Default for PricingTable {
    fn default() -> Self {
        Self {
            explicit: std::collections::HashMap::new(),
            fallback: PricingInfo::default(),
        }
    }
}

impl PricingTable {
    pub fn load() -> Self {
        let mut explicit: std::collections::HashMap<String, PricingInfo> =
            std::collections::HashMap::new();

        // Read Claude price overrides if present. Resolves via the sandbox
        // grant when applicable (`~/.claude` is otherwise unreadable in the App
        // Store build); falls back to built-in pricing when not granted.
        if let Some(claude) = crate::grants::claude_root() {
            let path = claude.join("readout-pricing.json");
            if let Ok(content) = std::fs::read_to_string(&path) {
                if let Ok(json) = serde_json::from_str::<serde_json::Value>(&content) {
                    let roots = [json.get("models").cloned(), Some(json.clone())];
                    for root in roots.into_iter().flatten() {
                        let obj = match root.as_object() {
                            Some(o) => o,
                            None => continue,
                        };
                        for (name, entry) in obj {
                            // Skip metadata keys
                            if !entry.is_object() {
                                continue;
                            }
                            let input = entry
                                .get("input")
                                .or_else(|| entry.get("inputPerMillion"))
                                .and_then(|v| v.as_f64());
                            let output = entry
                                .get("output")
                                .or_else(|| entry.get("outputPerMillion"))
                                .and_then(|v| v.as_f64());
                            let cache_write = entry
                                .get("cacheWrite")
                                .or_else(|| entry.get("cacheWritePerMillion"))
                                .and_then(|v| v.as_f64());
                            let cache_read = entry
                                .get("cacheRead")
                                .or_else(|| entry.get("cacheReadPerMillion"))
                                .and_then(|v| v.as_f64());
                            if input.is_none() && output.is_none() {
                                continue;
                            }
                            explicit.insert(
                                name.to_string(),
                                PricingInfo {
                                    input_per_mtok: input.unwrap_or(3.0),
                                    cache_write_per_mtok: cache_write.unwrap_or(3.75),
                                    cache_read_per_mtok: cache_read.unwrap_or(0.30),
                                    output_per_mtok: output.unwrap_or(15.0),
                                },
                            );
                        }
                    }
                }
            }
        }

        Self {
            explicit,
            fallback: PricingInfo::default(),
        }
    }

    /// Look up pricing for a model name. Order:
    /// 1. exact match in explicit overrides
    /// 2. exact match in built-in defaults
    /// 3. substring match against built-in defaults (longest first)
    /// 4. family fallback
    pub fn for_model(&self, model: &str) -> PricingInfo {
        if model.is_empty() {
            return self.fallback.clone();
        }
        if let Some(p) = self.explicit.get(model) {
            return p.clone();
        }
        if let Some(p) = builtin_pricing(model) {
            return p;
        }
        self.fallback.clone()
    }
}

/// Built-in pricing for known model families. Resolved by substring match so
/// dated suffixes like `claude-sonnet-4-5-20250929` map to the right entry.
/// Longest patterns first so `gpt-5-mini` beats `gpt-5`.
fn builtin_pricing(model: &str) -> Option<PricingInfo> {
    let lower = model.to_ascii_lowercase();
    // (pattern, input, cache_write, cache_read, output)
    const TABLE: &[(&str, f64, f64, f64, f64)] = &[
        // Anthropic Claude
        ("claude-opus-4-7", 15.0, 18.75, 1.50, 75.0),
        ("claude-opus-4-6", 15.0, 18.75, 1.50, 75.0),
        ("claude-opus-4-5", 15.0, 18.75, 1.50, 75.0),
        ("claude-opus",     15.0, 18.75, 1.50, 75.0),
        ("opus-4-7",        15.0, 18.75, 1.50, 75.0),
        ("opus-4-6",        15.0, 18.75, 1.50, 75.0),
        ("opus-4-5",        15.0, 18.75, 1.50, 75.0),
        ("claude-sonnet-4-6", 3.0, 3.75, 0.30, 15.0),
        ("claude-sonnet-4-5", 3.0, 3.75, 0.30, 15.0),
        ("claude-sonnet",     3.0, 3.75, 0.30, 15.0),
        ("sonnet-4-6",        3.0, 3.75, 0.30, 15.0),
        ("sonnet-4-5",        3.0, 3.75, 0.30, 15.0),
        ("claude-haiku-4-5",  1.0, 1.25, 0.10,  5.0),
        ("claude-haiku",      1.0, 1.25, 0.10,  5.0),
        ("haiku-4-5",         1.0, 1.25, 0.10,  5.0),
        // OpenAI / Codex (cache_write=0 — OpenAI bills cached_input directly)
        ("gpt-5-nano", 0.05, 0.0, 0.005, 0.40),
        ("gpt-5-mini", 0.25, 0.0, 0.025, 2.0),
        ("gpt-5.5",    1.25, 0.0, 0.125, 10.0),
        ("gpt-5.4",    1.25, 0.0, 0.125, 10.0),
        ("gpt-5.2",    1.25, 0.0, 0.125, 10.0),
        ("gpt-5",      1.25, 0.0, 0.125, 10.0),
        ("gpt-4.1-mini", 0.40, 0.0, 0.10, 1.60),
        ("gpt-4.1-nano", 0.10, 0.0, 0.025, 0.40),
        ("gpt-4.1",    2.0,  0.0, 0.50,  8.0),
        ("gpt-4o-mini", 0.15, 0.0, 0.075, 0.60),
        ("gpt-4o",      2.50, 0.0, 1.25,  10.0),
        ("o1-mini",     1.10, 0.0, 0.55,  4.40),
        ("o1",         15.0,  0.0, 7.50,  60.0),
        ("o3-mini",     1.10, 0.0, 0.55,  4.40),
        ("o3",          2.0,  0.0, 0.50,  8.0),
    ];

    let mut best: Option<&(&str, f64, f64, f64, f64)> = None;
    for entry in TABLE {
        if lower.contains(entry.0) {
            match best {
                Some(b) if b.0.len() >= entry.0.len() => {}
                _ => best = Some(entry),
            }
        }
    }
    best.map(|(_, input, cw, cr, output)| PricingInfo {
        input_per_mtok: *input,
        cache_write_per_mtok: *cw,
        cache_read_per_mtok: *cr,
        output_per_mtok: *output,
    })
}

// Codex models
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CodexThread {
    pub id: String,
    pub tokens_used: Option<u64>,
    pub model_provider: Option<String>,
    pub title: Option<String>,
    pub cwd: Option<String>,
    pub created_at: Option<String>,
    pub git_branch: Option<String>,
    pub rollout_path: Option<String>,
}

#[derive(Debug, Clone, Default)]
pub struct CodexTokenUsage {
    pub input_tokens: u64,
    pub cached_input_tokens: u64,
    pub output_tokens: u64,
    pub message_count: u32,
    pub first_timestamp: Option<String>,
    pub last_timestamp: Option<String>,
    pub model: Option<String>,
}
