---
name: cage-iterate
description: >-
  Continuous improvement loop for trusty-cage orchestration. Dispatches a task to
  an inner Claude via cage-orchestrator, assesses results and orchestration friction,
  plans improvements to trusty-cage and/or the cage-orchestrator skill, implements
  them, and re-tests. Use when the user wants to improve the cage workflow, says
  "let's iterate on the cage", "improve the orchestrator", or "run the cage loop".
  Do NOT use for one-off cage tasks without improvement intent — use cage-orchestrator
  directly for those.
---

# SKILL: Cage Iteration Loop

## Description

You are a systems engineer focused on continuously improving the trusty-cage orchestration pipeline. Your job is to run the full cycle: dispatch work to an inner Claude in a cage, assess how the orchestration performed, identify friction and failures, plan and implement improvements to the trusty-cage CLI and cage-orchestrator skill, then re-test to verify the improvements work. Each cycle should leave the system measurably better than before.

## Companion skill: Kanbaroo bridge (optional)

If the user's Claude Code session also has the [`kanbaroo-plugin`](https://github.com/areese801/kanbaroo-plugin) installed and a Kanbaroo MCP wired up for this project, the **`kanbaroo-cage-bridge`** skill will activate during Step 2 (when you delegate to `cage-orchestrator`) and mirror that dispatch's lifecycle onto a Kanbaroo story automatically.

**Kanbaroo as a durable home for friction reports.** The iteration loop generates exactly the kind of artefact a board is good at holding: a friction report per cycle, an enhancement candidate list, a comparison of "resolved" vs "still open" between runs. When Kanbaroo is available you have two complementary patterns:

- **Per-cycle parent story.** Create one Kanbaroo story per iteration cycle (e.g. "Iteration cycle: improve auth + messaging — 2026-05-08") and use the cycle's friction report (Step 3b/3c), the enhancement plan (Step 4), and the close-the-loop comparison (Step 7) as comments on that single story. The cage dispatched in Step 2 still gets its own story via the bridge — link the two manually using `kanbaroo-workflow`.
- **Per-friction sub-stories.** When a cycle's enhancement list is large enough to span multiple cages, file each enhancement as a separate Kanbaroo story so it can be picked up independently in subsequent cycles. The parent cycle story then links to those.

**Note: the bridge does not currently know about cage-iterate.** The existing `kanbaroo-cage-bridge` skill is `cage-orchestrator`-aware: it auto-mirrors a single cage dispatch. The iterate-loop integration above is therefore manual today — when a step below says "post the friction report to Kanbaroo," that means asking `kanbaroo-workflow` to create a comment, not relying on the bridge to do it. A future `kanbaroo-cage-iterate-bridge` (or extension to the existing bridge) could automate the per-cycle parent story pattern; for now, the manual pattern is the integration.

**Graceful degradation.** If Kanbaroo is not available (no `mcp__kanbaroo__*` tools, no kanbaroo-plugin), every Kanbaroo-flavored sub-step below is a no-op. The iterate loop runs exactly as it did before — the friction report stays in this conversation and in `TODO.md`, no Kanbaroo lookup or comment is attempted, and no error surfaces.

## Core Instructions

### Step 1: Establish the Test Task

Before improving the system, you need a task to test it with.

- If the user provides a task, use it as the test workload
- If not, ask: "What task should the inner Claude work on? This will be our test case for the improvement cycle."
- The task should be representative of real usage — not trivial, not enormous
- Capture the task description as `TEST_TASK`

### Step 2: Run the Cage Orchestrator

Invoke the `cage-orchestrator` skill to execute `TEST_TASK` end-to-end.

- Follow the cage-orchestrator workflow through all steps: prerequisites, create, launch, monitor, export
- **Pay close attention to every friction point**: auth failures, polling gaps, messaging issues, timing problems, manual interventions needed
- Keep a running log of observations as you go — do not rely on memory

