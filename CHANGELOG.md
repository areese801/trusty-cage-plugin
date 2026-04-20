# Changelog

All notable changes to the trusty-cage plugin are documented here.

This project follows [Semantic Versioning](https://semver.org/): `MAJOR.MINOR.PATCH`.

---

## [1.4.0] - 2026-04-19

### Added
- **`smoke-test-templates.md`** — Host-side live smoke test starting points (HTTP API, CLI tool, TUI, MCP server) to run after `tc export`. Referenced from `SKILL.md` Step 9d and the Additional Resources list. Covers the sandbox + readiness-probe + curl + trap-cleanup pattern that avoids the backgrounded-process traps forbidden inside the cage. Completes phase-1 enhancement G as a doc pattern rather than a CLI command.

## [1.3.0] - 2026-04-19

### Added
- **Inner-prompt "do test, don't background-and-kill" guidance (Step 7).** The default Task Prompt template in `cage-orchestrator/SKILL.md` now explicitly tells the inner agent to run unit tests, integration tests, linters, type-checkers, and builds — but prohibits starting long-running servers/TUIs/MCPs in the cage and forbids `pkill`/`pgrep`/`kill -9` cleanup. Rationale: two cages in the phase-1 campaign died because the inner agent ran `pkill` as smoke-test cleanup and matched its own process tree. Regular testing is encouraged; only live-server E2E smoke is forbidden (that belongs to the outer orchestrator after `tc export`).
- **Same universal "don't background-and-kill" rule added to `inner-agent-protocol.md`** so sessions that land directly on the inner-agent protocol (e.g. interactive `claude` inside the cage, or a new session after `going_idle`) get the rule too.
- **PR merge verification step (Step 11b).** After the user reports a PR as merged, `cage-orchestrator` runs `gh pr view --json state,mergedAt,mergedBy` to verify the claim before destroying the cage. Skipped automatically for non-GitHub remotes (no `gh` dependency). Autonomous long-campaign mode can poll gently (every 5–10 min) instead of asking the user.
- **Deterministic env-naming recipe (Step 6).** Names now follow `<repo-basename>-<task-slug>` (slug derived from the task description, lowercase, hyphen-separated, ≤ 20 chars). Examples included in SKILL.md. Fixes the ad-hoc naming seen in the 12-cage campaign (`kanberoo-m04-rest`, `kanberoo-m06-ctl`, `kanberoo-m13-tui-detail`, …).
- **Restored `CLAUDE.md`** with versioning + structure guidance (was added in `63c9b78` but never made it to `main`).
- **Added `CHANGELOG.md`** — version history now has a user-facing home alongside commit messages.

## [1.2.0] - 2026-04-03

### Changed
- Extracted Inner Agent Protocol, Messaging Protocol Reference, and Prompt Templates into separate files to stay under Claude Code's recommended ~500-line SKILL.md size.
- Made git remote optional in prerequisites so repos without a remote can use `tc create --dir` mode.
- Replaced the inline polling script in the Standard Messaging Block with the `cage-wait` helper (installed in every cage since `trusty-cage` 0.9.0).

## [1.1.0] - 2026-03-31

### Fixed
- Inner-agent polling schedule: replaced exponential backoff with a tiered (10s / 30s / 60s) schedule so revisions are picked up faster.

## [1.0.0] - initial

- Initial plugin: `cage-orchestrator` and `cage-iterate` skills.
