import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { useWindowVirtualizer } from "@tanstack/react-virtual";
import { motion, AnimatePresence } from "framer-motion";
import type { OverviewMetrics, SessionSummary, ProjectSummary, SessionDetail, TurnMetrics, ContentAnalysis, ContentCategory } from "./types";
import { LoadingScreen } from "./LoadingScreen";

import "./App.css";

type Tab = "overview" | "sessions" | "projects";
type SortField = "cost" | "date" | "input" | "output" | "cache_write" | "cache_read" | "cache_hit" | "messages" | "duration";
type SortDir = "asc" | "desc";
type DateRange = "7d" | "30d" | "90d" | "all" | "custom";

type ModelPricing = { label: string; input: number; output: number; cacheWrite: number; cacheRead: number };

const MODEL_PRICING: Record<string, ModelPricing> = {
  opus:       { label: "Opus 4",     input: 15.0,  output: 75.0,  cacheWrite: 18.75, cacheRead: 1.50 },
  sonnet:     { label: "Sonnet 4",   input: 3.0,   output: 15.0,  cacheWrite: 3.75,  cacheRead: 0.30 },
  haiku:      { label: "Haiku 3.5",  input: 0.80,  output: 4.0,   cacheWrite: 1.0,   cacheRead: 0.08 },
  "gpt-5.4":  { label: "GPT-5.4",   input: 2.50,  output: 10.0,  cacheWrite: 0,     cacheRead: 0 },
  "gpt-5.2":  { label: "GPT-5.2",   input: 1.25,  output: 5.0,   cacheWrite: 0,     cacheRead: 0 },
  "gpt-4.1":  { label: "GPT-4.1",   input: 2.0,   output: 8.0,   cacheWrite: 0,     cacheRead: 0 },
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

function filterByDateRange(sessions: SessionSummary[], range: DateRange, customFrom?: string, customTo?: string): SessionSummary[] {
  if (range === "all") return sessions;
  if (range === "custom") {
    return sessions.filter((s) => {
      const ts = s.first_timestamp ?? "";
      if (customFrom && ts < customFrom) return false;
      if (customTo && ts > new Date(new Date(customTo).getTime() + 86400000).toISOString()) return false;
      return true;
    });
  }
  const days = range === "7d" ? 7 : range === "30d" ? 30 : 90;
  const cutoff = new Date();
  cutoff.setDate(cutoff.getDate() - days);
  const cutoffStr = cutoff.toISOString();
  return sessions.filter((s) => (s.first_timestamp ?? "") >= cutoffStr);
}

function getModelPricing(model: string): ModelPricing {
  return MODEL_PRICING[model] ?? MODEL_PRICING.sonnet;
}

function calcSessionCost(s: SessionSummary, p: ModelPricing): number {
  return (s.total_input_tokens / 1e6) * p.input + (s.total_output_tokens / 1e6) * p.output +
    (s.total_cache_write_tokens / 1e6) * p.cacheWrite + (s.total_cache_read_tokens / 1e6) * p.cacheRead;
}

function computeOverview(sessions: SessionSummary[], model: string = "sonnet"): OverviewMetrics {
  const p = getModelPricing(model);
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

/* --- FilterDropdown: generic reusable dropdown trigger + panel --- */

function FilterDropdown({ label, value, renderContent, className }: { label: string; value: string; renderContent: (close: () => void) => React.ReactNode; className?: string }) {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    const handler = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
    };
    document.addEventListener("mousedown", handler);
    return () => document.removeEventListener("mousedown", handler);
  }, [open]);

  return (
    <div ref={ref} className={`relative ${className ?? ""}`}>
      <button
        className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg border border-[var(--color-border)] bg-[var(--color-surface)] text-[13px] font-medium cursor-pointer transition-all duration-150 hover:border-[var(--color-primary)] min-w-[120px]"
        onClick={() => setOpen(!open)}
      >
        <span className="text-[var(--color-muted)]">{label}:</span>
        <span className="truncate max-w-[120px]">{value}</span>
        <span className={`text-[10px] text-[var(--color-muted)] ml-auto transition-transform duration-150 ${open ? "rotate-180" : ""}`}>▾</span>
      </button>
      {open && (
        <div className="filter-dropdown-panel absolute top-full left-0 mt-1 min-w-[200px] rounded-lg border border-[var(--color-border)] bg-[var(--color-surface)] shadow-lg z-50 py-1 max-h-[300px] overflow-y-auto">
          {renderContent(() => setOpen(false))}
        </div>
      )}
    </div>
  );
}

