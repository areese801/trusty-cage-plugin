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

### Step 2: Validate Prerequisites and Set Up Environment

**Set up a project-local venv with trusty-cage:**

1. Check if `venv/bin/tc` exists in the project directory
2. If not, create a venv and install trusty-cage:

```bash
python3 -m venv venv
venv/bin/pip install trusty-cage
```

3. All subsequent `tc` commands in this workflow must use `venv/bin/tc` (not a global install)

**Then check the remaining prerequisites.** If any fail, stop and report the error with fix instructions.

| Check | Command | Error Message |
|-------|---------|---------------|
| trusty-cage installed | `venv/bin/tc --help` | "trusty-cage venv setup failed. Check Python and pip." |
| Docker running | `docker info >/dev/null 2>&1` | "Docker is not running. Start Docker or OrbStack first." |
| Git repo | `git rev-parse --is-inside-work-tree` | "Current directory is not a git repository." |

**Optionally** check for a git remote — this determines how the cage is created (Step 5/6):

```bash
REPO_URL=$(git remote get-url origin 2>/dev/null || echo "")
```

If `REPO_URL` is empty, the cage will be created from the local directory using `--dir`. A remote is **not** required.

**Important:** Ensure the project has a `.gitignore` that includes `venv/` so the venv is not committed to git and is protected from deletion during `tc export` (which uses `rsync --delete` but respects `.gitignore` patterns).

### Step 3: Gather Task Description

- If the user already described the task, confirm your understanding and capture it as `TASK_DESCRIPTION`
- If not, ask: "What task should the inner Claude work on?"
- Be specific — this prompt is passed verbatim to the inner agent

### Step 4: Suggest Feature Branch

Per dotfiles conventions, if currently on `main` (or `master`), prompt:

> "You're on the main branch. Would you like to create a feature branch for the cage output? This lets you review changes via PR."

If the user agrees, create the branch before proceeding. If they decline, continue on current branch.

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
venv/bin/tc exists "$ENV_NAME"
```

If exit code is 0 (exists), ask the user: **reuse**, **destroy and recreate**, or **abort**.

**Choose auth mode:**
- If `ANTHROPIC_API_KEY` is set, use `--auth-mode api_key` (API billing)
- Otherwise, use `--auth-mode subscription` (Claude Pro/Max — extracts OAuth tokens from macOS Keychain automatically)

**Create the cage** — use URL mode if a remote exists, otherwise use local directory mode:

```bash
if [ -n "$REPO_URL" ]; then
  venv/bin/tc create "$REPO_URL" --name "$ENV_NAME" --auth-mode <mode> --no-attach
else
  venv/bin/tc create --dir "$(git rev-parse --show-toplevel)" --name "$ENV_NAME" --auth-mode <mode> --no-attach
fi
```

The `create` command automatically initializes messaging directories at `/home/trustycage/.cage/{outbox,inbox,cursor}` inside the container and installs `cage-send` at `/usr/local/bin/cage-send`.

### Step 7: Launch Inner Claude

**Pre-flight check** — verify Claude can start before sending the real task:

```bash
venv/bin/tc launch "$ENV_NAME" --test
```

If it fails, run `venv/bin/tc auth "$ENV_NAME" --login` to fix credentials interactively.

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
venv/bin/tc launch "$ENV_NAME" --prompt "$INNER_PROMPT" --background
```

For long prompts, write to a temp file first:

```bash
echo "$INNER_PROMPT" > /tmp/cage-prompt-$ENV_NAME.txt
venv/bin/tc launch "$ENV_NAME" --prompt-file /tmp/cage-prompt-$ENV_NAME.txt --background
```

Tell the user: "Inner Claude is working in the cage. I'll check on it periodically."

### Step 8: Monitor Progress

Monitor via CLI commands:
- Stream inner Claude's reasoning: `venv/bin/tc logs "$ENV_NAME" -f`
- Poll for structured messages: `venv/bin/tc outbox "$ENV_NAME" --poll`

**Watch the stream (optional):** Show the user they can observe in real-time:

```bash
venv/bin/tc logs "$ENV_NAME" -f
```

Use `tc outbox --poll` to block until a `task_complete` message arrives:

```bash
venv/bin/tc outbox "$ENV_NAME" --poll --timeout 1800 --interval 30
```

`tc outbox --poll` will:
- Print `progress_update` and `error` messages as they arrive
- Exit with code 0 when `task_complete` is received
- Exit with code 2 when `going_idle` is received (inner Claude timed out waiting for revisions)
- Exit with code 1 on error or timeout

**If you need more control** (e.g., to handle `info_request` messages), poll manually:

```bash
venv/bin/tc outbox "$ENV_NAME"
```

To respond to an `info_request`:

```bash
# Read the requested file from the host
venv/bin/tc inbox "$ENV_NAME" info_response '{"request_id":"req-001","content":"file contents here","files":[{"path":"package.json","content":"..."}]}'
```

**Fallback process check:** If polling times out, verify Claude is still running:

```bash
docker exec -u trustycage "isolated-dev-$ENV_NAME" pgrep -f claude
```

Handle the exit code:
- **Exit 0** → proceed to Step 9
- **Exit 2** → inform user that inner Claude went idle; offer to re-launch if needed
- **Exit 1** → diagnose (check container status, `venv/bin/tc logs`)

### Step 9: Export, Validate, and Overlay

**9a — Pre-export snapshot:**

Record the working tree state before exporting so you can detect unexpected changes:

```bash
git status --short
```

**9b — Preview with stats:**

Before exporting, show the user what the inner agent changed with language-aware code statistics:

```bash
venv/bin/tc diff "$ENV_NAME" --stats
```

This shows a file change summary (added/modified/deleted) plus a per-language breakdown of lines added, removed, and modified. If `cloc` is installed on the host, stats are language-aware; otherwise a built-in line counter is used.

**9c — Export:**

```bash
venv/bin/tc export "$ENV_NAME" --yes --stats --output-dir .
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
2. Send to inner Claude:
   ```bash
   venv/bin/tc inbox "$ENV_NAME" task_revision '{"instructions": "<user feedback here>"}'
   ```
3. Go back to **Step 8** (Monitor Progress)

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
venv/bin/tc destroy "$ENV_NAME" --yes
```

### Edge Cases

**Inner Claude goes idle during revision cycle:**
If `tc outbox --poll` exits with code 2 (`going_idle`), inner Claude's polling timed out. The cage is still alive. Inform the user and offer to re-launch:
```bash
venv/bin/tc launch "$ENV_NAME" --prompt "Check your inbox for instructions and continue working on the project"
```
This starts a fresh Claude session (losing conversational context) but preserves all file state.

**Inner Claude crashes:**
If `tc outbox --poll` times out (exit 1) without receiving `task_complete`, verify inner Claude is alive before sending a `task_revision`. Check container status or try `venv/bin/tc logs "$ENV_NAME"`. If dead, offer to re-launch.

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
