# Messaging Protocol Reference

## Message Envelope

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

## Directory Layout

```
/home/trustycage/.cage/
  outbox/           # Inner writes, outer reads
  inbox/            # Outer writes, inner reads
  cursor/
    outbox.cursor   # Outer's read position (managed by trusty-cage)
    inbox.cursor    # Inner's read position
```

## Message Types

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

## File Naming

Messages are named by timestamp with colons replaced by dashes for filesystem safety:
`2026-03-26T14-30-00.000Z.json`

Lexicographic sort of filenames equals chronological order.
