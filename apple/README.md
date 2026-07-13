# Token Wise (Swift)

Native macOS rewrite of Token Wise — a local, private cost & token-usage
dashboard for **Claude Code** and **Codex**. Pure Swift, no Rust/React/Tauri.

It reads your `~/.claude` session transcripts and `~/.codex` history directly on
your machine (nothing is uploaded) and shows where your tokens and dollars go,
per session and per project.

## Layout

```
apple/
  Sources/
    TokenWiseCore/   Parsing, pricing, aggregation, AI analysis (no UI, no deps)
    token-wise/      CLI (total / today / sessions / analyze)
    TokenWiseApp/    SwiftUI menu-bar + window app
  Tests/             Unit tests for pricing, parsing, formatting
```

The core has **zero external dependencies** — only Foundation and the system
`SQLite3` module — so it builds fully offline.

## Build & run

```sh
cd apple
swift build -c release
swift test

# CLI
.build/release/token-wise total
.build/release/token-wise today
.build/release/token-wise sessions --limit 10
.build/release/token-wise analyze            # AI advice via your local claude/codex

# GUI (menu-bar cost readout + dashboard window)
swift run -c release TokenWiseApp
```

## Performance

The first load parses every session file (~10–12s for several thousand
sessions, parsed in parallel across cores). Results are cached to
`~/Library/Caches/token-wise/` keyed by each file's modification time + size, so
subsequent runs only re-parse sessions that changed — `token-wise today` returns
in under two seconds.

## AI auto-analysis

`token-wise analyze` (and the **Analyze** tab in the app) discovers your
installed `claude` / `codex` CLI and runs it **headlessly with your existing
subscription** (`claude -p` / `codex exec`) — no API key. It feeds the model an
aggregate summary of your usage and asks for:

- **Actionable fixes** — concrete, numbers-grounded changes to cut spend
  (trim CLAUDE.md/skills/MCP tool defs, batch short sessions, raise cache hit
  rate, right-size the model).
- **Narrative** — a short plain-English read on where the money goes.

## Status

Ported and working: models, pricing (with current-gen models + a fallback
flag), Claude + Codex parsing, overview/daily/hourly/project aggregation,
content analysis, CLI, menu-bar + dashboard GUI, and the AI analyzer.

Deferred: the per-session cache-savings analyzer (`cache_savings.rs`), the
turn-by-turn detail charts in the GUI, and App Store sandbox/bookmark handling
for distribution.
