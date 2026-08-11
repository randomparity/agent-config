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

## Task 2 — the workflow wiring

**File:** `.github/workflows/verify.yml`, `verify` job only.

Add, before the existing `Check matrix result` step: a `Checkout` step reusing the same
SHA-pinned `actions/checkout` reference and `persist-credentials: false` as the `suite` job
(no `fetch-depth`, nothing here reads history), then a step named `Prove the hook bodies are
POSIX` running `./scripts/claude-settings-hooks-test.sh` with
`env: POSIX_ASSERTIONS_REQUIRED: '1'`.

A comment says why the proof lives in this job rather than a matrix leg, and points at ADR
0053. Do not touch the `suite` job or the matrix.

This lands **before** task 3, because task 3's suite asserts this wiring exists and would
otherwise be knowingly red at its own task boundary.

**Acceptance:** `just actions-check` clean (`actionlint`, `zizmor --offline`).

## Task 3 — the guard suite

**File:** new `scripts/claude-settings-posix-guard-test.sh`, discovered automatically by
`just test` (`git ls-files '*-test.sh'`), `just lint` and `just format-check`
(`scripts/list-shell-sources.sh`). No recipe edit — but discovery is from the **index**, so
`chmod +x` it and `git add` it before running any guardrail. Until then `just test` passes
without ever running it, which is a locally green inert guard of exactly the kind this
change exists to remove. Confirm positively that `just test` prints
`== scripts/claude-settings-posix-guard-test.sh`.

Three assertions, all runnable on every host:

1. **The guard bites.** With a `sh` that is really bash first on `PATH` (a symlink in a
   `mktemp -d` directory — the hooks suite resolves `sh` through `PATH`, so this reproduces
   an image whose `/bin/sh` is bash), `POSIX_ASSERTIONS_REQUIRED=1` makes the hooks suite
   exit non-zero and its output contains the literal `POSIX_ASSERTIONS_REQUIRED`. Match that
   token, not the surrounding sentence: asserting on prose the same change is rewriting makes
   a green build depend on the wording of a `printf`, which ADR 0053 rejects by name.
2. **The skip is not weakened.** Under the same shim, invoked as
   `POSIX_ASSERTIONS_REQUIRED= ./scripts/claude-settings-hooks-test.sh` — explicitly empty
   rather than merely unexported, so an operator running `POSIX_ASSERTIONS_REQUIRED=1 just
   test` does not invert the assertion — the hooks suite exits 0 and prints the verdict
   `POSIX assertions SKIPPED`. That verdict string is contract; the notice around it is not.
3. **The wiring is present, at step granularity.** Extract the proof step's block from
   `.github/workflows/verify.yml` — the lines from its `- name:` to the next step at the same
   indent — and assert *within that block* that it runs
   `scripts/claude-settings-hooks-test.sh`, that its `env:` sets `POSIX_ASSERTIONS_REQUIRED`
   to `1`, and that it carries no `continue-on-error`. Ignore commented lines. A bare grep
   over the whole file is not sufficient: it cannot tell the proof step's `env:` from the
   same key on another step or in a comment, cannot see the `run:` deleted while the `env:`
   stayed, and cannot see the step neutralised with `continue-on-error: true` — which ADR
   0053's own Consequences bullet anticipates someone reaching for on the day this gate reds
   the repository. There is no YAML parser in the toolchain (`install-tools.sh` installs jq,
   shellcheck, shfmt, actionlint and zizmor, no `yq`), so this is a line-oriented extraction;
   keep it to `awk`/`sed` within the bash 3.2 floor and fail loudly when the step cannot be
   located rather than passing on an empty block.

Clean up the shim directory on exit through a trap, guarding the path before removal the way
the hooks suite guards its own scratch.

**Acceptance:** `just test` runs the new suite by name and it passes; deleting the `env:`
line from `verify.yml`, adding `continue-on-error: true` to the proof step, or removing the
requirement branch from task 1 each turn it red.

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

Files touched: `scripts/claude-settings-hooks-test.sh`,
`scripts/claude-settings-posix-guard-test.sh`, `.github/workflows/verify.yml`, plus
`docs/adr/0053-*.md`, the spec and this plan.

Pre-merge, abandoning the branch is enough. Post-merge, revert **only the three code files**:
reverting the whole branch deletes ADR 0053, and `.github/scripts/check-records.sh` raises
`E-GONE` for a record that stops being a record at its path, so the reverting pull request
would fail `just records`. A merged record is resolved in place — a banner, or a new record
superseding it — never by deletion. Reverting those three files restores #112's behaviour
exactly; nothing else reads `POSIX_ASSERTIONS_REQUIRED`, and no state outside the repository
is written.
