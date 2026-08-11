# 0053 — The required check proves shell portability, not a matrix leg

## Status

Accepted (2026-08-10)

## Context

The shipped Claude `PreToolUse` hook bodies must stay inside POSIX shell, because the shell
Claude Code runs a hook body in is not this repository's to choose.
`scripts/claude-settings-hooks-test.sh` proves that by re-running bodies under `sh` and
comparing exit statuses. It covers two of the five bodies
`agents/claude/shared/settings.base.json` ships — the `git clean` guard and the masked-exit
guard — which is the extent of the guarantee below; widening it is issue #157.

Since #112 the suite resolves `sh` by what it accepts rather than by where `/bin/sh`
points, and where `sh` turns out to be an extended shell it prints a skip notice instead of
a green line it has not earned. The operator rejected raising the toolchain floor —
declaring `dash` a prerequisite — so on macOS and on the Fedora developer hosts the skip is
the intended outcome.

That leaves the property proven in exactly one environment: the `ubuntu-latest` leg of
`.github/workflows/verify.yml`, whose `/bin/sh` is dash. Issue #136 enumerates the three
ways that stops being true; in each of them every leg skips, every leg exits 0, and the
aggregating `verify` job — which asserts only `needs.suite.result == success` — keeps
reporting that every leg passed. The suite's own comment named the ubuntu leg as the
proving ground: a claim in a comment with no enforcement behind it.

## Decision

**The proving ground is the `verify` job, not a matrix leg, and it runs the suite in a mode
where the skip is refused.**

Two halves, which must land in the same change or the guard ships inert:

1. `scripts/claude-settings-hooks-test.sh` refuses the skip when `POSIX_ASSERTIONS_REQUIRED`
   is set and `sh` accepts bashisms. Unset or empty leaves #112's skip as shipped: same
   condition, same notice, same `posix_verdict`, same exit status.
2. The `verify` job checks the repository out and runs that suite with
   `POSIX_ASSERTIONS_REQUIRED=1`.

The variable takes `1` or nothing. Any other non-empty value is a hard error naming the
variable, so a wiring that says `true` reds instead of being silently ignored, and `0` reds
instead of meaning its opposite. Both are the same failure — a guard that reads as wired
and is not — and neither is worth a convention a reader has to remember.

`verify` is the home because it is the one job in this workflow the matrix cannot reach: it
already exists to keep a stable required-check context and already runs unconditionally on
`ubuntu-latest`. The matrix legs are left alone — the ubuntu leg still proves the property
as a by-product and macOS still skips.

What this delivers is bounded, and the bound is the point. It removes the two silent routes
— the leg dropped from the matrix, the leg moved into a container — because neither can
reach the `verify` job, and it turns the third, image drift, into a red build. It does not
defend against deleting the step or its `env:` line, which returns the suite to the skip
branch and a green log; nothing here detects that, and `verify.runs-on` is now load-bearing
in the way `matrix.os` was, fail-closed but equally single-line.

Two sentences in the suite's POSIX region name the ubuntu leg as the sole proving ground
and point at #136 as open work. Both stop being true here, so both are corrected in the
same change. What the notice says changes; what it does does not.

`scripts/claude-settings-posix-guard-test.sh` exercises the refusal on every host and every
CI leg, since the guard's failure path is otherwise never taken anywhere.

## Consequences

- The required check now fails for a reason that has nothing to do with the matrix, so
  `verify: suite matrix reported ...` is no longer the only way the job can go red.
- **The designed failure blocks the whole repository, and its remedy is a decision nobody
  has taken yet.** When `ubuntu-latest` stops shipping dash as `/bin/sh` — an upstream
  change arriving without warning — `verify` reds on every open pull request, including
  ones touching nothing here. The intended response is to install a POSIX shell in that one
  step and point `sh` at it: the CI-only toolchain floor rejected below, rejected as today's
  mechanism rather than forever. It costs nothing to skip while the image supplies dash, and
  if the image stops, the choice is forced and is the operator's. Relaxing or deleting the
  gate under a red required check is the outcome this bullet exists to prevent.
