# A proving ground that cannot be dropped by accident

Design for [issue #136](https://github.com/randomparity/agent-config/issues/136).
Decision record: [ADR 0053](../../adr/0053-the-required-check-proves-shell-portability.md).

## Problem

`scripts/claude-settings-hooks-test.sh` proves that shipped Claude `PreToolUse` hook bodies
stay inside POSIX shell by re-running them under `sh`. It covers two of the five bodies
`settings.base.json` ships, behaviourally — exit status for chosen inputs, not construct
conformance. Widening that is [issue #157](https://github.com/randomparity/agent-config/issues/157),
not this change; what follows takes the guarantee's extent as it stands and stops it from
disappearing. Since #112 the suite resolves `sh` by what it accepts (`sh -c '[[ -n x ]]'`)
and, where `sh` turns out to be an extended shell, prints a skip notice instead of a green
line it has not earned.

The skip is correct and stays. What is missing is a floor under it. The assertions run in
exactly one environment — the `ubuntu-latest` leg of `.github/workflows/verify.yml`, whose
`/bin/sh` is dash — and nothing fails if that stops being true:

- the leg is dropped from the matrix;
- a future `ubuntu-latest` image ships a different `/bin/sh`;
- the leg moves to a container or self-hosted runner whose `sh` is bash.

In each case every leg skips, every leg exits 0, and the aggregating `verify` job — which
asserts only `needs.suite.result == success` — reports `verify: every suite leg passed`.
The property stops being tested and no signal fires.

## Approach

Stop making the proof a property of a matrix leg. The `verify` job already exists to be
the one stable required-check context and already runs on `ubuntu-latest` independently of
the matrix; it proves the property itself, in a mode where the skip is refused.

Two halves, landing together:

1. **A refusable skip in the suite.** When `POSIX_ASSERTIONS_REQUIRED` is set to a
   non-empty value and `sh` accepts bashisms, the suite fails instead of skipping. Unset or
   empty leaves #112's skip as shipped: same condition, same notice, same `posix_verdict`,
   same exit status. Two sentences inside that region — the comment naming the ubuntu leg
   as the sole proving ground, and the notice's "this run did not check" paragraph pointing
   at #136 as open work — stop being true and are corrected in the same change.
2. **The wiring in the `verify` job.** The job checks out the repository and runs the suite
   with `POSIX_ASSERTIONS_REQUIRED=1`. It is not a matrix leg, so no matrix edit can remove
   it, and any environment change that takes the proving ground away turns that step red.

A third piece keeps the guard from shipping inert: a suite beside it,
`scripts/claude-settings-posix-guard-test.sh`, puts a `sh` that is really bash on `PATH`
and asserts that the hooks suite fails under the requirement and still skips cleanly
without it. It runs on every leg and every developer host through `just test`.

## Behaviour

### `POSIX_ASSERTIONS_REQUIRED`

| `sh` accepts `[[ ]]` | variable | result |
|---|---|---|
| no | unset / empty | assertions run; `ok (POSIX assertions ran under <path>)` |
| no | `1` | assertions run; identical output — the requirement is already met |
| yes | unset / empty | skip notice; `ok (POSIX assertions SKIPPED)` — unchanged from #112 |
| yes | `1` | `fail` with exit 1, naming the shell and the variable |
| either | any other non-empty value | `fail` with exit 1, naming the variable and `1` |

The value is validated rather than merely tested for emptiness. Matching only the literal
`1` and ignoring everything else fails open: a workflow that says `true` gets a no-op gate
that reads as wired, which is the inert guard this issue is about. Treating any non-empty
value as yes fails the other way: `POSIX_ASSERTIONS_REQUIRED=0` would require the
assertions. Rejecting the unrecognised value costs one branch and avoids both.

The variable is read once, at the point of decision, and nothing else in the repository
sets it. It is a new contract on a tracked script, so it is documented where it is read.

### The `verify` job

Steps become: checkout, prove, then the existing matrix-result assertion.

The proof runs before the matrix assertion deliberately. Both failures are red, but the
matrix result is legible from the leg's own check entry, while this job is the only place
the POSIX verdict is reported at all — so on a run where both would fail, running the
unique signal first is worth the five seconds of checkout.

The step needs `jq`, `bash`, `sh`, `grep` and `mktemp`, all present on the runner image.
`install-tools.sh` is deliberately not run here: `jq` is the only real dependency and its
absence fails loudly on the first `hook_command` call, so paying a full toolchain install
to convert a loud failure into a slightly earlier loud failure buys nothing.

## What each named route now does

| Change | Before | After |
|---|---|---|
| `ubuntu-latest` dropped from the matrix | silent green, property untested | green, and honest: the `verify` job still proves it |
| `ubuntu-latest` image's `/bin/sh` stops being dash | silent green | **red** — the `verify` job's proof step fails |
| `verify` moved to macOS, or to a container whose `sh` is bash | n/a | **red** — same step |
| the proof step is deleted | n/a | a visible workflow diff, like any removed gate |
| macOS leg skipping | green | green, unchanged |

The first row is the one place this design does not do what the issue's acceptance sentence
literally asks. Dropping the leg no longer removes the proving ground, so there is nothing
left to turn red; the failure mode the issue names — the guarantee silently disappearing —
is closed by removing the route rather than by detecting it. Encoding "the matrix must
contain `ubuntu-latest`" would be a different property (OS coverage, ADR 0027's subject)
guarded in the wrong place.

The fourth row is the bound. Deleting the step or its `env:` line returns the suite to the
skip branch and a green log, and nothing here detects that; `verify.runs-on` is now
load-bearing in the way `matrix.os` was, fail-closed but equally one line. What the design
removes is the churn that takes the proving ground away as a side effect of an unrelated
decision, not deliberate removal.

## Verification

- `just verify` bare, including `actionlint` and `zizmor --offline .github/workflows/`.
- `scripts/claude-settings-posix-guard-test.sh` — the guard's failure path, exercised on
  every host and every CI leg.
- Manual demonstration on a host whose `/bin/sh` is bash:
  `POSIX_ASSERTIONS_REQUIRED=1 ./scripts/claude-settings-hooks-test.sh` must exit 1. This
  is the `verify` job's new step run in exactly the environment the second and third rows
  above describe.
- The macOS CI leg must still print the skip notice and pass.

## Threat model

**Boundaries.** The change adds one: the `verify` job now checks out and executes
repository code, where before it only compared a string. On a `pull_request` event from a
fork that code is the contributor's.

**Actors.** An untrusted fork contributor opening a pull request; nobody else reaches this
job.

**Controls.** The workflow's `permissions: contents: read` is unchanged, the job holds no
secrets, and the checkout pins the same SHA-pinned action the `suite` job uses with
`persist-credentials: false`, so no token is left in the worktree. The exposure is not new
in kind: the `suite` job already checks out and runs the same contributor code through
`install-tools.sh` and `just ci` on both legs, with the same token and the same
permissions. This job executes strictly less of it.

**Out of scope.** Fork pull requests executing repository code at all — that is the
repository's existing CI posture, decided before this change and not altered by it. Runner
compromise and action supply chain are covered by SHA pinning and `zizmor` in
`actions-check`.

## When the guard fires

The designed trigger is an upstream change nobody here controls: `ubuntu-latest` ceasing to
ship dash as `/bin/sh`. It reds `verify` — the required check — on every open pull request,
not only ones touching shell. The intended response is to install a POSIX shell in that one
step and point `sh` at it, which is the CI-only toolchain floor rejected today and the
operator's call on the day it is needed. Relaxing or deleting the gate under a red required
check is what stating this in advance exists to prevent.

## Not doing

- **Installing dash in CI now.** The operator rejected raising the toolchain floor when
  deciding #112; this design keeps the floor where they put it while the image supplies
  dash for free.
- **Weakening the skip.** Same condition, same notice, same verdict line, same exit status
  on the unrequired path; two factually stale sentences inside it are corrected.
- **Replacing the executable proof with `shellcheck -s sh` over the extracted bodies.**
  Simpler and broader, and it can never skip — but it proves constructs rather than exit
  statuses, so it is issue #157's addition, not this change's substitution. See the ADR.
- **Cross-job reporting of which leg proved what.** See the ADR.
