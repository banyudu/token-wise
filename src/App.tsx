import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { useVirtualizer } from "@tanstack/react-virtual";
import type { OverviewMetrics, SessionSummary, ProjectSummary, SessionDetail, TurnMetrics } from "./types";

import "./App.css";

type Tab = "overview" | "sessions" | "projects";
type SortField = "cost" | "date" | "input" | "output" | "cache_write" | "cache_read" | "cache_hit" | "messages" | "duration";
type SortDir = "asc" | "desc";
type DateRange = "7d" | "30d" | "90d" | "all";
type ModelId = "opus" | "sonnet" | "haiku";

const MODEL_PRICING: Record<ModelId, { label: string; input: number; output: number; cacheWrite: number; cacheRead: number }> = {
  opus:   { label: "Opus 4",   input: 15.0,  output: 75.0,  cacheWrite: 18.75, cacheRead: 1.50 },
  sonnet: { label: "Sonnet 4", input: 3.0,   output: 15.0,  cacheWrite: 3.75,  cacheRead: 0.30 },
  haiku:  { label: "Haiku 3.5",  input: 0.80,  output: 4.0,   cacheWrite: 1.0,   cacheRead: 0.08 },
};

function formatTokens(n: number): string {
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
  if (n >= 1_000) return `${(n / 1_000).toFixed(1)}K`;
  return n.toString();
}

function formatCost(n: number): string {
  return `$${n.toFixed(2)}`;
}

function formatPercent(n: number): string {
  return `${(n * 100).toFixed(1)}%`;
}

