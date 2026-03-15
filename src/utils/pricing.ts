import type { SessionSummary } from "../types";

export type ModelId = "opus" | "sonnet" | "haiku";

export const MODEL_PRICING: Record<ModelId, { label: string; input: number; output: number; cacheWrite: number; cacheRead: number }> = {
  opus:   { label: "Opus 4",   input: 15.0,  output: 75.0,  cacheWrite: 18.75, cacheRead: 1.50 },
  sonnet: { label: "Sonnet 4", input: 3.0,   output: 15.0,  cacheWrite: 3.75,  cacheRead: 0.30 },
  haiku:  { label: "Haiku 3.5",  input: 0.80,  output: 4.0,   cacheWrite: 1.0,   cacheRead: 0.08 },
};

export function getSessionDurationMs(s: SessionSummary): number {
  if (!s.first_timestamp || !s.last_timestamp) return 0;
  return Math.max(0, new Date(s.last_timestamp).getTime() - new Date(s.first_timestamp).getTime());
}

export function calcSessionCost(s: SessionSummary, p: typeof MODEL_PRICING[ModelId]): number {
  return (s.total_input_tokens / 1e6) * p.input + (s.total_output_tokens / 1e6) * p.output +
    (s.total_cache_write_tokens / 1e6) * p.cacheWrite + (s.total_cache_read_tokens / 1e6) * p.cacheRead;
}
