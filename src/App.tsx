import { useEffect, useMemo, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import type { OverviewMetrics, SessionSummary, ProjectSummary } from "./types";
import "./App.css";

type Tab = "overview" | "sessions" | "projects";
type SortField = "cost" | "date" | "tokens" | "cache_hit" | "messages";
type SortDir = "asc" | "desc";
type DateRange = "7d" | "30d" | "90d" | "all";

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
  if (!ts) return "—";
  const d = new Date(ts);
  return d.toLocaleDateString("en-US", { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" });
}

function shortenProject(path: string): string {
  const parts = path.split("/");
  return parts.length > 2 ? parts.slice(-2).join("/") : path;
}

function filterByDateRange(sessions: SessionSummary[], range: DateRange): SessionSummary[] {
  if (range === "all") return sessions;
  const days = range === "7d" ? 7 : range === "30d" ? 30 : 90;
  const cutoff = new Date();
  cutoff.setDate(cutoff.getDate() - days);
  const cutoffStr = cutoff.toISOString();
  return sessions.filter((s) => (s.first_timestamp ?? "") >= cutoffStr);
}

function computeOverview(sessions: SessionSummary[]): OverviewMetrics {
  let totalInput = 0, totalOutput = 0, totalCacheWrite = 0, totalCacheRead = 0, totalCost = 0;
  const projectMap = new Map<string, SessionSummary[]>();
  const dailyMap = new Map<string, { cost: number; input: number; output: number; cw: number; cr: number; source: string }>();

  let systemOverhead = 0;
  for (const s of sessions) {
    totalInput += s.total_input_tokens;
    totalOutput += s.total_output_tokens;
    totalCacheWrite += s.total_cache_write_tokens;
    totalCacheRead += s.total_cache_read_tokens;
    totalCost += s.estimated_cost_usd;

    const key = s.project || "unknown";
    if (!projectMap.has(key)) projectMap.set(key, []);
    projectMap.get(key)!.push(s);

    if (s.first_timestamp) {
      const date = s.first_timestamp.slice(0, 10);
      const d = dailyMap.get(date) ?? { cost: 0, input: 0, output: 0, cw: 0, cr: 0, source: s.source };
      d.cost += s.estimated_cost_usd;
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
  const inputCost = (totalInput / 1e6) * 5.0;
  const outputCost = (totalOutput / 1e6) * 25.0;
  const cwCost = (totalCacheWrite / 1e6) * 6.25;
  const crCost = (totalCacheRead / 1e6) * 0.5;

  const projectSummaries = Array.from(projectMap.entries()).map(([proj, sess]) => {
    const pi = sess.reduce((a, s) => a + s.total_input_tokens, 0);
    const po = sess.reduce((a, s) => a + s.total_output_tokens, 0);
    const pcw = sess.reduce((a, s) => a + s.total_cache_write_tokens, 0);
    const pcr = sess.reduce((a, s) => a + s.total_cache_read_tokens, 0);
    const pc = sess.reduce((a, s) => a + s.estimated_cost_usd, 0);
    const ptc = pcr + pcw + pi;
    return {
      project: proj,
      session_count: sess.length,
      total_cost_usd: pc,
      total_input_tokens: pi,
      total_output_tokens: po,
      total_cache_write_tokens: pcw,
      total_cache_read_tokens: pcr,
      avg_cache_hit_rate: ptc > 0 ? pcr / ptc : 0,
    };
  }).sort((a, b) => b.total_cost_usd - a.total_cost_usd);

  const dailyCosts = Array.from(dailyMap.entries()).map(([date, d]) => ({
    date, cost_usd: d.cost, input_tokens: d.input, output_tokens: d.output,
    cache_write_tokens: d.cw, cache_read_tokens: d.cr, source: d.source,
  })).sort((a, b) => a.date.localeCompare(b.date));

  const topSessions = [...sessions].sort((a, b) => b.estimated_cost_usd - a.estimated_cost_usd).slice(0, 20);

  return {
    total_sessions: sessions.length,
    total_cost_usd: totalCost,
    total_input_tokens: totalInput,
    total_output_tokens: totalOutput,
    total_cache_write_tokens: totalCacheWrite,
    total_cache_read_tokens: totalCacheRead,
    avg_cache_hit_rate: totalCtx > 0 ? totalCacheRead / totalCtx : 0,
    cost_breakdown: { input_cost: inputCost, output_cost: outputCost, cache_write_cost: cwCost, cache_read_cost: crCost, total_cost: inputCost + outputCost + cwCost + crCost },
    estimated_system_overhead_tokens: systemOverhead,
    daily_costs: dailyCosts,
    project_summaries: projectSummaries,
    top_sessions: topSessions,
  };
}

function DateRangeSelector({ value, onChange }: { value: DateRange; onChange: (v: DateRange) => void }) {
  const options: { label: string; value: DateRange }[] = [
    { label: "7 Days", value: "7d" },
    { label: "30 Days", value: "30d" },
    { label: "90 Days", value: "90d" },
    { label: "All Time", value: "all" },
  ];
  return (
    <div className="date-range-selector">
      {options.map((o) => (
        <button key={o.value} className={value === o.value ? "active" : ""} onClick={() => onChange(o.value)}>
          {o.label}
        </button>
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
          <div
            key={s.label}
            className="cost-bar-segment"
            style={{ width: `${(s.value / total) * 100}%`, backgroundColor: s.color }}
            title={`${s.label}: ${formatCost(s.value)}`}
          />
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

function DailyCostChart({ dailyCosts }: { dailyCosts: OverviewMetrics["daily_costs"] }) {
  if (dailyCosts.length === 0) return null;

  const recent = dailyCosts.slice(-30);
  const maxCost = Math.max(...recent.map((d) => d.cost_usd), 0.01);

  return (
    <div className="daily-chart-section">
      <h3>Daily Cost (last 30 days)</h3>
      <div className="daily-chart">
        {recent.map((d) => {
          const total = d.cost_usd || 0.01;
          const breakdown = {
            input: (d.input_tokens / 1_000_000) * 5.0,
            output: (d.output_tokens / 1_000_000) * 25.0,
            cache_write: (d.cache_write_tokens / 1_000_000) * 6.25,
            cache_read: (d.cache_read_tokens / 1_000_000) * 0.5,
          };
          const barTotal = breakdown.input + breakdown.output + breakdown.cache_write + breakdown.cache_read;
          const heightPct = (total / maxCost) * 100;

          return (
            <div key={d.date} className="daily-bar-wrapper" title={`${d.date}: ${formatCost(d.cost_usd)}`}>
              <div className="daily-bar-stack" style={{ height: `${heightPct}%` }}>
                {barTotal > 0 && (
                  <>
                    <div className="stack-segment" style={{ flex: breakdown.output, backgroundColor: "var(--color-output)" }} />
                    <div className="stack-segment" style={{ flex: breakdown.cache_write, backgroundColor: "var(--color-cache-write)" }} />
                    <div className="stack-segment" style={{ flex: breakdown.input, backgroundColor: "var(--color-input)" }} />
                    <div className="stack-segment" style={{ flex: breakdown.cache_read, backgroundColor: "var(--color-cache-read)" }} />
                  </>
                )}
                {barTotal === 0 && <div className="stack-segment" style={{ flex: 1, backgroundColor: "var(--color-primary)" }} />}
              </div>
              <div className="daily-label">{d.date.slice(5)}</div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

function SortHeader({
  label,
  field,
  currentField,
  currentDir,
  onSort,
}: {
  label: string;
  field: SortField;
  currentField: SortField;
  currentDir: SortDir;
  onSort: (f: SortField) => void;
}) {
  const active = currentField === field;
  return (
    <th className={`sortable ${active ? "sort-active" : ""}`} onClick={() => onSort(field)}>
      {label} {active ? (currentDir === "desc" ? "↓" : "↑") : ""}
    </th>
  );
}

function Recommendations({ sessions, overview }: { sessions: SessionSummary[]; overview: OverviewMetrics }) {
  const tips = useMemo(() => {
    const result: { severity: "high" | "medium" | "low"; text: string }[] = [];

    // Cache hit rate analysis
    if (overview.avg_cache_hit_rate < 0.5) {
      result.push({
        severity: "high",
        text: `Cache hit rate is ${formatPercent(overview.avg_cache_hit_rate)} — below 50%. Short sessions cause frequent cache misses. Try longer, focused sessions to improve cache reuse.`,
      });
    } else if (overview.avg_cache_hit_rate < 0.7) {
      result.push({
        severity: "medium",
        text: `Cache hit rate is ${formatPercent(overview.avg_cache_hit_rate)}. Consider consolidating related tasks into fewer sessions to improve cache efficiency.`,
      });
    }

    // Cache write cost analysis
    const cacheWriteCostPct = overview.cost_breakdown.cache_write_cost / (overview.cost_breakdown.total_cost || 1);
    if (cacheWriteCostPct > 0.3) {
      result.push({
        severity: "high",
        text: `Cache writes account for ${formatPercent(cacheWriteCostPct)} of total cost (${formatCost(overview.cost_breakdown.cache_write_cost)}). Each new session pays the full cache write cost. Reduce session restarts and trim CLAUDE.md/skills to lower this.`,
      });
    }

    // System overhead analysis
    if (overview.estimated_system_overhead_tokens > 50000) {
      result.push({
        severity: "medium",
        text: `Estimated system overhead is ${formatTokens(overview.estimated_system_overhead_tokens)} tokens per session. Review your CLAUDE.md, installed skills, and plugins — each adds to the "token tax" paid on every session start.`,
      });
    }

    // Short session detection
    const shortSessions = sessions.filter((s) => s.source === "claude" && s.message_count <= 4 && s.estimated_cost_usd > 0.5);
    if (shortSessions.length > 5) {
      result.push({
        severity: "medium",
        text: `${shortSessions.length} short sessions (≤4 messages, >$0.50 each) detected. These pay full cache write costs with minimal cache reuse. Consider batching related questions.`,
      });
    }

    // Output-heavy sessions
    const outputCostPct = overview.cost_breakdown.output_cost / (overview.cost_breakdown.total_cost || 1);
    if (outputCostPct > 0.5) {
      result.push({
        severity: "medium",
        text: `Output tokens account for ${formatPercent(outputCostPct)} of costs. Consider asking for more concise responses or using diff-style edits instead of full file rewrites.`,
      });
    }

    if (result.length === 0) {
      result.push({
        severity: "low",
        text: "Your usage patterns look efficient. Keep monitoring cache hit rates and session lengths.",
      });
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

function ContextComposition({ overview }: { overview: OverviewMetrics }) {
  const totalContext = overview.total_input_tokens + overview.total_cache_write_tokens + overview.total_cache_read_tokens;
  if (totalContext === 0) return null;

  const overhead = overview.estimated_system_overhead_tokens;
  const overheadCost = (overhead / 1_000_000) * 6.25 * overview.total_sessions;

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

function SessionsTable({
  sessions,
  sortField,
  sortDir,
  onSort,
  filter,
  onFilterChange,
}: {
  sessions: SessionSummary[];
  sortField: SortField;
  sortDir: SortDir;
  onSort: (f: SortField) => void;
  filter: string;
  onFilterChange: (v: string) => void;
}) {
  const filtered = useMemo(() => {
    let result = sessions;
    if (filter) {
      const q = filter.toLowerCase();
      result = result.filter(
        (s) =>
          s.project.toLowerCase().includes(q) ||
          (s.git_branch ?? "").toLowerCase().includes(q) ||
          s.source.toLowerCase().includes(q)
      );
    }

    const sorted = [...result].sort((a, b) => {
      let cmp = 0;
      switch (sortField) {
        case "cost":
          cmp = a.estimated_cost_usd - b.estimated_cost_usd;
          break;
        case "date":
          cmp = (a.first_timestamp ?? "").localeCompare(b.first_timestamp ?? "");
          break;
        case "tokens":
          cmp =
            a.total_input_tokens + a.total_output_tokens - (b.total_input_tokens + b.total_output_tokens);
          break;
        case "cache_hit":
          cmp = a.cache_hit_rate - b.cache_hit_rate;
          break;
        case "messages":
          cmp = a.message_count - b.message_count;
          break;
      }
      return sortDir === "desc" ? -cmp : cmp;
    });

    return sorted;
  }, [sessions, filter, sortField, sortDir]);

  return (
    <div>
      <div className="filter-bar">
        <input
          type="text"
          placeholder="Filter by project, branch, or source..."
          value={filter}
          onChange={(e) => onFilterChange(e.target.value)}
          className="filter-input"
        />
        <span className="filter-count">{filtered.length} sessions</span>
      </div>
      <div className="table-container">
        <table>
          <thead>
            <tr>
              <th>Project</th>
              <th>Branch</th>
              <SortHeader label="Messages" field="messages" currentField={sortField} currentDir={sortDir} onSort={onSort} />
              <SortHeader label="Cost" field="cost" currentField={sortField} currentDir={sortDir} onSort={onSort} />
              <SortHeader label="Cache Hit" field="cache_hit" currentField={sortField} currentDir={sortDir} onSort={onSort} />
              <SortHeader label="Input" field="tokens" currentField={sortField} currentDir={sortDir} onSort={onSort} />
              <th>Output</th>
              <th>Cache Write</th>
              <th>Cache Read</th>
              <th>Subagents</th>
              <th>Source</th>
              <SortHeader label="Date" field="date" currentField={sortField} currentDir={sortDir} onSort={onSort} />
            </tr>
          </thead>
          <tbody>
            {filtered.map((s) => (
              <tr key={s.session_id}>
                <td title={s.project}>{shortenProject(s.project)}</td>
                <td>{s.git_branch ?? "—"}</td>
                <td>{s.message_count}</td>
                <td className="cost-cell">{formatCost(s.estimated_cost_usd)}</td>
                <td>{formatPercent(s.cache_hit_rate)}</td>
                <td>{formatTokens(s.total_input_tokens)}</td>
                <td>{formatTokens(s.total_output_tokens)}</td>
                <td>{formatTokens(s.total_cache_write_tokens)}</td>
                <td>{formatTokens(s.total_cache_read_tokens)}</td>
                <td>{s.subagent_count > 0 ? `${s.subagent_count} (${formatCost(s.subagent_cost_usd)})` : "—"}</td>
                <td><span className={`source-badge ${s.source}`}>{s.source}</span></td>
                <td>{formatDate(s.first_timestamp)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

function ProjectsTable({ projects }: { projects: ProjectSummary[] }) {
  const [sortBy, setSortBy] = useState<"cost" | "sessions" | "cache">("cost");
  const sorted = useMemo(() => {
    return [...projects].sort((a, b) => {
      switch (sortBy) {
        case "cost":
          return b.total_cost_usd - a.total_cost_usd;
        case "sessions":
          return b.session_count - a.session_count;
        case "cache":
          return b.avg_cache_hit_rate - a.avg_cache_hit_rate;
        default:
          return 0;
      }
    });
  }, [projects, sortBy]);

  return (
    <div className="table-container">
      <table>
        <thead>
          <tr>
            <th>Project</th>
            <th className={`sortable ${sortBy === "sessions" ? "sort-active" : ""}`} onClick={() => setSortBy("sessions")}>
              Sessions {sortBy === "sessions" ? "↓" : ""}
            </th>
            <th className={`sortable ${sortBy === "cost" ? "sort-active" : ""}`} onClick={() => setSortBy("cost")}>
              Total Cost {sortBy === "cost" ? "↓" : ""}
            </th>
            <th className={`sortable ${sortBy === "cache" ? "sort-active" : ""}`} onClick={() => setSortBy("cache")}>
              Cache Hit Rate {sortBy === "cache" ? "↓" : ""}
            </th>
            <th>Input</th>
            <th>Output</th>
            <th>Cache Write</th>
            <th>Cache Read</th>
          </tr>
        </thead>
        <tbody>
          {sorted.map((p) => (
            <tr key={p.project}>
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

function App() {
  const [rawOverview, setRawOverview] = useState<OverviewMetrics | null>(null);
  const [allSessions, setAllSessions] = useState<SessionSummary[]>([]);
  const [tab, setTab] = useState<Tab>("overview");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [dateRange, setDateRange] = useState<DateRange>("30d");

  // Session table state
  const [sortField, setSortField] = useState<SortField>("date");
  const [sortDir, setSortDir] = useState<SortDir>("desc");
  const [filter, setFilter] = useState("");

  const handleSort = (field: SortField) => {
    if (field === sortField) {
      setSortDir(sortDir === "desc" ? "asc" : "desc");
    } else {
      setSortField(field);
      setSortDir("desc");
    }
  };

  const loadData = async () => {
    setLoading(true);
    setError(null);
    try {
      const [ov, sess] = await Promise.all([
        invoke<OverviewMetrics>("get_overview"),
        invoke<SessionSummary[]>("get_sessions"),
      ]);
      setRawOverview(ov);
      setAllSessions(sess);
    } catch (e) {
      setError(String(e));
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadData();
  }, []);

  const sessions = useMemo(() => filterByDateRange(allSessions, dateRange), [allSessions, dateRange]);
  const overview = useMemo(() => sessions.length > 0 ? computeOverview(sessions) : rawOverview, [sessions, rawOverview]);

  if (loading) {
    return (
      <main className="container">
        <div className="loading">Loading session data...</div>
      </main>
    );
  }

  if (error) {
    return (
      <main className="container">
        <div className="error">Error: {error}</div>
      </main>
    );
  }

  if (!overview) return null;

  return (
    <main className="app">
      <header className="app-header">
        <div className="header-top">
          <div>
            <h1>Token Wise</h1>
            <p className="app-subtitle">AI Coding Agent Cost Analyzer</p>
          </div>
          <div className="header-controls">
            <DateRangeSelector value={dateRange} onChange={setDateRange} />
            <button className="refresh-btn" onClick={loadData} disabled={loading}>
              {loading ? "Loading..." : "Refresh"}
            </button>
          </div>
        </div>
      </header>

      <nav className="tabs">
        <button className={tab === "overview" ? "active" : ""} onClick={() => setTab("overview")}>
          Overview
        </button>
        <button className={tab === "sessions" ? "active" : ""} onClick={() => setTab("sessions")}>
          Sessions ({overview.total_sessions})
        </button>
        <button className={tab === "projects" ? "active" : ""} onClick={() => setTab("projects")}>
          Projects ({overview.project_summaries.length})
        </button>
      </nav>

      <div className="content">
        {tab === "overview" && (
          <>
            <div className="metrics-grid">
              <MetricCard label="Total Cost" value={formatCost(overview.total_cost_usd)} />
              <MetricCard label="Sessions" value={overview.total_sessions.toString()} />
              <MetricCard
                label="Cache Hit Rate"
                value={formatPercent(overview.avg_cache_hit_rate)}
                sub="higher is better"
              />
              <MetricCard
                label="System Overhead"
                value={formatTokens(overview.estimated_system_overhead_tokens)}
                sub="per session (est.)"
              />
              <MetricCard label="Output Tokens" value={formatTokens(overview.total_output_tokens)} />
              <MetricCard label="Cache Write Tokens" value={formatTokens(overview.total_cache_write_tokens)} sub="$6.25/MTok" />
            </div>

            <CostBar breakdown={overview.cost_breakdown} />
            <ContextComposition overview={overview} />
            <DailyCostChart dailyCosts={overview.daily_costs} />
            <Recommendations sessions={sessions} overview={overview} />

            <div className="section">
              <h3>Top Sessions by Cost</h3>
              <SessionsTable
                sessions={overview.top_sessions}
                sortField={sortField}
                sortDir={sortDir}
                onSort={handleSort}
                filter=""
                onFilterChange={() => {}}
              />
            </div>
          </>
        )}

        {tab === "sessions" && (
          <SessionsTable
            sessions={sessions}
            sortField={sortField}
            sortDir={sortDir}
            onSort={handleSort}
            filter={filter}
            onFilterChange={setFilter}
          />
        )}

        {tab === "projects" && <ProjectsTable projects={overview.project_summaries} />}
      </div>
    </main>
  );
}

export default App;
