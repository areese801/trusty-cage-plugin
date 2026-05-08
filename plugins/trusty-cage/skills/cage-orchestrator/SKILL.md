---
name: cage-orchestrator
description: Orchestrates trusty-cage containers for autonomous AI work. Use when the user wants to delegate a task to an isolated Claude Code instance inside a trusty-cage container, or when the user says "spin up a cage", "run this in a cage", "let Claude go wild on this". Do NOT use for manual trusty-cage commands the user wants to run themselves. If running inside a trusty-cage container (TRUSTY_CAGE=1 or user is `trustycage`), follow inner-agent protocol instead.
---

# SKILL: Cage Orchestrator

Spin up an isolated trusty-cage container, launch an inner Claude Code agent to work autonomously, monitor for completion, and overlay results back onto the host repo.

## Step 1: Detection Gate

Check if running inside a cage:

1. Check `echo $TRUSTY_CAGE` — if value is `1`, load [inner-agent-protocol.md](inner-agent-protocol.md) and follow it instead of this workflow
2. Fallback: run `whoami` — if output is `trustycage`, load [inner-agent-protocol.md](inner-agent-protocol.md) and follow it instead of this workflow
3. Otherwise → continue with **Outer Orchestration Workflow**

---

## Outer Orchestration Workflow

### Companion skill: Kanbaroo bridge (optional)

If the user's Claude Code session also has the [`kanbaroo-plugin`](https://github.com/areese801/kanbaroo-plugin) installed and a Kanbaroo MCP wired up for this project (`mcp__kanbaroo__*` tools visible, a workspace identifiable for the project), the **`kanbaroo-cage-bridge`** skill from that plugin will activate alongside this orchestrator. The bridge mirrors cage lifecycle events onto a Kanbaroo story automatically:

- creates or attaches a story before dispatch,
- posts a throttled comment per `progress_update`,
- posts a summary comment on `tc export`,
- captures revision instructions as a comment before `tc inbox`.

You do not need to call `mcp__kanbaroo__*` tools yourself — the bridge owns the Kanbaroo side. This SKILL still owns every `tc` command and the cage lifecycle. Where the bridge augments a step, the inline note in that step says so explicitly.

**Graceful degradation.** If the bridge is not loaded (kanbaroo-plugin not installed, no Kanbaroo MCP configured, or no workspace identifiable for the project), this workflow runs exactly as it did before — no extra prompts, no failed tool calls, no Kanbaroo-shaped placeholders. Treat every "if the bridge is active" note below as a no-op in that case. Never block a cage dispatch waiting for Kanbaroo.

### Step 2: Validate Prerequisites and Set Up Environment

**Resolve `tc` once.** Prefer a global install; fall back to a project-local venv only when needed. Capture the resolved path in `$TC` — every subsequent step in this workflow uses `$TC` rather than a hardcoded path.

```bash
if command -v tc >/dev/null 2>&1 && tc --help >/dev/null 2>&1; then
  TC=tc
else
  python3 -m venv venv
  venv/bin/pip install trusty-cage
  TC=venv/bin/tc
fi
echo "Using tc at: $(command -v "$TC" || echo "$TC")"
```

If you fell back to the local venv path, ensure the project's `.gitignore` includes `venv/` so the venv is not committed to git and is protected from deletion during `tc export` (which uses `rsync --delete` but respects `.gitignore` patterns). When `$TC` resolved to a global install, this `.gitignore` advice does not apply.

**Then check the remaining prerequisites.** If any fail, stop and report the error with fix instructions.

| Check | Command | Error Message |
|-------|---------|---------------|
| trusty-cage installed | `$TC --help` | "trusty-cage is not available. Install with `pipx install trusty-cage` or let this skill create a project-local venv on the next run." |
| Docker running | `docker info >/dev/null 2>&1` | "Docker is not running. Start Docker or OrbStack first." |
| Git repo | `git rev-parse --is-inside-work-tree` | "Current directory is not a git repository." |

**Optionally** check for a git remote — this determines how the cage is created (Step 5/6):

