# 0049 — A refused overlay withholds one file, not the run

## Status

Accepted (2026-08-10)

## Context

[ADR 0043](0043-overlays-may-not-replace-a-base-array.md) made an overlay that would erase a value
the base defines a hard install failure. It is implemented as `exit 1` inside
`merge_json_settings`, and every call to that function happens before the agent's first
`install_managed_path`. So the refusal withholds far more than the file it is about: the agent's
skills tree, `CLAUDE.md`, and the shared `content/` payload are all skipped too, and under
`--agent all` — where Claude is first — a bad Claude overlay installs nothing whatsoever. 0043
recorded that consequence and left it to issue #126.

Independent review of #132 established what the abort actually costs, and it is not `settings.json`
exposure. Before 0043, an operator re-running with a clobbering overlay got the clobbered file
*redeployed* — equally unguarded — so the deployed settings file is no more exposed after the
change than before, and the unguarded window was already unbounded. What is new is that an operator
whose overlay is stale silently stops receiving *every* update for that agent, for a reason that
concerns one file. The failure is loud about the settings file and silent about the rest: the
message says no settings file was deployed, and an operator can reasonably read that as the whole
of what stopped.

There is a second residual. 0043's message can only say the deployed file "may already be missing
these values", because nothing looks at it. The installer holds the base and can read the deployed
file; the hedge is a choice, not a limit.

## Decision

**A refused overlay withholds the settings file it governs, and nothing else. The rest of that
agent's managed tree installs, the remaining agents install, and the run still fails.**

Three parts.

*The refusal is a return, not an exit.* `merge_json_settings` reports and returns non-zero. Each
call site installs its destination paths from the merged file on success and **retains** them on
refusal. Retaining is not merely "skip": the path is recorded in the new manifest, because a
manifest that omits it is a manifest that instructs `prune_removed` to delete the deployed file.
Withholding a deploy must never become deleting a deployment, and that manifest entry is the whole
of the defense — the abort used to stop before pruning, and now it does not.

*The report names what is live.* On the refusal path the installer compares the base against the
**deployed** file and says which protected base paths that file is missing now, or that it carries
them all, or that it is absent, or that it could not be read as JSON. It is the same
derived-protected-set check the merge uses, pointed at what is loaded rather than at what would
have been written. Nothing is written on this path, so the report cannot damage anything — a
deliberate hand edit that erased a guard is named and left exactly as the operator wrote it.

*The run still fails.* Every requested agent is attempted, then the installer names the count of
withheld settings files and exits non-zero. Anything reading the exit status sees no change.

Repair stays the operator's, through the route that already exists: fix or remove the overlay and
re-run. `install_managed_path` then sees the deployed file differ from the merged result, backs the
current one up under `.agent-config-backups/<timestamp>/drift/`, and replaces it. That route was
always there; what it lacked was any way to learn it was owed. Making the condition legible is the
whole of the remedy, and the repair itself is left to the managed-path code that has always owned
that file.

The result is idempotent by construction. A second run with the same overlay retains the same file,
prints the same report, and exits the same way, because the refusal path performs no writes at all.

## Consequences

- 0043's "the abort ends the run" no longer holds, and the paragraph stating that agents later in
  the sequence do not install at all is superseded on that point. Its protected-set rule — which
  values are protected and what a merged result must preserve — is untouched, and every case in
  0043's contract keeps its verdict.
- A refused run now reaches `prune_removed` for that agent. That is the ordinary pruning of a run
  that installed everything else, and the retained manifest entry is what keeps the deployed
  settings file out of it. A future call site that skips a deploy without retaining the path would
  delete an operator's file; the retain step is the one that must not be dropped.
- The refusal output grows a second paragraph about a different file, so it says two things at once:
  the overlay is bad, and here is what your live file holds. Distinct wording is doing the work of
  keeping them apart.
- An operator whose deployed file is already correct now learns that on a refused run, which is the
  common case and reads as reassurance rather than as a second failure.
- The check costs one extra `jq` invocation, on the refusal path only.
- The report says nothing about whether the *overlay* would have repaired the deployed file, because
  the overlay was refused and no merged result exists to describe.
- A refused settings overlay no longer implies a stale skills tree, so the two conditions have to be
  read separately now. That is the point, and it is also one more thing to read.

## Considered & rejected

- **Repair the deployed file from the base.** Rejected: with the overlay refused there is no merged
  result to write, so the only thing available is the bare base — which discards every legitimate
  scalar override the operator has, silently, in their home directory. It answers a broken overlay
  by throwing away the working part of it.
- **Apply the overlay, then reassert the base's protected values.** Already rejected by 0043 for
  making the overlay's stated intent vanish without a word. Re-examined here because it is the one
  alternative that would *repair* an unguarded deployment on the next run, which is what #126 asked
  for. Still rejected, and for 0043's reason rather than a new one: it buys the repair with a second
  silent failure mode, and this record's whole complaint is about a cost that is not stated.
- **A `--repair-settings` flag or an equivalent environment variable.** Rejected: nobody asked for
  it, and it would have to answer what to do about the overlay — which is the actual defect — before
  it could decide what a repaired file contains. The existing route already replaces the file and
  keeps a backup.
- **Keep the abort and improve only the message.** Rejected: #110 already improved the message, and
  the issue's own reframing is that the message is not the cost. A better sentence about the
  settings file does not unfreeze the skills tree.
- **Compare the deployed file against the base on every run, not only on refusal.** Rejected: on a
  run that is not refused the installer replaces the deployed file with the merged result, so a
  clobbered file is repaired that same run and the report would describe a state that no longer
  exists by the time the run ends.
- **Withhold the settings file and exit 0.** Rejected: the operator's overlay is broken and the file
  it names was not installed. A green run says otherwise, and the exit status is the one signal a
  wrapper script reads.
- **Do nothing; #110's message already tells the operator to fix the overlay.** Rejected: it tells
  them their settings file was not deployed, which is true and incomplete. The operator who reads it
  and shrugs — the overlay is stale but the deployment is fine — is not told that they have also
  stopped receiving skills, instructions and shared content, and there is nothing in the output from
  which to infer it.
