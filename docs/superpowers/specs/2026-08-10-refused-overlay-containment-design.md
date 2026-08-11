# Refused Overlay Containment Design

## External authority

Issue #126 reports the residual [ADR 0043](../../adr/0043-overlays-may-not-replace-a-base-array.md)
recorded against itself: the protected-key guarantee covers what the installer *writes*, not what
is already deployed, so a host whose `~/.claude/settings.json` was clobbered by the pre-#110 merge
keeps that file. The issue asks for "some route by which a host running the installer ends up
guarded, or knowingly not", and names two candidates — detect that the deployed file is missing
values its base defines and say so distinctly from the overlay rejection, or offer an explicit
re-deploy-from-base path.

The issue's own comment (owner, 2026-08-10) reframes the cost after independent review of #132.
Before #110 an operator re-running with a clobbering overlay got the clobbered file *redeployed* —
equally unguarded — so the abort did not worsen `settings.json` exposure; the unguarded window was
already unbounded. What the abort newly costs is the rest of that agent's managed content: skills,
`CLAUDE.md`, and the shared `content/` payload, because `install.sh` aborts before
`install_managed_path` runs for any of them. Under `--agent all` the agents later in the sequence
do not install at all. "What needs a route is not 'repair the settings file' so much as 'do not let
one bad overlay freeze an agent's entire managed tree'."

The campaign orchestrator's dispatch brief adds: the #110 refusal must not be weakened or bypassed
and keeps its verdicts on five named cases; every test operates on a temp `HOME`/dest; the
temp-file + rename + EXIT-trap discipline is preserved and the refusal leaves no half-written file;
`install-test.sh` covers the clobbered-state scenario against a **deployed** file and reddens when
the fix is reverted; whatever is chosen is idempotent; `README.md` documents the operator-visible
behavior; a narrowing of #110's shipped freeze is recorded in ADR 0049; and `just verify` passes
bare.