function FilterOption({ selected, onClick, label, sub, tooltip }: { selected: boolean; onClick: () => void; label: string; sub?: string; tooltip?: string }) {
  return (
    <button
      className={`w-full text-left px-3 py-2 text-[13px] border-none bg-transparent cursor-pointer transition-all duration-100 flex items-center justify-between gap-2 font-[inherit] ${selected ? "text-[var(--color-primary)] font-semibold bg-[rgba(74,144,217,0.08)]" : "text-inherit hover:bg-[rgba(74,144,217,0.05)]"}`}
      onClick={onClick}
      title={tooltip}
    >
      <span className="flex items-center gap-2">
        <span className={`w-3.5 h-3.5 rounded-full border-2 flex items-center justify-center flex-shrink-0 ${selected ? "border-[var(--color-primary)]" : "border-[var(--color-border)]"}`}>
          {selected && <span className="w-1.5 h-1.5 rounded-full bg-[var(--color-primary)]" />}
        </span>
        {label}
      </span>
      {sub && <span className="text-[var(--color-muted)] text-xs">{sub}</span>}
    </button>
  );
}

function DateRangeSelector({ value, onChange, customFrom, customTo, onCustomFromChange, onCustomToChange }: {
  value: DateRange; onChange: (v: DateRange) => void;
  customFrom: string; customTo: string;
  onCustomFromChange: (v: string) => void; onCustomToChange: (v: string) => void;
}) {
  const presets: { label: string; value: DateRange }[] = [
    { label: "7 Days", value: "7d" }, { label: "30 Days", value: "30d" }, { label: "90 Days", value: "90d" }, { label: "All Time", value: "all" },
  ];
  const displayValue = value === "custom" && customFrom
    ? `${new Date(customFrom).toLocaleDateString("en-US", { month: "short", day: "numeric" })} – ${customTo ? new Date(customTo).toLocaleDateString("en-US", { month: "short", day: "numeric" }) : "now"}`
    : presets.find((p) => p.value === value)?.label ?? "30 Days";

  return (
    <FilterDropdown label="Range" value={displayValue} renderContent={(close) => (<>
      {presets.map((o) => (
        <FilterOption key={o.value} selected={value === o.value} label={o.label} onClick={() => { onChange(o.value); close(); }} />
      ))}
      <div className="border-t border-[var(--color-border)] mt-1 pt-1 px-3 pb-2">
        <div className="text-[11px] text-[var(--color-muted)] font-medium mb-1.5">Custom Range</div>
        <div className="flex gap-2 items-center">
          <input type="date" value={customFrom} onChange={(e) => { onCustomFromChange(e.target.value); onChange("custom"); }}
            className="flex-1 px-2 py-1 text-xs rounded border border-[var(--color-border)] bg-[var(--color-surface)] text-inherit font-[inherit]" />
          <span className="text-[var(--color-muted)] text-xs">–</span>
          <input type="date" value={customTo} onChange={(e) => { onCustomToChange(e.target.value); onChange("custom"); }}
            className="flex-1 px-2 py-1 text-xs rounded border border-[var(--color-border)] bg-[var(--color-surface)] text-inherit font-[inherit]" />
        </div>
      </div>
    </>)} />
  );
}