```bash
REPO_URL=$(git remote get-url origin 2>/dev/null || echo "")
```

If `REPO_URL` is empty, the cage will be created from the local directory using `--dir`. A remote is **not** required.

### Step 3: Gather Task Description

- If the user already described the task, confirm your understanding and capture it as `TASK_DESCRIPTION`
- If not, ask: "What task should the inner Claude work on?"
- Be specific — this prompt is passed verbatim to the inner agent

**If the user references a Kanbaroo story human ID** (e.g. "let's work on `KAN-123`") and the bridge is active, the bridge will look the story up via `mcp__kanbaroo__get_story`, surface the title/description, and embed a condensed context block into the cage prompt automatically. You do not need to query Kanbaroo yourself; capture whatever description the user provides as `TASK_DESCRIPTION` and let the bridge enrich it. If the bridge is not active, treat the human ID as ordinary task context — there is no Kanbaroo lookup to perform.

### Step 4: Suggest Feature Branch

Per dotfiles conventions, if currently on `main` (or `master`), prompt:

> "You're on the main branch. Would you like to create a feature branch for the cage output? This lets you review changes via PR."

If the user agrees, create the branch before proceeding. If they decline, continue on current branch.

**If the bridge surfaced a Kanbaroo story human ID** during Step 3, prefer it as the branch prefix per the dotfiles convention for ticket-prefixed branches (e.g. `KAN-123_add_rest_endpoints`). When the bridge is not active, use the standard `feature/<description>` / `fix/<description>` / `chore/<description>` shape.

### Step 5: Derive Repo URL (if remote exists)

Use the `REPO_URL` value determined in Step 2. If a remote exists and the URL is SSH format (`git@github.com:...`), convert to HTTPS:

```bash
if [ -n "$REPO_URL" ]; then
  REPO_URL=$(${CLAUDE_PLUGIN_ROOT}/skills/cage-orchestrator/scripts/tc-url-convert.sh "$REPO_URL")
fi
```

If `REPO_URL` is empty, the cage will be created from the local directory in Step 6.

### Step 6: Create Cage Environment

**Derive an environment name** using a deterministic recipe so names stay consistent across a campaign:

```
<repo-basename>-<task-slug>
```

- `<repo-basename>`: `basename $(git rev-parse --show-toplevel)` (e.g., `kanberoo`)
- `<task-slug>`: a short, lowercase, hyphen-separated slug derived from `TASK_DESCRIPTION` — keep it ≤ 20 characters; drop stopwords (`add`, `the`, `a`, `and`, `to`) if needed

Examples:
- Repo `kanberoo`, task "Add REST endpoint models" → `kanberoo-rest-models`
- Repo `kanberoo`, task "Fix TUI detail pane scrolling bug" → `kanberoo-tui-detail-scroll`
- Repo `snippets`, task "Add gist publishing support" → `snippets-gist-publish`

If the operator already set `$ENV_NAME` or the user gave an explicit name, use that instead:

```bash
ENV_NAME="${ENV_NAME:-<recipe above>}"
```

Check if the environment already exists:

```bash
$TC exists "$ENV_NAME"
```

If exit code is 0 (exists), ask the user: **reuse**, **destroy and recreate**, or **abort**.

**Choose auth mode:**
- If `ANTHROPIC_API_KEY` is set, use `--auth-mode api_key` (API billing)
- Otherwise, use `--auth-mode subscription` (Claude Pro/Max — extracts OAuth tokens from macOS Keychain automatically)

**Create the cage** — use URL mode if a remote exists, otherwise use local directory mode:

```bash
if [ -n "$REPO_URL" ]; then
  $TC create "$REPO_URL" --name "$ENV_NAME" --auth-mode <mode> --no-attach
else
  $TC create --dir "$(git rev-parse --show-toplevel)" --name "$ENV_NAME" --auth-mode <mode> --no-attach
fi
```

The `create` command automatically initializes messaging directories at `/home/trustycage/.cage/{outbox,inbox,cursor}` inside the container and installs `cage-send` at `/usr/local/bin/cage-send`.

