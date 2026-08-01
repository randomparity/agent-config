---
name: triage-issues
description: "Analyze GitHub issues and apply a consistent type, priority, status, risk, and effort taxonomy, including bootstrapping missing labels. Use when asked to triage issues, label a backlog, prepare issues for work selection, or create the label set required by issue workflows."
---
# Triage GitHub Issues

Analyze one or more GitHub issues and apply the repo labels that help with
selecting features to work on. On a repo that lacks a usable label taxonomy,
offer to bootstrap one. The skill is **add-only** except within the
single-value dimensions `priority:`, `status:`, and `risk:`, where it swaps the
existing value. It never closes an issue and never edits an issue body.

Input: use the user-supplied issue numbers, or sweep untriaged open issues when none are supplied.

Execute every step below in order. Both writes to GitHub (creating labels,
applying labels) are gated behind a single explicit confirmation each — do not
write to GitHub before the user confirms that step.

## Curated triage taxonomy

The label set the skill checks for and can bootstrap:

| Dimension | Labels |
|---|---|
| `type:`     | `type:bug`, `type:feature`, `type:docs`, `type:chore` |
| `priority:` | `priority:P0`, `priority:P1`, `priority:P2`, `priority:P3` |
| `status:`   | `status:needs-triage`, `status:ready`, `status:in-progress`, `status:in-review`, `status:awaiting-merge`, `status:blocked`, `status:needs-human` |
| `risk:`     | `risk:night-safe`, `risk:night-watch`, `risk:daytime-only` |
| `effort:`   | `effort:S`, `effort:M`, `effort:L` |
| misc        | `good first issue` |

The `status:` lifecycle values and their colors are defined once in the `github-tracking`
skill — the authority for this dimension. `$triage-issues` normally applies only
`needs-triage`/`ready`/`blocked`; the in-flight values (`in-progress`/`in-review`/
`awaiting-merge`/`needs-human`) are written by the lifecycle commands, but this skill's
bootstrap gate provisions the full set so a fresh repo is writable before the first
`$work-issue`.

The `risk:` dimension — how expensive a change is to undo — is likewise defined once in
the `github-tracking` skill: its three values, their hex colors, the criteria that
separate them, the multi-match/no-match rules, and the human-read invariant this command
must satisfy when it proposes one. Read it there rather than restating it here, so a later
amendment of the rubric reaches every assigner at once.

`priority:`, `status:`, and `risk:` are **single-value dimensions**: an issue should carry
at most one label from each. `type:` and `effort:` are single-value by
convention, but the command only ever adds one to an issue that currently lacks
it, so no swap arises there.

## Labeling policy

- **Add** any `type:`, `effort:`, or `good first issue` label the issue lacks.
- **Swap** within `priority:`/`status:`/`risk:`: when the issue already carries any
  value in that dimension and the assessment differs, remove *every* existing value in
  that dimension and add the new one in the same `gh issue edit` call. These are the
  only cases where the skill removes a label.
- **Never** remove a `type:`/`effort:` label, close an issue, or edit its body.
- Prefer an **adopted** pre-existing equivalent (see step 2) over creating a
  prefixed duplicate.

## Steps

1. **Resolve repo.** Run `gh repo view --json nameWithOwner --jq .nameWithOwner`
   to get `owner/name`. Pass `--repo <owner/name>` on every subsequent `gh`
   call. Do not use `git remote` — this workflow reads through `gh` only.

2. **Label inventory, reconcile, bootstrap gate.** Run
   `gh label list --repo <owner/name> --limit 200 --json name,description`
   (`gh label list` defaults to 30, so pass `--limit` to see the whole set).
   Diff the existing labels against the taxonomy. Before proposing to create a
   taxonomy label, check for an existing semantic equivalent — e.g. `bug` for
   `type:bug`, `enhancement` for `type:feature`, `documentation` for
   `type:docs`. When one exists, **adopt** it for that slot and do not propose
   the prefixed duplicate; record the adopted label's actual name (e.g. `bug`,
   not `type:bug`) — that real name is what goes into the available label set
   and what step 4 proposes. The three `risk:` values are **exempt from adoption**: they
   are a contract read by literal name, so they are created under their exact names or the
   dimension is absent — never served by a pre-existing near-equivalent.
   Offer to create only the genuinely-absent slots,
   via
   `gh label create "<name>" --repo <owner/name> --color <hex> --description "<text>"`.
   Creating labels writes to GitHub — list the labels you would create and get
   one explicit confirmation before running any `gh label create`. The labels
   that exist after this step (pre-existing + adopted + any the user approved for
   creation) are the **available label set** used in step 6.
   When bootstrapping, create the full seven-value `status:` set from the `github-tracking`
   skill (with its hex colors), not just the three triage-time values — the lifecycle
   commands apply the in-flight values later and fail if they were never created.
   Provision the three `risk:` values (with their hex colors) as their **own separately
   declinable group** in the create list, so declining the risk dimension on a fresh repo
   does not also decline the `status:` set this step provisions. The dimension is
   all-or-nothing: a partial `risk:` set is not usable, since the no-match rule needs every
   bucket available to fall back to.

