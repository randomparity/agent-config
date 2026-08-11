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
`scripts/claude-settings-posix-guard-test.sh`, which asserts two things on every leg and
every developer host through `just test`.

1. **The guard bites.** With a `sh` that is really bash on `PATH`, the hooks suite must fail
   under the requirement and must still skip cleanly without it.
2. **The wiring is present.** `.github/workflows/verify.yml` must still set
   `POSIX_ASSERTIONS_REQUIRED` to `1`. This is the only defence against the axis the value
   validation cannot reach: a mistyped key, a job-level shadow, or a step refactor that drops
   the line leaves the variable unset, and on a dash runner an unset variable and a correct
   one produce identical output. The difference would surface only on the day the image
   drifts, which is the one day the gate had to work.

The refusal message names the variable, the shell that failed the test, and the two ways
out — give the step a POSIX `sh`, or fix the hook bodies — because the operator who meets it
will be meeting it years from now with no context.

## Behaviour

### `POSIX_ASSERTIONS_REQUIRED`

| `sh` accepts `[[ ]]` | variable | result |
|---|---|---|
| no | unset / empty | assertions run; `ok (POSIX assertions ran under <path>)` |
| no | `1` | assertions run; identical output — the requirement is already met |
| yes | unset / empty | skip notice; `ok (POSIX assertions SKIPPED)` — unchanged from #112 |
| yes | `1` | `fail` with exit 1, naming the shell, the variable and the way out |
| either | any other non-empty value | `fail` with exit 1, naming the variable and `1` |

The value is validated rather than merely tested for emptiness. Matching only the literal
`1` and ignoring everything else fails open: a workflow that says `true` gets a no-op gate
that reads as wired, which is the inert guard this issue is about. Treating any non-empty
value as yes fails the other way: `POSIX_ASSERTIONS_REQUIRED=0` would require the
assertions. Rejecting the unrecognised value costs one branch and avoids both.

**The value is validated before the skip predicate is consulted**, beside the other
environment resolution, not inside the skip branch. Validating it where the skip is decided
would mean a mistyped `POSIX_ASSERTIONS_REQUIRED: 'true'` in the workflow never reds on the
runner it targets — `sh` is dash there, the branch is never taken, and the typo surfaces
only on the day the image drifts, which is the one day the gate had to work. Nothing else
in the repository sets the variable. It is a new contract on a tracked script, so it is
documented where it is read.

`just ci` never sets it, so `just verify`, `just ci` and the `scripts/verify-push.sh`
pre-push rehearsal all keep taking #112's skip on a developer host. That is deliberate —
the alternative reds every local run — and it means the pre-push rehearsal no longer covers
the whole required check. ADR 0053 records that as a bounded amendment to ADR 0039.

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

The fourth row is the bound, and the ADR states it: what the design removes is churn that
takes the proving ground away as a side effect of an unrelated decision, not deliberate
removal of the step.

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

## Not doing

- **Installing dash in the CI job.** #136 marks the CI-only case an open operator call,
  separate from #112's developer-host rejection. It stays open, and the ADR names it as the
  remedy if the image drifts.
- **Weakening the skip.** Same condition, same notice, same verdict line, same exit status
  on the unrequired path; two factually stale sentences inside it are corrected.
- **Replacing the executable proof with `shellcheck -s sh` over the extracted bodies.**
  Issue #157.
- **Cross-job reporting of which leg proved what.** See the ADR.
