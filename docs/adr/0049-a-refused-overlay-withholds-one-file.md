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
refusal. Two invariants of the same class hold this up, and neither is optional. The script runs
under `set -e`, so a call site must test the status explicitly; a bare call to a function that
returns non-zero ends the script exactly as the old `exit 1` did, after the refusal text has
printed and before any withheld-file count, which looks identical to today's behavior while this
record claims the opposite. And retaining is not merely "skip": the path is recorded in the new
manifest, because a manifest that omits it is a manifest that instructs `prune_removed` to delete
the deployed file. Withholding a deploy must never become deleting a deployment, and the abort used
to stop before pruning where now it does not.

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

Repeating a refused run changes nothing about the file the refusal is over: nothing on that path
writes to the settings destination, so the deployed file and the refusal report are the same on the
second run as on the first. The rest of the run is idempotent for the ordinary reason —
`install_managed_path` compares before it copies — and its summary counts do differ between the run
that installs a tree and the run that finds it unchanged.

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
- The withheld count is reported when the run reaches its end. `install.sh` still exits directly on
  a missing command, an unsafe managed path, a symlinked ancestor, an uncomparable payload or a
  missing source, so an unrelated hard failure while installing a later agent preempts the count and
  the operator sees only that failure. Accepted rather than engineered around: a summary-on-exit
  trap would run on every exit path in the script to cover a compound, low-frequency case.
- **A refused run now deploys a current tree beside a settings file of arbitrary vintage.** Under the
  abort those two came from the same successful run and were stale together; now the newest
  `skills/`, `CLAUDE.md`, `statusline.sh` and `content/` land next to a settings file that may
  predate them by any amount — and they reference each other, since the base's `statusLine.command`
  names the separately installed `~/.claude/statusline.sh` and the shipped instructions assume the
  `PreToolUse` guards are present. The withheld file can therefore fall behind a guard the base has
  since added while the operator keeps receiving every instruction that assumes it.
- **The freeze was also a forcing function, and this gives it up.** A run that installed nothing was
  not livable; a run that installs almost everything and exits non-zero is. An operator whose
  deployed file happens to be correct now reads the report as reassurance and has little pressure to
  fix the stale overlay — which is the state in which the next base guard never reaches them. That
  is a real loss, taken deliberately: coercing a fix by withholding unrelated content charges the
  cost to the wrong files.

## Considered & rejected

- **Narrow the refusal and stop there** — return instead of exit, install the rest of the tree, and
  leave #110's message as shipped. The cheapest option that answers the issue comment in full, and
  it drops the second jq invocation, the second output paragraph, and any chance of naming a
  deliberate hand edit. Rejected because the message it keeps can only say the deployed file "may
  already be missing these values": the operator cannot tell an unguarded deployment from a sound
  one, and so cannot tell whether fixing the overlay is urgent or housekeeping. Once the freeze is
  gone that judgment is the only thing left driving a repair, so the saving comes out of the
  requirement rather than out of the decision.
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
