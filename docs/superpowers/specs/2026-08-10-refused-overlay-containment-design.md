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
alternatives — repairing the deployed file from the base, reasserting base values over a merged
overlay (already rejected by 0043), a `--repair-settings` flag, keeping the abort and improving
only the message, checking the deployed file on every run, and skipping the deploy while exiting 0.

## Behavior

### `merge_json_settings`

Signature and merge rule are unchanged. What changes is the failure mechanism.

| Input | Behavior |
|---|---|
| No overlay file | Copy the base through `jq '.'`; report no overlay. Return 0. Unchanged. |
| Overlay whose merged result preserves every protected base value | Merge; report the overlay applied. Return 0. Unchanged. |
| Overlay whose merged result changes a base non-empty array or leaves a non-object where the base held a non-empty object | Report to standard error, naming the overlay and each outermost base path not preserved, and **return 1**. Was `exit 1`. |

The merged temp file is still written before the check and still removed by the EXIT trap. The
refusal path writes nothing to the destination, so no half-written file can survive it.

### Call sites

Three call sites, four destination paths (Bob's merged MCP document installs to both `mcp.json`
and `mcp_settings.json`). Each becomes: merge; on success install every destination path from the
merged file; on refusal **retain** every destination path.

Retaining a path means:

1. It is counted `retained` and reported in the agent's summary line.
2. It is **added to the new manifest**. A manifest that omits it is a manifest that tells
   `prune_removed` to delete the deployed file — withholding a deploy must never become deleting a
   deployment. This is the one place where narrowing the abort could destroy operator data, and the
   manifest entry is the whole of the defense.
3. The base is compared against the **deployed** file and the result reported:
   - deployed file absent → say the agent has no settings file until the overlay is fixed;
   - deployed file present and carrying every protected base value → say so;
   - deployed file present and missing some → name them, and state the repair route.
   - deployed file present and unreadable as JSON → say so and name it, without guessing.

The comparison is `erased_base_paths base deployed` — the same derived-protected-set check the
merge uses, applied to what is live rather than to what would have been written. A deployed file
produced by a legitimate overlay passes it, because that is exactly the property the merge enforces.
A hand-edited file that overrode a scalar also passes, because scalars are unprotected. A hand-edited
file that erased a protected array is reported — correctly, since it is in the same unguarded state
the report exists to surface. Nothing is written either way, so no report can damage a deliberate
edit.

### Run outcome

The run attempts every agent it was asked for. Afterwards, if any settings file was withheld, the
installer names the count on standard error and exits 1. An operator or wrapper reading only the
exit status sees no change from today.

### Repair route

The route back to a correct file is the one the installer already has, and it is now reachable:
fix or remove the overlay and re-run. `install_managed_path` sees the deployed file differ from the
merged result, backs the current one up under `<dest>/.agent-config-backups/<timestamp>/drift/`,
and replaces it. Nothing new writes to the operator's home directory; the repair happens through
the managed-path route that has always owned that file, with the backup it has always taken.

## Success criteria

Each is a test in `install-test.sh` unless noted.

1. **Clobbered deployment, reported.** A deployed `settings.json` missing the base's
   `hooks.PreToolUse` in a temp dest, refused overlay: standard error names the deployed file's
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
   file carries every base value says so rather than naming paths.
7. **Idempotent.** Running the refused case twice leaves the same deployed file, the same exit
   status, and the same report.
8. **#110's verdicts unchanged.** The five constrained cases keep theirs: clobbering
   `hooks.PreToolUse` refused; `permissions.deny` replacement refused; `permissions.allow` addition
   installed; `{"env":null}` refused; `{"hooks":"x"}` refused naming `hooks` and not `PreToolUse`.
   Already covered by existing cases 2–6, 9, 10.
9. **No test writes outside its fixture.** Every case exports `HOME`, `*_CONFIG_DIR`, and
   `AGENT_CONFIG_PRIVATE_DIR` under the suite's `mktemp -d`, removed by the existing EXIT trap.
10. `README.md` states the withheld-file behavior and the repair route. Not a test.
11. `just verify` passes bare.

## Out of scope

- Repairing a deployed file the installer cannot correctly reconstruct. With the overlay refused
  there is no merged result to write, and writing the bare base would discard every legitimate
  scalar override the operator has.
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
