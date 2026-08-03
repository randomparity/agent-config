# 0023 — Tracker Inputs Are Validated Against Fixed Grammars

## Status

Accepted (2026-08-03)

## Context

`tracker.sh` (ADR 0021) resolves a profile name, concatenates it into
`profiles/<name>.sh`, and sources it. Two routes supply that name: the
`issue-tracker:` declaration in the repo's `AGENTS.md`, whose grammar
`resolve_tracker` pins to `[a-z0-9-]+`, and the `--profile` flag, which took the
value verbatim from argv and tested only that the resulting path was a regular
file. A relative path with the right depth therefore sourced and ran an
arbitrary file inside the engine's process, with the engine's environment and
whatever credentials `gh` would use. Two routes to one value admitted two
different value sets; only one of them was constrained.

The GitHub profile has the same shape of gap on its issue selectors. Every
operation takes the selector as a positional and hands it straight to `gh`, and
`label-history` and `link-parent` interpolate it into a REST path segment —
`repos/$TRACKER_TARGET/issues/$id/timeline`. Callers compose those selectors
from issue references read out of GitHub bodies and comments, which any account
can write on a public repo. The profile already demonstrates the alternative:
`label-history` restricts its label argument to the character set GitHub labels
use because the value is spliced into a jq program, and `link-blocks` requires a
numeric blocker because the value is spliced into a regular expression.

`gh issue view` accepts both an issue number and a full issue URL, so a numeric
grammar is narrower than what the underlying tool would take.

## Decision

Two value classes crossing from an argument vector into a path or a REST path
segment are validated against a fixed grammar at the boundary they cross, before
they are used: the profile name, and every issue selector. The classes are named
rather than stated as a universal rule, because this record's own scope does not
close every value the profile passes to `gh` — see the residuals below.

`--profile` is checked against `^[a-z0-9-]+$` in the argument-parsing arm that
reads it, which is the same set `resolve_tracker` admits. A name outside that
set is a usage error, so both resolution routes admit the same values and
neither can name a path outside the profiles directory. The check lives in the
parsing arm rather than after the loop so that `--profile ''` is rejected as the
usage error it is, instead of silently falling through to the declaration.

Issue selectors are numbers: `^[0-9]+$`, enforced by one shared
`github_require_id` guard. Every operation calls it on every value naming an
issue — the positionals, and `create`'s `--parent`, which is the same value class
carried by a flag. One guard rather than a check per call site, so the contract
suite can assert its use mechanically: the suite reads the profile's own
declarations, and every declared operation outside a named exemption list must
call the guard. An operation added later that takes a selector and forgets it
fails the suite, which a list of today's operations would not catch.

Narrowing below what `gh` accepts is deliberate. The contract already normalizes
an issue's identity to its number — `profile_view` emits `id` as a number-string
and `profile_search` emits an array of number-strings — so a number is the only
form a caller composing from this contract's own output can hold. Accepting URLs
would mean accepting an attacker-chosen host and path in a value that is
interpolated into a REST path, to support a form no caller in this repository
produces.

The public-safety scan carries two Atlassian credential shapes alongside the
GitHub, OpenAI, AWS and Slack shapes it already had: the plaintext `ATATT` token,
and the `base64(email:token)` form held in an `ATLASSIAN_`-prefixed variable,
which contains no literal `ATATT` at any alignment and no `Basic` header word, so
neither existing pattern sees it. Both tests assemble their fixture at run time,
as the neighbouring tenant-hostname case does, so the test file is not itself a
match for the scan it exercises, and each has a negative case so prose naming the
token format or the variable stays committable.

Two residuals are named rather than closed, and are recorded in
`docs/debt/0011-tracker-values-still-unvalidated.md`: `--target`, which is
interpolated into every REST path this profile builds, and `search`'s `--parent`
predicate, whose accepted forms are GitHub's `parent-issue:` qualifier rather
than this contract's. `search` is therefore on the guard-coverage exemption list
for a different reason than its two neighbours, and the list says so at that
location rather than leaving the record to carry it alone.

