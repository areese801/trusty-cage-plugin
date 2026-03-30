---
name: cage-orchestrator
description: Orchestrates trusty-cage containers for autonomous AI work. Use when the user wants to delegate a task to an isolated Claude Code instance inside a trusty-cage container, or when the user says "spin up a cage", "run this in a cage", "let Claude go wild on this". Do NOT use for manual trusty-cage commands the user wants to run themselves. If running inside a trusty-cage container (TRUSTY_CAGE=1 or user is `trustycage`), follow inner-agent protocol instead.
---

# SKILL: Cage Orchestrator

Spin up an isolated trusty-cage container, launch an inner Claude Code agent to work autonomously, monitor for completion, and overlay results back onto the host repo.

## Step 1: Detection Gate

Check if running inside a cage:

1. Check `echo $TRUSTY_CAGE` — if value is `1`, jump to **Inner Agent Protocol**
2. Fallback: run `whoami` — if output is `trustycage`, jump to **Inner Agent Protocol**
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
| Git remote | `git remote get-url origin` | "No git remote 'origin' found. Add one before using cage-orchestrator." |

**Important:** Ensure the project has a `.gitignore` that includes `venv/` so the venv is not committed to git and is protected from deletion during `tc export` (which uses `rsync --delete` but respects `.gitignore` patterns).

### Step 3: Gather Task Description

- If the user already described the task, confirm your understanding and capture it as `TASK_DESCRIPTION`
- If not, ask: "What task should the inner Claude work on?"
- Be specific — this prompt is passed verbatim to the inner agent

### Step 4: Suggest Feature Branch

Per dotfiles conventions, if currently on `main` (or `master`), prompt:

> "You're on the main branch. Would you like to create a feature branch for the cage output? This lets you review changes via PR."

If the user agrees, create the branch before proceeding. If they decline, continue on current branch.

### Step 5: Derive Repo URL

```bash
REPO_URL=$(git remote get-url origin)
```

If the URL is SSH format (`git@github.com:...`), convert to HTTPS using the helper script:

```bash
REPO_URL=$(${CLAUDE_PLUGIN_ROOT}/skills/cage-orchestrator/scripts/tc-url-convert.sh "$REPO_URL")
```

### Step 6: Create Cage Environment

Derive an environment name from the repo directory name, or let the user specify one.

```bash
ENV_NAME="${ENV_NAME:-$(basename $(git rev-parse --show-toplevel))}"
```

Check if the environment already exists:

```bash
venv/bin/tc exists "$ENV_NAME"
```

If exit code is 0 (exists), ask the user: **reuse**, **destroy and recreate**, or **abort**.

**Choose auth mode:**
- If `ANTHROPIC_API_KEY` is set, use `--auth-mode api_key` (API billing)
- Otherwise, use `--auth-mode subscription` (Claude Pro/Max — extracts OAuth tokens from macOS Keychain automatically)

```bash
venv/bin/tc create "$REPO_URL" --name "$ENV_NAME" --auth-mode <mode> --no-attach
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
- Send progress_update messages every few minutes during long tasks
- Do not attempt to read outside ~/.cage/inbox/ — you cannot see the host filesystem

## After Task Completion

When you have completed the task:
1. Send a `task_complete` message via `cage-send`
2. Run the following polling script to wait for revised instructions:
```bash
INTERVAL=10; MAX_WAIT=3600; ELAPSED=0
CURSOR_FILE=~/.cage/cursor/inbox.cursor
CURSOR=$(cat "$CURSOR_FILE" 2>/dev/null || echo "")
while [ $ELAPSED -lt $MAX_WAIT ]; do
  for f in $(ls -1 ~/.cage/inbox/ 2>/dev/null | sort); do
    if [ -z "$CURSOR" ] || [ "$f" \> "$CURSOR" ]; then
      cat ~/.cage/inbox/"$f"
      echo "$f" > "$CURSOR_FILE"
      exit 0
    fi
  done
  sleep $INTERVAL
  ELAPSED=$((ELAPSED + INTERVAL))
  INTERVAL=$((INTERVAL * 2 > 300 ? 300 : INTERVAL * 2))