function ModelSelector({ value, onChange, sourceFilter }: { value: string; onChange: (v: string) => void; sourceFilter: string }) {
  const [search, setSearch] = useState("");
  const displayValue = value === "all" ? "All" : (MODEL_PRICING[value]?.label ?? value);

  const modelEntries = useMemo(() => {
    let entries = Object.entries(MODEL_PRICING);
    if (sourceFilter === "claude") entries = entries.filter(([id]) => !id.startsWith("gpt"));
    else if (sourceFilter === "codex") entries = entries.filter(([id]) => id.startsWith("gpt"));
    return entries;
  }, [sourceFilter]);

  const filteredModels = useMemo(() => {
    if (!search) return modelEntries;
    return modelEntries.filter(([, p]) => p.label.toLowerCase().includes(search.toLowerCase()));
  }, [modelEntries, search]);

  const showSearch = modelEntries.length > 10;

  return (
    <FilterDropdown label="Model" value={displayValue} renderContent={(close) => (<>
      <FilterOption selected={value === "all"} label="All"
        tooltip="Average across all models"
        onClick={() => { onChange("all"); close(); setSearch(""); }} />
      {showSearch && (
        <div className="px-3 pb-1 pt-1">
          <input type="text" value={search} onChange={(e) => setSearch(e.target.value)}
            placeholder="Search models..."
            className="w-full px-2 py-1.5 text-[13px] rounded border border-[var(--color-border)] bg-[var(--color-surface)] text-inherit font-[inherit] outline-none focus:border-[var(--color-primary)]" />
        </div>
      )}
      {filteredModels.map(([id, p]) => (
        <FilterOption key={id} selected={value === id} label={p.label}
          tooltip={`Input: $${p.input}/MTok · Output: $${p.output}/MTok${p.cacheWrite ? ` · Cache Write: $${p.cacheWrite}/MTok · Cache Read: $${p.cacheRead}/MTok` : ""}`}
          onClick={() => { onChange(id); close(); setSearch(""); }} />
      ))}
      {filteredModels.length === 0 && (
        <div className="px-3 py-2 text-[13px] text-[var(--color-muted)]">No models found</div>
      )}
    </>)} />
  );
}