function formatDate(ts: string | null): string {
  if (!ts) return "\u2014";
  const d = new Date(ts);
  return d.toLocaleDateString("en-US", { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" });
}

function shortenProject(path: string): string {
  const parts = path.split("/");
  return parts.length > 2 ? parts.slice(-2).join("/") : path;
}

function getSessionDurationMs(s: SessionSummary): number {
  if (!s.first_timestamp || !s.last_timestamp) return 0;
  return Math.max(0, new Date(s.last_timestamp).getTime() - new Date(s.first_timestamp).getTime());
}

function formatDuration(ms: number): string {
  if (ms <= 0) return "\u2014";
  const mins = Math.floor(ms / 60_000);
  if (mins < 1) return "<1m";
  if (mins < 60) return `${mins}m`;
  const hours = Math.floor(mins / 60);
  const remainMins = mins % 60;
  if (hours < 24) return `${hours}h ${remainMins}m`;
  const days = Math.floor(hours / 24);
  return `${days}d ${hours % 24}h`;
}

function filterByDateRange(sessions: SessionSummary[], range: DateRange): SessionSummary[] {
  if (range === "all") return sessions;
  const days = range === "7d" ? 7 : range === "30d" ? 30 : 90;
  const cutoff = new Date();
  cutoff.setDate(cutoff.getDate() - days);
  const cutoffStr = cutoff.toISOString();
  return sessions.filter((s) => (s.first_timestamp ?? "") >= cutoffStr);
}

function calcSessionCost(s: SessionSummary, p: typeof MODEL_PRICING[ModelId]): number {
  return (s.total_input_tokens / 1e6) * p.input + (s.total_output_tokens / 1e6) * p.output +
    (s.total_cache_write_tokens / 1e6) * p.cacheWrite + (s.total_cache_read_tokens / 1e6) * p.cacheRead;
}

function computeOverview(sessions: SessionSummary[], model: ModelId = "sonnet"): OverviewMetrics {
  const p = MODEL_PRICING[model];
  let totalInput = 0, totalOutput = 0, totalCacheWrite = 0, totalCacheRead = 0, totalCost = 0;
  const projectMap = new Map<string, SessionSummary[]>();
  const dailyMap = new Map<string, { cost: number; input: number; output: number; cw: number; cr: number; source: string }>();
  let systemOverhead = 0;

  for (const s of sessions) {
    const sessionCost = calcSessionCost(s, p);
    totalInput += s.total_input_tokens;
    totalOutput += s.total_output_tokens;
    totalCacheWrite += s.total_cache_write_tokens;
    totalCacheRead += s.total_cache_read_tokens;
    totalCost += sessionCost;
    const key = s.project || "unknown";
    if (!projectMap.has(key)) projectMap.set(key, []);
    projectMap.get(key)!.push(s);
    if (s.first_timestamp) {
      const date = s.first_timestamp.slice(0, 10);
      const d = dailyMap.get(date) ?? { cost: 0, input: 0, output: 0, cw: 0, cr: 0, source: s.source };
      d.cost += sessionCost;
      d.input += s.total_input_tokens;
      d.output += s.total_output_tokens;
      d.cw += s.total_cache_write_tokens;
      d.cr += s.total_cache_read_tokens;
      dailyMap.set(date, d);
    }
    if (s.source === "claude" && s.total_cache_write_tokens > systemOverhead) {
      systemOverhead = s.total_cache_write_tokens;
    }
  }

  const totalCtx = totalCacheRead + totalCacheWrite + totalInput;
  const inputCost = (totalInput / 1e6) * p.input;
  const outputCost = (totalOutput / 1e6) * p.output;
  const cwCost = (totalCacheWrite / 1e6) * p.cacheWrite;
  const crCost = (totalCacheRead / 1e6) * p.cacheRead;

  const projectSummaries: ProjectSummary[] = Array.from(projectMap.entries()).map(([proj, sess]) => {
    const pi = sess.reduce((a, s) => a + s.total_input_tokens, 0);
    const po = sess.reduce((a, s) => a + s.total_output_tokens, 0);
    const pcw = sess.reduce((a, s) => a + s.total_cache_write_tokens, 0);
    const pcr = sess.reduce((a, s) => a + s.total_cache_read_tokens, 0);
    const pc = (pi / 1e6) * p.input + (po / 1e6) * p.output + (pcw / 1e6) * p.cacheWrite + (pcr / 1e6) * p.cacheRead;
    const ptc = pcr + pcw + pi;
    return { project: proj, session_count: sess.length, total_cost_usd: pc, total_input_tokens: pi, total_output_tokens: po, total_cache_write_tokens: pcw, total_cache_read_tokens: pcr, avg_cache_hit_rate: ptc > 0 ? pcr / ptc : 0 };
  }).sort((a, b) => b.total_cost_usd - a.total_cost_usd);

  const dailyCosts = Array.from(dailyMap.entries()).map(([date, d]) => ({
    date, cost_usd: d.cost, input_tokens: d.input, output_tokens: d.output, cache_write_tokens: d.cw, cache_read_tokens: d.cr, source: d.source,
  })).sort((a, b) => a.date.localeCompare(b.date));

  const topSessions = [...sessions]
    .map((s) => ({ ...s, estimated_cost_usd: calcSessionCost(s, p) }))
    .sort((a, b) => b.estimated_cost_usd - a.estimated_cost_usd)
    .slice(0, 20);

  return {
    total_sessions: sessions.length, total_cost_usd: totalCost, total_input_tokens: totalInput, total_output_tokens: totalOutput,
    total_cache_write_tokens: totalCacheWrite, total_cache_read_tokens: totalCacheRead,
    avg_cache_hit_rate: totalCtx > 0 ? totalCacheRead / totalCtx : 0,
    cost_breakdown: { input_cost: inputCost, output_cost: outputCost, cache_write_cost: cwCost, cache_read_cost: crCost, total_cost: inputCost + outputCost + cwCost + crCost },
    estimated_system_overhead_tokens: systemOverhead, daily_costs: dailyCosts, project_summaries: projectSummaries, top_sessions: topSessions,
  };
}

/* --- Pill button group (shared by DateRange, Model, Source selectors) --- */

const pillGroup = "flex gap-0.5 rounded-md p-0.5";
const pillBtn = "border-none bg-transparent px-2.5 py-1 text-xs font-medium text-[var(--color-muted)] cursor-pointer rounded font-[inherit] transition-all duration-150";
const pillBtnHover = "hover:text-[var(--color-primary)]";

function DateRangeSelector({ value, onChange }: { value: DateRange; onChange: (v: DateRange) => void }) {
  const options: { label: string; value: DateRange }[] = [
    { label: "7 Days", value: "7d" }, { label: "30 Days", value: "30d" }, { label: "90 Days", value: "90d" }, { label: "All Time", value: "all" },
  ];
  return (
    <div className={`${pillGroup} bg-[var(--color-border)]`}>
      {options.map((o) => (
        <button
          key={o.value}
          className={`${pillBtn} ${pillBtnHover} ${value === o.value ? "bg-[var(--color-surface)] text-[var(--color-primary)] font-semibold shadow-sm" : ""}`}
          onClick={() => onChange(o.value)}
        >
          {o.label}
        </button>
      ))}
    </div>
  );
}

function ModelSelector({ value, onChange }: { value: ModelId; onChange: (v: ModelId) => void }) {
  return (
    <div className={`${pillGroup} bg-[var(--color-border)] border border-[var(--color-border)]`}>
      {(Object.entries(MODEL_PRICING) as [ModelId, typeof MODEL_PRICING[ModelId]][]).map(([id, p]) => (
        <button
          key={id}
          className={`${pillBtn} ${value === id ? "!bg-[var(--color-primary)] !text-white" : "hover:text-inherit"}`}
          onClick={() => onChange(id)}
        >
          {p.label}
        </button>
      ))}
    </div>
  );
}

function MetricCard({ label, value, sub }: { label: string; value: string; sub?: string }) {
  return (
    <div className="bg-[var(--color-surface)] border border-[var(--color-border)] rounded-lg p-4">
      <div className="text-2xl font-bold leading-tight">{value}</div>
      <div className="text-xs text-[var(--color-muted)] mt-1 uppercase tracking-wide">{label}</div>
      {sub && <div className="text-[11px] text-[var(--color-muted)] mt-0.5">{sub}</div>}
    </div>
  );
}

function CostBar({ breakdown }: { breakdown: OverviewMetrics["cost_breakdown"] }) {
  const total = breakdown.total_cost || 1;
  const segments = [
    { label: "Output", value: breakdown.output_cost, color: "var(--color-output)" },
    { label: "Cache Write", value: breakdown.cache_write_cost, color: "var(--color-cache-write)" },
    { label: "Input", value: breakdown.input_cost, color: "var(--color-input)" },
    { label: "Cache Read", value: breakdown.cache_read_cost, color: "var(--color-cache-read)" },
  ];
  return (
    <div className="bg-[var(--color-surface)] border border-[var(--color-border)] rounded-lg p-4 mb-6">
      <h3 className="text-sm font-semibold mb-3">Cost Breakdown</h3>
      <div className="flex h-6 rounded overflow-hidden mb-3">
        {segments.map((s) => (
          <div key={s.label} className="min-w-0.5 transition-[width] duration-300" style={{ width: `${(s.value / total) * 100}%`, backgroundColor: s.color }} title={`${s.label}: ${formatCost(s.value)}`} />
        ))}
      </div>
      <div className="flex flex-wrap gap-3">
        {segments.map((s) => (
          <div key={s.label} className="flex items-center gap-1.5 text-xs">
            <span className="w-2.5 h-2.5 rounded-sm shrink-0" style={{ backgroundColor: s.color }} />
            <span>{s.label}: {formatCost(s.value)} ({formatPercent(s.value / total)})</span>
          </div>
        ))}
      </div>
    </div>
  );
}

function DailyCostChart({ dailyCosts, pricing }: { dailyCosts: OverviewMetrics["daily_costs"]; pricing: { input: number; output: number; cacheWrite: number; cacheRead: number } }) {
  if (dailyCosts.length === 0) return null;
  const maxCost = Math.max(...dailyCosts.map((d) => d.cost_usd), 0.01);
  return (
    <div className="bg-[var(--color-surface)] border border-[var(--color-border)] rounded-lg p-4 mb-6">
      <h3 className="text-sm font-semibold mb-3">Daily Cost ({dailyCosts.length} days)</h3>
      <div className="flex gap-0.5">
        {dailyCosts.map((d) => {
          const bd = { input: (d.input_tokens / 1e6) * pricing.input, output: (d.output_tokens / 1e6) * pricing.output, cache_write: (d.cache_write_tokens / 1e6) * pricing.cacheWrite, cache_read: (d.cache_read_tokens / 1e6) * pricing.cacheRead };
          const barTotal = bd.input + bd.output + bd.cache_write + bd.cache_read;
          const heightPct = (d.cost_usd / maxCost) * 100;
          return (
            <div key={d.date} className="flex-1 flex flex-col items-center" title={`${d.date}: ${formatCost(d.cost_usd)}`}>
              <div className="w-full h-[120px] flex flex-col justify-end">
                <div className="w-full flex flex-col rounded-t-sm overflow-hidden min-h-px" style={{ height: `${heightPct}%` }}>
                  {barTotal > 0 ? (<>
                    <div className="w-full" style={{ flex: bd.output, backgroundColor: "var(--color-output)" }} />
                    <div className="w-full" style={{ flex: bd.cache_write, backgroundColor: "var(--color-cache-write)" }} />
                    <div className="w-full" style={{ flex: bd.input, backgroundColor: "var(--color-input)" }} />
                    <div className="w-full" style={{ flex: bd.cache_read, backgroundColor: "var(--color-cache-read)" }} />
                  </>) : <div className="w-full" style={{ flex: 1, backgroundColor: "var(--color-primary)" }} />}
                </div>
              </div>
              <div className="text-[9px] text-[var(--color-muted)] mt-1 [writing-mode:vertical-rl] [text-orientation:mixed] h-9 overflow-hidden">{d.date.slice(5)}</div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

function SortHeader({ label, field, currentField, currentDir, onSort }: { label: string; field: SortField; currentField: SortField; currentDir: SortDir; onSort: (f: SortField) => void }) {
  const active = currentField === field;
  return (
    <th
      className={`text-left px-3 py-2.5 font-semibold text-[11px] uppercase tracking-wide whitespace-nowrap cursor-pointer select-none ${active ? "text-[var(--color-primary)]" : "text-[var(--color-muted)]"} hover:text-[var(--color-primary)]`}
      onClick={() => onSort(field)}
    >
      {label} {active ? (currentDir === "desc" ? "\u2193" : "\u2191") : ""}
    </th>
  );
}

function Recommendations({ sessions, overview }: { sessions: SessionSummary[]; overview: OverviewMetrics }) {
  const tips = useMemo(() => {
    const result: { severity: "high" | "medium" | "low"; text: string }[] = [];
    if (overview.avg_cache_hit_rate < 0.5) {
      result.push({ severity: "high", text: `Cache hit rate is ${formatPercent(overview.avg_cache_hit_rate)} \u2014 below 50%. Short sessions cause frequent cache misses. Try longer, focused sessions to improve cache reuse.` });
    } else if (overview.avg_cache_hit_rate < 0.7) {
      result.push({ severity: "medium", text: `Cache hit rate is ${formatPercent(overview.avg_cache_hit_rate)}. Consider consolidating related tasks into fewer sessions to improve cache efficiency.` });
    }
    const cacheWriteCostPct = overview.cost_breakdown.cache_write_cost / (overview.cost_breakdown.total_cost || 1);
    if (cacheWriteCostPct > 0.3) {
      result.push({ severity: "high", text: `Cache writes account for ${formatPercent(cacheWriteCostPct)} of total cost (${formatCost(overview.cost_breakdown.cache_write_cost)}). Each new session pays the full cache write cost. Reduce session restarts and trim CLAUDE.md/skills to lower this.` });
    }
    if (overview.estimated_system_overhead_tokens > 50000) {
      result.push({ severity: "medium", text: `Estimated system overhead is ${formatTokens(overview.estimated_system_overhead_tokens)} tokens per session. Review your CLAUDE.md, installed skills, and plugins \u2014 each adds to the "token tax" paid on every session start.` });
    }
    const shortSessions = sessions.filter((s) => s.source === "claude" && s.message_count <= 4 && s.estimated_cost_usd > 0.5);
    if (shortSessions.length > 5) {
      result.push({ severity: "medium", text: `${shortSessions.length} short sessions (\u22644 messages, >$0.50 each) detected. These pay full cache write costs with minimal cache reuse. Consider batching related questions.` });
    }
    const outputCostPct = overview.cost_breakdown.output_cost / (overview.cost_breakdown.total_cost || 1);
    if (outputCostPct > 0.5) {
      result.push({ severity: "medium", text: `Output tokens account for ${formatPercent(outputCostPct)} of costs. Consider asking for more concise responses or using diff-style edits instead of full file rewrites.` });
    }
    const sessionsWithDuration = sessions.filter((s) => s.source === "claude" && getSessionDurationMs(s) > 60_000);
    if (sessionsWithDuration.length > 0) {
      const avgCostPerHour = sessionsWithDuration.reduce((sum, s) => {
        const hours = getSessionDurationMs(s) / 3_600_000;
        return sum + (hours > 0 ? s.estimated_cost_usd / hours : 0);
      }, 0) / sessionsWithDuration.length;
      if (avgCostPerHour > 10) {
        result.push({ severity: "medium", text: `Average cost rate is ${formatCost(avgCostPerHour)}/hour across ${sessionsWithDuration.length} sessions. High output volume or frequent cache misses may be driving costs up.` });
      }
    }
    if (result.length === 0) {
      result.push({ severity: "low", text: "Your usage patterns look efficient. Keep monitoring cache hit rates and session lengths." });
    }
    return result;
  }, [sessions, overview]);

  const severityStyles: Record<string, string> = {
    high: "bg-[rgba(231,76,60,0.08)] border-l-3 border-l-[#e74c3c]",
    medium: "bg-[rgba(243,156,18,0.08)] border-l-3 border-l-[#f39c12]",
    low: "bg-[rgba(39,174,96,0.08)] border-l-3 border-l-[#27ae60]",
  };
  const badgeStyles: Record<string, string> = {
    high: "bg-[rgba(231,76,60,0.15)] text-[#e74c3c]",
    medium: "bg-[rgba(243,156,18,0.15)] text-[#f39c12]",
    low: "bg-[rgba(39,174,96,0.15)] text-[#27ae60]",
  };

  return (
    <div className="bg-[var(--color-surface)] border border-[var(--color-border)] rounded-lg p-4 mb-6">
      <h3 className="text-sm font-semibold mb-3">Cost Optimization Recommendations</h3>
      <div className="flex flex-col gap-2">
        {tips.map((tip, i) => (
          <div key={i} className={`flex items-start gap-2.5 px-3 py-2.5 rounded-md text-[13px] leading-relaxed ${severityStyles[tip.severity]}`}>
            <span className={`text-[10px] font-bold uppercase tracking-wide px-1.5 py-0.5 rounded shrink-0 mt-px ${badgeStyles[tip.severity]}`}>{tip.severity}</span>
            <span className="flex-1">{tip.text}</span>
          </div>
        ))}
      </div>
    </div>
  );
}

function SavingsPotential({ overview, sessions, pricing }: { overview: OverviewMetrics; sessions: SessionSummary[]; pricing: typeof MODEL_PRICING[ModelId] }) {
  const savings = useMemo(() => {
    const currentCacheRate = overview.avg_cache_hit_rate;
    const totalContext = overview.total_input_tokens + overview.total_cache_write_tokens + overview.total_cache_read_tokens;
    if (totalContext === 0 || currentCacheRate >= 0.85) return null;

    const targetRate = Math.min(currentCacheRate + 0.2, 0.85);
    const currentCacheReadTokens = overview.total_cache_read_tokens;
    const currentNonCacheTokens = overview.total_input_tokens + overview.total_cache_write_tokens;

    const targetCacheReadTokens = totalContext * targetRate;
    const tokenShift = targetCacheReadTokens - currentCacheReadTokens;

    const inputRatio = currentNonCacheTokens > 0 ? overview.total_input_tokens / currentNonCacheTokens : 0.5;
    const inputReduction = tokenShift * inputRatio;
    const cwReduction = tokenShift * (1 - inputRatio);

    const currentCost = overview.cost_breakdown.total_cost;
    const newInputCost = ((overview.total_input_tokens - inputReduction) / 1e6) * pricing.input;
    const newCwCost = ((overview.total_cache_write_tokens - cwReduction) / 1e6) * pricing.cacheWrite;
    const newCrCost = (targetCacheReadTokens / 1e6) * pricing.cacheRead;
    const newOutputCost = overview.cost_breakdown.output_cost;
    const projectedCost = newInputCost + newCwCost + newCrCost + newOutputCost;
    const savedAmount = currentCost - projectedCost;

    const shortSessions = sessions.filter((s) => s.source === "claude" && s.message_count <= 3);
    const shortSessionCost = shortSessions.reduce((sum, s) => sum + s.estimated_cost_usd, 0);

    return {
      currentRate: currentCacheRate, targetRate, currentCost,
      projectedCost: Math.max(0, projectedCost), savedAmount: Math.max(0, savedAmount),
      savedPercent: currentCost > 0 ? Math.max(0, savedAmount) / currentCost : 0,
      shortSessionCount: shortSessions.length, shortSessionCost,
    };
  }, [overview, sessions, pricing]);

  if (!savings) return (
    <div className="bg-[var(--color-surface)] border border-[var(--color-border)] rounded-lg p-4 mb-6">
      <h3 className="text-sm font-semibold mb-3">Savings Potential</h3>
      <div className="text-[var(--color-cache-read)] text-[13px] py-2">Your cache hit rate is already excellent ({formatPercent(overview.avg_cache_hit_rate)}). Keep it up!</div>
    </div>
  );

  return (
    <div className="bg-[var(--color-surface)] border border-[var(--color-border)] rounded-lg p-4 mb-6">
      <h3 className="text-sm font-semibold mb-3">Savings Potential</h3>
      <div className="grid grid-cols-[repeat(auto-fit,minmax(280px,1fr))] gap-4">
        <div className="border border-[var(--color-border)] rounded-lg p-4">
          <div className="flex items-center gap-4 mb-3">
            <div className="flex-1 text-center">
              <div className="text-[11px] uppercase tracking-wide text-[var(--color-muted)] mb-1">Current</div>
              <div className="text-xl font-bold">{formatCost(savings.currentCost)}</div>
              <div className="text-[11px] text-[var(--color-muted)] mt-0.5">Cache: {formatPercent(savings.currentRate)}</div>
            </div>
            <div className="text-xl text-[var(--color-muted)] shrink-0">{"\u2192"}</div>
            <div className="flex-1 text-center">
              <div className="text-[11px] uppercase tracking-wide text-[var(--color-muted)] mb-1">Projected</div>
              <div className="text-xl font-bold">{formatCost(savings.projectedCost)}</div>
              <div className="text-[11px] text-[var(--color-muted)] mt-0.5">Cache: {formatPercent(savings.targetRate)}</div>
            </div>
          </div>
          <div className="text-xs text-[var(--color-cache-read)] font-medium pt-2 border-t border-[var(--color-border)]">
            Save {formatCost(savings.savedAmount)} ({formatPercent(savings.savedPercent)}) by improving cache hit rate to {formatPercent(savings.targetRate)}
          </div>
        </div>
        {savings.shortSessionCount > 3 && (
          <div className="border border-[var(--color-border)] rounded-lg p-4">
            <div className="text-xl font-bold">{savings.shortSessionCount} short sessions</div>
            <div className="text-[11px] text-[var(--color-muted)] mt-0.5">{formatCost(savings.shortSessionCost)} spent on sessions with {"\u2264"}3 messages</div>
            <div className="text-xs text-[var(--color-cache-read)] font-medium pt-2 border-t border-[var(--color-border)] mt-3">Consolidating these into longer sessions could significantly reduce cache write overhead</div>
          </div>
        )}
      </div>
    </div>
  );
}

function ContextComposition({ overview, cacheWriteRate }: { overview: OverviewMetrics; cacheWriteRate: number }) {
  const totalContext = overview.total_input_tokens + overview.total_cache_write_tokens + overview.total_cache_read_tokens;
  if (totalContext === 0) return null;
  const overhead = overview.estimated_system_overhead_tokens;
  const overheadCost = (overhead / 1_000_000) * cacheWriteRate * overview.total_sessions;
  const items = [
    { value: formatTokens(overhead), label: "System Overhead / Session", sub: "CLAUDE.md + skills + tools + system prompt" },
    { value: formatCost(overheadCost), label: "Est. Overhead Cost", sub: `across ${overview.total_sessions} sessions` },
    { value: formatPercent(overview.total_cache_write_tokens / (totalContext || 1)), label: "Cache Miss Rate", sub: "tokens written vs total context" },
    { value: formatPercent(overview.total_cache_read_tokens / (totalContext || 1)), label: "Cache Reuse Rate", sub: "tokens read from cache" },
  ];
  return (
    <div className="bg-[var(--color-surface)] border border-[var(--color-border)] rounded-lg p-4 mb-6">
      <h3 className="text-sm font-semibold mb-3">Context Composition</h3>
      <div className="grid grid-cols-[repeat(auto-fit,minmax(160px,1fr))] gap-4">
        {items.map((item) => (
          <div key={item.label} className="text-center">
            <div className="text-xl font-bold">{item.value}</div>
            <div className="text-xs text-[var(--color-muted)] mt-1">{item.label}</div>
            <div className="text-[11px] text-[var(--color-muted)] mt-0.5">{item.sub}</div>
          </div>
        ))}
      </div>
    </div>
  );
}

const thBase = "text-left px-3 py-2.5 font-semibold text-[11px] uppercase tracking-wide text-[var(--color-muted)] whitespace-nowrap";
const tdBase = "px-3 py-2 border-t border-[var(--color-border)] whitespace-nowrap max-w-[200px] overflow-hidden text-ellipsis";

function SessionsTable({ sessions, sortField, sortDir, onSort, filter, onFilterChange, onSelectSession }: {
  sessions: SessionSummary[]; sortField: SortField; sortDir: SortDir; onSort: (f: SortField) => void;
  filter: string; onFilterChange: (v: string) => void; onSelectSession?: (id: string) => void;
}) {
  const filtered = useMemo(() => {
    let result = sessions;
    if (filter) {
      const q = filter.toLowerCase();
      result = result.filter((s) => s.project.toLowerCase().includes(q) || (s.git_branch ?? "").toLowerCase().includes(q) || s.source.toLowerCase().includes(q) || (s.title ?? "").toLowerCase().includes(q));
    }
    return [...result].sort((a, b) => {
      let cmp = 0;
      switch (sortField) {
        case "cost": cmp = a.estimated_cost_usd - b.estimated_cost_usd; break;
        case "date": cmp = (a.first_timestamp ?? "").localeCompare(b.first_timestamp ?? ""); break;
        case "input": cmp = a.total_input_tokens - b.total_input_tokens; break;
        case "output": cmp = a.total_output_tokens - b.total_output_tokens; break;
        case "cache_write": cmp = a.total_cache_write_tokens - b.total_cache_write_tokens; break;
        case "cache_read": cmp = a.total_cache_read_tokens - b.total_cache_read_tokens; break;
        case "cache_hit": cmp = a.cache_hit_rate - b.cache_hit_rate; break;
        case "messages": cmp = a.message_count - b.message_count; break;
        case "duration": cmp = getSessionDurationMs(a) - getSessionDurationMs(b); break;
      }
      return sortDir === "desc" ? -cmp : cmp;
    });
  }, [sessions, filter, sortField, sortDir]);

  const parentRef = useRef<HTMLDivElement>(null);
  const ROW_HEIGHT = 36;

  const virtualizer = useVirtualizer({
    count: filtered.length,
    getScrollElement: () => parentRef.current,
    estimateSize: () => ROW_HEIGHT,
    overscan: 20,
  });

  return (
    <div>
      <div className="flex items-center gap-3 mb-3">
        <input
          type="text"
          placeholder="Filter by project, branch, or source..."
          value={filter}
          onChange={(e) => onFilterChange(e.target.value)}
          className="flex-1 max-w-[400px] px-3 py-2 border border-[var(--color-border)] rounded-md bg-[var(--color-surface)] text-inherit text-[13px] font-[inherit] outline-none transition-colors duration-200 focus:border-[var(--color-primary)]"
        />
        <span className="text-xs text-[var(--color-muted)]">{filtered.length} sessions</span>
      </div>
      <div className="bg-[var(--color-surface)] border border-[var(--color-border)] rounded-lg overflow-x-auto virtual-table-container" ref={parentRef}>
        <table className="w-full border-collapse text-[13px]">
          <thead className="border-b border-[var(--color-border)]">
            <tr>
              <th className={`${thBase} min-w-[280px]`}>Project</th>
              <th className={thBase}>Title</th>
              <th className={thBase}>Branch</th>
              <SortHeader label="Messages" field="messages" currentField={sortField} currentDir={sortDir} onSort={onSort} />
              <SortHeader label="Duration" field="duration" currentField={sortField} currentDir={sortDir} onSort={onSort} />
              <SortHeader label="Cost" field="cost" currentField={sortField} currentDir={sortDir} onSort={onSort} />
              <SortHeader label="Cache Hit" field="cache_hit" currentField={sortField} currentDir={sortDir} onSort={onSort} />
              <SortHeader label="Input" field="input" currentField={sortField} currentDir={sortDir} onSort={onSort} />
              <SortHeader label="Output" field="output" currentField={sortField} currentDir={sortDir} onSort={onSort} />
              <SortHeader label="Cache Write" field="cache_write" currentField={sortField} currentDir={sortDir} onSort={onSort} />
              <SortHeader label="Cache Read" field="cache_read" currentField={sortField} currentDir={sortDir} onSort={onSort} />
              <th className={thBase}>Subagents</th>
              <th className={thBase}>Source</th>
              <SortHeader label="Date" field="date" currentField={sortField} currentDir={sortDir} onSort={onSort} />
            </tr>
          </thead>
          <tbody style={{ height: `${virtualizer.getTotalSize()}px`, position: "relative" }}>
            {virtualizer.getVirtualItems().map((virtualRow) => {
              const s = filtered[virtualRow.index];
              return (
                <tr
                  key={s.session_id}
                  className={`hover:bg-[rgba(74,144,217,0.05)] ${onSelectSession && s.source === "claude" ? "cursor-pointer hover:bg-[rgba(74,144,217,0.1)]!" : ""}`}
                  onClick={() => onSelectSession && s.source === "claude" && onSelectSession(s.session_id)}
                  style={{
                    position: "absolute",
                    top: 0,
                    left: 0,
                    width: "100%",
                    height: `${virtualRow.size}px`,
                    transform: `translateY(${virtualRow.start}px)`,
                  }}
                >
                  <td className={`${tdBase} min-w-[280px] max-w-[400px]`} title={s.project}>{shortenProject(s.project)}</td>
                  <td className={`${tdBase} max-w-[300px]`} title={s.title ?? ""}>{s.title ?? "\u2014"}</td>
                  <td className={`${tdBase} max-w-[200px]`}>{s.git_branch ?? "\u2014"}</td>
                  <td className={tdBase}>{s.message_count}</td>
                  <td className={tdBase}>{formatDuration(getSessionDurationMs(s))}</td>
                  <td className={`${tdBase} font-semibold text-[var(--color-output)]`}>{formatCost(s.estimated_cost_usd)}</td>
                  <td className={tdBase}>{formatPercent(s.cache_hit_rate)}</td>
                  <td className={tdBase}>{formatTokens(s.total_input_tokens)}</td>
                  <td className={tdBase}>{formatTokens(s.total_output_tokens)}</td>
                  <td className={tdBase}>{formatTokens(s.total_cache_write_tokens)}</td>
                  <td className={tdBase}>{formatTokens(s.total_cache_read_tokens)}</td>
                  <td className={tdBase}>{s.subagent_count > 0 ? `${s.subagent_count} (${formatCost(s.subagent_cost_usd)})` : "\u2014"}</td>
                  <td className={tdBase}>
                    <span className={`inline-block px-2 py-0.5 rounded text-[11px] font-semibold uppercase ${s.source === "claude" ? "bg-[rgba(74,144,217,0.15)] text-[var(--color-primary)]" : "bg-[rgba(39,174,96,0.15)] text-[var(--color-cache-read)]"}`}>{s.source}</span>
                  </td>
                  <td className={tdBase}>{formatDate(s.first_timestamp)}</td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </div>
  );
}

function SourceFilter({ value, onChange, counts }: { value: string; onChange: (v: string) => void; counts: { all: number; claude: number; codex: number } }) {
  const options = [
    { label: `All (${counts.all})`, value: "all" },
    { label: `Claude (${counts.claude})`, value: "claude" },
    { label: `Codex (${counts.codex})`, value: "codex" },
  ];
  return (
    <div className={`${pillGroup} bg-[var(--color-border)]`}>
      {options.map((o) => (
        <button
          key={o.value}
          className={`${pillBtn} ${pillBtnHover} ${value === o.value ? "bg-[var(--color-surface)] text-[var(--color-primary)] font-semibold shadow-sm" : ""}`}
          onClick={() => onChange(o.value)}
        >
          {o.label}
        </button>
      ))}
    </div>
  );
}

function ProjectsTable({ projects, onSelectProject }: { projects: ProjectSummary[]; onSelectProject?: (project: string) => void }) {
  const [sortBy, setSortBy] = useState<"cost" | "sessions" | "cache">("cost");
  const sorted = useMemo(() => {
    return [...projects].sort((a, b) => {
      switch (sortBy) {
        case "cost": return b.total_cost_usd - a.total_cost_usd;
        case "sessions": return b.session_count - a.session_count;
        case "cache": return b.avg_cache_hit_rate - a.avg_cache_hit_rate;
        default: return 0;
      }
    });
  }, [projects, sortBy]);

  const sortThCls = (field: typeof sortBy) =>
    `${thBase} cursor-pointer select-none ${sortBy === field ? "text-[var(--color-primary)]" : ""} hover:text-[var(--color-primary)]`;

  return (
    <div className="bg-[var(--color-surface)] border border-[var(--color-border)] rounded-lg overflow-x-auto">
      <table className="w-full border-collapse text-[13px]">
        <thead className="border-b border-[var(--color-border)]">
          <tr>
            <th className={`${thBase} min-w-[280px]`}>Project</th>
            <th className={sortThCls("sessions")} onClick={() => setSortBy("sessions")}>Sessions {sortBy === "sessions" ? "\u2193" : ""}</th>
            <th className={sortThCls("cost")} onClick={() => setSortBy("cost")}>Total Cost {sortBy === "cost" ? "\u2193" : ""}</th>
            <th className={sortThCls("cache")} onClick={() => setSortBy("cache")}>Cache Hit Rate {sortBy === "cache" ? "\u2193" : ""}</th>
            <th className={thBase}>Input</th>
            <th className={thBase}>Output</th>
            <th className={thBase}>Cache Write</th>
            <th className={thBase}>Cache Read</th>
          </tr>
        </thead>
        <tbody>
          {sorted.map((p) => (
            <tr key={p.project} className={`hover:bg-[rgba(74,144,217,0.05)] ${onSelectProject ? "cursor-pointer hover:bg-[rgba(74,144,217,0.1)]!" : ""}`} onClick={() => onSelectProject?.(p.project)}>
              <td className={`${tdBase} min-w-[280px] max-w-[400px]`} title={p.project}>{shortenProject(p.project)}</td>
              <td className={tdBase}>{p.session_count}</td>
              <td className={`${tdBase} font-semibold text-[var(--color-output)]`}>{formatCost(p.total_cost_usd)}</td>
              <td className={tdBase}>{formatPercent(p.avg_cache_hit_rate)}</td>
              <td className={tdBase}>{formatTokens(p.total_input_tokens)}</td>
              <td className={tdBase}>{formatTokens(p.total_output_tokens)}</td>
              <td className={tdBase}>{formatTokens(p.total_cache_write_tokens)}</td>
              <td className={tdBase}>{formatTokens(p.total_cache_read_tokens)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function ContextGrowthChart({ turns }: { turns: TurnMetrics[] }) {
  if (turns.length === 0) return null;
  const [mode, setMode] = useState<"per-turn" | "cumulative" | "cost">("per-turn");

  const perTurnTotals = turns.map((t) => t.input_tokens + t.cache_write_tokens + t.cache_read_tokens);
  const maxPerTurn = Math.max(...perTurnTotals, 1);
  const maxCumulative = Math.max(...turns.map((t) => t.cumulative_context), 1);
  const maxCost = Math.max(...turns.map((t) => t.cost_usd), 0.000001);
  const totalCost = turns.reduce((sum, t) => sum + t.cost_usd, 0);

  const [zoom, setZoom] = useState(1);
  const containerRef = useRef<HTMLDivElement>(null);

  const handleWheel = useCallback((e: React.WheelEvent) => {
    if (e.ctrlKey || e.metaKey) {
      e.preventDefault();
      const container = containerRef.current;
      if (!container) return;
      const rect = container.getBoundingClientRect();
      const pointerRatio = (e.clientX - rect.left + container.scrollLeft) / (container.scrollWidth);
      setZoom((prev) => {
        const next = Math.min(Math.max(prev * (1 - e.deltaY * 0.005), 1), 20);
        requestAnimationFrame(() => {
          if (!container) return;
          const newScrollWidth = container.scrollWidth;
          container.scrollLeft = pointerRatio * newScrollWidth - (e.clientX - rect.left);
        });
        return next;
      });
    }
  }, []);

  // For many turns, show every Nth label adjusted by zoom
  const effectiveTurns = turns.length / zoom;
  const labelInterval = effectiveTurns > 80 ? 10 : effectiveTurns > 40 ? 5 : effectiveTurns > 20 ? 2 : 1;

  return (
    <div className="bg-[var(--color-surface)] border border-[var(--color-border)] rounded-lg p-4 mb-6">
      <div className="flex items-center justify-between mb-3">
        <div className="flex items-center gap-2">
          <h3 className="text-sm font-semibold">Context Growth</h3>
          {zoom > 1 && (
            <button
              className="border-none px-1.5 py-0.5 text-[10px] font-medium cursor-pointer rounded font-[inherit] bg-[var(--color-border)] text-[var(--color-muted)] hover:text-[var(--color-primary)] transition-all duration-150"
              onClick={() => setZoom(1)}
            >
              {Math.round(zoom * 100)}% — Reset
            </button>
          )}
        </div>
        <div className="flex gap-0.5 rounded-md p-0.5 bg-[var(--color-border)]">
          <button
            className={`border-none px-2 py-0.5 text-[11px] font-medium cursor-pointer rounded font-[inherit] transition-all duration-150 ${mode === "per-turn" ? "bg-[var(--color-surface)] text-[var(--color-primary)] shadow-sm" : "bg-transparent text-[var(--color-muted)]"}`}
            onClick={() => setMode("per-turn")}
          >
            Per Turn
          </button>
          <button
            className={`border-none px-2 py-0.5 text-[11px] font-medium cursor-pointer rounded font-[inherit] transition-all duration-150 ${mode === "cumulative" ? "bg-[var(--color-surface)] text-[var(--color-primary)] shadow-sm" : "bg-transparent text-[var(--color-muted)]"}`}
            onClick={() => setMode("cumulative")}
          >
            Cumulative
          </button>
          <button
            className={`border-none px-2 py-0.5 text-[11px] font-medium cursor-pointer rounded font-[inherit] transition-all duration-150 ${mode === "cost" ? "bg-[var(--color-surface)] text-[var(--color-output)] shadow-sm" : "bg-transparent text-[var(--color-muted)]"}`}
            onClick={() => setMode("cost")}
          >
            Cost
          </button>
        </div>
      </div>
      {/* Cumulative line overlay */}
      {mode === "per-turn" && (
        <div className="flex items-center gap-1.5 text-[11px] text-[var(--color-muted)] mb-2">
          <span>Max per turn: {formatTokens(maxPerTurn)}</span>
          <span className="mx-1">{"\u00b7"}</span>
          <span>Total cumulative: {formatTokens(maxCumulative)}</span>
        </div>
      )}
      {mode === "cost" && (
        <div className="flex items-center gap-1.5 text-[11px] text-[var(--color-muted)] mb-2">
          <span>Total cost: {formatCost(totalCost)}</span>
          <span className="mx-1">{"\u00b7"}</span>
          <span>Max per turn: {formatCost(maxCost)}</span>
        </div>
      )}
      <div ref={containerRef} className="overflow-x-auto" onWheel={handleWheel}>
        <div className="flex gap-px" style={{ width: zoom > 1 ? `${zoom * 100}%` : undefined }}>
          {turns.map((t) => {
            const perTurnTotal = t.input_tokens + t.cache_write_tokens + t.cache_read_tokens;
            const heightPct = mode === "cost"
              ? (t.cost_usd / maxCost) * 100
              : mode === "per-turn"
                ? (perTurnTotal / maxPerTurn) * 100
                : (t.cumulative_context / maxCumulative) * 100;
            const showLabel = (t.turn_index % labelInterval === 0) || t.turn_index === turns.length - 1;
            return (
              <div key={`${mode}-${t.turn_index}`} className="flex-1 flex flex-col items-center min-w-0" title={`Turn ${t.turn_index + 1} (${t.role}): ${formatTokens(perTurnTotal)} this turn, ${formatTokens(t.cumulative_context)} cumulative, ${formatCost(t.cost_usd)}, cache hit ${formatPercent(t.cache_hit_rate)}`}>
                <div className="w-full h-[160px] flex flex-col justify-end">
                  <div className="w-full flex flex-col rounded-t-sm overflow-hidden" style={{ height: `${Math.max(heightPct, 0.5)}%` }}>
                    {mode === "cost" ? (
                      <div className="w-full h-full" style={{ backgroundColor: "var(--color-output)" }} />
                    ) : perTurnTotal > 0 ? (<>
                      <div className="w-full" style={{ flex: t.cache_write_tokens, backgroundColor: "var(--color-cache-write)" }} />
                      <div className="w-full" style={{ flex: t.input_tokens, backgroundColor: "var(--color-input)" }} />
                      <div className="w-full" style={{ flex: t.cache_read_tokens, backgroundColor: "var(--color-cache-read)" }} />
                    </>) : <div className="w-full" style={{ flex: 1, backgroundColor: "var(--color-primary)" }} />}
                  </div>
                </div>
                <div className={`text-[9px] mt-1 ${showLabel ? "text-[var(--color-muted)]" : "text-transparent"}`}>{t.turn_index + 1}</div>
              </div>
            );
          })}
        </div>
      </div>
      <div className="flex flex-wrap gap-3 mt-2">
        {mode === "cost" ? (
          <div className="flex items-center gap-1.5 text-xs"><span className="w-2.5 h-2.5 rounded-sm shrink-0 bg-[var(--color-output)]" /><span>Cost per turn</span></div>
        ) : (<>
          <div className="flex items-center gap-1.5 text-xs"><span className="w-2.5 h-2.5 rounded-sm shrink-0 bg-[var(--color-cache-write)]" /><span>Cache Write</span></div>
          <div className="flex items-center gap-1.5 text-xs"><span className="w-2.5 h-2.5 rounded-sm shrink-0 bg-[var(--color-input)]" /><span>Input</span></div>
          <div className="flex items-center gap-1.5 text-xs"><span className="w-2.5 h-2.5 rounded-sm shrink-0 bg-[var(--color-cache-read)]" /><span>Cache Read</span></div>
        </>)}
      </div>
    </div>
  );
}

function costColor(cost: number, maxCost: number): string {
  if (maxCost <= 0) return "var(--color-cache-read)";
  const ratio = cost / maxCost;
  if (ratio >= 0.66) return "var(--color-output)";
  if (ratio >= 0.33) return "#e67e22";
  return "var(--color-cache-read)";
}

function SessionDetailView({ detail, onBack }: { detail: SessionDetail; onBack: () => void }) {
  const { summary, turns } = detail;
  const firstTurnCacheWrite = turns.length > 0 ? turns[0].cache_write_tokens : 0;
  const maxTurnCost = Math.max(...turns.map((t) => t.cost_usd), 0);
  return (
    <div className="max-w-[1200px] mx-auto bg-[var(--color-surface)] rounded-xl p-6 shadow-lg">
      <button className="bg-none border border-[var(--color-border)] px-3.5 py-1.5 text-[13px] font-medium rounded-md cursor-pointer text-[var(--color-muted)] font-[inherit] mb-4 transition-all duration-150 hover:text-[var(--color-primary)] hover:border-[var(--color-primary)]" onClick={onBack}>{"\u2190"} Back to Sessions</button>
      <div className="mb-5">
        <h2 className="text-xl font-bold mb-2">{shortenProject(summary.project)}</h2>
        <div className="flex gap-3 items-center text-[13px] text-[var(--color-muted)] flex-wrap">
          <span>{summary.git_branch ?? "no branch"}</span>
          <span className={`inline-block px-2 py-0.5 rounded text-[11px] font-semibold uppercase ${summary.source === "claude" ? "bg-[rgba(74,144,217,0.15)] text-[var(--color-primary)]" : "bg-[rgba(39,174,96,0.15)] text-[var(--color-cache-read)]"}`}>{summary.source}</span>
          <span>{formatDate(summary.first_timestamp)}</span>
          <span>{formatDuration(getSessionDurationMs(summary))}</span>
        </div>
      </div>
      <div className="grid grid-cols-[repeat(auto-fit,minmax(180px,1fr))] gap-4 mb-6">
        <MetricCard label="Total Cost" value={formatCost(summary.estimated_cost_usd)} sub={(() => { const hours = getSessionDurationMs(summary) / 3_600_000; return hours > 0.01 ? `${formatCost(summary.estimated_cost_usd / hours)}/hr` : undefined; })()} />
        <MetricCard label="Turns" value={turns.length.toString()} sub={`${summary.message_count} messages`} />
        <MetricCard label="Cache Hit Rate" value={formatPercent(summary.cache_hit_rate)} />
        <MetricCard label="System Overhead (est.)" value={formatTokens(firstTurnCacheWrite)} sub="first turn cache write" />
        {summary.subagent_count > 0 && <MetricCard label="Subagents" value={summary.subagent_count.toString()} sub={formatCost(summary.subagent_cost_usd)} />}
        {(summary.ephemeral_5m_tokens > 0 || summary.ephemeral_1h_tokens > 0) && (
          <MetricCard label="Ephemeral Cache" value={formatTokens(summary.ephemeral_5m_tokens + summary.ephemeral_1h_tokens)} sub={`5m: ${formatTokens(summary.ephemeral_5m_tokens)} / 1h: ${formatTokens(summary.ephemeral_1h_tokens)}`} />
        )}
      </div>
      <ContextGrowthChart turns={turns} />
      <div className="mb-6">
        <h3 className="text-sm font-semibold mb-3">Turn-by-Turn Metrics</h3>
        <div className="bg-[var(--color-surface)] border border-[var(--color-border)] rounded-lg overflow-x-auto">
          <table className="w-full border-collapse text-[13px]">
            <thead className="border-b border-[var(--color-border)]">
              <tr>
                <th className={thBase}>#</th><th className={thBase}>Input</th><th className={thBase}>Output</th><th className={thBase}>Cache Write</th><th className={thBase}>Cache Read</th><th className={thBase}>Cache Hit</th><th className={thBase}>Cumulative</th><th className={thBase}>Cost</th><th className={thBase}>Time</th>
              </tr>
            </thead>
            <tbody>
              {turns.map((t) => (
                <tr key={t.turn_index} className={`hover:bg-[rgba(74,144,217,0.05)] ${t.cache_hit_rate < 0.3 ? "bg-[rgba(231,76,60,0.04)]" : ""}`}>
                  <td className={tdBase}>{t.turn_index + 1}</td>
                  <td className={tdBase}>{formatTokens(t.input_tokens)}</td>
                  <td className={tdBase}>{formatTokens(t.output_tokens)}</td>
                  <td className={tdBase}>{formatTokens(t.cache_write_tokens)}</td>
                  <td className={tdBase}>{formatTokens(t.cache_read_tokens)}</td>
                  <td className={tdBase}>{formatPercent(t.cache_hit_rate)}</td>
                  <td className={tdBase}>{formatTokens(t.cumulative_context)}</td>
                  <td className={`${tdBase} font-semibold`} style={{ color: costColor(t.cost_usd, maxTurnCost) }}>{formatCost(t.cost_usd)}</td>
                  <td className={tdBase}>{t.timestamp ? formatDate(t.timestamp) : "\u2014"}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}

function App() {
  const [allSessions, setAllSessions] = useState<SessionSummary[]>([]);
  const [tab, setTab] = useState<Tab>("overview");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [dateRange, setDateRange] = useState<DateRange>("30d");
  const [model, setModel] = useState<ModelId>("sonnet");
  const [sessionDetail, setSessionDetail] = useState<SessionDetail | null>(null);
  const [refreshing, setRefreshing] = useState(false);
  const [detailLoading, setDetailLoading] = useState(false);
  const [sortField, setSortField] = useState<SortField>("date");
  const [sortDir, setSortDir] = useState<SortDir>("desc");
  const [filter, setFilter] = useState("");
  const [sourceFilter, setSourceFilter] = useState("all");
  const [projectFilter, setProjectFilter] = useState<string | null>(null);

  const handleSort = (field: SortField) => {
    if (field === sortField) setSortDir(sortDir === "desc" ? "asc" : "desc");
    else { setSortField(field); setSortDir("desc"); }
  };

  const loadData = useCallback(async () => {
    setLoading(true); setError(null);
    try { setAllSessions(await invoke<SessionSummary[]>("get_sessions")); }
    catch (e) { setError(String(e)); }
    finally { setLoading(false); }
  }, []);

  const refreshData = useCallback(async () => {
    setRefreshing(true); setError(null);
    try { setAllSessions(await invoke<SessionSummary[]>("refresh_sessions")); }
    catch (e) { setError(String(e)); }
    finally { setRefreshing(false); }
  }, []);

  const loadSessionDetail = useCallback(async (sessionId: string) => {
    setDetailLoading(true);
    try {
      const detail = await invoke<SessionDetail | null>("get_session_detail", { sessionId });
      if (detail) setSessionDetail(detail);
    } catch (e) { setError(`Failed to load session detail: ${String(e)}`); }
    finally { setDetailLoading(false); }
  }, []);

  useEffect(() => { loadData(); }, [loadData]);

  const sessions = useMemo(() => filterByDateRange(allSessions, dateRange), [allSessions, dateRange]);
  const pricedSessions = useMemo(() => {
    const p = MODEL_PRICING[model];
    return sessions.map((s) => ({ ...s, estimated_cost_usd: calcSessionCost(s, p) }));
  }, [sessions, model]);
  const sourceCounts = useMemo(() => ({
    all: pricedSessions.length,
    claude: pricedSessions.filter((s) => s.source === "claude").length,
    codex: pricedSessions.filter((s) => s.source === "codex").length,
  }), [pricedSessions]);

  const filteredSessions = useMemo(() => {
    let result = pricedSessions;
    if (sourceFilter !== "all") result = result.filter((s) => s.source === sourceFilter);
    if (projectFilter) result = result.filter((s) => s.project === projectFilter);
    return result;
  }, [pricedSessions, sourceFilter, projectFilter]);

  const overview = useMemo(() => computeOverview(filteredSessions, model), [filteredSessions, model]);

  if (loading) return <main className="flex justify-center items-center min-h-screen"><div className="text-base p-10">Loading session data...</div></main>;
  if (error) return <main className="flex justify-center items-center min-h-screen"><div className="text-base p-10 text-[#e74c3c]">Error: {error}</div></main>;

  if (detailLoading || sessionDetail) {
    return (
      <main className="max-w-[1400px] mx-auto p-5">
        <header className="mb-6">
          <div className="flex justify-between items-start gap-4 flex-wrap"><div><h1 className="text-2xl font-bold whitespace-nowrap">Token Wise</h1><p className="text-sm text-[var(--color-muted)] mt-1 whitespace-nowrap">AI Coding Agent Cost Analyzer</p></div></div>
        </header>
        {detailLoading ? <div className="text-base p-10">Loading session detail...</div> : sessionDetail ? <SessionDetailView detail={sessionDetail} onBack={() => setSessionDetail(null)} /> : null}
      </main>
    );
  }

  return (
    <main className="max-w-[1400px] mx-auto p-5">
      <header className="mb-6">
        <div className="flex justify-between items-start gap-4 flex-wrap">
          <div>
            <h1 className="text-2xl font-bold whitespace-nowrap">Token Wise</h1>
            <p className="text-sm text-[var(--color-muted)] mt-1 whitespace-nowrap">AI Coding Agent Cost Analyzer</p>
          </div>
          <div className="flex items-center gap-3 flex-wrap">
            <SourceFilter value={sourceFilter} onChange={setSourceFilter} counts={sourceCounts} />
            <ModelSelector value={model} onChange={setModel} />
            <DateRangeSelector value={dateRange} onChange={setDateRange} />
            <button className="bg-[var(--color-primary)] text-white border-none px-4 py-1.5 rounded-md text-xs font-semibold cursor-pointer font-[inherit] transition-opacity duration-200 hover:opacity-90 disabled:opacity-50 disabled:cursor-not-allowed" onClick={refreshData} disabled={refreshing}>{refreshing ? "Refreshing..." : "Refresh"}</button>
          </div>
        </div>
      </header>
      <nav className="flex gap-1 border-b-2 border-[var(--color-border)] mb-6">
        {([["overview", "Overview"], ["sessions", `Sessions (${overview.total_sessions})`], ["projects", `Projects (${overview.project_summaries.length})`]] as const).map(([t, label]) => (
          <button
            key={t}
            className={`bg-none border-none px-4 py-2 text-sm font-medium cursor-pointer border-b-2 -mb-0.5 transition-colors duration-200 font-[inherit] ${tab === t ? "text-[var(--color-primary)] border-b-[var(--color-primary)]" : "text-[var(--color-muted)] border-b-transparent"} hover:text-[var(--color-primary)]`}
            onClick={() => setTab(t)}
          >
            {label}
          </button>
        ))}
      </nav>
      <div>
        {projectFilter && (
          <div className="flex items-center gap-3 px-3 py-2 bg-[rgba(74,144,217,0.08)] border border-[rgba(74,144,217,0.2)] rounded-md mb-4 text-[13px]">
            <span>Filtered by project: <strong>{shortenProject(projectFilter)}</strong></span>
            <button className="bg-none border border-[var(--color-border)] px-2.5 py-1 rounded text-xs cursor-pointer text-[var(--color-muted)] font-[inherit] transition-all duration-150 hover:text-[var(--color-output)] hover:border-[var(--color-output)]" onClick={() => setProjectFilter(null)}>Clear filter</button>
          </div>
        )}
        {tab === "overview" && (<>
          <div className="grid grid-cols-[repeat(auto-fit,minmax(180px,1fr))] gap-4 mb-6">
            <MetricCard label="Total Cost" value={formatCost(overview.total_cost_usd)} sub={overview.total_sessions > 0 ? `${formatCost(overview.total_cost_usd / overview.total_sessions)} avg/session` : undefined} />
            <MetricCard label="Sessions" value={overview.total_sessions.toString()} sub={(() => { const totalMs = pricedSessions.reduce((s, x) => s + getSessionDurationMs(x), 0); return totalMs > 0 ? `${formatDuration(totalMs)} total` : undefined; })()} />
            <MetricCard label="Cache Hit Rate" value={formatPercent(overview.avg_cache_hit_rate)} sub="higher is better" />
            <MetricCard label="System Overhead" value={formatTokens(overview.estimated_system_overhead_tokens)} sub="per session (est.)" />
            <MetricCard label="Output Tokens" value={formatTokens(overview.total_output_tokens)} />
            <MetricCard label="Cache Write Tokens" value={formatTokens(overview.total_cache_write_tokens)} sub={`$${MODEL_PRICING[model].cacheWrite}/MTok`} />
          </div>
          <CostBar breakdown={overview.cost_breakdown} />
          <ContextComposition overview={overview} cacheWriteRate={MODEL_PRICING[model].cacheWrite} />
          <DailyCostChart dailyCosts={overview.daily_costs} pricing={MODEL_PRICING[model]} />
          <Recommendations sessions={pricedSessions} overview={overview} />
          <SavingsPotential overview={overview} sessions={pricedSessions} pricing={MODEL_PRICING[model]} />
          <div className="mb-6">
            <h3 className="text-sm font-semibold mb-3">Top Sessions by Cost</h3>
            <SessionsTable sessions={overview.top_sessions} sortField={sortField} sortDir={sortDir} onSort={handleSort} filter="" onFilterChange={() => {}} onSelectSession={loadSessionDetail} />
          </div>
        </>)}
        {tab === "sessions" && <SessionsTable sessions={filteredSessions} sortField={sortField} sortDir={sortDir} onSort={handleSort} filter={filter} onFilterChange={setFilter} onSelectSession={loadSessionDetail} />}
        {tab === "projects" && <ProjectsTable projects={overview.project_summaries} onSelectProject={(project) => { setProjectFilter(project); setTab("sessions"); }} />}
      </div>
    </main>
  );
}

export default App;
