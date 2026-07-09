# Audit agent prompt template

Fill in the `<...>` header, then use as the spawned agent's full prompt.

---

You are performing a whole-repository health audit of `<repo path>` (`<one-line stack summary>`). Read CLAUDE.md and README.md first for context and repo conventions. Repo-specific invariants to check against: `<invariants from CLAUDE.md, e.g. "every prod change must also land in dev in the same change">`.

Explore the entire codebase and return a prioritized list of concrete, actionable suggestions. For every finding: cite specific files/lines, explain why it matters, and propose a fix. Rank by impact-to-effort ratio. Skip nitpicks that don't change maintainability, correctness, or operability.

## What to look for

1. **Leaky abstractions** — modules/stacks/scripts that expose internals callers shouldn't know about, or force callers to coordinate details the abstraction should own (e.g. a module that requires its consumer to know its resource naming scheme).

2. **Cleaner abstractions & patterns** — places where a better-shaped interface, a shared module, or an established pattern (already used elsewhere in the repo) would simplify things. Prefer patterns the repo already has over inventing new ones.

3. **Missing leverage from existing tools/libraries** — hand-rolled code that a well-maintained library, module, task-runner recipe, or built-in feature already solves. Also flag the inverse: dependencies carried but barely used.

4. **Stale or wrong docs** — README, docs/, CLAUDE.md, comments, and spec files that no longer match the code. Docs describing how something used to work are worse than no docs.

5. **Inconsistent naming** — resources, tags, hostnames, variables, files, directories not following the dominant convention. Identify the majority convention, then list every deviation and the rename needed. Include env-suffix placement, separators, abbreviations.

6. **Over-documentation** — comments restating what code does, boilerplate doc headers, narration. Comments should explain *why*: constraints, gotchas, non-obvious tradeoffs. Flag comments to delete.

7. **DRY / single source of truth** — duplicated values or logic that should live in one place and be derived everywhere (domains, image tags, ports, env lists, naming prefixes). Prefer mechanisms that *fail loudly* when source and consumers drift (validation, git hooks, CI checks, generated code) over conventions relying on humans remembering.

8. **Observability at key points** — do critical paths (bootstrap, deploy, workers, schedulers, health checks) emit enough logging/metrics to diagnose a 3am incident without adding printlns first? Flag missing logs at decision points AND noisy logs burying signal. Check log levels are meaningful.

9. **Scale readiness** — what breaks or gets painful at 3x the apps, environments, or contributors? Per-app copy-paste that should be generated or parameterized, implicit ordering dependencies, manual steps needing automation, anything where adding "one more X" touches N files.

10. **Dead code & orphans** — unused variables, unreferenced files/modules/scripts, commented-out blocks, committed build artifacts, stale worktrees/branches, TODO/FIXME/HACK markers (list all, with age from git blame if cheap to derive).

11. **Error handling & failure modes** — scripts without `set -euo pipefail`, ignored exit codes, missing timeouts/retries, operations that half-fail leaving inconsistent state, missing preconditions that would let us fail early with a clear message instead of late with a cryptic one.

12. **Env parity & config drift** — differences between environments not intentional and documented. Every divergence should be explicit.

13. **Secrets & security hygiene** — secrets or sensitive values outside the secret store, secrets landing in state/outputs/logs, overly broad permissions/tokens, anything that would leak via a public repo. Report only; do not fix.

14. **CI/CD & automation gaps** — checks that run only on humans-remembering (fmt, validate, lint, drift detection), slow/flaky pipeline steps, missing pre-merge validation that would catch bugs you found above.

15. **Testing gaps** — critical logic (workers, scripts, modules) with no validation at all; where the cheapest meaningful test would go.

16. **Onboarding friction** — what a new contributor trips over in the first hour: undocumented prerequisites, magic commands, tribal knowledge.

## Output format

Group findings by category. Each finding must include:
- `severity (high/med/low)`, `file:line`, `estimated effort (S = <30 min, M = hours, L = day+)`
- **Evidence:** the command you ran and a one-line summary of its output (the grep proving zero references, the diff proving duplication). A claim without reproducible evidence is a guess — label it as such or drop it.
- **Current vs proposed:** what exists now, and the change. For S-effort mechanical fixes (deletes, renames, one-liners) include a concrete ```diff``` block. For M/L findings describe the change — do not implement it.

End with a top-10 shortlist: highest-leverage changes across all categories.

Read-only: do NOT modify any files. Your final message must contain the full findings report.
