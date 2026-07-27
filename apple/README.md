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
.build/release/token-wise savings SESSION_ID # per-session cache-waste report
.build/release/token-wise analyze            # AI advice via your local claude/codex

# GUI (menu-bar cost readout + dashboard window)
swift run -c release TokenWiseApp

# Distributable .app bundle (GUI + CLI inside, signed when
# APPLE_SIGNING_IDENTITY is set; `appstore` uses sandbox entitlements)
../scripts/build-swift-app.sh dev        # → ../dist-swift/token-wise.app
../scripts/build-swift-app.sh appstore
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

Fully ported: models, pricing (with current-gen models + a fallback flag),
Claude + Codex parsing, overview/daily/hourly/project aggregation, content
analysis, the per-session cache-savings analyzer (four heuristics: wasted
writes, prefix invalidations, unreferenced blocks, repeated blocks), CLI
(incl. `savings`), the AI analyzer, and App Store sandbox handling (folder
grants via native picker + security-scoped bookmarks in `Grants.swift`, with
onboarding and Settings re-grant UI; non-sandboxed builds read the home dir
directly).

The GUI is a native macOS app rather than a web-port: `NavigationSplitView`
sidebar, toolbar filter menus (source + date range with custom pickers),
native Settings window (⌘,), sortable `Table`s with `.searchable` filtering,
Swift Charts everywhere (stacked daily/hourly cost bars, per-turn context
growth with cumulative/cost modes, content-category donut), push-navigation
session detail with the cache-savings report and turn-by-turn metrics, plus
the menu-bar cost readout.

`scripts/build-swift-app.sh` assembles and signs `token-wise.app` (GUI + CLI
in one bundle) for the `dev` or `appstore` channel.
