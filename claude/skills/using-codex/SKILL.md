---
name: using-codex
description: Use when Claude should delegate work to OpenAI Codex CLI, consult Codex for a second opinion, compare model behavior, or run Codex as a non-interactive coding agent from the shell.
---

# Using Codex CLI

Use this skill when you want Codex to act as a second coding agent, reviewer, debugger, or implementation worker from the command line.

## Hard Rules

- Always invoke `codex exec --yolo`.
- Always choose a model with `-m`.
- Do not use interactive `codex` for this skill.
- Quote the prompt as a single shell argument.
- Always start Codex in the background so the main conversation can continue.
  Write output to a log file and poll it later instead of blocking.

Default command shape:

```bash
mkdir -p .agent-runs
log=".agent-runs/codex-$(date +%Y%m%d-%H%M%S).log"
codex exec --yolo -m gpt-5.5 "prompt goes here" >"$log" 2>&1 &
echo "Codex running in background: pid=$! log=$log"
```

The model slug uses hyphens: `gpt-5.5`, not `gpt5.5`.

## Model Selection

Pick the model based on the task Codex should perform:

- `gpt-5.5`: [opus] use for hard implementation, architecture, multi-file debugging, complex refactors, subtle test failures, security-sensitive reasoning, and any task where correctness matters more than speed.
- `gpt-5.4`: [sonnet or lower Opus-class] use for normal coding tasks, focused feature work, medium debugging, test writing, and repo analysis.
- `gpt-5.4-mini`: [haiku or efficient Sonnet-class] use for simple edits, summaries, mechanical transformations, small scripts, formatting help, and low-risk quick checks.
- `gpt-5.3-codex-spark`: [fast Haiku-style coding model] use for fastest narrow tasks, quick consultation, small command suggestions, or interruptible exploratory work.

If unsure, use `gpt-5.5`.


## Listing Models

To list all models Codex exposes:

```bash
codex debug models | jq -r '.models[] | select(.visibility == "list") | "\(.slug)\t\(.display_name)"'
```

If a chosen model is unavailable, list models and choose the closest available model by capability and speed.

## Delegation Patterns

```bash
codex exec --yolo -m gpt-5.5 "Implement the requested change. Keep edits minimal, follow the repo's existing patterns, and run the relevant tests before summarizing what changed."
```

For review or consultation, explicitly prohibit edits:

```bash
codex exec --yolo -m gpt-5.5 "Review the current repository state for likely bugs or design issues. Do not edit files. Report findings with file paths and line numbers where possible."
```

For quick model-assisted analysis:

```bash
codex exec --yolo -m gpt-5.4-mini "Summarize the repository structure and identify the most important entry points."
```

For piping context into Codex, put the instruction in the prompt and pipe the data as context:

```bash
mkdir -p .agent-runs
log=".agent-runs/codex-$(date +%Y%m%d-%H%M%S).log"
npm test 2>&1 | codex exec --yolo -m gpt-5.5 "Analyze these test failures and suggest the smallest likely fix." >"$log" 2>&1 &
echo "Codex running in background: pid=$! log=$log"
```

Check progress with `tail -f "$log"` or `tail -n 200 "$log"` when you need the
result.

## Safety Notes

`--yolo` bypasses approvals and sandboxing. Use clear prompts that constrain Codex's scope, especially for implementation tasks.

When asking Codex to consult only, include `Do not edit files.` in the prompt. When asking Codex to implement, include the expected verification command and any files or areas that are out of scope.
