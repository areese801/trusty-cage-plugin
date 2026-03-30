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

Ask the user: "Run another cycle, or stop here?"

## Rules & Guardrails

- **NEVER** skip the assessment step. The whole point is to identify improvements, not just run tasks.
- **NEVER** implement improvements without user approval on the plan.
- **NEVER** auto-commit. Always ask before committing.
- **ALWAYS** log friction points as you encounter them during Step 2 — don't wait until the assessment.
- **ALWAYS** re-test after implementing improvements. Untested improvements are assumptions.
- **ALWAYS** update TODO.md with the full enhancement list, including items not tackled this cycle.
- **ALWAYS** keep changes scoped to one cycle. Don't try to fix everything at once.
