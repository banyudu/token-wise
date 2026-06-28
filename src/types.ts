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
  title: string | null;
  message_count: number;
  total_input_tokens: number;
  total_output_tokens: number;
  total_cache_write_tokens: number;
  total_cache_read_tokens: number;
  cache_hit_rate: number;
  estimated_cost_usd: number;
  cost_breakdown: CostBreakdown;
  first_timestamp: string | null;
  last_timestamp: string | null;
  subagent_count: number;
  subagent_cost_usd: number;
  source: string;
  model: string | null;
  ephemeral_5m_tokens: number;
  ephemeral_1h_tokens: number;
}

export interface PaginatedSessions {
  sessions: SessionSummary[];
  total: number;
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
  cost_breakdown: CostBreakdown;
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

export interface ContentCategory {
  category: string;
  subcategory: string | null;
  estimated_tokens: number;
  byte_size: number;
  count: number;
  percentage: number;
}

export interface ContentItem {
  category: string;
  tool_name: string | null;
  source: string | null;
  estimated_tokens: number;
  preview: string;
  full_content: string;
  turn_index: number;
}

export interface ContentAnalysis {
  categories: ContentCategory[];
  total_estimated_tokens: number;
  all_items: ContentItem[];
  suggestions: string[];
}

export interface WastedWrite {
  turn_index: number;
  wasted_tokens: number;
  wasted_cost_usd: number;
  reason: string;
}

export interface InvalidationEvent {
  turn_index: number;
  dropped_tokens: number;
  rewrite_cost_usd: number;
  suspected_cause: string | null;
  suspected_preview: string | null;
}

export interface UnreferencedBlock {
  turn_index: number;
  label: string;
  estimated_tokens: number;
  carried_turns: number;
  wasted_cost_usd: number;
  preview: string;
}

export interface RepeatedBlock {
  occurrences: number;
  first_turn: number;
  last_turn: number;
  estimated_tokens_each: number;
  total_wasted_tokens: number;
  wasted_cost_usd: number;
  category: string;
  preview: string;
}

export interface CacheSavingsReport {
  wasted_cache_writes: WastedWrite[];
  invalidation_events: InvalidationEvent[];
  unreferenced_blocks: UnreferencedBlock[];
  repeated_blocks: RepeatedBlock[];
  total_potential_savings_usd: number;
}

export interface CliStatus {
  on_path: boolean;
  link_exists: boolean;
  link_path: string;
  bin_dir_on_path: boolean;
  sandboxed: boolean;
  exe_path: string;
}

export interface CliInstallResult {
  ok: boolean;
  outcome: "installed" | "already" | "sandboxed" | "error";
  message: string;
  status: CliStatus;
}

export interface SessionDetail {
  summary: SessionSummary;
  turns: TurnMetrics[];
  content_analysis: ContentAnalysis | null;
  cache_savings: CacheSavingsReport | null;
}

