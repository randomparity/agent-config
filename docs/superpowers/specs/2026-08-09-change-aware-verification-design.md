# Change-Aware Verification Design

## External authority

Issue #93 asks the repository to reduce verification time without inordinately reducing
coverage. The operator clarified that local commits should be cheap, while a branch push should
be thorough and identical to the GitHub CI workflow. The issue also requires global recipes,
shared contracts, hook configuration, and unmapped files to fail closed to full verification;
central repository recipes; selection and timing output; and deterministic regression coverage.

This design excludes wall-clock pass/fail thresholds and any weakening of branch-push or GitHub
CI verification. It permits changes to hook setup and configuration, Justfile recipes, a
repository-owned selector and tests, CI wiring, setup documentation, and ADR 0002's lifecycle
marker. The frozen scope is issue #93 plus `scope-93-20260809-b942f071`; no design-changing
ambiguity remains.

## Approaches

The chosen approach is a small Bash selector behind one pre-commit hook, plus one unconditional
pre-push hook. It preserves Just as the command surface, puts path policy in a unit-testable
component, and makes pre-push and CI parity literal: both execute `just ci`.

Defining many path-filtered prek hooks would use built-in filtering, but it would distribute
ordering, timing, and fallback behavior across configuration entries. Keeping full verification
on commits while adding caching or parallelism would preserve coverage, but unrelated suites
would still run and cache validity would become a second correctness contract. Both alternatives
are rejected in [ADR 0036](../../adr/0036-stage-verification-by-git-event.md).

## Verification contract

There are three event contracts:

| Event | Repository entry point | Required behavior |
|---|---|---|
| Commit | `just commit-check` | Select focused recipes or fail closed to `just ci` |
| Branch push | `just push-check` | Validate pushed branch refs, then invoke `just ci` once |
| GitHub CI leg | `just ci` | Use the identical thorough path as branch push |

`just verify` remains the complete suite. `just ci` is a timed wrapper around one invocation of
`just verify`, not a second aggregate and not a prek-hook runner. It prints that thorough
verification was selected and the elapsed whole-suite time. GitHub's two operating-system legs
therefore retain the existing portability coverage without recursively invoking the full suite.

The prek configuration has separate stage-scoped hooks. Pre-commit uses `always_run`, passes no
filenames, and invokes `just commit-check` once; pre-push also passes no filenames and invokes
`just push-check`, the repository ref-validation wrapper. Only `push-check` invokes fixed
`just ci`, after validation. The repository `hooks` recipe installs both shims explicitly, and
`install-tools.sh` delegates hook setup to that recipe after confirming Just is available. Full
verification dry-runs both configured stages so malformed configuration or a missing stage fails
without executing either hook.

## Commit selector

`scripts/select-verification.sh` derives the complete staged set in one process with
`git diff --cached --name-only -z --no-renames`. Disabling rename detection makes a rename appear
as its old deleted path and new added path, so either endpoint can trigger full fallback. NUL
delimiters preserve every valid Git pathname without shell splitting or argument-size batching.
The selector captures that stream in a temporary file, checks Git's exit status, and only then
reads it. Enumeration failure removes the temporary file and stops with an actionable diagnostic;
only a successful zero-record result is an empty-change no-op. The selector classifies each path
with quoted `case` patterns, accumulates fixed Just recipe names, deduplicates them in stable order,
then invokes and times each recipe. It never evaluates a path or constructs a recipe name from
path text. Selection output names recipes, not contributor-controlled paths.

The first policy version deliberately maps only these exact surfaces:

| Staged path pattern | Complete focused recipe set | Evidence |
|---|---|---|
| `docs/superpowers/specs/*.md` | `public-safety references-check` | Both scripts scan tracked prose; no other `verify` recipe consumes spec files |
| `docs/superpowers/plans/*.md` | `public-safety references-check` | Both scripts scan tracked prose; no other `verify` recipe consumes plan files |
| `docs/adr/*.md` | `records public-safety references-check` | `records` owns ADRs; both repository-wide prose checks also observe them |
| `docs/debt/*.md` | `records public-safety references-check` | `records` owns debt; both repository-wide prose checks also observe it |
| `scripts/check-public-safety.sh` | `lint format-check test-public-safety suites-check public-safety` | Shell recipes and suite reachability observe the source; its fixture and live gate prove behavior |
| `scripts/check-public-safety-test.sh` | `lint format-check test-public-safety suites-check` | Shell recipes, the focused fixture, and suite reachability observe the test |

A focused mapping is valid only when its policy row accounts for every complete-suite recipe that
can observe or be affected by the path. An independent policy-coverage fixture records the
normalized `just --dry-run` command inventory for every `verify` dependency and fails when a
dependency is added or its command surface changes until the observer inventory is reviewed and
updated. Selector tests separately assert every row's entire selected recipe set. If the observer
set cannot be established from recipe inputs and guardrail contracts, the path remains unmapped
and selects `just ci`.

