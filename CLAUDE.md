# CLAUDE.md — trusty-cage-plugin

## Overview

Claude Code plugin providing skills for orchestrating trusty-cage containers. Published as a marketplace plugin — users install via `/plugin marketplace add areese801/trusty-cage-plugin`.

## Versioning

**IMPORTANT:** Bump the version in `plugins/trusty-cage/.claude-plugin/plugin.json` whenever skill files change. Without a version bump, users won't receive updates due to caching.

- Version lives in `plugin.json` only (not `marketplace.json` — `plugin.json` wins silently if both are set)
- Follow semver: patch for fixes, minor for new features, major for breaking changes
- After bumping, users get the update via `/plugin update trusty-cage@trusty-cage-plugin`

## Structure

```
.claude-plugin/marketplace.json          # Marketplace metadata (name, owner, plugin list)
plugins/trusty-cage/
  .claude-plugin/plugin.json             # Plugin metadata + VERSION (canonical source)
  skills/
    cage-orchestrator/SKILL.md           # Outer/inner orchestration workflow
    cage-iterate/SKILL.md                # Continuous improvement loop
  scripts/
    tc-url-convert.sh                    # SSH-to-HTTPS URL converter
```

## Git Workflow

- Work happens on feature branches off `main`
- Merges to `main` via PR (branch protection enabled)
- Never push directly to `main`
