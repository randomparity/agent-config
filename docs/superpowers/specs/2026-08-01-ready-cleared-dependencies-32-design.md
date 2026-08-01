# Ready Cleared Dependencies Design

## Scope

Issue #32 defines one lifecycle edge: an open, non-epic issue with
`status:blocked` becomes `status:ready` after every dependency recorded by a canonical
whole-line `Blocked by #N` entry is closed. Merge cleanup owns the normal post-merge edge;
orphan recovery proposes the identical repair behind its existing confirmation gate.

Campaign selection is unchanged. Triage remains a manual reassessment path. Arbitrary prose,
comments, and non-canonical dependency spellings have no lifecycle meaning.

## Approaches considered

1. Teach each consumer, including campaigns, to interpret dependencies. This duplicates
   parsing and makes `status:ready` non-authoritative, so it is rejected.
2. Add a standalone dependency-reconciliation command. This creates a new entry point and
   still leaves the common merge path dependent on an extra operator action, so it is
   rejected.
3. Define one reusable shell recipe in the tracking contract and have merge cleanup and
   recovery invoke it at their existing lifecycle boundaries. This is selected because it
   preserves one parser and one transition rule without adding a new skill.

## Canonical dependency contract

A canonical reference is a body line matching exactly `Blocked by #N`, where `N` is one or
more decimal digits. Matching is case-sensitive and permits no leading/trailing whitespace,
punctuation, list marker, or extra text. The parser considers only the issue body, never
comments. Lines beginning with `Blocked by #` that do not match the canonical form are
malformed dependency records and make evaluation fail closed with the offending dependent
and line reported. Other prose is ignored.

An eligible dependent must be open, non-epic, and carry `status:blocked`. It must contain at
least one canonical reference. Every referenced issue is read explicitly with GitHub CLI.
The dependent stays blocked if a reference is open, missing, malformed, or unreadable. The
report names the dependent, reference when available, reason, and a suggested operator
action. Duplicate references may be resolved once but do not change the all-closed rule.

When all references resolve closed, the writer ensures `status:ready` exists, then performs
one `gh issue edit` call that removes every current `status:` label and adds
`status:ready`. A failure to ensure the destination label or update the issue is reported
and does not count as a transition.

The lifecycle contract assumes its documented one-writer-per-transition-edge discipline:
merge cleanup and recovery never write this edge concurrently. Immediately before the edit,
the writer re-reads the dependent's state, labels, body, and every blocker. A changed or
unreadable value cancels the transition and reports a stale evaluation. After the edit it
reads the labels back and reports failure unless `status:ready` is the only `status:` value.
This does not claim transactional isolation from an operator editing GitHub concurrently;
it makes the supported workflow deterministic and detects conflicting status writes.

## Shared recipe and ownership

`github-tracking` documents a `reconcile_cleared_dependencies` shell recipe. It exhaustively
lists open issues with explicit JSON fields and pagination, filters blocked non-epics
client-side, parses body lines, resolves blockers, and either plans or applies transitions.
It must not silently truncate the repository at the CLI default page. Its mode is explicit:

- apply mode is owned primarily by `merge-cleanup` after the merged issue is verified
  closed; it evaluates all blocked dependents, which supports multiple dependents and avoids
  relying on GitHub search syntax;
- plan mode is used by `recover-orphans`, which adds proposed cleared-dependency repairs to
  its reconciliation table and applies them only after its existing single confirmation.

The recovery path reads and reports with the same recipe before confirmation, then invokes
the recipe for each confirmed eligible issue. It does not restore the old blanket rule that
all blocked issues are human-owned: only blocked issues without a fully cleared canonical
dependency set remain held.

`triage-issues` retains its explicit/manual fallback. It may reassess a cleared dependency,
but is no longer described as the required release mechanism.

## Error handling

Evaluation is per dependent: one unreadable or malformed issue does not prevent other
dependents from being evaluated. All uncertainty fails closed. Reports distinguish
`open blocker`, `missing blocker`, `unreadable blocker`, `malformed reference`, `no canonical
references`, and `label update failed`. Reads use explicit JSON fields and no status-label
server-side filter.

## Tests

A shell regression test builds a fake `gh` executable and exercises the documented recipe
as executable shell. It proves:

- one and multiple closed blockers transition one and multiple dependents;
- open, missing, unreadable, and malformed references retain `status:blocked` and report why;
- prose, comments, whitespace variants, epics, and issues without canonical references do
  not transition;
- the update is one label edit containing removal of every prior `status:` label plus the
  addition of `status:ready`;
- a dependent beyond one result page is evaluated, and a changed pre-write snapshot cancels
  the edit while a conflicting post-write status is reported;
- plan mode emits the same eligible set without writing, and confirmed apply performs the
  repair.

`just verify` remains the aggregate local gate and CI continues to run it through `just ci`.

## Durable execution facts

- Branch: `feat/ready-cleared-dependencies-32`
- Base branch: `main`
- Guardrail: `just verify`
- ADR/index: no ADR; no index
