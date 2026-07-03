---
name: writing-goals
description: Use when Calum asks to create, write, set, formulate, or improve a /goal (Claude Code's goal command). ALWAYS load this BEFORE composing any goal condition, no matter what — even a one-line "set a goal to X" request.
---

# Writing Goals

## Core principle

A `/goal` condition is judged by a fast model running as a Stop hook. **The evaluator only reads the conversation transcript — it does NOT run commands or read files.** So the goal must be provable from Claude's own surfaced output, and the more specific the condition, the less room Claude has to declare victory early or wander off.

**Vague goals go off the rails. Specific goals can't.**

## The formula

Every goal = **end state + the exact check that proves it + the boundaries that must not move**.

1. **One measurable end state** — an exit code, a count, an empty queue, a clean tree. Not "it works", not "the bug is fixed".
2. **The exact check** — name the command and the success signal: ``gate.sh`` exits 0, "142 tests pass", ``git status`` clean.
3. **Boundaries / forbidden shortcuts** — what must NOT change to get there: don't delete or skip tests, don't touch other files, don't weaken assertions.

## Make it sharper (the specificity ladder)

Calum's rule: keep tightening until there's exactly one way to satisfy it. "All tests pass and lint is clean" is a starting point, not a finished goal.

| Level | Condition |
|---|---|
| ❌ Vague | `fix the bug` / `make it work` / `optimize performance` |
| ⚠️ Loose | `all tests pass and lint is clean` |
| ✅ Tight | ``gate.sh`` exits 0 with zero warnings, all 142 tests in `test/` pass with 0 skipped and 0 new xfail, ``git status`` shows only the files I set out to change, and no test was deleted or weakened to get there |

Each rung adds a dimension Claude could otherwise exploit:
- **Exact signal** — `exit 0` / a count, not "passes"
- **Scope** — *which* tests, *which* files
- **Anti-cheating** — forbid skip/xfail/delete/weaken (the evaluator can see the transcript, so name the dodge)
- **Blast radius** — only the intended files changed

## Fuzzy goals (no natural exit code)

The dangerous case: "document the config module", "clean up X", "improve the API". There's no command that returns 0/1, so a vague goal lets Claude declare victory on a vibe. **Invent a transcript-checkable proxy:**

- A **count driven to 0** — "surface the count of exported symbols with no doc comment, show it reach 0" (or a `missing_docs` / doc-lint that exits 0).
- A **command** that stands in for the quality — a linter/formatter/typecheck on the named scope, exit 0, output shown.
- And an **anti-fake clause** — "no placeholder or TODO doc comments", "don't suppress warnings or weaken the linter config to pass".

Never ship a goal whose only success word is "clean", "good", or "well-documented". The evaluator can't judge a vibe.

## Big goals: the textbook process (ground, persist, write to a file)

For anything bigger than a one-liner (ship a feature, finish a design, drive an epic to prod), the goal text alone is not the job. Do this, in order:

1. **Ground the goal in REAL facts first.** Never compose a big goal from assumptions. Explore the codebase, dig up prior session transcripts (`~/.claude/projects/<proj>/*.jsonl`), and read the relevant bd tickets, dispatching agents to fan out. A goal built on a wrong premise (an integration that isn't wired, a file that doesn't exist, a credential that's missing) is unsatisfiable. Surface the real entity ids, file paths, and verified commands, then write the goal against those.

2. **Persist the durable inputs to `main` BEFORE writing the goal.** If the goal depends on a spec, design bundle, or notes, commit them into the repo (e.g. `docs/<feature>/`) and reference them by path, so the executor and any fresh workflow worktree can read them. Distil verified facts (entity ids, working API/SOAP calls, gotchas) into a notes file next to the spec. Exclude any reference/prototype bundle from the lint and dead-code gates (biome `files.includes`, knip `ignore`) so it can't break CI. Get this on `origin/main`, gates green, before the goal exists.

3. **Write the goal to a FILE on `main`, not just inline.** A long ship-to-prod goal belongs in `docs/<feature>/GOAL.md` so Calum can invoke `/goal @docs/<feature>/GOAL.md`. Make the file self-contained: it IS the condition. Merge it to `main` (no PR) and push so the `@file` reference resolves.

4. **Name the executor.** If the work should run via a workflow (e.g. `ship` on a bd epic, `push:true`), say so in the goal and tell it to parallelize. The goal stays the contract; the workflow is how it gets done.

### The standard dimensions of a "ship a feature to prod" goal

A complete prod goal almost always needs ALL of these, each transcript-provable:

- **Scope** — the exact components/files/hooks to build, and what is explicitly OUT (parked).
- **Real integrations, no fake data** — services THROW when unconfigured; name the guard (`scripts/check-fake-data.sh`) and a `grep` that must come back empty. Real credentials resolve from 1Password, never stubs.
- **Gates green** — `typecheck`, `test` (0 failed, **0 skipped**), `biome check .`, `knip` (zero findings), each run with output shown, none weakened to pass.
- **Storybook / docs** — every new component has a story with autodocs plus tests; name the docs guard.
- **Shipped** — commit format the guard requires (`type(area/CC-xxx)`), merged to `main` with NO PR, pushed, `git status` clean, CI + deploy green, the deploy actually rolled.
- **Verified live in a browser, in PROD** — agent-browser against the real prod URL at the real viewport (not local/storybook). Screenshot EVERY surface (each tile AND each modal) and **state in the transcript what each screenshot shows** (the real values), since the evaluator can't see the image. One screenshot per surface, named.
- **No regressions** — the rest of the app still renders, browser console clean of new errors, `main` clean. The change didn't break neighbours to land.

## Quick checklist

- [ ] Can I name the single command whose output settles done-or-not? If not, tighten.
- [ ] Is the success signal exact (exit code / count), not a vibe?
- [ ] Did I forbid the obvious shortcuts (skipping tests, editing unrelated files, loosening asserts)?
- [ ] Is the scope named (which files / which suite)?
- [ ] (Big goal) Did I ground it in real facts first (codebase, prior transcripts, bd tickets), persist the spec/notes to `main`, and write the goal to a `@file` on `main`?
- [ ] (Ship to prod) Does it cover all the standard dimensions: scope, real integrations/no-fake-data, gates green, storybook/docs, shipped+deployed, browser-verified in prod (every surface, described in transcript), no regressions?

## Common mistakes

- **Unverifiable from transcript** — `the code is correct`. The evaluator can't check it. Make Claude run a command and surface the result.
- **Leaving the dodge open** — `all tests pass` invites `#[ignore]` / `.skip`. Close it: "...with 0 skipped and no test deleted."
- **No scope** — `tests pass` vs `all tests in test/auth pass`. Name it.
