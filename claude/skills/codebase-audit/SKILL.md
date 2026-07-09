---
name: codebase-audit
description: Use when asked to review, audit, or health-check a whole repository — "review the codebase", "find tech debt", "what should we clean up", "are we ready to scale". NOT for reviewing a diff, branch, or PR (that's code review, e.g. /code-review).
---

# Codebase Audit

## Overview

Whole-repo health audit: naming drift, DRY violations, stale docs, dead code, observability gaps, scale readiness. Repo-scoped and debt-focused, where code review is diff-scoped and bug-focused. Run every few weeks, not per-change.

## Workflow

1. Spawn ONE read-only `general-purpose` agent. Its prompt = the full contents of [audit-prompt.md](audit-prompt.md), with the repo path, stack summary, and any repo-specific invariants (from CLAUDE.md) filled into the header. Tell it to read CLAUDE.md and README.md first.
2. When the report lands, render it for the user in the Report Format below — verbatim structure, no improvising.
3. Offer to execute the S-effort items; wait for the user to pick.

## Report Format

The user-facing deliverable is exactly this shape:

```markdown
# Codebase Audit — <repo> @ <short-sha> — <YYYY-MM-DD>

## Health summary
One paragraph: overall state, strongest areas, most concentrated problem areas.

## Scoreboard
| ID | Sev | Category | Finding | Where | Effort |
|----|-----|----------|---------|-------|--------|
| H1 | 🔴 high | dead code | Orphaned unit nothing references | infra/layers/.../terragrunt.hcl | S |
| M1 | 🟡 med  | DRY       | Registry string in 3 places     | 3 files | M |
| L1 | 🟢 low  | docs      | Stale layout section            | README.md:36 | S |

## Details
### H1 — <short title>
- **Where:** file:line (every claim cited)
- **Problem:** what is wrong
- **Why it matters:** consequence if left
- **Fix:** concrete change

## Top picks
Numbered shortlist (≤10) by impact-to-effort, referencing IDs: "1. H1 — delete orphaned unit (S)".
```

Rules:
- IDs are severity-prefixed and sequential (H1, H2, M1, L1) so the user can reply "do H1–H3, M2".
- Effort scale: S < 30 min, M = hours, L = day+.
- Sort scoreboard by severity, then impact-to-effort.
- Every finding cites file:line. A finding with no citation gets dropped, not padded.
- No praise padding; the health summary carries anything positive, once.

## Common Mistakes

- Running a diff review instead — naming drift and dev/prod parity are invisible in a diff.
- Letting the agent return prose walls — hold it to the report format; re-ask if it free-forms.
- Dumping 80 equal-weight bullets — the scoreboard + top picks exist to force ranking.
- Auto-fixing findings — audit is read-only; fixes are a separate, user-approved step.
