# CLAUDE.md — trusty-cage-plugin

## Overview

Claude Code plugin providing skills for orchestrating trusty-cage containers. Published as a marketplace plugin — users install via `/plugin marketplace add areese801/trusty-cage-plugin`.

## Versioning

**IMPORTANT:** Bump the version in `plugins/trusty-cage/.claude-plugin/plugin.json` whenever skill files change. Without a version bump, users won't receive updates due to the plugin cache.

- Version lives in `plugin.json` only (not `marketplace.json` — `plugin.json` wins silently if both are set)
- Follow semver: patch for fixes, minor for new features, major for breaking changes
- After bumping, users get the update via `/plugin update trusty-cage@trusty-cage-plugin`
- Also add an entry to `CHANGELOG.md` under the new version heading

## Structure

```
.claude-plugin/marketplace.json          # Marketplace metadata (name, owner, plugin list)
plugins/trusty-cage/
  .claude-plugin/plugin.json             # Plugin metadata + VERSION (canonical source)
  skills/
    cage-orchestrator/
      SKILL.md                           # Outer/inner orchestration workflow
      inner-agent-protocol.md            # Rules for when Claude is inside a cage
      messaging-protocol.md              # Message envelope / directory layout
      prompt-templates.md                # Optional task-prompt starting points
      scripts/tc-url-convert.sh          # SSH-to-HTTPS URL converter
    cage-iterate/SKILL.md                # Continuous improvement loop
CHANGELOG.md                             # User-facing change history
```

## Git Workflow

- Work happens on feature branches off `main`
- Merges to `main` via PR (branch protection enabled)
- Never push directly to `main`
- Update `CHANGELOG.md` in the same PR as any user-facing skill change
