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

You are working on **token-wise**, a native SwiftUI macOS app for analyzing AI coding agent session data and optimizing costs.

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
2. Follow the existing code style and conventions (Swift, SwiftUI, Swift Package Manager).
3. Write clean, self-documenting Swift code.
4. Keep shared parsing and business logic in `apple/Sources/TokenWiseCore/`.
5. Test changes with `cd apple && swift build && swift test`.
6. Create a PR with a clear description of what was done.