function MetricCard({ label, value, sub }: { label: string; value: string; sub?: string }) {
  return (
    <div className="bg-[var(--color-surface)] border border-[var(--color-border)] rounded-lg p-4">
      <div className="text-2xl font-bold leading-tight">{value}</div>
      <div className="text-xs text-[var(--color-muted)] mt-1 uppercase tracking-wide">{label}</div>
      <div className="text-[11px] text-[var(--color-muted)] mt-0.5">{sub ?? "\u00A0"}</div>
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

function SortHeader({ label, field, currentField, currentDir, onSort }: { label: string; field: SortField; currentField: SortField | null; currentDir: SortDir; onSort: (f: SortField) => void }) {
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

function SavingsPotential({ overview, sessions, pricing }: { overview: OverviewMetrics; sessions: SessionSummary[]; pricing: ModelPricing }) {
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
  sessions: SessionSummary[]; sortField: SortField | null; sortDir: SortDir; onSort: (f: SortField) => void;
  filter: string; onFilterChange: (v: string) => void; onSelectSession?: (id: string) => void;
}) {
  const filtered = useMemo(() => {
    let result = sessions;
    if (filter) {
      const q = filter.toLowerCase();
      result = result.filter((s) => s.project.toLowerCase().includes(q) || (s.git_branch ?? "").toLowerCase().includes(q) || s.source.toLowerCase().includes(q) || (s.title ?? "").toLowerCase().includes(q));
    }
    if (!sortField) return result;
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

  const tableRef = useRef<HTMLDivElement>(null);
  const [scrollMargin, setScrollMargin] = useState(0);
  const ROW_HEIGHT = 36;

  useEffect(() => {
    if (tableRef.current) {
      setScrollMargin(tableRef.current.offsetTop);
    }
  });

  const virtualizer = useWindowVirtualizer({
    count: filtered.length,
    estimateSize: () => ROW_HEIGHT,
    overscan: 20,
    scrollMargin,
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
      <div className="bg-[var(--color-surface)] border border-[var(--color-border)] rounded-lg overflow-x-auto virtual-table-container" ref={tableRef}>
        <table className="w-full border-collapse text-[13px]">
          <thead className="border-b border-[var(--color-border)]">
            <tr>
              <th className={`${thBase} min-w-[360px]`}>Project</th>
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
                    transform: `translateY(${virtualRow.start - virtualizer.options.scrollMargin}px)`,
                  }}
                >
                  <td className={tdBase} style={{ minWidth: 360, maxWidth: 520 }} title={s.project}>{shortenProject(s.project)}</td>
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
    { label: "All", value: "all", count: counts.all },
    { label: "Claude", value: "claude", count: counts.claude },
    { label: "Codex", value: "codex", count: counts.codex },
  ];
  const displayValue = options.find((o) => o.value === value)?.label ?? "All";
  return (
    <FilterDropdown label="Source" value={displayValue} renderContent={(close) => (<>
      {options.map((o) => (
        <FilterOption key={o.value} selected={value === o.value} label={o.label}
          sub={`${o.count}`} onClick={() => { onChange(o.value); close(); }} />
      ))}
    </>)} />
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
            <th className={`${thBase} min-w-[360px]`}>Project</th>
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
              <td className={tdBase} style={{ minWidth: 360, maxWidth: 520 }} title={p.project}>{shortenProject(p.project)}</td>
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

  // For many turns, show every Nth label — cap at ~20 visible labels max
  const effectiveTurns = turns.length / zoom;
  const labelInterval = effectiveTurns > 400 ? 50 : effectiveTurns > 200 ? 20 : effectiveTurns > 80 ? 10 : effectiveTurns > 40 ? 5 : effectiveTurns > 20 ? 2 : 1;

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
            const showLabel = t.turn_index === 0 || ((t.turn_index + 1) % labelInterval === 0) || t.turn_index === turns.length - 1;
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
                <div className={`text-[9px] mt-1 select-none ${showLabel ? "text-[var(--color-muted)]" : "text-transparent"}`}>{t.turn_index + 1}</div>
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

const CATEGORY_COLORS: Record<string, string> = {
  "File Reads": "#4A90D9",
  "Code Search": "#7B68EE",
  "Shell Commands": "#E74C3C",
  "File Edits": "#F39C12",
  "Web Content": "#1ABC9C",
  "Subagents": "#9B59B6",
  "External Tools": "#27AE60",
  "Thinking": "#95A5A6",
  "Assistant Text": "#3498DB",
  "User Prompts": "#E67E22",
  "Other Tools": "#BDC3C7",
  "Other": "#BDC3C7",
};

function DonutChart({ categories, total }: { categories: ContentCategory[]; total: number }) {
  const size = 200;
  const cx = size / 2;
  const cy = size / 2;
  const outerR = 90;
  const innerR = 55;

  if (total === 0) return null;

  const segments: { path: string; color: string; label: string; pct: number }[] = [];
  let cumAngle = -Math.PI / 2;

  // Merge small categories into a combined list sorted by tokens
  const sorted = [...categories].sort((a, b) => b.estimated_tokens - a.estimated_tokens);

  for (const cat of sorted) {
    const fraction = cat.estimated_tokens / total;
    if (fraction < 0.005) continue;
    const angle = fraction * 2 * Math.PI;
    const startAngle = cumAngle;
    const endAngle = cumAngle + angle;
    const largeArc = angle > Math.PI ? 1 : 0;

    const x1o = cx + outerR * Math.cos(startAngle);
    const y1o = cy + outerR * Math.sin(startAngle);
    const x2o = cx + outerR * Math.cos(endAngle);
    const y2o = cy + outerR * Math.sin(endAngle);
    const x1i = cx + innerR * Math.cos(endAngle);
    const y1i = cy + innerR * Math.sin(endAngle);
    const x2i = cx + innerR * Math.cos(startAngle);
    const y2i = cy + innerR * Math.sin(startAngle);

    const path = `M ${x1o} ${y1o} A ${outerR} ${outerR} 0 ${largeArc} 1 ${x2o} ${y2o} L ${x1i} ${y1i} A ${innerR} ${innerR} 0 ${largeArc} 0 ${x2i} ${y2i} Z`;
    segments.push({ path, color: CATEGORY_COLORS[cat.category] || "#BDC3C7", label: cat.category, pct: cat.percentage });
    cumAngle = endAngle;
  }

  return (
    <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} className="block mx-auto">
      {segments.map((seg, i) => (
        <path key={i} d={seg.path} fill={seg.color} stroke="var(--color-surface)" strokeWidth="1.5">
          <title>{seg.label}: {seg.pct.toFixed(1)}%</title>
        </path>
      ))}
      <text x={cx} y={cy - 6} textAnchor="middle" fill="var(--color-text)" fontSize="16" fontWeight="bold">{formatTokens(total)}</text>
      <text x={cx} y={cy + 12} textAnchor="middle" fill="var(--color-muted)" fontSize="11">est. tokens</text>
    </svg>
  );
}

function ContentAnalysisView({ analysis }: { analysis: ContentAnalysis }) {
  const [showTopItems, setShowTopItems] = useState(false);

  // Merge categories by category name for the legend
  const mergedCategories = useMemo(() => {
    const map = new Map<string, { tokens: number; count: number; pct: number }>();
    for (const c of analysis.categories) {
      const existing = map.get(c.category);
      if (existing) {
        existing.tokens += c.estimated_tokens;
        existing.count += c.count;
        existing.pct += c.percentage;
      } else {
        map.set(c.category, { tokens: c.estimated_tokens, count: c.count, pct: c.percentage });
      }
    }
    return [...map.entries()]
      .sort((a, b) => b[1].tokens - a[1].tokens)
      .map(([name, data]) => ({ name, ...data }));
  }, [analysis.categories]);

  return (
    <div className="mb-6">
      <h3 className="text-sm font-semibold mb-3">Content Analysis</h3>
      <div className="bg-[var(--color-surface)] border border-[var(--color-border)] rounded-lg p-4">
        <div className="grid grid-cols-1 md:grid-cols-[200px_1fr] gap-6 items-start">
          {/* Donut chart */}
          <DonutChart categories={analysis.categories} total={analysis.total_estimated_tokens} />

          {/* Category legend + table */}
          <div className="overflow-x-auto">
            <table className="w-full border-collapse text-[13px]">
              <thead className="border-b border-[var(--color-border)]">
                <tr>
                  <th className={thBase}>Category</th>
                  <th className={thBase}>Est. Tokens</th>
                  <th className={thBase}>Count</th>
                  <th className={thBase}>%</th>
                </tr>
              </thead>
              <tbody>
                {mergedCategories.map((c) => (
                  <tr key={c.name} className="hover:bg-[rgba(74,144,217,0.05)]">
                    <td className={tdBase}>
                      <span className="inline-block w-2.5 h-2.5 rounded-full mr-2 align-middle" style={{ backgroundColor: CATEGORY_COLORS[c.name] || "#BDC3C7" }} />
                      {c.name}
                    </td>
                    <td className={tdBase}>{formatTokens(c.tokens)}</td>
                    <td className={tdBase}>{c.count}</td>
                    <td className={tdBase}>{c.pct.toFixed(1)}%</td>
                  </tr>
                ))}
              </tbody>
            </table>

            {/* Subcategory detail for categories with subcategories */}
            {analysis.categories.filter(c => c.subcategory).length > 0 && (
              <div className="mt-3 pt-3 border-t border-[var(--color-border)]">
                <div className="text-[11px] text-[var(--color-muted)] font-semibold mb-2 uppercase">Subcategories</div>
                <table className="w-full border-collapse text-[12px]">
                  <tbody>
                    {analysis.categories.filter(c => c.subcategory).map((c, i) => (
                      <tr key={i} className="hover:bg-[rgba(74,144,217,0.05)]">
                        <td className={tdBase}>
                          <span className="inline-block w-2 h-2 rounded-full mr-1.5 align-middle" style={{ backgroundColor: CATEGORY_COLORS[c.category] || "#BDC3C7" }} />
                          {c.category} / {c.subcategory}
                        </td>
                        <td className={tdBase}>{formatTokens(c.estimated_tokens)}</td>
                        <td className={tdBase}>{c.count}</td>
                        <td className={tdBase}>{c.percentage.toFixed(1)}%</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>
        </div>

        {/* Top items (collapsible) */}
        {analysis.top_items.length > 0 && (
          <div className="mt-4 pt-4 border-t border-[var(--color-border)]">
            <button
              className="bg-none border-none text-[13px] font-semibold cursor-pointer text-[var(--color-primary)] p-0 hover:underline"
              onClick={() => setShowTopItems(!showTopItems)}
            >
              {showTopItems ? "\u25BC" : "\u25B6"} Top {analysis.top_items.length} Largest Content Blocks
            </button>
            {showTopItems && (
              <table className="w-full border-collapse text-[12px] mt-2">
                <thead className="border-b border-[var(--color-border)]">
                  <tr>
                    <th className={thBase}>Turn</th>
                    <th className={thBase}>Category</th>
                    <th className={thBase}>Tool</th>
                    <th className={thBase}>Est. Tokens</th>
                    <th className={thBase}>Preview</th>
                  </tr>
                </thead>
                <tbody>
                  {analysis.top_items.map((item, i) => (
                    <tr key={i} className="hover:bg-[rgba(74,144,217,0.05)]">
                      <td className={tdBase}>{item.turn_index + 1}</td>
                      <td className={tdBase}>
                        <span className="inline-block w-2 h-2 rounded-full mr-1.5 align-middle" style={{ backgroundColor: CATEGORY_COLORS[item.category] || "#BDC3C7" }} />
                        {item.category}
                      </td>
                      <td className={tdBase}>{item.tool_name ?? "\u2014"}</td>
                      <td className={tdBase}>{formatTokens(item.estimated_tokens)}</td>
                      <td className={`${tdBase} max-w-[300px] truncate`} title={item.preview}>{item.preview || "\u2014"}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>
        )}

        {/* Suggestions */}
        {analysis.suggestions.length > 0 && (
          <div className="mt-4 pt-4 border-t border-[var(--color-border)]">
            <div className="bg-[rgba(74,144,217,0.08)] border border-[rgba(74,144,217,0.2)] rounded-lg p-3">
              <div className="text-[12px] font-semibold text-[var(--color-primary)] mb-2">Optimization Suggestions</div>
              <ul className="list-none p-0 m-0">
                {analysis.suggestions.map((s, i) => (
                  <li key={i} className="text-[12px] text-[var(--color-muted)] mb-1 pl-4 relative before:content-['•'] before:absolute before:left-0 before:text-[var(--color-primary)]">{s}</li>
                ))}
              </ul>
            </div>
          </div>
        )}
      </div>
    </div>
  );
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
      {detail.content_analysis && <ContentAnalysisView analysis={detail.content_analysis} />}
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
  const [model, setModel] = useState<string>("all");
  const [customDateFrom, setCustomDateFrom] = useState("");
  const [customDateTo, setCustomDateTo] = useState("");
  const [sessionDetail, setSessionDetail] = useState<SessionDetail | null>(null);
  const [refreshing, setRefreshing] = useState(false);
  const [detailLoading, setDetailLoading] = useState(false);
  const [sortField, setSortField] = useState<SortField | null>(null);
  const [sortDir, setSortDir] = useState<SortDir>("desc");
  const [filter, setFilter] = useState("");
  const [sourceFilter, setSourceFilter] = useState("all");
  const [projectFilter, setProjectFilter] = useState<string | null>(null);

  const handleSort = (field: SortField) => {
    if (field === sortField) {
      if (sortDir === "desc") setSortDir("asc");
      else { setSortField(null); setSortDir("desc"); }
    } else { setSortField(field); setSortDir("desc"); }
  };

  const loadData = useCallback(async () => {
    setLoading(true); setError(null);
    try { setAllSessions(await invoke<SessionSummary[]>("get_sessions")); }
    catch (e) { setError(String(e)); }
    finally { setLoading(false); }
  }, []);

  const refreshData = useCallback(() => {
    setRefreshing(true); setError(null);
    // Defer invoke to next frame so React renders the loading state first
    requestAnimationFrame(() => {
      invoke<SessionSummary[]>("refresh_sessions")
        .then((data) => setAllSessions(data))
        .catch((e) => setError(String(e)))
        .finally(() => setRefreshing(false));
    });
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

  const sessions = useMemo(() => filterByDateRange(allSessions, dateRange, customDateFrom, customDateTo), [allSessions, dateRange, customDateFrom, customDateTo]);
  const pricedSessions = useMemo(() => {
    const p = getModelPricing(model);
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

  if (loading) return <LoadingScreen message="Loading session data..." />;
  if (error) return <main className="flex justify-center items-center min-h-screen"><motion.div initial={{ opacity: 0, scale: 0.95 }} animate={{ opacity: 1, scale: 1 }} className="text-base p-10 text-[#e74c3c]">Error: {error}</motion.div></main>;

  if (detailLoading || sessionDetail) {
    return (
      <div>
        <header className="glass-header mb-6">
          <div className="max-w-[1400px] mx-auto px-5">
            <div className="flex items-center gap-4 py-3">
              <img src="/icon-horizontal.png" alt="Token Wise" className="h-10" />
            </div>
          </div>
        </header>
        <main className="max-w-[1400px] mx-auto px-5">
          {detailLoading ? <LoadingScreen message="Loading session detail..." /> : sessionDetail ? <SessionDetailView detail={sessionDetail} onBack={() => setSessionDetail(null)} /> : null}
        </main>
      </div>
    );
  }

  return (
    <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }} transition={{ duration: 0.4 }}>
      <header className="glass-header mb-6">
        <div className="max-w-[1400px] mx-auto px-5">
          <div className="flex items-center gap-6 py-3">
            <motion.img
              src="/icon-horizontal.png"
              alt="Token Wise"
              className="h-10"
              initial={{ opacity: 0, x: -20 }}
              animate={{ opacity: 1, x: 0 }}
              transition={{ duration: 0.4, ease: "easeOut" }}
            />
            <nav className="flex gap-1 flex-1 justify-center">
              {([["overview", "Overview"], ["sessions", `Sessions (${overview.total_sessions})`], ["projects", `Projects (${overview.project_summaries.length})`]] as const).map(([t, label]) => (
                <motion.button
                  key={t}
                  className={`relative border-none px-4 py-1.5 rounded-full text-sm font-medium cursor-pointer transition-colors duration-200 font-[inherit] ${tab === t ? "bg-[var(--color-primary)] text-white shadow-sm" : "bg-transparent text-[var(--color-muted)] hover:text-[var(--color-primary)] hover:bg-[rgba(74,144,217,0.08)]"}`}
                  onClick={() => setTab(t)}
                  whileHover={{ scale: 1.05 }}
                  whileTap={{ scale: 0.95 }}
                >
                  {label}
                </motion.button>
              ))}
            </nav>
            <motion.button
              className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg border border-[var(--color-border)] bg-[var(--color-surface)] text-[13px] font-medium text-[var(--color-muted)] cursor-pointer transition-colors duration-150 hover:text-[var(--color-primary)] hover:border-[var(--color-primary)] disabled:opacity-50 disabled:cursor-not-allowed"
              onClick={refreshData}
              disabled={refreshing}
              title="Refresh data"
              whileHover={{ scale: 1.05 }}
              whileTap={{ scale: 0.95 }}
            >
              <svg className={refreshing ? "refresh-spin" : ""} width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
                <path d="M3 12a9 9 0 0 1 15-6.7L21 8" />
                <path d="M21 12a9 9 0 0 1-15 6.7L3 16" />
                <polyline points="21 3 21 8 16 8" />
                <polyline points="3 21 3 16 8 16" />
              </svg>
              Refresh
            </motion.button>
          </div>
          <div className="flex items-center gap-3 pb-3 flex-wrap">
            <SourceFilter value={sourceFilter} onChange={setSourceFilter} counts={sourceCounts} />
            <ModelSelector value={model} onChange={setModel} sourceFilter={sourceFilter} />
            <DateRangeSelector value={dateRange} onChange={setDateRange}
              customFrom={customDateFrom} customTo={customDateTo}
              onCustomFromChange={setCustomDateFrom} onCustomToChange={setCustomDateTo} />
          </div>
        </div>
      </header>
      <main className="max-w-[1400px] mx-auto px-5">
      <div>
        <AnimatePresence>
          {projectFilter && (
            <motion.div
              initial={{ opacity: 0, height: 0 }}
              animate={{ opacity: 1, height: "auto" }}
              exit={{ opacity: 0, height: 0 }}
              className="flex items-center gap-3 px-3 py-2 bg-[rgba(74,144,217,0.08)] border border-[rgba(74,144,217,0.2)] rounded-md mb-4 text-[13px] overflow-hidden"
            >
              <span>Filtered by project: <strong>{shortenProject(projectFilter)}</strong></span>
              <button className="bg-none border border-[var(--color-border)] px-2.5 py-1 rounded text-xs cursor-pointer text-[var(--color-muted)] font-[inherit] transition-all duration-150 hover:text-[var(--color-output)] hover:border-[var(--color-output)]" onClick={() => setProjectFilter(null)}>Clear filter</button>
            </motion.div>
          )}
        </AnimatePresence>
        <AnimatePresence mode="wait">
          <motion.div
            key={tab}
            initial={{ opacity: 0, y: 12 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -12 }}
            transition={{ duration: 0.2, ease: "easeInOut" }}
          >
            {tab === "overview" && (<>
              <div className="grid grid-cols-[repeat(auto-fit,minmax(180px,1fr))] gap-4 mb-6">
                {[
                  { label: "Total Cost", value: formatCost(overview.total_cost_usd), sub: overview.total_sessions > 0 ? `${formatCost(overview.total_cost_usd / overview.total_sessions)} avg/session` : undefined },
                  { label: "Sessions", value: overview.total_sessions.toString(), sub: (() => { const totalMs = pricedSessions.reduce((s, x) => s + getSessionDurationMs(x), 0); return totalMs > 0 ? `${formatDuration(totalMs)} total` : undefined; })() },
                  { label: "Cache Hit Rate", value: formatPercent(overview.avg_cache_hit_rate), sub: "higher is better" },
                  { label: "System Overhead", value: formatTokens(overview.estimated_system_overhead_tokens), sub: "per session (est.)" },
                  { label: "Output Tokens", value: formatTokens(overview.total_output_tokens) },
                  { label: "Cache Write Tokens", value: formatTokens(overview.total_cache_write_tokens), sub: `$${getModelPricing(model).cacheWrite}/MTok` },
                ].map((card, i) => (
                  <motion.div
                    key={card.label}
                    initial={{ opacity: 0, y: 20 }}
                    animate={{ opacity: 1, y: 0 }}
                    transition={{ delay: i * 0.05, duration: 0.3, ease: "easeOut" }}
                  >
                    <MetricCard {...card} />
                  </motion.div>
                ))}
              </div>
              <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }} transition={{ delay: 0.2 }}>
                <CostBar breakdown={overview.cost_breakdown} />
              </motion.div>
              <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }} transition={{ delay: 0.25 }}>
                <ContextComposition overview={overview} cacheWriteRate={getModelPricing(model).cacheWrite} />
              </motion.div>
              <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }} transition={{ delay: 0.3 }}>
                <DailyCostChart dailyCosts={overview.daily_costs} pricing={getModelPricing(model)} />
              </motion.div>
              <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }} transition={{ delay: 0.35 }}>
                <Recommendations sessions={pricedSessions} overview={overview} />
              </motion.div>
              <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }} transition={{ delay: 0.4 }}>
                <SavingsPotential overview={overview} sessions={pricedSessions} pricing={getModelPricing(model)} />
              </motion.div>
              <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }} transition={{ delay: 0.45 }} className="mb-6">
                <h3 className="text-sm font-semibold mb-3">Top Sessions by Cost</h3>
                <SessionsTable sessions={overview.top_sessions} sortField={sortField} sortDir={sortDir} onSort={handleSort} filter="" onFilterChange={() => {}} onSelectSession={loadSessionDetail} />
              </motion.div>
            </>)}
            {tab === "sessions" && <SessionsTable sessions={filteredSessions} sortField={sortField} sortDir={sortDir} onSort={handleSort} filter={filter} onFilterChange={setFilter} onSelectSession={loadSessionDetail} />}
            {tab === "projects" && <ProjectsTable projects={overview.project_summaries} onSelectProject={(project) => { setProjectFilter(project); setTab("sessions"); }} />}
          </motion.div>
        </AnimatePresence>
      </div>
    </main>
    </motion.div>
  );
}

export default App;