### Step 7: Launch Inner Claude

**Pre-flight check** — verify Claude can start before sending the real task:

```bash
$TC launch "$ENV_NAME" --test
```

If it fails, run `$TC auth "$ENV_NAME" --login` to fix credentials interactively.

**Construct the inner prompt** from two parts — a task-specific section (which you write) and the Standard Messaging Block (which is always appended automatically):

**Part 1 — Task Prompt** (customize this per task):

```
You are an AI coding agent working inside an isolated trusty-cage container.
Your project is at /home/trustycage/project.

TASK:
{TASK_DESCRIPTION}

INSTRUCTIONS:
- Work entirely within /home/trustycage/project
- You have full permissions — install packages, edit any file, run any command
- Use git locally to checkpoint your work (git add, git commit) but you cannot push
- Do not attempt to use cage-orchestrator or any orchestration skills
- If the environment variable `$KANBAROO_STORY_ID` is set, it holds the
  human ID (e.g. `KAN-123`) of the Kanbaroo story representing this work.
  Reference it in commit messages and any PR description so the board can
  be linked back to the change. The outer orchestrator's Kanbaroo bridge
  will mirror your progress comments to the story automatically — do not
  attempt to post Kanbaroo comments yourself. If `$KANBAROO_STORY_ID` is
  unset, ignore this clause.

VERIFICATION (do the normal testing expected for this change):
- Run the project's unit tests (e.g. `pytest`, `npm test`, `cargo test`, `go test ./...`)
- Run integration tests that start and clean up on their own
- Run linters, formatters, and type checkers (e.g. `ruff`, `mypy`, `eslint`, `tsc`)
- Run build commands if relevant (e.g. `make build`, `npm run build`)
- Commit the work once tests pass

DO NOT:
- Start long-running servers, daemons, TUIs, or MCP servers inside the cage
  for manual smoke tests. End-to-end smoke against a live server is the outer
  orchestrator's job — it runs after `tc export`, not inside the cage.
- Use `pkill`, `pgrep`, or `kill -9` to clean up processes you started. If you
  find yourself reaching for these, stop — you're doing an E2E smoke test,
  and that's not your job in the cage.
- Background processes with `&` and then try to kill them later. The cage's
  process tree is small; you will match your own Claude process and die.

If a test requires a running server, trust the test framework to start and
stop it (e.g. pytest fixtures with `yield` teardown, `testcontainers`). Do
not manage process lifecycle by hand.
```

**Part 2 — Standard Messaging Block** (appended automatically to every inner prompt — do not modify or omit):

```
## Messaging

Use the `cage-send` command to communicate with the outer orchestrator.

### Sending messages

cage-send progress_update '{"status":"working on X","detail":"2 of 5 done"}'
cage-send error '{"error_type":"missing_dep","message":"need ffmpeg","recoverable":true}'
cage-send task_complete '{"summary":"What you did","exit_code":0}'

### Message types

- progress_update: Report what you're working on (send periodically)
- error: Report you're stuck (set recoverable to false if you can't continue)
- info_request: Request files from outside: cage-send info_request '{"request_id":"req-001","description":"Need package.json","paths":["package.json"]}'
- task_complete: REQUIRED when done. exit_code 0 for success, 1 for failure.

### Reading responses

After sending info_request, check ~/.cage/inbox/ for responses:
  ls ~/.cage/inbox/*.json 2>/dev/null | sort | while read f; do cat "$f"; echo; done

### Important

- You MUST send a task_complete message when your work is done
- You MUST send progress_update messages at least every 3 minutes during long tasks — if the host doesn't hear from you for 5+ minutes, it will assume you are stuck
- Do not attempt to read outside ~/.cage/inbox/ — you cannot see the host filesystem

## After Task Completion (REQUIRED — do this IMMEDIATELY)

When you have completed the task:
1. Send a `task_complete` message via `cage-send`
2. IMMEDIATELY run `cage-wait` to wait for revised instructions — do not do anything else first:
   ```bash
   cage-wait
   ```
   This blocks until the host sends a follow-up message or 2 hours pass.
3. If `cage-wait` outputs JSON, it is a `task_revision` message. Read the `payload.instructions` field and continue working on the project accordingly. When done with the revision, repeat from step 1.
4. If `cage-wait` outputs `POLL_TIMEOUT`, send a `going_idle` message and stop:
   ```bash
   cage-send going_idle '{"reason":"No task_revision received within polling timeout","waited_seconds":7200}'
   ```
```