- **The required check asserts something `just ci` cannot reproduce.** The gate is a bare
  script invocation with an inline environment variable, outside the guardrail recipe ADR
  0039 makes the proof boundary. That is deliberate and unavoidable: folding it into
  `just ci` would red on every developer host, which is exactly what #112 settled against.
  The divergence predates this record — the ubuntu leg already proved something no local run
  did — and this moves it rather than creating it. A `just` recipe would not close it either,
  since such a recipe fails by design everywhere but a POSIX-`sh` host, which is worse than
  having no recipe.
- The guarantee is two of five hook bodies, and behavioural rather than structural: a
  non-POSIX construct on a branch the chosen inputs do not reach is not detected. Issue
  #157 owns widening it.
- The hooks suite runs twice per CI run on Linux, once in the ubuntu leg and once in
  `verify`. It takes seconds and needs no toolchain install, so the duplication is cheaper
  than any mechanism for reporting one job's internal verdict to another.
- `verify` gains a checkout and therefore executes contributor code on a fork pull request,
  where before it only compared a string. The `suite` job already does strictly more of this
  under the same `contents: read` permission and the same SHA-pinned checkout with
  `persist-credentials: false`, so the exposure is not new in kind.
- The step depends on the runner image providing `jq`. Its absence fails loudly on the first
  call rather than skipping, so the dependency cannot rot into a silent pass.

## Considered & rejected

- **Set `POSIX_ASSERTIONS_REQUIRED=1` on the ubuntu matrix leg** — issue #136's option 1,
  and one line shorter. Rejected because the requirement then lives inside the thing that
  can be removed: deleting `ubuntu-latest` from the matrix deletes the guard with it, which
  is the first route the issue names and leaves the defect half-fixed. This is also why
  dropping that leg can no longer turn CI red — the decision answers the requirement behind
  that acceptance sentence, that the loss must not be silent, by removing the route rather
  than detecting it.
- **Install dash as a CI prerequisite** — issue #136's option 2. Rejected as the mechanism:
  the operator rejected raising the toolchain floor at #112, and an installed package is
  what a future image change quietly undoes. Kept as the remedy if the image drifts.
- **Check the extracted bodies statically with `shellcheck -s sh` instead.** Simpler,
  broader and unskippable, but it proves the bodies contain no non-POSIX construct rather
  than that they still exit 0 and 2 for the right inputs under a real POSIX shell. The right
  addition, not the right substitution: issue #157.
- **Require the assertions only on push to `main` or on a schedule**, leaving pull requests
  to the matrix leg. It bounds the blast radius above — an upstream image change would stop
  merges rather than blocking every open pull request — and it still fails loudly. Rejected
  because it detects drift after merge, and because a pull request adding a bashism to a hook
  body would then be caught only by the matrix leg, which is the thing that can go away.
- **Report a leg's verdict to the aggregating job**, by artifact or job output, and fail
  when no leg proved. The only shape that literally turns "matrix leg dropped" red. Rejected
  as more machinery than the guarantee costs: matrix job outputs are last-writer-wins and
  cannot distinguish "a leg proved it" from "the last leg to finish did not", and the
  artifact version buys with an upload per leg and a download-and-count what running the
  suite in `verify` provides outright.
- **Parse the suite's log line from the aggregating job.** Rejected: it makes a green build
  depend on the exact wording of a `printf`, which a later change is entitled to improve.
- **Assert in `verify` only that this runner's `sh` rejects bashisms**, without running the
  suite. Cheaper, and it catches image drift. Rejected because it proves an environment
  exists rather than that the hook bodies pass in it, so a body that acquired a bashism would
  still ship green wherever the matrix no longer covered it.
- **Do nothing.** Rejected: nothing regressed at #112, but a single-legged guarantee whose
  loss is silent is one nobody is told they have lost. The narrowness conceded above is an
  argument for #157, not for leaving the remaining guarantee undefended.
