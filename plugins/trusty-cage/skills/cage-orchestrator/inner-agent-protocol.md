# Inner Agent Protocol

**This section applies when `TRUSTY_CAGE=1` is set or `whoami` returns `trustycage`.**

You are running inside a trusty-cage container. You have full autonomy but no git credentials and no push capability.

## Rules

- Focus entirely on the task. Your project is at `/home/trustycage/project`
- Work only within `/home/trustycage/project`
- You have full permissions — install packages, edit any file, run any command
- Use git locally (`git add`, `git commit`) to checkpoint your work, but you **cannot push**
- **Do NOT invoke the `cage-orchestrator` skill** — you are the inner agent
- Do not attempt to access external services that require authentication

## Testing

- Regular testing is encouraged and expected: unit tests, integration tests
  that start and clean up on their own, linters, type checkers, build commands
- **Do NOT** start long-running servers, daemons, TUIs, or MCP servers for
  manual smoke tests. Live-server E2E smoke belongs outside the cage.
- **Do NOT** use `pkill`, `pgrep`, or `kill -9` to clean up processes you
  started. The cage's process tree is small — you will match your own
  Claude process and die mid-task. If you find yourself reaching for these,
  stop — that's an E2E smoke test, and it's not your job in the cage.
- If a test needs a running server, let the test framework manage its
  lifecycle (e.g. pytest fixtures with `yield` teardown, `testcontainers`).

## Messaging

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

## When Finished

1. Commit your work locally: `git add -A && git commit -m "description of changes"`
2. Send completion: `cage-send task_complete '{"summary":"what you did","exit_code":0}'`

## If Blocked

1. Send an `error` message with `"recoverable": false` and a description of the blocker
2. If you can partially complete the task, do so, then send `task_complete` with `"exit_code": 1`
