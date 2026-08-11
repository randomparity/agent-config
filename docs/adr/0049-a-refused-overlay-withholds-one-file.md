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

Independent review of #132 established that the abort's cost is not `settings.json` exposure — a
pre-0043 re-run with a clobbering overlay simply redeployed the clobbered file, equally unguarded —
but the agent's whole managed tree. An operator whose overlay is stale silently stops receiving
*every* update for that agent, for a reason that concerns one file. The failure is loud about the
settings file and silent about the rest: the message says no settings file was deployed, and an
operator can reasonably read that as the whole of what stopped. The one place the exposure
comparison does not hold is a *first* install, where pre-0043 deployed a merged file carrying every
guard the overlay did not name; that is what the empty-destination rule below exists for.

There is a second residual. 0043's message can only say the deployed file "may already be missing
these values", because nothing looks at it. The installer holds the base and can read the deployed
file; the hedge is a choice, not a limit.

## Decision

**A refused overlay withholds the destination paths that merge feeds, and nothing else. The rest of
that agent's managed tree installs, the remaining agents install, and the run still fails.**

The unit is the destination path, not the agent and not "the settings file". One refused merge can
feed several: Bob's merged MCP document installs to both `mcp.json` and `mcp_settings.json`. Every
rule below is stated over that set.

Five things are normative; how bash is made to do them belongs to the implementation, which the
design spec carries.

1. **A refusal is the only condition that returns.** Any other failure — the merge itself, or
   either protected-set comparison — still exits. Load-bearing rather than tidy: testing the status
   at a call site suppresses `set -e` for the whole function body, so a failed merge would fall
   through and accuse a blameless overlay of erasing everything, and a failed comparison would
   produce an empty result that reads as a clean verdict. No comparison that did not run may be
   reported as one that found nothing.
2. **A refused merge leaves no installable artifact.** The merged file is written before it is
   checked, so on refusal a guard-erased document exists on disk; `exit 1` used to make it
   unreachable. It is removed, so a mis-written call site fails loudly on a missing source instead
   of deploying it under a green summary. 0043's "no unguarded settings file is deployed" stays
   structural rather than becoming a convention.
3. **A withheld destination path stays in the manifest.** A manifest that omits it instructs
   `prune_removed` to delete the deployed file, and the abort used to stop before pruning where now
   it does not. Withholding a deploy must never become deleting a deployment.
4. **A wholly empty destination gets the base.** Where *every* destination path the refused merge
   feeds holds no file, the base alone is deployed and named as such. It is not a repair and
   overwrites nothing; the choice it settles is whether a fresh destination gets a guarded default
   or nothing at all, beside an instruction tree that assumes the guards are there. The operator
   still does not get their overlay — that is the refusal's doing, not this rule's, and the
   alternative delivers no overlay *and* no guards. The condition is over the whole set rather than
   per path, or Bob's one merged MCP document could land as two files with different contents. A
   partially populated set is therefore retained whole and its absent path stays absent until the
   overlay is fixed: a decision, taken because consistency across one document outranks filling one
   half of it.
5. **The refusal reports what is live.** On refusal the installer compares the base against each
   **deployed** file and says whether it is the base alone — no overlay of theirs has ever applied —
   or carries every protected base path, or is missing some, or cannot be read as JSON. Same
   derived-protected-set check, pointed at what is loaded rather than at what would have been
   written. Where paths are missing it also names `<dest>/.agent-config-backups/`: if an earlier run
   replaced that file, its predecessor was copied there. It only reports — a deliberate hand edit
   that erased a guard is named and left exactly as the operator wrote it.

The run then attempts every agent it was asked for, and exits non-zero having named the withheld
paths. That summary is emitted from the existing `trap cleanup EXIT`, so a later unrelated hard
exit cannot swallow it. The status is unchanged; what it reports is not. Before, non-zero from a
refused Claude overlay meant nothing was deployed for that agent and, under `--agent all`, nothing
after it either. Now it means the agent's tree, the later agents, and everything but the withheld
paths went to the operator's home directory. A wrapper reading non-zero as "the install did not take
effect" is wrong after this change, and that is the price of not charging an unrelated freeze for
one bad overlay.