**Assemble and launch** — combine Part 1 + Part 2 into `INNER_PROMPT`. For short prompts, pass inline:

```bash
$TC launch "$ENV_NAME" --prompt "$INNER_PROMPT" --background
```

For long prompts, write to a temp file first:

```bash
echo "$INNER_PROMPT" > /tmp/cage-prompt-$ENV_NAME.txt
$TC launch "$ENV_NAME" --prompt-file /tmp/cage-prompt-$ENV_NAME.txt --background
```

**If the bridge is active and surfaced a Kanbaroo story ID** at this point, pass it to `tc launch` as a launch-time environment variable so the inner Claude can reference it in commit messages and PR descriptions. The exact env-injection flag is `tc`'s, not this skill's — confirm with `$TC launch --help` if you have not used it on this machine before. Typical shape:

```bash
$TC launch "$ENV_NAME" \
  --prompt-file /tmp/cage-prompt-$ENV_NAME.txt \
  --env KANBAROO_STORY_ID="$KANBAROO_STORY_ID" \
  --background
```

When the bridge is not active, omit the env injection — the conditional clause in the Task Prompt above self-skips when `$KANBAROO_STORY_ID` is unset, so it is safe to leave the prompt text in place.

Tell the user: "Inner Claude is working in the cage. I'll check on it periodically."

### Step 8: Monitor Progress

Monitor via CLI commands:
- Stream inner Claude's reasoning: `$TC logs "$ENV_NAME" -f`
- Poll for structured messages: `$TC outbox "$ENV_NAME" --poll`

**Watch the stream (optional):** Show the user they can observe in real-time:

```bash
$TC logs "$ENV_NAME" -f
```

Use `tc outbox --poll` to block until a `task_complete` message arrives:

```bash
$TC outbox "$ENV_NAME" --poll --timeout 1800 --interval 30
```

`tc outbox --poll` will:
- Print `progress_update` and `error` messages as they arrive
- Exit with code 0 when `task_complete` is received
- Exit with code 2 when `going_idle` is received (inner Claude timed out waiting for revisions)
- Exit with code 1 on error or timeout

**If the bridge is active**, each `progress_update` and `error` it observes (via the messages this skill surfaces) is mirrored to the active Kanbaroo story as a throttled comment. The bridge handles formatting and rate-limiting per its own rules — do not duplicate that work here, and do not call `mcp__kanbaroo__comment_on_story` yourself. When the bridge is not active, surfacing messages to the user is the only mirroring that happens.

**If you need more control** (e.g., to handle `info_request` messages), poll manually:

```bash
$TC outbox "$ENV_NAME"
```

To respond to an `info_request`:

```bash
# Read the requested file from the host
$TC inbox "$ENV_NAME" info_response '{"request_id":"req-001","content":"file contents here","files":[{"path":"package.json","content":"..."}]}'
```

**Fallback process check:** If polling times out, verify Claude is still running:

```bash
docker exec -u trustycage "isolated-dev-$ENV_NAME" pgrep -f claude
```

Handle the exit code:
- **Exit 0** → proceed to Step 9
- **Exit 2** → inform user that inner Claude went idle; offer to re-launch if needed
- **Exit 1** → diagnose (check container status, `$TC logs`)

### Step 9: Export, Validate, and Overlay

**9a — Pre-export snapshot:**

Record the working tree state before exporting so you can detect unexpected changes:

```bash
git status --short
```

**9b — Preview with stats:**

Before exporting, show the user what the inner agent changed with language-aware code statistics:

