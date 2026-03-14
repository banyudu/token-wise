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
pub struct ClaudeMessage {
    #[serde(default)]
    pub r#type: String,
    #[serde(default)]
    pub message: Option<serde_json::Value>,
    #[serde(default)]
    pub usage: Option<TokenUsage>,
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
    pub message_count: u32,
    pub total_input_tokens: u64,
    pub total_output_tokens: u64,
    pub total_cache_write_tokens: u64,
    pub total_cache_read_tokens: u64,
    pub cache_hit_rate: f64,
    pub estimated_cost_usd: f64,
    pub first_timestamp: Option<String>,
    pub last_timestamp: Option<String>,
    pub subagent_count: u32,
    pub subagent_cost_usd: f64,
    pub source: String,
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
    pub input_tokens: u64,
    pub output_tokens: u64,
    pub cache_write_tokens: u64,
    pub cache_read_tokens: u64,
    pub source: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CostBreakdown {
    pub input_cost: f64,
    pub output_cost: f64,
    pub cache_write_cost: f64,
    pub cache_read_cost: f64,
    pub total_cost: f64,
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
        Self {
            input_per_mtok: 5.0,
            cache_write_per_mtok: 6.25,
            cache_read_per_mtok: 0.50,
            output_per_mtok: 25.0,
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
}
