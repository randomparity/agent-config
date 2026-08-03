# 0011 — Two tracker values still reach GitHub unvalidated

## Status

Open
review-by: 2026-11-01

## Concern

The branch review of #51 found that the change closes the profile name and every
issue selector, but two values in the same file still cross into GitHub without a
grammar.

1. **`--target` is spliced raw into every REST path the profile builds.**
   `github_require_target` checks only that it is non-empty, and the value then
   appears in `repos/$TRACKER_TARGET/issues/$id/timeline` and
   `repos/$TRACKER_TARGET/issues/$parent/sub_issues`. A value carrying `..` or a
   query string reshapes the request path, which is the same primitive the issue
   selectors were guarded against. It also lands unquoted in the search query
   string as `repo:$TRACKER_TARGET`, where the existing double-quote rejection
   covers the predicate values but not the target itself.

2. **`search --parent` is an issue selector with no grammar.** It carries only
   the double-quote rejection every search predicate carries, and it is
   interpolated into `parent-issue:"$parent"`. It was deliberately left off the
   guard because GitHub's `parent-issue:` search qualifier accepts forms this
   contract does not define — an issue reference or URL rather than a bare
   number — and narrowing it to `^[0-9]+$` without confirming that would break a
   documented predicate. `search` is therefore on the contract suite's
   guard-coverage exemption list, which is where a reader will find this open.

## Why deferred

`--target` is excluded by #51's frozen scope: the issue enumerates three input
classes and names neither of these, and the follow-on issue that moves these
files is expected to touch the same lines. Widening the change to cover it would
have taken the branch outside the surface the scope annotation froze.

Neither is reachable the way the selectors were. `--target` is supplied by the
calling skill at the call site, not composed from issue references read out of
bodies and comments that any account can write — the untrusted path that
motivated the selector guards. `search --parent` reaches a search query rather
than a path segment, and the query is already scoped by `repo:` and rejects
double quotes, so the worst case is a malformed query returning nothing rather
than a request against another object.

Settling `search --parent` needs one fact this run could not establish offline:
which forms GitHub's `parent-issue:` qualifier accepts. Guessing it produces
either a guard that breaks a working predicate or a grammar wide enough to be
decorative.

## Non-regression boundary

The guards this change added must not be relaxed to accommodate either residual.
Specifically: `github_require_id` stays `^[0-9]+$`; every operation outside the
suite's exemption list keeps calling it; the exemption list does not grow without
a record saying why; and `--profile` stays pinned to `^[a-z0-9-]+$`. Adding a new
operation that interpolates `--target` or a selector into a path without a guard
re-opens this at higher severity.

## What would resolve it

For `--target`: a grammar check in `github_require_target` — GitHub's own
owner/name rules, `^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$`, is the obvious candidate —
plus a contract case per REST-path operation asserting a traversing target is a
usage error. Done when a target carrying `..`, a slash-separated third segment,
or a query character cannot reach a REST path.

For `search --parent`: confirm the accepted forms of GitHub's `parent-issue:`
qualifier against its documentation, then either guard it with the grammar that
matches those forms and remove `search` from the exemption list, or record in
ADR 0023 that the predicate is deliberately wider and why. Done when the
exemption list carries no unexplained entry.

## Provenance

target: content/skills/github-tracking/assets/profiles/github.sh
Adversarial branch review of #51 (`$review-loop`, 1 pass), 2026-08-03. Deferred
as finding 1's residual after the same finding's in-scope part — `create`'s
unguarded `--parent` — was fixed on the branch.
tracker: #51