`Justfile` exposes focused recipes for existing individual suites so the selector never embeds
raw test commands. Shared command strings are held once and expanded by both the focused recipe
and the complete `test` recipe, preserving the existing suite-reachability gate's dry-run view.

The following select `just ci` immediately: `Justfile`, `.pre-commit-config.yaml`, workflow and
tool-installation files, the selector or its policy test, shared instruction contracts, record or
suite-coverage gate machinery, a mixture containing both focused and full-risk paths, and every
unmapped path. The fallback is intentionally broader than the initial focused map. New surfaces
become cheap only with a regression case proving their owning checks.

Zero paths is a successful no-op because no staged content exists to verify. Deleted paths remain
in the staged set, and both endpoints of a rename are classified. Duplicate paths and overlapping
categories run each recipe once. A focused recipe failure stops the hook immediately and
preserves its exit status. Elapsed seconds are printed after each successful recipe; timing is
never asserted numerically by tests.

## Failure handling

- An unavailable required tool fails through the selected recipe with its existing actionable
  diagnostic.
- An unknown, global, or shared path reports the full-verification reason and runs `just ci`.
- A staged-path enumeration failure reports that Git could not read the index and exits nonzero;
  it never falls through to the successful empty-change path.
- If one focused check fails, later checks do not run; the failing command's output remains intact.
- Invalid prek configuration fails `just verify` during stage dry-runs without recursively running
  either hook.
- For remote branch updates, a non-delete pushed object that is not the checked-out `HEAD`,
  multiple pushed trees, or any dirty working-tree state fails before verification with an
  actionable diagnostic. Non-branch ref updates do not trigger or block verification.
- A pre-push failure blocks the push. A contributor who bypasses it receives the same failure from
  GitHub CI.

## Threat model

The added boundary is contributor-controlled staged pathname data entering a local pre-commit
process. The actors are repository contributors who can propose unusual filenames and the local
operator or CI job executing repository commands. Git emits one NUL-delimited, no-rename staged
set; each path remains quoted after reading; matching is through literal shell patterns; selected
recipe names come from a fixed allowlist; no `eval`, word re-parsing, pathname execution, or
path-derived command construction is allowed. Logs report only fixed recipe names, preventing
terminal-control text in a filename from entering output.

The pre-push boundary receives Git ref updates from Git. A repository-owned wrapper parses the
fixed four-field lines and selects only remote `refs/heads/*` updates. Branch deletions are ignored;
each remaining branch local object must equal the checked-out `HEAD`. When at least one branch is
updated, the wrapper requires a clean working tree before running fixed `just ci`. Malformed input,
a non-HEAD branch object, multiple branch trees, or dirty state fails with an actionable diagnostic
instead of testing different content. Non-branch remote refs pass through without invoking `ci`.
Hook installation crosses the existing local-tool boundary governed by ADR 0036: setup invokes
the repository recipe only after tool checks succeed. No credentials, network destinations,
privileges, authorization, or tenant data are added.

Out of scope are a compromised Git, Just, prek, or shell binary; deliberate use of Git's hook
bypass flags; and denial of service from the already-authorized complete repository suite. GitHub
CI remains the independent full-verification backstop for hook bypass.

## Regression proof

The selector test uses a fake `just` executable and a disposable Git repository. It proves
ordinary prose, record files, representative known shell families, projection content, duplicate
categories, and multi-file focused changes select the intended recipes once and in stable order.
It proves global recipes, shared contracts, hook configuration, selector policy, workflows,
unknown paths, deletions, either endpoint of a rename, a large staged set, and mixed
focused/global changes invoke `ci` exactly once. A crafted filename containing spaces, shell
metacharacters, and terminal-control text must neither execute nor appear in output.

The push-wrapper fixture supplies Git-shaped ref lines and fake repository state. It proves a
clean checked-out branch `HEAD` runs `ci` once; branch deletions and non-branch refs do not invoke
or block it; and malformed, dirty, non-HEAD, or multiple-tree branch pushes fail before `ci` with
the relevant diagnostic.

The test also proves an empty staged set is a no-op, an enumerator failure is nonzero, a focused
failure is propagated, and later recipes stop. Configuration checks prove pre-commit always runs
`commit-check` without filenames, pre-push runs `push-check` without filenames, and hook setup
installs both stages. A disposable repository installs the configured pre-push shim and invokes it
with Git-shaped standard input, proving the real hook reaches the wrapper and `ci` exactly once.
A fake-command integration case separately proves `just ci` invokes `just verify` once and never
invokes a prek hook. Output assertions require selection and elapsed-time labels but do not compare
duration values.

Implementation follows TDD: first add red selector/configuration/CI-count cases, then implement
the selector, recipes, stage configuration, setup wiring, and documentation. Focused tests and
linters run at each commit; `just verify` proves the completed branch before review and shipping.

## Execution context

- Branch: `feat/change-aware-verification-93`
- Base branch: `main`
- Required complete guardrail: `just verify`
- CI entry point: `just ci`
- ADR/index coupling: not coupled; the directory listing is the ADR index.
