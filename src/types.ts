export interface CostBreakdown {
  input_cost: number;
  output_cost: number;
  cache_write_cost: number;
  cache_read_cost: number;
  total_cost: number;
}

export interface SessionSummary {
  session_id: string;
  project: string;
  git_branch: string | null;
  message_count: number;
  total_input_tokens: number;
  total_output_tokens: number;
  total_cache_write_tokens: number;
  total_cache_read_tokens: number;
  cache_hit_rate: number;
  estimated_cost_usd: number;
  first_timestamp: string | null;
  last_timestamp: string | null;
  subagent_count: number;
  subagent_cost_usd: number;
  source: string;
  ephemeral_5m_tokens: number;
  ephemeral_1h_tokens: number;
}

export interface ProjectSummary {
  project: string;
  session_count: number;
  total_cost_usd: number;
  total_input_tokens: number;
  total_output_tokens: number;
  total_cache_write_tokens: number;
  total_cache_read_tokens: number;
  avg_cache_hit_rate: number;
}

export interface DailyCost {
  date: string;
  cost_usd: number;
  input_tokens: number;
  output_tokens: number;
  cache_write_tokens: number;
  cache_read_tokens: number;
  source: string;
}

export interface OverviewMetrics {
  total_sessions: number;
  total_cost_usd: number;
  total_input_tokens: number;
  total_output_tokens: number;
  total_cache_write_tokens: number;
  total_cache_read_tokens: number;
  avg_cache_hit_rate: number;
  cost_breakdown: CostBreakdown;
  estimated_system_overhead_tokens: number;
  daily_costs: DailyCost[];
  project_summaries: ProjectSummary[];
  top_sessions: SessionSummary[];
}

export interface TurnMetrics {
  turn_index: number;
  role: string;
  input_tokens: number;
  output_tokens: number;
  cache_write_tokens: number;
  cache_read_tokens: number;
  cumulative_context: number;
  cache_hit_rate: number;
  cost_usd: number;
  timestamp: string | null;
}

export interface SessionDetail {
  summary: SessionSummary;
  turns: TurnMetrics[];
}

export interface PricingInfo {
  input_per_mtok: number;
  cache_write_per_mtok: number;
  cache_read_per_mtok: number;
  output_per_mtok: number;
}
