# Require Verify Branch Protection Design

Issue: #16

## Approved requirement and assumptions

Issue #16 requires GitHub to make the real pull-request check named `verify`
mandatory for ordinary changes to `main`, prove that a failing run blocks a pull
request, document recovery for renamed or stuck checks, and resolve the existing
root debt record. The operator explicitly authorized the repository-setting write
and temporary failing-proof pull request.

This is a dispatched design: the issue body and the operator authorization are the
approved requirement. The proof must not risk merging its deliberately invalid
fixture. GitHub's reported `BLOCKED` merge state plus the failed required check is
the proof; no merge command will be attempted against the proof pull request.

## Goals

- Require the exact `verify` context observed on PRs #5 and #19 for `main`.
- Apply the requirement to administrators so the authenticated owner used for the
  proof cannot silently bypass it.
- Demonstrate a failed `verify` run and a `BLOCKED` pull-request merge state.
- Remove every temporary proof artifact after recording its evidence.
- Document how maintainers discover and replace a renamed or stuck required check.
- Resolve `docs/debt/0001-require-verify-branch-protection.md` in place.

## Non-goals

- Requiring reviews, signed commits, linear history, or conversation resolution.
- Changing the `Verify` workflow or its job name.
- Adding a second CI workflow, local branch-protection emulator, or policy bot.
- Attempting to merge the deliberately failing proof pull request.

## Approaches considered

### Classic branch protection with one required context — chosen

Create protection for `main` through GitHub's branch-protection API with
`verify` as the only required status context and admin enforcement enabled. The
repository currently has neither classic protection nor rulesets, so this adds
the smallest policy that meets the issue without replacing other rules.

### Repository ruleset

A ruleset can require status checks and define bypass actors. It introduces a
new named policy object and more configuration surface while providing no needed
capability beyond classic protection for this repository.

### Document the check without enforcing it

Documentation would explain intent but leave the advisory merge path that caused
the debt. It does not satisfy the issue.

## Design

### Policy capture and write

Before the write, capture:

- `gh pr checks 19 --json name,state,link,bucket,workflow`, which reports the
  emitted check name as `verify`;
- the matching check run from PR #19's head commit, which reports GitHub Actions
  app ID `15368` as the producer;
- classic protection for `main`;
- repository rulesets; and
- effective rules for `main`.

Re-read the same policy immediately before writing and stop if it changed after
capture. The captured baseline is empty. Create classic branch protection with:

- required status checks: `strict: false`, checks: `verify` from app ID `15368`;
- enforce administrators: `true`; and
- every unrelated protection feature left disabled or unset.

Binding the context to GitHub Actions prevents a same-named result from another
producer from satisfying the gate. `strict: false` avoids adding an up-to-date-branch
requirement that issue #16 did not request. The required check still must succeed for
the pull request's latest head commit. After the write, read the setting back and
assert the context, app ID, strictness, and admin enforcement exactly.

### Failing proof

Create a temporary branch from current `origin/main` in its own external worktree.
Add one deliberately malformed debt record so the existing `verify` job fails
through the repository's real `just ci` path. Push the branch and open a temporary
pull request.

Wait for the `verify` check to finish, then require all of these observations:

- the check name is exactly `verify`;
- its producer is GitHub Actions app ID `15368`;
- its state is `FAILURE`;
- the pull request reports `mergeable: MERGEABLE` (the git histories do not
  conflict); and
- `mergeStateStatus` is `BLOCKED` (policy, not a conflict, prevents merge).

Do not invoke a merge command: if the setting were wrong, that could merge the
known-bad fixture. Record the check URL, pull-request number, head SHA, policy
snapshot, and merge-state observation in issue #16. Then close the proof pull
request, delete its remote branch, remove its worktree, and delete its local
branch. Verify all proof artifacts are gone.

### Repository documentation

Add a branch-protection subsection to `README.md` that states the required context
is the lowercase job name `verify`, shows how to copy current names from a real pull
request, and shows how to inspect and update required status-check protection.

Recovery replaces the required context and app binding only after a real run emits the
replacement. This handles a renamed check and a permanently pending stale context without
disabling protection. The instructions preserve admin enforcement and avoid rewriting
unrelated protection fields by patching only the required-status-check endpoint.

Resolve the debt record by replacing `Open` and `review-by:` with a dated resolution
banner naming issue #16 and the recorded enforcement proof. Its substantive sections
remain immutable.

## Failure behavior and rollback

- If the baseline contains an unexpected protection or ruleset, stop before writing
  rather than overwrite it.
- If policy read-back differs from the requested context, app binding, or admin
  enforcement, re-read live policy. Restore the captured baseline only when live policy
  exactly equals this run's expected post-write snapshot; otherwise stop and report both
  snapshots for manual reconciliation without overwriting the concurrent change.
- If the proof check does not fail for the expected record-gate reason, close and clean
  the proof artifacts, then diagnose before claiming enforcement.
- If the pull request is not `BLOCKED`, leave the debt open, remove or restore the new
  policy from the captured baseline, and stop.
- If `verify` is renamed or stuck later, use a real pull request to discover the emitted
  replacement and patch the required-context endpoint. Removing all required contexts is
  not the recovery path.

## Threat model

### Boundary inventory

- An authenticated repository administrator changes external GitHub authorization
  policy for `main`.
- Contributor-controlled commits produce check runs that GitHub uses as merge gates.
- A temporary deliberately malformed record enters the public proof branch and PR.

### Actors and trust

Repository administrators are trusted to change protection settings and can still
change or remove the policy later. Contributors and their branch contents are untrusted.
GitHub supplies check results and merge-state evaluation. The local operator controls the
temporary proof branch but must treat it as known-bad input that cannot reach `main`.

### Controls

- Resolve the exact check context and producer app ID from a real successful PR rather
  than prose or memory.
- Enable admin enforcement so the authenticated owner receives the same required-check
  gate during the proof.
- Inspect live policy before and after the write and change no unrelated setting.
- Prove enforcement through failed-check and `BLOCKED` state observations without
  attempting a merge.
- Close the proof PR and delete both branch copies and its external worktree.
- Keep tokens out of commands, files, comments, and logs; `gh` uses its credential store.

### Out of scope

The policy cannot prevent an administrator from later editing or deleting the policy.
The proof establishes GitHub's current enforcement for the configured repository, not a
general guarantee about future GitHub behavior.

## Acceptance checks

- A pre-write policy query proves `main` had no protection or ruleset.
- PR #19 reports one successful check named exactly `verify`.
- Post-write protection reports only `verify` from app ID `15368`, `strict: false`, and
  admin enforcement.
- The temporary proof PR reports failed `verify`, a conflict-free head, and `BLOCKED`.
- The proof PR is closed and its local and remote branches and worktree are absent.
- README recovery commands preserve the rest of branch protection.
- The existing debt record carries a valid dated resolution marker.
- `just verify` passes on the real feature branch.
