---
name: codebase-audit
description: Use when asked to review, audit, or health-check a whole repository — "review the codebase", "find tech debt", "what should we clean up", "are we ready to scale". NOT for reviewing a diff, branch, or PR (that's code review, e.g. /code-review).
---

# Codebase Audit

## Overview

Whole-repo health audit: naming drift, DRY violations, stale docs, dead code, observability gaps, scale readiness. Repo-scoped and debt-focused, where code review is diff-scoped and bug-focused. Run every few weeks, not per-change.

## Workflow

1. **Audit.** Spawn ONE read-only `general-purpose` agent. Its prompt = the full contents of [audit-prompt.md](audit-prompt.md), with the repo path, stack summary, and any repo-specific invariants (from CLAUDE.md) filled into the header. Tell it to read CLAUDE.md and README.md first.
2. **Verify.** Spawn a SECOND, fresh read-only agent (no shared context with the auditor — the finder must not grade its own work). Give it the raw findings and instruct: for every high/med finding, reproduce the evidence with real commands (the actual grep for references, the actual `diff`, a build after simulating a removal where cheap) and tag it `CONFIRMED` (evidence attached) or `UNVERIFIED`. Drop or downgrade UNVERIFIED findings before rendering.
3. **Render** the report for the user in the Report Format below — verbatim structure, no improvising.
4. **Persist.** Write the exact same report to `.codebase-audits/<YYYY-MM-DD-HHMM>.md` in the target repo (create the dir if missing; commit it with the repo's usual workflow). These files are the audit trail *and* the training corpus for improving this skill.
5. **Offer** to execute the S-effort items; wait for the user to pick.
6. **Fix-time safety.** Audit-time verification goes stale as soon as the repo changes. When executing any removal/dead-code fix, re-verify references at that moment, and run the repo's build/tests before committing. No removal commit without a green check.
7. **Log outcomes.** As findings are resolved or rejected, append an `## Outcomes` section to that audit file: `H1 — fixed <sha>` / `M3 — rejected: <reason>` / `H2 — false positive: <what the auditor got wrong>`. False positives and rejections are the treasure — before the *next* audit of any repo, skim the latest audit files' Outcomes and fold recurring auditor mistakes back into audit-prompt.md or the repo's CLAUDE.md.

## Report Format

The user-facing deliverable is exactly this shape: findings grouped by category, each finding a self-contained card readable without cross-referencing.

```markdown
# Codebase Audit — <repo> @ <short-sha> — <YYYY-MM-DD>

## Health summary
One paragraph: overall state, strongest areas, most concentrated problem areas.

## Index
One line per finding: `H1 — <title> (dead code, S, CONFIRMED)` — for picking, not reading.

## <Category name>

### H1 — <short title>  `🔴 high · S · CONFIRMED`
**Current:** what exists now, with file:line and the evidence (grep/diff output summarized).
**Proposed:** the change. For S-effort mechanical fixes (deletes, renames, one-liners), show a
concrete ```diff``` block against current code. For M/L findings, describe the change and show
the current-state snippet — do not half-implement the fix.
**Why:** consequence if left as-is.
**Verification:** what to re-check at fix time (re-grep, build, test) before committing.

## Top picks
Numbered shortlist (≤10) by impact-to-effort, referencing IDs: "1. H1 — delete orphaned unit (S)".
```

Rules:
- IDs are severity-prefixed and sequential (H1, H2, M1, L1) so the user can reply "do H1–H3, M2".
- Effort scale: S < 30 min, M = hours, L = day+.
- Order categories by their worst finding; order findings within a category by impact-to-effort.
- Every card cites file:line and carries a confidence tag. A finding with no citation gets dropped, not padded.
- No praise padding; the health summary carries anything positive, once.

## Common Mistakes

- Running a diff review instead — naming drift and dev/prod parity are invisible in a diff.
- Letting the auditor grade its own findings — the verify pass must be a fresh agent.
- Rendering UNVERIFIED high/med findings as fact — tag or drop them.
- Letting the agent return prose walls — hold it to the report format; re-ask if it free-forms.
- Dumping 80 equal-weight bullets — the index + top picks exist to force ranking.
- Auto-fixing findings — audit is read-only; fixes are a separate, user-approved step.
- Executing a removal fix on stale audit evidence — re-verify + build/test at fix time, always.
- Losing the report in chat scrollback — always persist to `.codebase-audits/` and log outcomes there.
