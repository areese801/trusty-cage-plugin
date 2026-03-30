# trusty-cage-plugin

Claude Code plugin for [trusty-cage](https://github.com/areese801/trusty-cage) — delegate tasks to isolated Claude Code instances running inside Docker containers.

## Installation

```
/plugin marketplace add areese801/trusty-cage-plugin
/plugin install trusty-cage@trusty-cage-plugin
```

### Prerequisites

- [trusty-cage](https://github.com/areese801/trusty-cage) CLI installed (`pip install trusty-cage`)
- Docker (Docker Desktop, OrbStack, or Docker Engine)

## Skills

### cage-orchestrator

Orchestrates the full trusty-cage lifecycle: creates an isolated container from your repo, launches an inner Claude with a task, monitors progress, exports completed work, and iterates on feedback.

Trigger it by asking Claude to run something in a cage:

> "Spin up a cage and implement feature X in this repo"

### cage-iterate

Continuous improvement loop for the cage workflow. Dispatches a task via cage-orchestrator, assesses results and orchestration friction, plans improvements, implements them, and re-tests.

Trigger it when you want to improve the cage workflow itself:

> "Let's iterate on the cage orchestration"

## License

MIT
