---
name: using-claude
description: Use when Codex (or any agent) should delegate work to Claude Code CLI, consult Claude for a second opinion, compare model behavior, or run Claude as a non-interactive coding agent from the shell.
---

# Using Claude Code CLI

Use this skill when you want Claude to act as a second coding agent, reviewer, debugger, or implementation worker from the command line.

## Hard Rules

- Always invoke `claude -p --dangerously-skip-permissions`.
- Always choose a model with `--model`.
- Do not start an interactive `claude` session for this skill.
- Quote the prompt as a single shell argument.
- Always start Claude with the agent harness's background execution mechanism so
  the main conversation can continue. Do not rely on shell `&` unless the
  harness has no native background/session support.
- Write output to a log file and poll it later instead of blocking.
- For long-running work, use `--verbose --output-format stream-json` so progress
  is visible while Claude runs. The Claude CLI requires `--verbose` when
  `-p/--print` and `--output-format stream-json` are combined.
- Never paste or read raw stream-json logs directly into agent context unless
  debugging the wrapper itself. Raw logs include hook payloads and session
  metadata. Poll compact summaries with `jq` and keep the full log on disk.

Default long-running command shape:

```bash
mkdir -p .agent-runs
log=".agent-runs/claude-$(date +%Y%m%d-%H%M%S).jsonl"
claude -p --dangerously-skip-permissions --model opus --verbose --output-format stream-json "prompt goes here" >"$log" 2>&1
echo "Claude log: $log"
```

Run that command with the harness background option:

- Codex: start it as a background/ongoing `exec_command` session and poll the
  session plus log later.
- Claude Code: use the Bash tool's background mode and poll with `BashOutput`.
- Fallback shell-only environments: append `&` and record the PID.

`-p`/`--print` runs non-interactively and exits. `--model` takes an alias (`opus`, `sonnet`, `haiku`, `fable`) or a full model name (e.g. `claude-opus-4-8`).
`--output-format stream-json` emits newline-delimited JSON events as they happen,
which makes the log useful before the final answer is ready. Poll it through
filters, not raw `tail`.

Compact progress view:

```bash
jq -r '
  if .type == "assistant" then
    "assistant: " + ((.message.content[]?.text? // "") | gsub("\n"; " ") | .[0:240])
  elif .type == "tool_use" then
    "tool: " + (.name // "unknown")
  elif .type == "system" and .subtype == "api_retry" then
    "retry: " + (.error_status|tostring) + " " + (.error // "")
  elif .type == "result" then
    "result: " + (if .is_error then "error" else "success" end) + " " + ((.result // "") | gsub("\n"; " ") | .[0:240])
  else empty end
' "$log" | tail -40
```

Final assistant text:

```bash
jq -r 'select(.type == "assistant") | .message.content[]?.text?' "$log"
```

Failure/result summary:

```bash
jq -r 'select(.type == "result") | {is_error, api_error_status, duration_ms, total_cost_usd, result}' "$log"
```

Use plain text output only for trivial calls where the final result should be
immediate, and still prefer a background log if there is any uncertainty:

```bash
mkdir -p .agent-runs
log=".agent-runs/claude-$(date +%Y%m%d-%H%M%S).log"
claude -p --dangerously-skip-permissions --model haiku "Short prompt." >"$log" 2>&1
echo "Claude log: $log"
```

## Model Selection

Pick the model based on the task Claude should perform. Codex → Claude mapping:

- `opus` (`claude-opus-4-8`): [Codex `gpt-5.5`] use for hard implementation, architecture, multi-file debugging, complex refactors, subtle test failures, security-sensitive reasoning, and any task where correctness matters more than speed.
- `sonnet` (`claude-sonnet-5`): [Codex `gpt-5.4`] use for normal coding tasks, focused feature work, medium debugging, test writing, and repo analysis.
- `haiku` (`claude-haiku-4-5`): [Codex `gpt-5.4-mini`] use for simple edits, summaries, mechanical transformations, small scripts, formatting help, and low-risk quick checks.
- `haiku` (`claude-haiku-4-5`): [Codex `gpt-5.3-codex-spark`] use for fastest narrow tasks, quick consultation, small command suggestions, or interruptible exploratory work. Claude has no separate "spark" tier; Haiku is the fastest.

If unsure, use `opus`.

## Listing Models

To list model aliases Claude exposes:

```bash
claude --help | grep -A5 -- '--model'
```

Aliases resolve to the latest model in each class. Use a full name (e.g. `claude-opus-4-8`) to pin a specific version. If a chosen model is unavailable, fall back to the closest alias by capability and speed.

## Delegation Patterns

Use this shape for implementation, review, or other work that may take more than
a minute:

```bash
mkdir -p .agent-runs
log=".agent-runs/claude-$(date +%Y%m%d-%H%M%S).jsonl"
claude -p --dangerously-skip-permissions --model opus --verbose --output-format stream-json "Implement the requested change. Keep edits minimal, follow the repo's existing patterns, and run the relevant tests before summarizing what changed." >"$log" 2>&1
echo "Claude log: $log"
```

For review or consultation, explicitly prohibit edits:

```bash
mkdir -p .agent-runs
log=".agent-runs/claude-$(date +%Y%m%d-%H%M%S).jsonl"
claude -p --dangerously-skip-permissions --model opus --verbose --output-format stream-json "Review the current repository state for likely bugs or design issues. Do not edit files. Report findings with file paths and line numbers where possible." >"$log" 2>&1
echo "Claude log: $log"
```

For quick model-assisted analysis:

```bash
mkdir -p .agent-runs
log=".agent-runs/claude-$(date +%Y%m%d-%H%M%S).jsonl"
claude -p --dangerously-skip-permissions --model haiku --verbose --output-format stream-json "Summarize the repository structure and identify the most important entry points." >"$log" 2>&1
echo "Claude log: $log"
```

For piping context into Claude, put the instruction in the prompt and pipe the data as context:

```bash
mkdir -p .agent-runs
log=".agent-runs/claude-$(date +%Y%m%d-%H%M%S).jsonl"
npm test 2>&1 | claude -p --dangerously-skip-permissions --model opus --verbose --output-format stream-json "Analyze these test failures and suggest the smallest likely fix." >"$log" 2>&1
echo "Claude log: $log"
```

Check progress with the compact `jq` progress view above. Avoid raw
`tail -f "$log"` and `tail -n 200 "$log"` because stream-json logs include large
hook payloads that waste context. For more granular streaming, add
`--include-partial-messages` with `--verbose --output-format stream-json`, then
still poll through `jq`. If a plain text `-p` run has no output yet, wait or
poll the process; do not assume it is hung solely because the log is quiet.

`--input-format stream-json` is separate: use it only when feeding Claude
realtime JSON input on stdin. For normal prompts, keep the default text input and
use `--output-format stream-json` for realtime output.

## Safety Notes

`--dangerously-skip-permissions` bypasses all permission checks (the Claude equivalent of Codex's `--yolo`). Recommended only for sandboxes with no untrusted internet access. Use clear prompts that constrain Claude's scope, especially for implementation tasks.

When asking Claude to consult only, include `Do not edit files.` in the prompt. When asking Claude to implement, include the expected verification command and any files or areas that are out of scope.