Values that only ever reach `gh` as separate elements of its argument vector — a
title, a colour, a description, a label passed to `label-edit` — stay
unvalidated. They are arbitrary text by contract and escape nothing. Where such a
value *is* spliced into a string it already carries a grammar written for that
splice, and this record does not disturb either: `label-history`'s label is
restricted to the character set GitHub labels use because it is interpolated into
a jq program, and `search`'s predicate values reject a double quote because they
are interpolated into the query. Those two guards are the precedent this record
generalizes, not exceptions to it.

## Consequences

- The arbitrary-source primitive is closed: `--profile` can only ever name a
  file in `profiles/`.
- A caller holding an issue URL must reduce it to a number before calling the
  contract. No caller in this repository does — `create-verified-issue.sh`
  passes `${issue_url##*/}` — but an out-of-tree caller passing a URL now gets a
  usage error instead of a successful call.
- A tracker whose native identifiers are not numeric (Jira's `SCRUM-12`) cannot
  reuse `github_require_id`. It supplies its own grammar in its own profile,
  which is where tracker knowledge belongs under ADR 0021; the shared engine
  keeps no id grammar.
- The contract suite grows one rejection case per guarded selector, a traversal
  case, the derived guard-coverage check, and a case relating the two profile-name
  routes, so a regression that removes the profile-name check, removes a guard
  call, or widens one of the three places the profile-name class is written fails
  `just verify` rather than production.
  The derived check's exemption list is the one hand-kept part: adding an
  operation to it is a deliberate edit a reviewer sees, which is the property a
  list of guarded operations would not have had.
- That check asserts presence, not arity: it requires each declared operation to
  call the guard, and cannot tell one guarded selector from two. An operation
  taking two selectors — `link-parent` and `link-blocks` do today — that guards
  one and forgets the other passes it. Deciding arity means parsing positional
  use out of a function body, which is more machinery than an eleven-operation
  profile justifies, so the limit is named here and the per-selector rejection
  cases cover today's operations.
- The scan's Atlassian shapes are prefix-and-length heuristics, like the four
  credential shapes beside them. They cover the plaintext token, and the base64
  variable form in the syntaxes it reaches a file in — a bare or quoted shell
  assignment, a JSON member, a YAML mapping. A differently-named variable
  holding the same base64, the value on a line of its own, and any sibling
  credential prefix Atlassian issues for scoped or Bitbucket tokens, still pass.

## Considered & rejected

- **Resolve the profile path and assert it stays inside `profiles/`** (realpath
  plus a prefix test). Rejected because it admits names the declaration route
  cannot express — the two routes stay divergent, which is the actual defect —
  and it makes the answer depend on symlinks and on the checkout's location
  rather than on the value.
- **An allowlist built from the profiles present on disk.** Rejected because the
  engine already reports an unknown-but-well-formed name as an actionable error
  naming the available profiles; folding validation into that lookup would give
  a traversal attempt the same message as a typo, and the grammar is what makes
  the two routes agree.
- **Accept the number-or-URL forms `gh` accepts, by validating a URL shape too.**
  Rejected on the reasoning in the Decision: it widens an interpolated value to
  attacker-chosen hosts and paths for a form nothing in this repository emits.
  An out-of-tree caller that needs it supersedes this record rather than working
  around it.
- **Validate inside `github_run` instead, so no operation can forget.**
  Rejected because `github_run` sees a flat argument vector and cannot tell an
  issue selector from a label, a title, or a file path. The guard has to be
  called where the argument's meaning is known.
- **Do nothing about the selectors and fix only `--profile`.** Rejected because
  the two REST interpolations are the same defect class as the source primitive,
  found by the same scan, and a selector that reaches a path segment is exactly
  the case the label and blocker guards already exist to prevent.
