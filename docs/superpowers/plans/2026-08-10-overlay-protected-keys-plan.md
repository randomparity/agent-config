# Overlay Protected Keys — Implementation Plan

Issue: [#110](https://github.com/randomparity/agent-config/issues/110) — private settings overlays
replace `hooks.PreToolUse` instead of merging it.

Design: [spec](../specs/2026-08-10-overlay-protected-keys-design.md) ·
[ADR 0043](../../adr/0043-overlays-may-not-replace-a-base-array.md)

Branch `feat/overlay-protected-keys-110` off `main`, in an external worktree beside the repo.
Guardrail: `just verify`, run bare. Commit-stage gate `just commit-check` runs from prek on every
commit.

The spec is the contract; this plan is the order of work. Where they disagree, the spec wins.

## Task 1 — Failing tests first

**Where this fits.** The suite currently proves nothing about base values surviving an overlay, so
the tests are written and observed failing before `install.sh` changes. Assertions 2, 3, 4, 7 and 10
fail against unmodified `install.sh`; 6 and 9 fail against an over-protecting implementation and
pass today.

**Files.** `install-test.sh` only.

**Do.**

1. Add a helper that runs one install in isolation: its own `AGENT_CONFIG_PRIVATE_DIR`, its own
   `CLAUDE_CONFIG_DIR`/`CODEX_CONFIG_DIR`/`BOB_CONFIG_DIR` under `$tmpdir`, capturing status and
   stderr. Per the spec's isolation rule, nothing new may reuse the suite's exported paths or
   disturb the existing assertion at `install-test.sh:278`.
2. Add an `assert_json_equal <file-a> <filter-a> <file-b> <filter-b>` helper for comparing a
   deployed subtree against the in-repo base.
3. Write assertions 1-10 exactly as the spec's Verification section numbers them. Notable shapes:
   - 2 asserts stderr contains **both** the overlay path and `hooks.PreToolUse`, so an unrelated
     non-zero exit cannot satisfy it;
   - 4 asserts stderr contains `hooks` and **not** `PreToolUse` — outermost-only, and proof the
     message is not jq's `Cannot index string with string "PreToolUse"`;
   - 6 and 9 assert **success**, guarding the empty-array exemption and the result-based rule;
   - 8 covers the no-overlay default and catches a shape check misplaced above the `-f` guard;
   - 10 installs benignly, re-runs with the clobbering overlay, and asserts the already-deployed
     file still holds the base's `hooks` and `permissions.deny`.

**Acceptance.** `./install-test.sh` fails, and the failures are 2, 3, 4, 7 and 10 — not a syntax
error and not a helper bug. Record which assertions failed and their messages; that record is the
evidence the tests bite. Commit the failing tests separately from the fix.

**Rollback.** Revert the commit; nothing outside `install-test.sh` moved.

## Task 2 — Implement the merge guard

**Where this fits.** Makes task 1 green. One function, three call sites unchanged — the protection
is derived from each base, so no call site passes a key list.

**Files.** `install.sh`, `merge_json_settings` (~343-356) only.

**Do.**

1. Keep the no-overlay branch exactly as it is (`jq '.'` plus the existing message).
2. **Inside** the `[[ -f "$overlay" ]]` branch — not beside `require_command jq`, which sits above
   it — add the shape check `jq -s -e 'length == 1 and (.[0] | type == "object")'`, failing with a
   message naming the overlay path and distinguishing "not a JSON object" from "more than one JSON
   value".
3. Merge into a temp file from `new_temp_file`, not straight to `$output`, so a rejected merge
   writes nothing to the destination.
4. Compare: for every path in the base whose value is a **non-empty array**, the merged value must
   be identical; for every path whose value is a **non-empty object**, the merged value must be an
   object. The lookup must be **guarded** (`try`/`catch`) — an unguarded `getpath` raises
   `Cannot index string with string ...` when an ancestor is no longer indexable — and must report
   **outermost paths only**, suppressing any path whose proper ancestor already mismatched.
5. On any mismatch: print the operation, the overlay path, each offending base path, and the
   sentence that the currently deployed settings file is unchanged and may already be missing those
   values. Exit non-zero. On success, `cp` the temp file to `$output` and keep the existing
   `applied private overlay` message.

**Acceptance.** `./install-test.sh` passes, including 6 and 9. `just verify` passes bare. The
function stays within the repo's complexity baseline; if the jq program grows past readability,
extract it as a single-purpose helper function rather than inlining a long program.

**Rollback.** Revert; task 1's tests go red again, which is the intended signal.

## Task 3 — Documentation

**Where this fits.** The contract is now enforced, so the published description must match it —
"docs that fail when followed are defects".

**Files.** `README.md` (Private Overlays, ~194-210); `scripts/claude-settings-hooks-test.sh`
**header comment lines 8-11 ONLY** — siblings own the rest of that file (#112 owns
`assert_posix_agrees`, #113 owns the limits block), so this edit stays inside those four lines.

**Do.**

1. README: state the contract over the **merged result**, not the overlay's shape — an overlay may
   add new keys and override scalars and object members; an overlay that *changes* a path the base
   holds as a non-empty array (including by extending it) or replaces a non-empty base object with a
   non-object fails the install and names the path. Do not publish a refusal the installer does not
   perform.
2. `claude-settings-hooks-test.sh` header: replace "Overlays must leave `hooks` alone" with the fact
   that the installer now enforces it, citing ADR 0043.

**Acceptance.** `just verify` passes bare. README's wording matches the contract table; no sentence
describes behavior the code does not have.

**Rollback.** Revert; behavior is unaffected.

## Out of scope

`agents/claude/shared/settings.base.json` deny entries (#111). `merge_toml_config` and the Codex
TOML overlay — flag only. Any route for a host-private `permissions.deny` entry (#118). Repairing an
already-deployed unguarded `settings.json` (ADR 0043 records it as a residual). Merging the PR.

## Verification

`just verify`, bare — no pipes, no `|| true`. The suite that matters is `./install-test.sh`, which
`just verify` reaches. Run `just records` after touching `docs/adr/`.