done
echo "POLL_TIMEOUT"
```
3. If the script returns JSON, parse it — it will be a `task_revision` message. Read the `payload.instructions` field and continue working on the project accordingly. When done, repeat from step 1.
4. If the script returns `POLL_TIMEOUT`, send a `going_idle` message via `cage-send`:
   ```bash
   cage-send going_idle '{"reason":"No task_revision received within polling timeout","waited_seconds":3600}'
   ```
   Then stop working.
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

**9b — Export:**

```bash
venv/bin/tc export "$ENV_NAME" --yes --output-dir .
```

This rsyncs container files into the current directory, excluding `.git/` so the host repo's git history is preserved.

**9c — Post-export validation and restore:**

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

5. Present a summary to the user:
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
Proceed to Step 12.

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

## Inner Agent Protocol

**This section applies when `TRUSTY_CAGE=1` is set or `whoami` returns `trustycage`.**

You are running inside a trusty-cage container. You have full autonomy but no git credentials and no push capability.

### Rules

- Focus entirely on the task. Your project is at `/home/trustycage/project`
- Work only within `/home/trustycage/project`
- You have full permissions — install packages, edit any file, run any command
- Use git locally (`git add`, `git commit`) to checkpoint your work, but you **cannot push**
- **Do NOT invoke the `cage-orchestrator` skill** — you are the inner agent
- Do not attempt to access external services that require authentication

### Messaging

Use `cage-send` to communicate with the outer orchestrator:

```bash
# Report progress (send periodically during long tasks)
cage-send progress_update '{"status":"implementing auth module","detail":"3 of 5 files done"}'

# Request files or info from outside the container
cage-send info_request '{"request_id":"req-001","description":"Need package.json","paths":["package.json"]}'

# Report an error / blocker
cage-send error '{"error_type":"missing_dependency","message":"Cannot resolve X","recoverable":false}'

# Signal completion (REQUIRED as your final action)
cage-send task_complete '{"summary":"Implemented feature X: added 3 files, modified 2","exit_code":0}'
```

After sending `info_request`, check `~/.cage/inbox/` for the response:

```bash
ls ~/.cage/inbox/*.json 2>/dev/null | sort | while read f; do cat "$f"; echo; done
```

### When Finished

1. Commit your work locally: `git add -A && git commit -m "description of changes"`
2. Send completion: `cage-send task_complete '{"summary":"what you did","exit_code":0}'`

### If Blocked

1. Send an `error` message with `"recoverable": false` and a description of the blocker
2. If you can partially complete the task, do so, then send `task_complete` with `"exit_code": 1`

---

## Messaging Protocol Reference

### Message Envelope

Every message (inbox and outbox) uses this JSON format:

```json
{
  "id": "msg-20260326T143000-a1b2",
  "type": "task_complete",
  "timestamp": "2026-03-26T14:30:00.000Z",
  "payload": { ... },
  "version": 1
}
```

### Directory Layout

```
/home/trustycage/.cage/
  outbox/           # Inner writes, outer reads
  inbox/            # Outer writes, inner reads
  cursor/
    outbox.cursor   # Outer's read position (managed by trusty-cage)
    inbox.cursor    # Inner's read position
```

### Message Types

| Type | Direction | Payload |
|------|-----------|---------|
| `task_complete` | inner → outer | `{"summary": str, "exit_code": int}` |
| `info_request` | inner → outer | `{"request_id": str, "description": str, "paths": [str]}` |
| `progress_update` | inner → outer | `{"status": str, "detail": str \| null}` |
| `error` | inner → outer | `{"error_type": str, "message": str, "recoverable": bool}` |
| `info_response` | outer → inner | `{"request_id": str, "content": str, "files": [{"path": str, "content": str}]}` |
| `ack` | outer → inner | `{"acked_id": str}` |
| `task_revision` | outer → inner | `{"instructions": str}` |
| `going_idle` | inner → outer | `{"reason": str, "waited_seconds": int}` |

### File Naming

Messages are named by timestamp with colons replaced by dashes for filesystem safety:
`2026-03-26T14-30-00.000Z.json`

Lexicographic sort of filenames equals chronological order.

---

## Known Limitations

1. **Single task per session**: One task dispatch per cage. The messaging system enables future multi-task support.
2. **Polling latency**: `tc outbox --poll` checks every 30 seconds by default (configurable with `--interval`).

---

## Prompt Templates (Optional)

These are suggested starting points for the Task Prompt (Part 1 of Step 7). Select the closest template and customize the task description. The Standard Messaging Block (Part 2) is appended automatically.

**Add a Feature:**
> Implement {feature description}. Write clean, idiomatic code following existing project conventions. Add tests if a test suite exists. Commit your work with a descriptive message.

**Fix a Bug:**
> Fix: {bug description}. Reproduce the issue first, then identify the root cause and implement a fix. Add a regression test if a test suite exists. Commit with a message describing the fix.

**Add Tests:**
> Add test coverage for {module or area}. Follow existing test patterns and conventions in the project. Aim for meaningful coverage of edge cases, not just happy paths. Commit your work.

**Refactor:**
> Refactor {area} to {goal}. Preserve all existing behavior — no functional changes. Run existing tests to verify nothing breaks. Commit your work with a descriptive message.
