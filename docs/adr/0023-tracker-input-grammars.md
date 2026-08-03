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

Every value crossing from an argument vector into a path, a `gh` argument, or a
REST path segment is validated against a fixed grammar at the boundary it
crosses, before it is used.

`--profile` is checked against `^[a-z0-9-]+$` in the argument-parsing arm that
reads it, which is the same set `resolve_tracker` admits. A name outside that
set is a usage error, so both resolution routes admit the same values and
neither can name a path outside the profiles directory. The check lives in the
parsing arm rather than after the loop so that `--profile ''` is rejected as the
usage error it is, instead of silently falling through to the declaration.

Issue selectors are numbers: `^[0-9]+$`, enforced by one shared
`github_require_id` guard that every operation calls on every positional naming
an issue. One guard rather than a check per call site, so an operation added
later fails the contract suite's per-operation case rather than shipping without
one.

Narrowing below what `gh` accepts is deliberate. The contract already normalizes
an issue's identity to its number — `profile_view` emits `id` as a number-string
and `profile_search` emits an array of number-strings — so a number is the only
form a caller composing from this contract's own output can hold. Accepting URLs
would mean accepting an attacker-chosen host and path in a value that is
interpolated into a REST path, to support a form no caller in this repository
produces.

The public-safety scan carries an `ATATT` credential shape alongside the GitHub,
OpenAI, AWS and Slack shapes it already had. Its test assembles the token from
fragments at run time, as the neighbouring tenant-hostname case does, so the
test file is not itself a match for the scan it exercises.

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
- The contract suite grows one case per guarded positional plus a traversal
  case, so a new operation that forgets the guard, or a regression that removes
  the profile-name check, fails `just verify` rather than production.
- The scan's Atlassian shape is a prefix-and-length heuristic, like the four
  credential shapes beside it. It will not catch a token format Atlassian
  introduces later.

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
