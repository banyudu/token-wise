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

function DateRangeSelector({ value, onChange }: { value: DateRange; onChange: (v: DateRange) => void }) {
  const options: { label: string; value: DateRange }[] = [
    { label: "7 Days", value: "7d" }, { label: "30 Days", value: "30d" }, { label: "90 Days", value: "90d" }, { label: "All Time", value: "all" },
  ];
  return (
    <div className="date-range-selector">
      {options.map((o) => (
        <button key={o.value} className={value === o.value ? "active" : ""} onClick={() => onChange(o.value)}>{o.label}</button>
      ))}
    </div>
  );
}

function ModelSelector({ value, onChange }: { value: ModelId; onChange: (v: ModelId) => void }) {
  return (
    <div className="model-selector">
      {(Object.entries(MODEL_PRICING) as [ModelId, typeof MODEL_PRICING[ModelId]][]).map(([id, p]) => (
        <button key={id} className={value === id ? "active" : ""} onClick={() => onChange(id)}>{p.label}</button>
      ))}
    </div>
  );
}

function MetricCard({ label, value, sub }: { label: string; value: string; sub?: string }) {
  return (
    <div className="metric-card">
      <div className="metric-value">{value}</div>
      <div className="metric-label">{label}</div>
      {sub && <div className="metric-sub">{sub}</div>}
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
    <div className="cost-bar-section">
      <h3>Cost Breakdown</h3>
      <div className="cost-bar">
        {segments.map((s) => (
          <div key={s.label} className="cost-bar-segment" style={{ width: `${(s.value / total) * 100}%`, backgroundColor: s.color }} title={`${s.label}: ${formatCost(s.value)}`} />
        ))}
      </div>
      <div className="cost-bar-legend">
        {segments.map((s) => (
          <div key={s.label} className="legend-item">
            <span className="legend-dot" style={{ backgroundColor: s.color }} />
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
    <div className="daily-chart-section">
      <h3>Daily Cost ({dailyCosts.length} days)</h3>
      <div className="daily-chart">
        {dailyCosts.map((d) => {
          const bd = { input: (d.input_tokens / 1e6) * pricing.input, output: (d.output_tokens / 1e6) * pricing.output, cache_write: (d.cache_write_tokens / 1e6) * pricing.cacheWrite, cache_read: (d.cache_read_tokens / 1e6) * pricing.cacheRead };
          const barTotal = bd.input + bd.output + bd.cache_write + bd.cache_read;
          const heightPct = (d.cost_usd / maxCost) * 100;
          return (
            <div key={d.date} className="daily-bar-wrapper" title={`${d.date}: ${formatCost(d.cost_usd)}`}>
              <div className="daily-bar-stack" style={{ height: `${heightPct}%` }}>
                {barTotal > 0 ? (<>
                  <div className="stack-segment" style={{ flex: bd.output, backgroundColor: "var(--color-output)" }} />
                  <div className="stack-segment" style={{ flex: bd.cache_write, backgroundColor: "var(--color-cache-write)" }} />
                  <div className="stack-segment" style={{ flex: bd.input, backgroundColor: "var(--color-input)" }} />
                  <div className="stack-segment" style={{ flex: bd.cache_read, backgroundColor: "var(--color-cache-read)" }} />
                </>) : <div className="stack-segment" style={{ flex: 1, backgroundColor: "var(--color-primary)" }} />}
              </div>
              <div className="daily-label">{d.date.slice(5)}</div>
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
    <th className={`sortable ${active ? "sort-active" : ""}`} onClick={() => onSort(field)}>
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

  return (
    <div className="recommendations-section">
      <h3>Cost Optimization Recommendations</h3>
      <div className="recommendations-list">
        {tips.map((tip, i) => (
          <div key={i} className={`recommendation ${tip.severity}`}>
            <span className="rec-severity">{tip.severity}</span>
            <span className="rec-text">{tip.text}</span>
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

    // If cache hit rate improved, more tokens would be cache reads (cheap) instead of cache writes/input (expensive)
    const targetCacheReadTokens = totalContext * targetRate;
    const tokenShift = targetCacheReadTokens - currentCacheReadTokens;

    // Shifted tokens come proportionally from input and cache write
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

    // Short session analysis
    const shortSessions = sessions.filter((s) => s.source === "claude" && s.message_count <= 3);
    const shortSessionCost = shortSessions.reduce((sum, s) => sum + s.estimated_cost_usd, 0);

    return {
      currentRate: currentCacheRate,
      targetRate,
      currentCost,
      projectedCost: Math.max(0, projectedCost),
      savedAmount: Math.max(0, savedAmount),
      savedPercent: currentCost > 0 ? Math.max(0, savedAmount) / currentCost : 0,
      shortSessionCount: shortSessions.length,
      shortSessionCost,
    };
  }, [overview, sessions, pricing]);

  if (!savings) return (
    <div className="savings-section">
      <h3>Savings Potential</h3>
      <div className="savings-good">Your cache hit rate is already excellent ({formatPercent(overview.avg_cache_hit_rate)}). Keep it up!</div>
    </div>
  );

  return (
    <div className="savings-section">
      <h3>Savings Potential</h3>
      <div className="savings-grid">
        <div className="savings-card">
          <div className="savings-comparison">
            <div className="savings-current">
              <div className="savings-label">Current</div>
              <div className="savings-value">{formatCost(savings.currentCost)}</div>
              <div className="savings-sub">Cache: {formatPercent(savings.currentRate)}</div>
            </div>
            <div className="savings-arrow">→</div>
            <div className="savings-projected">
              <div className="savings-label">Projected</div>
              <div className="savings-value">{formatCost(savings.projectedCost)}</div>
              <div className="savings-sub">Cache: {formatPercent(savings.targetRate)}</div>
            </div>
          </div>
          <div className="savings-amount">
            Save {formatCost(savings.savedAmount)} ({formatPercent(savings.savedPercent)}) by improving cache hit rate to {formatPercent(savings.targetRate)}
          </div>
        </div>
        {savings.shortSessionCount > 3 && (
          <div className="savings-card">
            <div className="savings-value">{savings.shortSessionCount} short sessions</div>
            <div className="savings-sub">{formatCost(savings.shortSessionCost)} spent on sessions with ≤3 messages</div>
            <div className="savings-amount">Consolidating these into longer sessions could significantly reduce cache write overhead</div>
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
  return (
    <div className="context-section">
      <h3>Context Composition</h3>
      <div className="context-grid">
        <div className="context-item">
          <div className="context-value">{formatTokens(overhead)}</div>
          <div className="context-label">System Overhead / Session</div>
          <div className="context-sub">CLAUDE.md + skills + tools + system prompt</div>
        </div>
        <div className="context-item">
          <div className="context-value">{formatCost(overheadCost)}</div>
          <div className="context-label">Est. Overhead Cost</div>
          <div className="context-sub">across {overview.total_sessions} sessions</div>
        </div>
        <div className="context-item">
          <div className="context-value">{formatPercent(overview.total_cache_write_tokens / (totalContext || 1))}</div>
          <div className="context-label">Cache Miss Rate</div>
          <div className="context-sub">tokens written vs total context</div>
        </div>
        <div className="context-item">
          <div className="context-value">{formatPercent(overview.total_cache_read_tokens / (totalContext || 1))}</div>
          <div className="context-label">Cache Reuse Rate</div>
          <div className="context-sub">tokens read from cache</div>
        </div>
      </div>
    </div>
  );
}

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
      <div className="filter-bar">
        <input type="text" placeholder="Filter by project, branch, or source..." value={filter} onChange={(e) => onFilterChange(e.target.value)} className="filter-input" />
        <span className="filter-count">{filtered.length} sessions</span>
      </div>
      <div className="table-container virtual-table-container" ref={parentRef}>
        <table>
          <thead>
            <tr>
              <th>Project</th>
              <th>Title</th>
              <th>Branch</th>
              <SortHeader label="Messages" field="messages" currentField={sortField} currentDir={sortDir} onSort={onSort} />
              <SortHeader label="Duration" field="duration" currentField={sortField} currentDir={sortDir} onSort={onSort} />
              <SortHeader label="Cost" field="cost" currentField={sortField} currentDir={sortDir} onSort={onSort} />
              <SortHeader label="Cache Hit" field="cache_hit" currentField={sortField} currentDir={sortDir} onSort={onSort} />
              <SortHeader label="Input" field="input" currentField={sortField} currentDir={sortDir} onSort={onSort} />
              <SortHeader label="Output" field="output" currentField={sortField} currentDir={sortDir} onSort={onSort} />
              <SortHeader label="Cache Write" field="cache_write" currentField={sortField} currentDir={sortDir} onSort={onSort} />
              <SortHeader label="Cache Read" field="cache_read" currentField={sortField} currentDir={sortDir} onSort={onSort} />
              <th>Subagents</th>
              <th>Source</th>
              <SortHeader label="Date" field="date" currentField={sortField} currentDir={sortDir} onSort={onSort} />
            </tr>
          </thead>
          <tbody style={{ height: `${virtualizer.getTotalSize()}px`, position: "relative" }}>
            {virtualizer.getVirtualItems().map((virtualRow) => {
              const s = filtered[virtualRow.index];
              return (
                <tr
                  key={s.session_id}
                  className={onSelectSession && s.source === "claude" ? "clickable-row" : ""}
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
                  <td title={s.project}>{shortenProject(s.project)}</td>
                  <td className="title-cell">{s.title ?? "\u2014"}</td>
                  <td>{s.git_branch ?? "\u2014"}</td>
                  <td>{s.message_count}</td>
                  <td>{formatDuration(getSessionDurationMs(s))}</td>
                  <td className="cost-cell">{formatCost(s.estimated_cost_usd)}</td>
                  <td>{formatPercent(s.cache_hit_rate)}</td>
                  <td>{formatTokens(s.total_input_tokens)}</td>
                  <td>{formatTokens(s.total_output_tokens)}</td>
                  <td>{formatTokens(s.total_cache_write_tokens)}</td>
                  <td>{formatTokens(s.total_cache_read_tokens)}</td>
                  <td>{s.subagent_count > 0 ? `${s.subagent_count} (${formatCost(s.subagent_cost_usd)})` : "\u2014"}</td>
                  <td><span className={`source-badge ${s.source}`}>{s.source}</span></td>
                  <td>{formatDate(s.first_timestamp)}</td>
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
    <div className="source-filter">
      {options.map((o) => (
        <button key={o.value} className={value === o.value ? "active" : ""} onClick={() => onChange(o.value)}>{o.label}</button>
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

  return (
    <div className="table-container">
      <table>
        <thead>
          <tr>
            <th>Project</th>
            <th className={`sortable ${sortBy === "sessions" ? "sort-active" : ""}`} onClick={() => setSortBy("sessions")}>Sessions {sortBy === "sessions" ? "\u2193" : ""}</th>
            <th className={`sortable ${sortBy === "cost" ? "sort-active" : ""}`} onClick={() => setSortBy("cost")}>Total Cost {sortBy === "cost" ? "\u2193" : ""}</th>
            <th className={`sortable ${sortBy === "cache" ? "sort-active" : ""}`} onClick={() => setSortBy("cache")}>Cache Hit Rate {sortBy === "cache" ? "\u2193" : ""}</th>
            <th>Input</th>
            <th>Output</th>
            <th>Cache Write</th>
            <th>Cache Read</th>
          </tr>
        </thead>
        <tbody>
          {sorted.map((p) => (
            <tr key={p.project} className={onSelectProject ? "clickable-row" : ""} onClick={() => onSelectProject?.(p.project)}>
              <td title={p.project}>{shortenProject(p.project)}</td>
              <td>{p.session_count}</td>
              <td className="cost-cell">{formatCost(p.total_cost_usd)}</td>
              <td>{formatPercent(p.avg_cache_hit_rate)}</td>
              <td>{formatTokens(p.total_input_tokens)}</td>
              <td>{formatTokens(p.total_output_tokens)}</td>
              <td>{formatTokens(p.total_cache_write_tokens)}</td>
              <td>{formatTokens(p.total_cache_read_tokens)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function ContextGrowthChart({ turns }: { turns: TurnMetrics[] }) {
  if (turns.length === 0) return null;
  const maxCtx = Math.max(...turns.map((t) => t.cumulative_context), 1);
  return (
    <div className="detail-chart-section">
      <h3>Context Growth</h3>
      <div className="context-growth-chart">
        {turns.map((t) => {
          const heightPct = (t.cumulative_context / maxCtx) * 100;
          const total = t.input_tokens + t.cache_write_tokens + t.cache_read_tokens;
          return (
            <div key={t.turn_index} className="growth-bar-wrapper" title={`Turn ${t.turn_index + 1} (${t.role}): ${formatTokens(t.cumulative_context)} cumulative, ${formatCost(t.cost_usd)}, cache hit ${formatPercent(t.cache_hit_rate)}`}>
              <div className="growth-bar-stack" style={{ height: `${heightPct}%` }}>
                {total > 0 ? (<>
                  <div className="stack-segment" style={{ flex: t.cache_write_tokens, backgroundColor: "var(--color-cache-write)" }} />
                  <div className="stack-segment" style={{ flex: t.input_tokens, backgroundColor: "var(--color-input)" }} />
                  <div className="stack-segment" style={{ flex: t.cache_read_tokens, backgroundColor: "var(--color-cache-read)" }} />
                </>) : <div className="stack-segment" style={{ flex: 1, backgroundColor: "var(--color-primary)" }} />}
              </div>
              <div className="growth-label">{t.turn_index + 1}</div>
            </div>
          );
        })}
      </div>
      <div className="cost-bar-legend" style={{ marginTop: 8 }}>
        <div className="legend-item"><span className="legend-dot" style={{ backgroundColor: "var(--color-cache-write)" }} /><span>Cache Write</span></div>
        <div className="legend-item"><span className="legend-dot" style={{ backgroundColor: "var(--color-input)" }} /><span>Input</span></div>
        <div className="legend-item"><span className="legend-dot" style={{ backgroundColor: "var(--color-cache-read)" }} /><span>Cache Read</span></div>
      </div>
    </div>
  );
}

function SessionDetailView({ detail, onBack }: { detail: SessionDetail; onBack: () => void }) {
  const { summary, turns } = detail;
  const firstTurnCacheWrite = turns.length > 0 ? turns[0].cache_write_tokens : 0;
  return (
    <div className="session-detail">
      <button className="back-btn" onClick={onBack}>{"\u2190"} Back to Sessions</button>
      <div className="detail-header">
        <h2>{shortenProject(summary.project)}</h2>
        <div className="detail-meta">
          <span>{summary.git_branch ?? "no branch"}</span>
          <span className={`source-badge ${summary.source}`}>{summary.source}</span>
          <span>{formatDate(summary.first_timestamp)}</span>
          <span>{formatDuration(getSessionDurationMs(summary))}</span>
        </div>
      </div>
      <div className="metrics-grid">
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
      <div className="section">
        <h3>Turn-by-Turn Metrics</h3>
        <div className="table-container">
          <table>
            <thead>
              <tr>
                <th>#</th><th>Role</th><th>Input</th><th>Output</th><th>Cache Write</th><th>Cache Read</th><th>Cache Hit</th><th>Cumulative</th><th>Cost</th><th>Time</th>
              </tr>
            </thead>
            <tbody>
              {turns.map((t) => (
                <tr key={t.turn_index} className={t.cache_hit_rate < 0.3 ? "low-cache-row" : ""}>
                  <td>{t.turn_index + 1}</td>
                  <td><span className={`role-badge ${t.role}`}>{t.role}</span></td>
                  <td>{formatTokens(t.input_tokens)}</td>
                  <td>{formatTokens(t.output_tokens)}</td>
                  <td>{formatTokens(t.cache_write_tokens)}</td>
                  <td>{formatTokens(t.cache_read_tokens)}</td>
                  <td>{formatPercent(t.cache_hit_rate)}</td>
                  <td>{formatTokens(t.cumulative_context)}</td>
                  <td className="cost-cell">{formatCost(t.cost_usd)}</td>
                  <td>{t.timestamp ? formatDate(t.timestamp) : "\u2014"}</td>
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

  if (loading) return <main className="container"><div className="loading">Loading session data...</div></main>;
  if (error) return <main className="container"><div className="error">Error: {error}</div></main>;

  if (detailLoading || sessionDetail) {
    return (
      <main className="app">
        <header className="app-header">
          <div className="header-top"><div><h1>Token Wise</h1><p className="app-subtitle">AI Coding Agent Cost Analyzer</p></div></div>
        </header>
        {detailLoading ? <div className="loading">Loading session detail...</div> : sessionDetail ? <SessionDetailView detail={sessionDetail} onBack={() => setSessionDetail(null)} /> : null}
      </main>
    );
  }

  return (
    <main className="app">
      <header className="app-header">
        <div className="header-top">
          <div><h1>Token Wise</h1><p className="app-subtitle">AI Coding Agent Cost Analyzer</p></div>
          <div className="header-controls">
            <SourceFilter value={sourceFilter} onChange={setSourceFilter} counts={sourceCounts} />
            <ModelSelector value={model} onChange={setModel} />
            <DateRangeSelector value={dateRange} onChange={setDateRange} />
            <button className="refresh-btn" onClick={loadData} disabled={loading}>{loading ? "Loading..." : "Refresh"}</button>
          </div>
        </div>
      </header>
      <nav className="tabs">
        <button className={tab === "overview" ? "active" : ""} onClick={() => setTab("overview")}>Overview</button>
        <button className={tab === "sessions" ? "active" : ""} onClick={() => setTab("sessions")}>Sessions ({overview.total_sessions})</button>
        <button className={tab === "projects" ? "active" : ""} onClick={() => setTab("projects")}>Projects ({overview.project_summaries.length})</button>
      </nav>
      <div className="content">
        {projectFilter && (
          <div className="active-filter-bar">
            <span>Filtered by project: <strong>{shortenProject(projectFilter)}</strong></span>
            <button className="clear-filter-btn" onClick={() => setProjectFilter(null)}>Clear filter</button>
          </div>
        )}
        {tab === "overview" && (<>
          <div className="metrics-grid">
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
          <div className="section">
            <h3>Top Sessions by Cost</h3>
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
