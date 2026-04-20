# Host-Side Smoke Test Templates

Starting points for the outer orchestrator to run **after `tc export`** brings work out of the cage. The inner agent should NOT start long-running servers or manage process lifecycles (see the "DO NOT" block in `SKILL.md` Step 7). That work lives here — on the host — where killing a backgrounded server is safe.

Load this when:
- You're at `SKILL.md` Step 9d's "offer to run tests" prompt
- The project is a service (HTTP API, TUI, MCP) that unit/integration tests alone can't fully verify
- The user wants a live smoke pass before committing

---

## Pattern: sandboxed server + readiness probe + curl + cleanup

The core shape of every live smoke test:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Isolated workspace — never use real config/home dirs
SMOKE_DIR=$(mktemp -d -t <project>-smoke-XXXX)
trap 'kill $SERVER_PID 2>/dev/null || true; wait 2>/dev/null || true; rm -rf "$SMOKE_DIR"' EXIT

# Initialize (point the project at the sandbox)
export <PROJECT>_CONFIG_DIR="$SMOKE_DIR"
<project-cli> init

# Start the service in the background
<project-cli> serve &
SERVER_PID=$!

# Wait for readiness — prefer a /health probe over sleep
for i in $(seq 1 30); do
  if curl -sf "http://127.0.0.1:${PORT}/health" >/dev/null; then break; fi
  sleep 0.3
done

# Smoke sequence
TOKEN=$(grep '^token' "$SMOKE_DIR/config.toml" | cut -d'"' -f2)
curl -sf -H "Authorization: Bearer $TOKEN" "http://127.0.0.1:${PORT}/api/v1/health"
curl -sf -H "Authorization: Bearer $TOKEN" -X POST \
  -d '{"name":"smoke"}' "http://127.0.0.1:${PORT}/api/v1/workspaces"
# ... more curls ...

echo "OK"
# trap handles kill + cleanup
```

**Key invariants:**
- `mktemp -d` for the sandbox (never `/tmp/<fixed-name>` — collides across parallel runs)
- `trap ... EXIT` for cleanup (works even on script failure or Ctrl-C)
- Readiness probe loop (not `sleep 5`) — avoids flaky startup races
- `set -euo pipefail` so a failing curl fails the whole script

---

## Variants

### HTTP API (as above)

The reference shape. Good for FastAPI, Flask, Node + Express, Go HTTP servers.

### CLI tool

No server, no cleanup complexity — just run the binary against test inputs:

```bash
SMOKE_DIR=$(mktemp -d -t cli-smoke-XXXX)
trap 'rm -rf "$SMOKE_DIR"' EXIT

<project-cli> --config-dir "$SMOKE_DIR" init
<project-cli> --config-dir "$SMOKE_DIR" create --name smoke
output=$(<project-cli> --config-dir "$SMOKE_DIR" list)
echo "$output" | grep -q smoke || { echo "FAIL: smoke not in list output"; exit 1; }
echo "OK"
```

### TUI (Textual, curses, Bubble Tea, etc.)

Full automation is hard; prefer **manual operator verification** after export. Suggest to the user:

> "The TUI is exported. Start it with `<project-cli> tui` and spot-check: screen renders, J/K navigation works, enter opens detail pane, Q quits. Report back if something is broken."

If automation is truly required, use the TUI framework's own test harness (e.g. Textual's `Pilot`) — in that case the test is unit/integration-level and belongs inside the cage, not here.

### MCP server

Use a dedicated MCP client or the spec's JSON-RPC directly:

```bash
SMOKE_DIR=$(mktemp -d -t mcp-smoke-XXXX)
trap 'kill $SERVER_PID 2>/dev/null || true; rm -rf "$SMOKE_DIR"' EXIT

<project-mcp-server> --config-dir "$SMOKE_DIR" &
SERVER_PID=$!
sleep 1

# List tools
echo '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | nc -q 1 127.0.0.1 "$MCP_PORT"
# Call a tool
echo '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"ping"}}' | \
  nc -q 1 127.0.0.1 "$MCP_PORT"
echo "OK"
```

(Or use `mcp-cli` or the official MCP SDK for a nicer interface.)

---

## When to skip

- Project has no network-exposed surface (pure library, static site) — unit tests are enough.
- Project has no meaningful end-to-end path beyond what the in-cage tests already cover.
- User says "skip smoke, I'll verify manually" — honor that; this is a suggestion, not a gate.

---

## Why this lives on the host, not in the cage

See `SKILL.md` Step 7's "DO NOT" block. Live-server smoke requires:
- Starting backgrounded processes
- Waiting for readiness
- Killing the server on success / failure / interrupt

The cage's process tree is small and the inner Claude's own process shows up in any `pkill -f <server>` pattern match. Two cages in the phase-1 Kanberoo campaign (D and F) died with intact work but no `task_complete` for exactly this reason. On the host, cleanup is safe — there's no ambiguity about which processes belong to the smoke test.