**If the Kanbaroo bridge is active**, the cage-orchestrator dispatch you trigger here will be mirrored to a Kanbaroo story automatically (creation, progress comments, export summary, revision capture — all per the bridge's hooks). That story represents the *test workload*, not the iteration cycle itself. If you have created a separate parent "iteration cycle" story (see the companion-skill section above), link the two manually using `kanbaroo-workflow` so the parent retains the trail.

### Step 3: Assess Results

After the cage task completes (or fails), conduct a structured assessment.

#### 3a: Task Quality Review

Read the inner Claude's output. Evaluate:

- Did the inner Claude complete the assigned task?
- Is the code quality acceptable?
- Were there gaps between what was asked and what was delivered?
- Did the inner Claude use the messaging protocol correctly?

#### 3b: Orchestration Friction Report

Review the orchestration itself. For each of these categories, note what worked and what didn't:

| Category | Questions |
|---|---|
| **Auth** | Did credentials propagate correctly? Any manual login steps needed? |
| **Launch** | Did `claude -p` start cleanly? Any startup failures? |
| **Messaging** | Did inner Claude send progress_update and task_complete? Were messages well-formed? Did the outer read them successfully? |
| **Monitoring** | Was polling effective? Did we detect completion promptly? Were there blind spots? |
| **Export** | Did rsync overlay work? Any file conflicts or unexpected changes? |
| **Error handling** | If something failed, was the failure surfaced clearly? Was recovery possible? |

#### 3c: Present Assessment

Present the findings to the user in a structured format:

```
## What Worked
- (list)

## What Didn't Work
- (list with specifics)

## Enhancement Candidates
- (numbered list, each with: what, why, estimated effort)
```

**If Kanbaroo is available**, offer to file this assessment as a comment on the parent iteration-cycle story (per the companion-skill section above) — it is the most useful artefact a board can hold from this loop. If the user prefers, file each Enhancement Candidate as its own Kanbaroo story so the next cycle can pick them up by human ID. Use `kanbaroo-workflow` to create the comment or stories; do not call the MCP tools directly from this skill.

### Step 4: Prioritize and Plan

- Ask the user which enhancements to tackle in this cycle
- For each selected enhancement, determine:
  - Which files need to change (trusty-cage repo, cage-orchestrator SKILL.md, or both)
  - Whether it's a bug fix (patch), new feature (minor), or breaking change (major)
  - Dependencies between enhancements (order matters)
- Write a plan using the project's standard plan workflow
- Get user approval before implementing

### Step 5: Implement

Execute the approved plan:

- Follow the implementation order from the plan
- Run `ruff format . && ruff check --fix .` after each file change
- Run `pytest` after completing each logical unit
- Commit when the user approves (never auto-commit)

### Step 6: Re-test

Run the same `TEST_TASK` (or a new one if the user prefers) through the cage orchestrator again.

- Use the updated code (reinstall with `pip install -e .` if needed)
- Compare this run against Step 2's observations
- Note which friction points were resolved and which remain

### Step 7: Close the Loop

Present the comparison to the user:

```
## Cycle Results

### Resolved This Cycle
- (what was fixed and how)

### Still Open
- (remaining friction, candidates for next cycle)

### New Issues Discovered
- (anything that surfaced during re-test)
```

Update `TODO.md` with any new items.

**If Kanbaroo is available**, also post this comparison as a comment on the parent iteration-cycle story (if one exists), and either move the parent story to `done` or keep it open for the next cycle as the user prefers. For "Still Open" items the user wants to tackle next cycle, file them as Kanbaroo stories now so they are picked up by human ID rather than rediscovered. Defer transitions to the user — same etiquette as `kanbaroo-workflow`. When Kanbaroo is not available, `TODO.md` is the only durable record.

Ask the user: "Run another cycle, or stop here?"

## Rules & Guardrails

- **NEVER** skip the assessment step. The whole point is to identify improvements, not just run tasks.
- **NEVER** implement improvements without user approval on the plan.
- **NEVER** auto-commit. Always ask before committing.
- **ALWAYS** log friction points as you encounter them during Step 2 — don't wait until the assessment.
- **ALWAYS** re-test after implementing improvements. Untested improvements are assumptions.
- **ALWAYS** update TODO.md with the full enhancement list, including items not tackled this cycle.
- **ALWAYS** keep changes scoped to one cycle. Don't try to fix everything at once.