```bash
$TC diff "$ENV_NAME" --stats
```

This shows a file change summary (added/modified/deleted) plus a per-language breakdown of lines added, removed, and modified. If `cloc` is installed on the host, stats are language-aware; otherwise a built-in line counter is used.

**9b.alt — Cleaner alternative for single-commit cages: `tc patch`**

If the cage's deliverable is one or more clean git commits (typical when the inner agent was instructed to commit its work), prefer `tc patch` over `tc export`:

```bash
$TC patch "$ENV_NAME" --base main
git am ./.trusty-cage-patches/"$ENV_NAME"/*.patch
```

Or, as a single streaming pipeline:

```bash
$TC patch "$ENV_NAME" --base main --stdout | git am
```

Why: `tc export` rsyncs the full working tree, which brings along any transient files the cage's tooling left behind (`.mypy_cache/`, `.pytest_cache/`, `.ruff_cache/`, `node_modules/`, plus whatever pip / uv installed). `tc patch` emits `git format-patch` output from inside the cage, so only the commit(s) land on the host.

Fallback for trusty-cage versions older than `0.13.0` (before `tc patch` existed):

```bash
docker exec -u trustycage "isolated-dev-$ENV_NAME" bash -c \
  "cd /home/trustycage/project && git format-patch main -o /tmp/tc-patches/"
docker cp "isolated-dev-$ENV_NAME:/tmp/tc-patches/." ./.cage-patches/
git am ./.cage-patches/*.patch
```

Use `tc export` (step 9c below) when the deliverable isn't cleanly committed (work-in-progress, generated assets the inner agent didn't git-add, multiple unrelated changes the user wants to stage themselves).

**9c — Export:**

```bash
$TC export "$ENV_NAME" --yes --stats --output-dir .
```

This rsyncs container files into the current directory, excluding `.git/` so the host repo's git history is preserved. The `--stats` flag prints a code statistics summary after export.

**9d — Post-export validation and restore:**

Immediately after export, validate and fix the results:

1. Show what changed:
   ```bash
   git diff --stat
   ```

2. Restore protected files that `tc export` may have overwritten or deleted:
   ```bash
   git checkout -- .gitignore
   ```
   If `.gitignore` was modified or deleted, warn the user: "Note: `.gitignore` was overwritten by `tc export` and has been restored."

3. Compare `git diff --stat` output against the pre-export snapshot. Flag any unexpected file deletions or modifications that fall outside the task scope.

4. If a test suite exists (e.g., `pytest`, `npm test`, `make test`), offer to run it to verify the exported code works on the host.

5. For service-style projects (HTTP API, TUI, MCP), offer a live smoke test using one of the shapes in [smoke-test-templates.md](smoke-test-templates.md). Live-server smoke is the outer orchestrator's job — it is explicitly forbidden inside the cage (see Step 7's "DO NOT" block).

6. Present a summary to the user:
   - Files added (new from cage)
   - Files modified (expected changes)
   - Files unexpectedly deleted or overwritten (flag these)

**If the bridge is active**, once you have surfaced the export results (the file-change summary plus `tc diff --stats` output), the bridge posts a single summary comment to the active Kanbaroo story and then asks the user whether to transition the story (typically to `in_review` if a PR is being opened, or `done` if the work is already merged outside the cage). Defer to the bridge for those Kanbaroo-side actions; do not transition the story yourself, and do not duplicate the summary comment. When the bridge is not active, the export results live only in this conversation — no Kanbaroo mirroring happens, by design.

### Step 10: Review Changes with User

Show the user the detailed diff for review:
```bash
git diff
```

Discuss the results. Let the user test, inspect, or ask questions.

**Do NOT auto-commit.** Let the user review and decide.

### Step 11: Revision Decision

Ask the user:
> "Would you like to revise and send inner Claude back to work, or are we done?"