3. **Select issues.** If the arguments contain issue numbers, use exactly those —
   fetching labels for them, since the epic drop below needs label data. Otherwise
   sweep: run
   `gh issue list --repo <owner/name> --state open --json number,labels --limit 500`,
   then keep client-side only the issues carrying no `type:*` label and no adopted
   equivalent ("untriaged"). On both paths, drop `epic`-labeled issues — epics sit
   outside the `status:` machine (see the `github-tracking` epic rule).
   Report `fetched N, untriaged M`, and — when the available label set holds all three
   `risk:` values — also name **every** open, non-`epic` issue carrying **no `risk:`
   value**, as `unjudged for risk: #a #b #c`, whatever its `status:`. **The selection
   predicate itself is unchanged**: these issues are reported, not swept in. An issue
   triaged before the dimension existed carries a `type:` label and so is never
   "untriaged", which is why reporting is the path that reaches it — the operator passes
   those numbers on an explicit run. Do **not** narrow this to `status:ready`: `$epic`'s
   sub-issues are born `status:blocked` or `status:needs-triage`, which is the population
   the `$issue` carried-confirmation carve-out deliberately leaves unassigned, and a
   birth-blocked issue taken by `$work-issue` goes straight to `status:in-progress` without
   ever passing through `ready`. Narrowing would make this report miss precisely the issues
   it exists to surface. On the sweep path the report costs nothing (a second filter over `number,labels`
   already fetched); on the explicit path it costs one
   `gh issue list --repo <owner/name> --state open --json number,labels --limit 500` call,
   carrying the same truncation warning. If the fetch
   returned 500 rows, warn that the sweep was truncated at the limit rather than
   treating it as the complete backlog. GitHub has no native "missing label"
   filter, so this filter is always client-side.

4. **Analyze.** For each selected issue, read its content with
   `gh issue view <n> --repo <owner/name> --json title,body,labels,comments` and
   map it to the taxonomy. Propose labels to add, using each slot's name from the
   available label set — when a slot was served by an adopted label, propose that
   adopted name (e.g. `bug`), never the prefixed taxonomy name. For
   `priority:`/`status:`/`risk:`, propose a swap when the assessed value differs from the
   existing one — but never propose a `status:` swap for an open issue carrying
   `status:blocked` with a `Blocked by #<n>` body line **while any referenced blocker
   is still open** (birth-blocked ordering state; `github-tracking` birth-blocked
   rule). Once every referenced blocker is closed, re-triage *is* the exit edge —
   propose the swap and note the cleared dependency. Do not infer priority beyond what
   the issue text actually states.

   Propose a `risk:` value **only when the available label set holds all three** — say so
   plainly when you skip the dimension, since a silently absent judgment is
   indistinguishable from a deliberate one. Apply the `github-tracking` criteria and its
   multi-match / no-match rules. Judge from what the issue text states, the same discipline
   `priority:` follows — where the text does not settle a conjunct, that is a no-match, not
   a reason to assume the permissive value.

5. **Present the plan.** Show a table `#issue → +labels / −labels (swaps)`. Drop
   from the plan any proposed label that is **not** in the available label set
   from step 2 (one the user declined to create), and list each dropped label so
   the omission is visible. Never plan an `--add-label` for a label that does not
   exist.

   Every proposed `risk:` value carries its reasoning in the table, per the
   `github-tracking` human-read invariant — a confirmation the value's grounds do not
   appear in is not a read of the value, and a confidently wrong `night-safe` is
   typographically identical to a correct one. A `night-safe` row states which of its three
   conjuncts the assessment judged satisfied and on what evidence from the issue text; a
   `night-watch` row states its evidence for reversal by `git revert` alone and names any
   `daytime-only` criterion in contention. `daytime-only` rows need no gloss — the value
   authorizes nothing. State in the confirmation prompt how many `night-safe` values it is
   about to apply, and render a swap toward a **less restrictive** value distinctly, showing
   the value being replaced.

6. **Confirm → apply.** After a single explicit confirmation of the whole plan,
   apply per issue with one call:
   `gh issue edit <n> --repo <owner/name> --add-label "<adds>"` — and for a swap,
   the same call additionally with `--remove-label "<old-values>"`. Report a
   summary of what was applied and any per-issue failures; do not abort the
   remaining issues on a single failure.

## Hard constraints

- `gh` and `Read` only — no file writes, no `git`.
- Add-only except `priority:`/`status:`/`risk:` swaps. Never remove a `type:`/`effort:`
  label, never close an issue, never edit an issue body.
- Both GitHub writes (label creation, label application) require explicit
  confirmation first.
- The apply set is derived from the available label set, so a `gh issue edit`
  never references a label the user declined to create.
