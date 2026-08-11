# Implementation plan — POSIX proof gate (#136)

Spec: `docs/superpowers/specs/2026-08-10-posix-proof-gate-design.md`.
Decision: `docs/adr/0053-the-required-check-proves-shell-portability.md`.

Branch `feat/posix-proof-gate-136` off `main`, in a worktree outside the repository tree.
Guardrails: `just verify` bare; record gate separately as
`BASE_SHA=$(git merge-base HEAD origin/main) just records`.
Shell floor: bash 3.2 — no `mapfile`, no associative arrays, no `inherit_errexit`.
Indentation: tabs (`scripts/` is in `list-shell-sources.sh --tabs`).

## Task 1 — the refusable skip

**Files:** `scripts/claude-settings-hooks-test.sh`, POSIX-assertion region only (the
`POSIX_SHELL` / `SH_ACCEPTS_BASHISMS` resolution near line 110, and the skip branch near
line 327). Issue #113 concurrently owns the header limits block at lines 13-23 — do not
touch it.

Beside the existing `sh` resolution, and therefore **before** the skip predicate is
consulted, resolve the requirement:

- `POSIX_ASSERTIONS_REQUIRED` unset or empty → not required;
- `1` → required;
- anything else → `fail`, naming the variable and the only accepted value.

Then in the skip branch, when required, `fail` instead of printing the skip. The message
names the variable, the resolved shell, and the two ways out: give the environment a POSIX
`sh`, or fix the hook bodies. The unrequired path keeps the same condition, notice, verdict
line and exit status as #112 shipped.

In the same region, correct the two sentences that stop being true: the comment naming the
ubuntu leg as the sole proving ground, and the notice paragraph pointing at #136 as open
work. Name the `verify` job instead.

**Acceptance:** `POSIX_ASSERTIONS_REQUIRED=1 ./scripts/claude-settings-hooks-test.sh` exits
1 on this host (Fedora, `/bin/sh` is bash 5) with a message naming the variable and the
shell; unset, the same command exits 0 and prints the skip; `POSIX_ASSERTIONS_REQUIRED=true`
exits 1 whatever `sh` is.

## Task 2 — the guard suite

**File:** new `scripts/claude-settings-posix-guard-test.sh`, discovered automatically by
`just test` (`git ls-files '*-test.sh'`), `just lint` and `just format-check`
(`scripts/list-shell-sources.sh`). No recipe edit.

Three assertions, all runnable on every host:

1. With a `sh` that is really bash first on `PATH` (a symlink in a `mktemp -d` directory —
   the suite resolves `sh` through `PATH`, so this reproduces an image whose `/bin/sh` is
   bash), `POSIX_ASSERTIONS_REQUIRED=1` makes the hooks suite exit non-zero, and the output
   names the variable. Asserting the message keeps an unrelated failure from passing as the
   guard firing.
2. Under the same shim with the variable unset, the hooks suite exits 0 and prints its skip
   notice — #112's behaviour is not weakened.
3. `.github/workflows/verify.yml` sets `POSIX_ASSERTIONS_REQUIRED` to `1`. This is the only
   check that catches a mistyped key, since on a dash runner an unset variable and a correct
   one produce identical output.

Clean up the shim directory on exit through a trap, guarding the path before removal the way
the hooks suite guards its own scratch.

**Acceptance:** the suite passes on this host; deleting the `env:` line from `verify.yml`
turns it red; removing the requirement branch from task 1 turns it red.

## Task 3 — the workflow wiring

**File:** `.github/workflows/verify.yml`, `verify` job only.

Add, before the existing `Check matrix result` step: a `Checkout` step reusing the same
SHA-pinned `actions/checkout` reference and `persist-credentials: false` as the `suite` job
(no `fetch-depth`, nothing here reads history), then a step running
`./scripts/claude-settings-hooks-test.sh` with `env: POSIX_ASSERTIONS_REQUIRED: '1'`.

A comment says why the proof lives in this job rather than a matrix leg, and points at ADR
0053. Do not touch the `suite` job or the matrix.

**Acceptance:** `actionlint` and `zizmor --offline .github/workflows/` clean via
`just actions-check`; the guard suite's third assertion passes.

## Task 4 — verify and demonstrate

- `just verify` bare, and `BASE_SHA=$(git merge-base HEAD origin/main) just records` bare.
- Demonstrate the red: `POSIX_ASSERTIONS_REQUIRED=1 ./scripts/claude-settings-hooks-test.sh`
  on this host is the workflow's new step run in exactly the environment that an
  `ubuntu-latest` image without dash would produce. Capture the exit status and message.
- Confirm the macOS leg still skips: with `sh` accepting bashisms and the variable unset,
  exit 0 and the skip notice.
- On CI, `suite (ubuntu-latest)` reports the assertions as having run, `suite (macos-latest)`
  reports the skip, and `verify` passes its proof step.

## Rollback

Every change is additive and confined to three files plus the two design documents. Reverting
the branch restores #112's behaviour exactly; nothing else reads
`POSIX_ASSERTIONS_REQUIRED`, and no state outside the repository is written.
