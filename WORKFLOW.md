---
tracker:
  kind: github
  project_slug: banyudu/token-wise

workspace:
  root: .worktrees
  strategy: worktree
  branch:
    base: main

agent:
  kind: claude-code
  max_concurrent_agents: 3

review:
  enabled: true
---

You are working on **token-wise**, a Tauri + React desktop app for analyzing AI coding agent session data and optimizing costs.

## Issue

- **{{ issue.identifier }}**: {{ issue.title }}
- **State**: {{ issue.state }}
- **URL**: {{ issue.url }}

{% if issue.description %}
### Description

{{ issue.description }}
{% endif %}

{% if issue.labels.size > 0 %}
### Labels
{% for label in issue.labels %}- {{ label }}
{% endfor %}
{% endif %}

## Instructions

1. Read the existing codebase to understand the project structure before making changes.
2. Follow the existing code style and conventions (React + TypeScript, Vite, Tauri).
3. Write clean, self-documenting TypeScript code.
4. If the issue involves UI changes, use the existing CSS patterns in `src/App.css`.
5. If the issue involves Tauri backend changes, work in `src-tauri/`.
6. Test your changes compile with `pnpm run build`.
7. Create a PR with a clear description of what was done.