Excluded: the host-private `permissions.deny` route (#118); the Codex `config.overlay.toml` gap
(#123); malformed-overlay handling (#125) — all flagged, not fixed; and merging the pull request,
which the orchestrator owns. The frozen scope is issue #126 plus `WS-126-4f7a`; no design-changing
ambiguity remains.

## Approach

Recorded in [ADR 0049](../../adr/0049-a-refused-overlay-withholds-one-file.md): a refused overlay
withholds the settings file it governs and nothing else. The record carries the rejected
alternatives — narrowing the refusal without adding the deployed-file report, repairing the
deployed file from the base, reasserting base values over a merged overlay (already rejected by
0043), a `--repair-settings` flag, keeping the abort and improving only the message, checking the
deployed file on every run, and skipping the deploy while exiting 0 — and the consequences it
accepts: mixed-vintage deployments, and the loss of the freeze as a forcing function.

## Behavior

### `merge_json_settings`

Signature and merge rule are unchanged. What changes is the failure mechanism.

| Input | Behavior |
|---|---|
| No overlay file | Copy the base through `jq '.'`; report no overlay. Return 0. The copy is now guarded — see below. |
| Overlay whose merged result preserves every protected base value | Merge; report the overlay applied. Return 0. Unchanged. |
| Overlay whose merged result changes a base non-empty array or leaves a non-object where the base held a non-empty object | Report to standard error, naming the overlay and each outermost base path not preserved, **delete the merged output**, and **return 1**. Was `exit 1`. |
| `jq` missing, or either `jq` invocation failing | Report and **`exit 1`**, as today. |

Two properties of that table matter more than they look.

**Refusal is the only condition that returns.** `install.sh` runs under `set -euo pipefail`, but
testing a function's status at the call site suppresses `errexit` for its *entire body*, not just
the tested command. So once the call sites branch on the status, a failing `jq -s '.[0] * .[1]'`
inside `merge_json_settings` no longer aborts: execution falls through to `erased_base_paths` with
an empty or truncated `$output`, every protected base path compares unequal, and the installer
accuses a blameless overlay of erasing all of them — then continues and installs the rest of the
tree. The guard is therefore over **every fallible command reachable inside `merge_json_settings`
and the refusal path it returns into** — not an enumerated few:

- the no-overlay `jq '.' "$base"`, whose failure is the worst of the set. It is on the *default*
  configuration, and its truncated output passes `install_managed_path`'s `[[ ! -e "$src" ]]`
  missing-source test, so an unguarded failure deploys a zero-byte `settings.json` and exits 0;
- the merge `jq -s '.[0] * .[1]'`;
- both `erased_base_paths` calls, since that helper reports "nothing erased" and "I could not tell"
  with the same empty stdout;
- the base render used for the empty-destination fill, whose output is installed; and
- the base normalization behind the base-alone comparison.

A comparison that did not run must never be reported as one that found nothing, and a document that
was not produced must never be deployed. The one failure that is a *verdict* rather than an error is
a deployed file that is not parseable JSON: that is reported and the run continues, because it
describes the operator's file rather than the installer's own machinery.

**A refused merge leaves no installable artifact.** The merged file is written before it is checked,
so on refusal a fully-formed, guard-erased settings document exists on disk; `exit 1` used to make
it unreachable. Removing it keeps ADR 0043's "no unguarded settings file is deployed" structural — a
call site that installs it anyway hits `install_managed_path`'s missing-source check and fails
loudly instead of deploying it under a green summary. The EXIT trap still covers the file on every
other path, and `cleanup` already tests for existence before unlinking, so the early delete is safe.

### Call sites

Three call sites, four destination paths — Bob's merged MCP document installs to both `mcp.json`
and `mcp_settings.json`, so **the unit is the destination path, not the agent**. Each call site
becomes: merge; on success install every destination path from the merged file; on refusal
**withhold** every destination path.

Withholding a path means:

1. **The base is deployed where nothing at all is deployed.** If *every* destination path fed by
   the refused merge holds no file, the normalized base — `jq '.' base`, byte-identical to what a
   no-overlay install writes — is installed at each and named as such. Nothing is overwritten;
   what it prevents is a fresh destination receiving the full instruction payload beside no
   settings file and therefore none of the base's guards. The condition is over the whole set
   because Bob's one merged MCP document feeds `mcp.json` and `mcp_settings.json`: filling only
   the empty one would leave a single logical document as two files with different contents. If
   any destination in the set holds a file, every path in that set is retained untouched.
2. It is **added to the new manifest** either way. A manifest that omits it is a manifest that tells
   `prune_removed` to delete the deployed file — withholding a deploy must never become deleting a
   deployment. This is the one place where narrowing the abort could destroy operator data, and the
   manifest entry is the whole of the defense. `mcp_settings.json` is the path most easily missed.
3. A retained path is counted `retained` in the agent's summary line, and the path is recorded so
   the end-of-run summary can name it. A path filled from the base is an ordinary `added`.
4. For a path that was retained, the base is compared against the **deployed** file and the result
   reported:
   - deployed file is byte-identical to the normalized base → say that no overlay has ever been
     applied there. This is the state rule 1 leaves behind, and without its own verdict every later
     refused run would report it as carrying every protected value — true, and reassuring about a
     configuration the operator never got. It holds only while the base is unchanged; once the base
     gains an entry the same file reports as missing it, which is accurate about the guard and
     silent about the cause;
   - deployed file carries every protected base value → say so;
   - deployed file is missing some → name them, state the repair route, and say that *if* an
     earlier run replaced that file its predecessor is under `<dest>/.agent-config-backups/`. The
     conditional is load-bearing: `backup_path` copies nothing when the path did not previously
     exist, so a host whose very first install clobbered the file has no predecessor there and may
     have no such directory at all;
   - deployed file cannot be read as JSON → say so and name it, without guessing.

The comparison is `erased_base_paths base deployed` — the same derived-protected-set check the
merge uses, applied to what is live rather than to what would have been written. A deployed file
produced by a legitimate overlay passes it, because that is exactly the property the merge enforces.
A hand-edited file that overrode a scalar also passes, because scalars are unprotected. A hand-edited
file that erased a protected array is reported — correctly, since it is in the same unguarded state
the report exists to surface. Nothing is written either way, so no report can damage a deliberate
edit.

### Run outcome

The run attempts every agent it was asked for and exits 1 if anything was withheld. The summary
naming the withheld paths is emitted from the **existing `trap cleanup EXIT`**, not from the end of
`main`: `install.sh` still exits directly on a missing command, an unsafe managed path, a symlinked
ancestor, an uncomparable payload or a missing source, and a summary written at the end of `main`
would be swallowed by any of them during a later agent. `cleanup` already prints without
propagating status, which is exactly the discipline this needs; it emits nothing when nothing was
withheld. The status is unchanged; what it now reports is a run that installed almost everything
and withheld some paths.

### Repair route

The route back to a correct file is the one the installer already has, and it is now reachable:
fix or remove the overlay and re-run. `install_managed_path` sees the deployed file differ from the
merged result, backs the current one up under `<dest>/.agent-config-backups/<timestamp>/drift/`,
and replaces it. Nothing new writes to the operator's home directory; the repair happens through
the managed-path route that has always owned that file, with the backup it has always taken.

## Success criteria

Each is a test in `install-test.sh` unless noted.

**Every destination under test is produced by a prior *successful* install** (valid or absent
overlay) before anything is planted into it. `prune_removed` returns immediately when the
destination has no `.agent-config-manifest` (`install.sh:299`), and that file is written only by a
completed `finish_agent` — so a hand-built destination leaves the retention rule unexercised, and a
"the file survived" assertion passes against an implementation that never retains anything. A
clobbered deployment has to be constructed this way in any case: #110 makes the installer refuse to
produce one.

1. **Clobbered deployment, reported.** Install successfully, plant a `settings.json` missing the
   base's `hooks.PreToolUse` over the result, then refuse: standard error names the deployed file's
   missing paths distinctly from the overlay's. Reddens if the deployed-file comparison is removed.
2. **Clobbered deployment, repaired.** The same dest, overlay fixed, re-run: the deployed file
   carries the base's `hooks` and `permissions.deny` again, and the clobbered content is under
   `.agent-config-backups/`.
3. **The tree no longer freezes.** A refused Claude overlay over a temp dest still installs
   `skills/`, `CLAUDE.md`, and `languages/`; the run still exits non-zero.
4. **`--agent all` continues.** A refused Claude overlay still installs Codex and Bob.
5. **The deployed settings file survives the refusal.** Already covered by the existing
   "refusal over a deployment" case; extended to assert the file is still present *after* the run
   reaches `prune_removed`, which the abort used to prevent.
6. **A clean deployment is reported clean.** A refused overlay over a dest whose deployed settings
   file carries every base value says so rather than naming paths. Its manifest still lists
   `settings.json` after the run — the half that reddens when a call site withholds without
   retaining, which "the file is still there" alone does not.
7. **Idempotent over a retained deployment.** Running the refused case twice against a destination
   that already holds a settings file leaves the same deployed file, the same exit status, and the
   same report. The empty-destination case converges rather than repeats, and criterion 9 owns it.
8. **The refused merge's output is unusable.** *Not a test.* Rule 2 is structural: the refusal
   unlinks the merged file, so a call site that installs it anyway hits `install.sh:268`'s
   missing-source `exit 1`. The merged file lives under `$TMPDIR` and `cleanup` unlinks it on every
   exit path, so nothing observable distinguishes "deleted early" from "deleted at exit" — an
   assertion here would be green against an implementation that never deletes it.
9. **An empty destination converges on the base.** A refused Claude overlay against a destination
   with no deployed `settings.json` deploys the base: the file exists afterwards, carries the base's
   `hooks` and `permissions.deny`, and does *not* carry the overlay's value. The run still exits
   non-zero. Every run after the first retains that file, reports it as base-alone rather than as
   carrying every protected value, and leaves it byte-identical. Reddens if the empty-destination
   rule or its base-alone verdict is removed.
10. **Bob's two MCP destinations stay one document.** A refused Bob `mcp.overlay.json` against a
    destination already holding `mcp.json` and `mcp_settings.json` leaves **both** present and
    unchanged after the run reaches `prune_removed`, with both still in the new manifest. Against a
    destination holding only `mcp.json`, neither is rewritten — the set is not wholly empty, so
    nothing is filled from the base. Reddens if only one path is retained, or if the fill is
    evaluated per path.
11. **A guard that did not run is not a clean verdict.** One case per guarded invocation, using a
    `jq` shim early on `PATH` that delegates to the real `jq` except for the call under test — a
    globally failing `jq` stops at the merge, so it can never reach either comparison and would
    leave both bare implementations green. The shim selects on argument shape: `-s` for the merge,
    `-rn`/`--slurpfile` for `erased_base_paths`. Expected observables: merge fails → non-zero, no
    path names printed, nothing deployed; overlay comparison fails → non-zero, no accusation against
    the overlay; deployed-file comparison fails → non-zero, no "carries every value" verdict.
12. **The no-overlay path fails closed.** With the base render made to fail and no overlay present,
    the run exits non-zero and no `settings.json` is deployed. This is the default configuration, so
    an unguarded failure here would deploy a zero-byte settings file to every fresh operator.
13. **The withheld summary survives a later hard failure.** The summary is emitted from the EXIT
    trap, so a refused agent followed by a hard failure in a later agent still names the withheld
    path.
14. **#110's verdicts unchanged.** The five constrained cases keep theirs: clobbering
    `hooks.PreToolUse` refused; `permissions.deny` replacement refused; `permissions.allow` addition
    installed; `{"env":null}` refused; `{"hooks":"x"}` refused naming `hooks` and not `PreToolUse`.
    Already covered by existing cases 2–6, 9, 10.
15. **No test writes outside its fixture.** Every case exports `HOME`, `*_CONFIG_DIR`, and
    `AGENT_CONFIG_PRIVATE_DIR` under the suite's `mktemp -d`, removed by the existing EXIT trap.
16. `README.md` states the withheld-path behavior, the empty-destination rule, and the repair route,
    **and corrects the existing overlay paragraph in place** — it currently says such an overlay
    "fails the install", which after this change describes only the exit status and not the run.
    Adding new prose while leaving that sentence would leave the pre-#126 behavior documented a few
    lines above the new behavior. Not a test.
17. `just verify` passes bare.

## Out of scope

- Repairing a deployed file. With the overlay refused there is no merged result to write, and
  writing the bare base over an existing file would discard every legitimate scalar override the
  operator has. The empty destination is not this case: nothing is overwritten there.
- Any new command-line flag or environment variable.
- `merge_toml_config`, which concatenates rather than merges and has no protected-value guarantee
  to withhold (#123).
- Malformed-overlay handling — a non-object overlay, two concatenated documents, a repeated key
  (#125).

## Security notes

Not security-relevant under the step-6 trigger: no entry point is added or widened, no secret is
handled, no permission grant widens, no dependency changes, and no non-literal is used to build a
command, query, path, or URL. Two properties are worth stating because the change is near a
guardrail:

- The change cannot cause an unguarded settings file to be *deployed*. The refusal path deploys no
  settings file at all; only the unchanged success path writes one, and it writes only a merged
  result that passed the ADR 0043 check.
- The change reads one additional file — the deployed `settings.json` in a destination the
  installer already writes — and only reports on it. `ensure_safe_rel` still governs the path.

The residual is that an agent's *other* managed content now installs where it previously did not.
That content is this repository's own payload, delivered from the checkout the operator invoked;
the alternative was leaving it stale indefinitely, which is the defect.