**If revise:**
1. Gather revised instructions from the user — what to change, fix, or improve
2. **If the bridge is active**, it captures the revision instructions verbatim as a comment on the active Kanbaroo story *before* this skill runs `tc inbox` — that comment is the durable record of what was asked of the cage. Do not post the revision comment yourself; let the bridge run first, then proceed with `tc inbox`. If the bridge is not active, skip this sub-step entirely.
3. Send to inner Claude:
   ```bash
   $TC inbox "$ENV_NAME" task_revision '{"instructions": "<user feedback here>"}'
   ```
4. Go back to **Step 8** (Monitor Progress)

**If done:**

If this cycle produced a pull request that the user merged, verify the merge before proceeding — trust, but confirm. See **Step 11b** below; then continue to Step 12.

### Step 11b: Verify PR Merge (when applicable)

If you created a pull request in this cycle (typically via `gh pr create`), capture the URL at creation time and verify the merge claim before destroying the cage.

**Skip this step entirely** if the repo has no GitHub remote — `gh` will not work for other forges.

```bash
# Check that a GitHub remote exists
if git remote get-url origin | grep -q 'github\.com'; then
  PR_URL="<the URL printed by gh pr create>"
  gh pr view "$PR_URL" --json state,mergedAt,mergedBy
fi
```

Interpret the result:

- `"state": "MERGED"` with a non-null `mergedAt` → proceed to Step 12
- `"state": "OPEN"` or `"state": "CLOSED"` (not merged) → flag the mismatch to the user: "The PR at `<url>` shows state `<state>` — it doesn't appear to be merged yet. Would you like to wait, or abandon this cycle?"
- `gh` not installed or auth failure → ask the user to confirm the merge manually; do not block.

**Autonomous long-campaign mode (optional):** If you are running a multi-cage campaign without a human in the loop, poll `gh pr view` on a gentle cadence (e.g. every 5–10 minutes) instead of asking the user. Do not poll eagerly — that wastes API quota and the user's agency. A cheap verification call right after the user says "merged" is almost always enough.

### Step 12: Cleanup

Ask the user:

> "Would you like to destroy the cage environment (`tc destroy $ENV_NAME`), or keep it for follow-up work?"

If destroy, run:

```bash
$TC destroy "$ENV_NAME" --yes
```

### Edge Cases

**Inner Claude goes idle during revision cycle:**
If `tc outbox --poll` exits with code 2 (`going_idle`), inner Claude's polling timed out. The cage is still alive. Inform the user and offer to re-launch:
```bash
$TC launch "$ENV_NAME" --prompt "Check your inbox for instructions and continue working on the project"
```
This starts a fresh Claude session (losing conversational context) but preserves all file state.

**Inner Claude crashes:**
If `tc outbox --poll` times out (exit 1) without receiving `task_complete`, verify inner Claude is alive before sending a `task_revision`. Check container status or try `$TC logs "$ENV_NAME"`. If dead, offer to re-launch.

**Multiple rapid revisions:**
Not supported — always wait for `task_complete` before offering another revision cycle.

---

## Known Limitations

1. **Single task per session**: One task dispatch per cage. The messaging system enables future multi-task support.
2. **Polling latency**: `tc outbox --poll` checks every 30 seconds by default (configurable with `--interval`).

---

## Additional resources

- [inner-agent-protocol.md](inner-agent-protocol.md) — Rules, messaging commands, and completion steps for when Claude is running **inside** a cage (`TRUSTY_CAGE=1`). Load this when the Detection Gate (Step 1) determines you are the inner agent.
- [messaging-protocol.md](messaging-protocol.md) — Message envelope schema, directory layout, all message types with payload definitions, and file naming conventions. Load this when you need details about the messaging format during monitoring (Step 8) or debugging.
- [prompt-templates.md](prompt-templates.md) — Suggested starting points for the Task Prompt (Part 1 of Step 7). Load this when constructing the inner prompt to choose an appropriate template.
- [smoke-test-templates.md](smoke-test-templates.md) — Host-side live smoke test shapes (HTTP API, CLI, TUI, MCP) to run after `tc export`. Load this at Step 9d when the project is service-style and you want to verify end-to-end behavior before committing.
