import { homeDir as tauriHomeDir } from "@tauri-apps/api/path";

let _homeDir: string | null = null;

export async function initHomeDir(): Promise<void> {
  _homeDir = (await tauriHomeDir()) ?? null;
}

function relativeToBase(path: string, basePath: string): string | null {
  for (const marker of ["/.worktrees/", "/.claude/worktrees/"]) {
    const idx = path.indexOf(marker);
    if (idx !== -1) {
      const repoRoot = path.slice(0, idx);
      if (!basePath.startsWith(repoRoot) && !repoRoot.startsWith(basePath)) return null;

      const after = path.slice(idx + marker.length);
      const slash = after.indexOf("/");
      const effectiveBase = slash !== -1
        ? path.slice(0, idx + marker.length + slash)
        : path;

      const rel = path.slice(effectiveBase.length).replace(/^\//, "");
      return rel || null;
    }
  }

  if (!path.startsWith(basePath)) return null;
  return path.slice(basePath.length).replace(/^\//, "");
}

export function formatPath(path: string, maxSegments = 3, basePath?: string): string {
  let result = path;
  if (_homeDir && path.startsWith(_homeDir)) {
    result = "~" + path.slice(_homeDir.length);
  }

  if (basePath) {
    const rel = relativeToBase(path, basePath);
    if (rel) return rel;
    let base = basePath;
    if (_homeDir && base.startsWith(_homeDir)) {
      base = "~" + base.slice(_homeDir.length);
    }
    if (result.startsWith(base + "/")) {
      const rel2 = result.slice(base.length + 1);
      if (rel2) return rel2;
    }
  }

  const parts = result.split("/");
  if (parts.length > maxSegments) {
    return ".../" + parts.slice(-(maxSegments - 1)).join("/");
  }
  return result;
}

export function formatTokens(n: number): string {
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
  if (n >= 1_000) return `${(n / 1_000).toFixed(1)}K`;
  return n.toString();
}

export function formatCost(n: number): string {
  return `$${n.toFixed(2)}`;
}

export function formatPercent(n: number): string {
  return `${(n * 100).toFixed(1)}%`;
}

export function formatDate(ts: string | null): string {
  if (!ts) return "\u2014";
  const d = new Date(ts);
  return d.toLocaleDateString("en-US", { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" });
}

export function shortenProject(path: string): string {
  const parts = path.split("/");
  return parts.length > 2 ? parts.slice(-2).join("/") : path;
}

export function formatDuration(ms: number): string {
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
