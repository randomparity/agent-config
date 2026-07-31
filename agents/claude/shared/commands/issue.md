---
description: Create a structured GitHub issue — read the code first, dedup against existing issues, enforce mandatory sections, born triaged
argument-hint: '[description of the problem]   (or: decompose #N into sub-issues)'
allowed-tools: Read, Grep, Glob, Bash(gh:*), Write
---

# Create a Structured GitHub Issue

Draft and file a GitHub issue for the problem in `$ARGUMENTS`, grounded in the actual code
and de-duplicated against existing issues. The single GitHub write (creating the issue, and
in decompose mode its sub-issues) is gated behind one explicit confirmation.

## Steps

1. **Resolve repo.** `gh repo view --json nameWithOwner --jq .nameWithOwner` → `owner/name`.
2. **Read the code before drafting.** Verify the claim in `$ARGUMENTS` against the source
   with `Grep`/`Glob`/`Read`. The body must carry `file:line` evidence — a claim you could
   not find in the code is a finding *against filing*, not for it; say so and stop.
3. **Dedup gate.** Search existing issues across **all states** — a closed duplicate
   (already fixed, or `wontfix`) is exactly the context you need before re-filing:
   `gh search issues --repo <owner/name> <keywords> --json number,title,state` (omit
   `--state`; it accepts only `open`/`closed`, never `all`). Rank by title/token overlap.
   If a near-match exists, present it **with its state** and offer **"comment on #N
   instead"** before proposing a new issue. Never file a duplicate silently.
4. **Draft with mandatory sections.** The body MUST contain: **Problem**, **Evidence**
   (the `file:line` refs from step 2), **Expected**, **Proposed approach**. Refuse to file a
   body missing **Evidence**.
5. **Triage at creation.** Apply the `/triage-issues` taxonomy (`type:`/`priority:`/
   `effort:` + adopted equivalents). Ensure-create the `status:` label you will apply using
   the `github-tracking` skill's `ensure_label` recipe. Born triaged:
   `status:ready` when you assigned all of `type:`, `priority:`, and `effort:`;
   `status:needs-triage` when any slot was left unassigned.

   **Also assign a `risk:` value**, against the criteria in the `github-tracking` skill,
   after one `gh label list --repo <owner/name> --limit 200 --json name` read — and **only
   when that inventory already holds all three values**. This command never *creates* a
   `risk:` label: `/triage-issues`' bootstrap gate is the sole provisioning point, so a
   decline there stays declined rather than being undone by the next `/issue` run. Show the
   value's reasoning in the step-6 draft, per the human-read invariant.

   `risk:` is deliberately **not** part of the born-ready conjunction above. Born-ready
   governs eligibility for *daytime* work; `risk:` gates only unattended work, and coupling
   them would park every issue the dimension has not reached.
6. **Confirm → create.** Show the full draft (title, body, labels) and get one explicit
   confirmation. Then `gh issue create --repo <owner/name> --title <t> --body-file <tmp>
   --label <labels>`. Prefer `--body-file` over inline `--body`; never `eval` argument
   tokens.
7. **Decompose mode** (arguments name a parent issue, e.g. "decompose #N"): read the parent
   (and its `/scope` split if present), draft each sub-issue through steps 2–6, and file each
   as a **native sub-issue** with `gh issue create --parent <N> ...` (the direct native
   path, `gh` ≥ 2.94.0; on older `gh`, or to link a *pre-existing* issue instead, use
   `gh api repos/<owner>/<name>/issues/<N>/sub_issues` or the `sub_issue_write` MCP tool).
   Add a `Part of #N` courtesy line to each sub-issue body.

   **Carried confirmation.** A calling command that has already shown these drafts and
   obtained one explicit confirmation (e.g. `/epic`'s step-6 gate) carries that
   confirmation into filing: do not re-confirm and do not re-run dedup (it already ran
   per sub-issue; sibling sub-issues of the same parent are never dedup candidates). An
   Evidence refusal aborts that one sub-issue and reports it via the caller's
   partial-filing path — it never prompts mid-set. **Leave the `risk:` slot unassigned on
   this path**, and skip its inventory read: `/epic`'s go/no-go displays only `status:`
   birth labels, so a value assigned here would reach GitHub unread, which the
   `github-tracking` human-read invariant forbids. The carve-out keys on the *carried
   confirmation*, not on decompose mode — a human-run `/issue decompose #N` still assigns,
   because step 6 shows it each draft. `/triage-issues` reaches these issues later via its
   report line. Birth labels come from the caller's
   per-entry state, overriding step 5: `status:blocked` + a `Blocked by #<n>` body line
   for dependents, `status:needs-triage` for open-question entries (blocked wins when
   both apply), else `status:ready` — the same rule recovery applies below.

   **Epic-parent recovery.** When the parent carries the `epic` label, its Decomposition
   section is the authoritative sub-issue list. Enumerate existing native sub-issues
   (`gh api repos/<owner>/<name>/issues/<N>/sub_issues`), diff by the entries' `#<n>`
   annotations first (an annotated entry is satisfied iff its number is in the list),
   falling back to exact title match only for unannotated entries. File only absent
   entries, in topological order, resolving `Blocked by` refs via the annotations —
   except `(adopted)`-annotated entries, which are **re-linked, never created**
   (re-check the adoption preconditions — still open, unparented, without sub-issues
   of its own, not `epic`-labeled; create with a fresh annotation and a
   dependents' `Blocked by` renumber only when the annotated issue no longer exists or
   is permanently disqualified, surfacing that to the operator). If a re-filed entry
   replaces a deleted blocker, update its dependents' `Blocked by #<old>` lines to the
   new number. An entry whose Evidence refusal is deterministic — genuinely greenfield,
   no existing code to cite — is surfaced as **unfileable, operator action required**,
   not looped back through the same refusal on every recovery pass.
   Re-filed entries take their birth labels from the entry's own state —
   `status:blocked` + `Blocked by #<n>` for dependents, `status:needs-triage` for
   open-question entries (blocked wins when both apply), else `status:ready`.
   After every recovery create — including a deleted-blocker replacement —
   write the annotation back to the epic's Decomposition entry (`#<old>` → `#<new>`;
   annotate previously-unannotated entries `#<n> — <title>`), so the next recovery run
   converges and files nothing.

## Hard constraints

- Read + `gh` only; no branches, no file writes outside the temp body file.
- Explicit `--json` fields on every `gh` read.
- One confirmation before any `gh issue create` / sub-issue write — a caller's carried
  confirmation (step 7) counts as that confirmation.
- Refuse to file without an Evidence section.