Repair stays the operator's, through the route that already exists: fix or remove the overlay and
re-run. `install_managed_path` then sees the deployed file differ from the merged result, backs the
current one up, and replaces it. What that route lacked was any way to learn it was owed, and
making the condition legible is the whole of the remedy here. It is not available to every operator:
0043 leaves a host whose overlay carries a private `permissions.deny` entry no fix short of
publishing the path (#118), and for that host this change turns a loud stop into an indefinitely
unguarded deployment that keeps receiving every other update. That is the sharpest instance of the
forcing-function loss below.

## Consequences

- 0043's "the abort ends the run" no longer holds, and the paragraph stating that agents later in
  the sequence do not install at all is superseded on that point. Its protected-set rule — which
  values are protected and what a merged result must preserve — is untouched, and every case in
  0043's contract keeps its verdict.
- A refused run now reaches `prune_removed` for that agent. That is the ordinary pruning of a run
  that installed everything else, and the retained manifest entries are what keep the deployed files
  out of it. A call site that withholds a destination path without retaining it deletes an
  operator's file — and the path most easily missed is Bob's `mcp_settings.json`, the second
  destination of a single merge.
- The refusal output grows a second paragraph about a different file, so it says two things at once:
  the overlay is bad, and here is what your live file holds. Distinct wording is doing the work of
  keeping them apart.
- An operator whose deployed file is already correct now learns that on a refused run, which is the
  common case and reads as reassurance rather than as a second failure. A destination filled by
  rule 4 is reported as base-alone instead, so a state the installer created does not read like one
  the operator arrived at — but only until the base changes. Every verdict is against the base *as
  of this run*: "missing some" means unguarded relative to today's base and does not separate a
  clobbered file from a merely stale one, and base-alone stops being detectable the moment the base
  gains an entry. Distinguishing them durably would need a marker of installer-written state, which
  is more machinery than the risk is worth.
- The check costs one extra `jq` invocation, on the refusal path only.
- The report says nothing about whether the *overlay* would have repaired the deployed file, because
  the overlay was refused and no merged result exists to describe.
- **The refusal stops being terminal output.** Today it is the last thing on the screen, because the
  run ends on it; now it lands mid-stream in a long, otherwise-successful log. 0043 rejected "warn
  and continue" partly on that ground, and the withheld-path summary is what answers it: emitted
  from the `trap cleanup EXIT` that is already installed, it is the last thing printed on *every*
  exit path, including a later unrelated hard failure. What remains is that the operator must read
  the tail rather than have the run stop in front of them.
- **A refused run now deploys a current tree beside a settings file of arbitrary vintage.** Under the
  abort those two came from the same successful run and were stale together; now the newest
  `skills/`, `CLAUDE.md`, `statusline.sh` and `content/` land next to a settings file that may
  predate them by any amount — and they reference each other, since the base's `statusLine.command`
  names the separately installed `~/.claude/statusline.sh` and the shipped instructions assume the
  `PreToolUse` guards are present. The withheld file can therefore fall behind a guard the base has
  since added while the operator keeps receiving every instruction that assumes it. What the
  empty-destination rule bounds is the extreme, not this: a stale deployed file is still stale, and
  only the case of *no* file is filled in.
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
- **Repair the deployed file from the base.** Rejected wherever a deployed file exists: the only
  thing available is the bare base, which discards every legitimate scalar override the operator
  already has *running*, silently, in their home directory — answering a broken overlay by throwing
  away the working part of it. Rule 4 is not an exception to that reason but a case it does not
  reach: with nothing deployed there is no running configuration to discard, and the comparison is
  against an absent file rather than a working one. The split is on "is anything deployed", not on
  "is anything wrong with what is deployed", so it never overwrites.
- **Leave an empty destination empty** — the null option for rule 4, and the only rule here that
  writes to the operator's home on the refusal path. Its price is a destination receiving the whole
  instruction payload with no settings file and therefore none of the base's guards, which is worse
  than anything reachable before this change. Rule 4's price is a file the operator did not
  configure, plus the base-alone verdict rule 5 has to carry to keep that file honest, plus a
  verdict that decays when the base moves. Rejected because an unguarded runtime state outweighs an
  unconfigured but guarded one, and because the run says which it produced.
- **Validate every requested agent's overlays up front, before the first install.** Genuinely
  distinct: it puts all refusals at the top of the log rather than mid-stream, without depending on
  anything at the tail. Rejected because it either merges twice per agent or holds every merged
  result across the run, restructuring the installer's per-agent flow to buy placement — and the
  summary emitted from the existing EXIT trap buys legibility for a few lines without touching that
  flow.
- **Apply the overlay, then reassert the base's protected values.** Already rejected by 0043 for
  making the overlay's stated intent vanish without a word. Re-examined here because it is the one
  alternative that would *repair* an unguarded deployment on the next run, which is what #126 asked
  for. Still rejected, and for 0043's reason rather than a new one: it buys the repair with a second
  silent failure mode, and this record's whole complaint is about a cost that is not stated.
- **A `--repair-settings` flag or an equivalent environment variable.** Rejected: nobody asked for
  it, and it would have to answer what to do about the overlay — which is the actual defect — before
  it could decide what a repaired file contains. The existing route already replaces the file and
  keeps a backup.
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
  which to infer it. Improving the message further does not answer this: a better sentence about the
  settings file does not unfreeze the skills tree.
