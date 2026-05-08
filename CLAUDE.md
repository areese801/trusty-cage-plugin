# CLAUDE.md — trusty-cage-plugin

## Overview

This repo is the marketplace + plugin that ships Claude Code skills for orchestrating [trusty-cage](https://github.com/areese801/trusty-cage) containers. Users install via:

```
/plugin marketplace add areese801/trusty-cage-plugin
/plugin install trusty-cage@trusty-cage-plugin
```

This file is for developers working **on** this plugin. The `SKILL.md` files under `plugins/trusty-cage/skills/` are for outer Claude when **using** the plugin — keep that distinction in mind when editing.

## Adjacent repos

This plugin is one of three coordinated repos. Know what lives where before you change anything.

| Repo | What it is | Relationship to this repo |
|------|-----------|---------------------------|
| [`areese801/trusty-cage`](https://github.com/areese801/trusty-cage) | The Python `tc` CLI (`pip install trusty-cage`). Owns `tc create`, `tc launch`, `tc inbox`, `tc outbox`, `tc export`, `tc patch`, `tc destroy`, `tc auth`, etc. | The skills here drive `tc` commands. Any change to `tc`'s subcommand surface, flag names, or message envelope schema must ship in **both** repos. |
| [`areese801/kanbaroo-plugin`](https://github.com/areese801/kanbaroo-plugin) | Sibling Claude Code marketplace plugin. Ships `kanbaroo-workflow` (general Kanbaroo etiquette) and `kanbaroo-cage-bridge` (auto-mirrors a single cage dispatch onto a Kanbaroo story). | When both plugins are installed, the bridge skill augments `cage-orchestrator`'s lifecycle. Changes here that touch where the bridge hooks in (Step 7, 8, 9, 11) are coordination-sensitive — see "Drift watch list" below. |

### When to update this repo vs the trusty-cage Python repo

| Change type | This repo | trusty-cage repo |
|------------|-----------|------------------|
| `tc` CLI subcommand or flag added/renamed/removed | ✅ update SKILL.md callsites | ✅ implement the CLI change |
| New message type in the messaging envelope | ✅ update `messaging-protocol.md` | ✅ implement send/receive |
| Skill workflow text refined (wording, ordering, new step) | ✅ | — |
| Inner-agent rule added (e.g. "do not background-and-kill") | ✅ update Task Prompt + `inner-agent-protocol.md` | — |
| New `tc` capability that needs a workflow step (e.g. `tc patch`) | ✅ add the step to SKILL.md | ✅ implement the capability |

If you find yourself updating only one side and the change involves the CLI surface, stop — the other side is almost certainly also affected.

### When to update this repo vs the kanbaroo-plugin repo

| Change type | This repo | kanbaroo-plugin |
|------------|-----------|-----------------|
| Cage-orchestrator step renumbered or renamed | ✅ | ✅ bridge re-anchors by name (re-check) |
| New cage lifecycle event the bridge should mirror | ✅ document the inline note | ✅ add a new bridge hook |
| Bridge changes its hook surface | — | ✅ |
| Graceful-degradation language for absent bridge | ✅ here only | — |

The bridge is loosely coupled by design (it observes messages this skill surfaces; it never invokes `tc` itself). Most edits here do not require a paired edit there. The exception is renumbering or renaming cage-orchestrator steps that the bridge anchors on — flag those in the PR description.

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
      smoke-test-templates.md            # Host-side live smoke test shapes
      scripts/tc-url-convert.sh          # SSH-to-HTTPS URL converter
    cage-iterate/SKILL.md                # Continuous improvement loop
CHANGELOG.md                             # User-facing change history
```

## SKILL.md frontmatter conventions

Each SKILL.md begins with YAML frontmatter that drives Claude Code's skill matcher. Two patterns in use:

```yaml
---
name: cage-orchestrator
description: Orchestrates trusty-cage containers for autonomous AI work. Use when ... Do NOT use for ... If running inside a trusty-cage container (TRUSTY_CAGE=1 or user is `trustycage`), follow inner-agent protocol instead.
---
```

```yaml
---
name: cage-iterate
description: >-
  Continuous improvement loop for trusty-cage orchestration. Dispatches a task to
  ...
  Do NOT use for one-off cage tasks without improvement intent — use cage-orchestrator
  directly for those.
---
```

Conventions:

- **`name`** matches the skill's directory name.
- **`description`** is the matcher's primary signal — write it so a fresh Claude session reading only this string picks the skill in the right circumstances and **avoids** picking it in the wrong ones. Include both "Use when …" and "Do NOT use for …" phrases. Mention trigger phrases the user is likely to say verbatim ("spin up a cage", "let's iterate on the cage").
- **Detection-gate hints** belong in the description when the skill behaves differently inside vs outside a cage (see `cage-orchestrator`'s `TRUSTY_CAGE=1` clause).
- Multi-line descriptions use `>-` (folded, strip-final-newline). Single-line descriptions are inline.

## Style and spelling

- **American English bias** in skill prose, comments, and commit messages: `behavior`, `recognize`, `optimize`, `flavored`, `modeled`. Match the surrounding text in any file you edit.
- Preserve British spellings inside code identifiers and stdlib API names (`asyncio.CancelledError`, `Future.cancelled()`) — don't Americanize names that don't belong to us.
- Keep SKILL.md files under Claude Code's recommended ~500-line size. When a file grows past that, extract supporting docs (the cage-orchestrator skill split out `inner-agent-protocol.md`, `messaging-protocol.md`, `prompt-templates.md`, and `smoke-test-templates.md` for this reason — see `CHANGELOG.md` 1.2.0).
- Use Markdown tables for branching guidance (auth modes, exit codes, file types) — they read better than nested bullet lists.
- Match this repo's existing markdown formatting and line widths. Don't reflow paragraphs you didn't touch.

## Versioning and release process

The version lives in **one** place: `plugins/trusty-cage/.claude-plugin/plugin.json`. There is no PyPI publish step — the marketplace installs from a tagged commit on GitHub.

Conventions (also documented in the file's `Versioning` section):

- Bump the version in `plugin.json` whenever skill files change. Without a bump, users do not receive updates due to the plugin cache.
- Follow [SemVer](https://semver.org/): patch for fixes, minor for new features, major for breaking changes.
- The version field exists in `marketplace.json` too but `plugin.json` wins silently if both are set — do not rely on `marketplace.json`'s version.
- Add a `CHANGELOG.md` entry under the new version heading in the same PR as the bump.
- Users get the update via `/plugin update trusty-cage@trusty-cage-plugin`.

Release flow:

1. Open PR on a feature branch. Update SKILL.md + `plugin.json` version + `CHANGELOG.md` together.
2. Merge PR (branch protection requires it).
3. **The human operator tags the merge commit** (e.g. `git tag v1.6.0 && git push --tags`) — agents should not push tags from inside a cage or otherwise.
4. Marketplace installs pick up the new version on next `/plugin update`.

## Testing approach

There is no automated test suite for this repo — SKILL.md files are markdown that Claude Code interprets at runtime, and the only useful "test" is a live activation probe.

What to do before merging a non-trivial change:

1. Install the plugin into a Claude Code session locally (`/plugin marketplace add` from a local path or a feature-branch ref).
2. Trigger the skill via its expected phrase ("spin up a cage and …", "let's iterate on the cage").
3. Walk through enough of the workflow to exercise the changed steps. For cage-orchestrator changes that touch Step 7+, run a real cage end-to-end against a small task.
4. If the change touches messaging-protocol.md or the Standard Messaging Block, verify the inner agent's `cage-send` calls still parse on the host side.
5. For Kanbaroo-bridge coordination changes, install both plugins together and dispatch a cage that references a Kanbaroo story human ID. Confirm the bridge's hooks fire at the right moments.

Type checking, linting, and unit tests live in the `trusty-cage` Python repo, not here.

## Drift watch list

These are the cross-cutting concerns most likely to silently rot. Re-check them when reviewing a PR.

- **Skill description drift.** The `description` frontmatter field is the matcher's only signal. If a skill's body grows new triggers (new phrases users say, new conditions for activation) but the description does not, Claude Code will not pick the skill in those cases. After any non-trivial body edit, re-read the description and ask: would this still match the new content?
- **`tc` CLI surface drift.** SKILL.md mentions specific subcommands (`tc create`, `tc launch`, `tc inbox`, `tc outbox`, `tc export`, `tc patch`, `tc diff`, `tc auth`, `tc destroy`, `tc exists`) and specific flags (`--auth-mode`, `--no-attach`, `--prompt`, `--prompt-file`, `--background`, `--env`, `--yes`, `--stats`, `--output-dir`, `--base`, `--stdout`, `--poll`, `--timeout`, `--interval`, `--test`). When the `trusty-cage` Python repo renames or removes any of these, the corresponding SKILL.md callsites here go stale silently — outer Claude will issue commands that error. Search for the changed name and update.
- **Inner-agent protocol drift.** The Task Prompt template (Part 1 of cage-orchestrator's Step 7) and `inner-agent-protocol.md` cover overlapping ground. New rules ("do not background-and-kill", "do not start long-running servers") need to land in **both** places — Task Prompt is the primary channel for the initial dispatch, but `inner-agent-protocol.md` is what loads when a fresh Claude restarts inside the cage (after `going_idle`, or when a user attaches interactively).
- **Cross-skill coordination drift with kanbaroo-plugin.** The `kanbaroo-cage-bridge` skill (in the sibling repo) anchors on cage-orchestrator's step names. If you renumber or rename steps that the bridge hooks into (currently 7, 8, 9, 11), call it out in the PR description so the sibling repo can re-anchor. The bridge's own SKILL.md says: "If that skill renumbers, re-anchor by name rather than by number" — but a heads-up still helps.
- **Graceful-degradation language drift.** Wherever this repo's SKILL.md files mention Kanbaroo, they should also state what happens **without** Kanbaroo. New mentions added later should follow the same pattern. Audit with: `grep -n -i kanbaroo plugins/trusty-cage/skills/**/SKILL.md` and confirm each hit has a paired no-op clause nearby.
- **CHANGELOG ⇄ version drift.** Every version bump should have a CHANGELOG entry; every CHANGELOG entry should correspond to a version bump (or be under an "Unreleased" header that gets renamed at release time).

## Git Workflow

- Work happens on feature branches off `main`.
- Merges to `main` via PR (branch protection enabled).
- Never push directly to `main`.
- Update `CHANGELOG.md` in the same PR as any user-facing skill change.
- The human operator tags releases — agents do not.
