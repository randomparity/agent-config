# Codex TOML overlay preservation — design

Issue: [#123](https://github.com/randomparity/agent-config/issues/123)
Decision record: [ADR 0057](../../adr/0057-a-codex-overlay-may-not-erase-a-base-value.md)
Accepted context: [ADR 0043](../../adr/0043-overlays-may-not-replace-a-base-array.md),
[ADR 0049](../../adr/0049-a-refused-overlay-withholds-one-file.md),
[ADR 0052](../../adr/0052-an-overlay-is-exactly-one-json-object.md)

## Measured current behaviour

Every row was produced by running `install.sh --agent codex` under `env -i` with `HOME`,
`TMPDIR`, `CODEX_CONFIG_DIR` and `AGENT_CONFIG_PRIVATE_DIR` pointed into a scratch
directory. `no parser` shadows `python3` with a shim that fails `import tomllib`, standing
in for stock macOS Python 3.9.

| # | Overlay | Parser | Exit | Deployed | Reported |
|---|---|---|---|---|---|
| 1 | absent | yes | 0 | base alone, valid | `no private overlay at <path>` |
| 2 | new root key + new table | yes | 0 | both applied, valid | `applied private overlay` |
| 3 | empty file | yes | 0 | base alone (with extra blank lines) | `applied private overlay` |
| 4 | `[features]` with a new key | yes | 1 | nothing | raw `<tmpfile>: invalid TOML: Cannot declare ('features',) twice` |
| 5 | `[features]` with `goals = false` | yes | 1 | nothing | same |
| 6 | not valid TOML | yes | 1 | nothing | raw `<tmpfile>: invalid TOML: Expected '=' …` |
| 7 | bare non-table value | yes | 1 | nothing | same class |
| 8 | root key opening a multi-line array whose continuation starts with `[` | yes | 1 | nothing | raw `<tmpfile>: invalid TOML: Invalid value` |
| 9 | **root key opening a multi-line string, then `[sandbox]`** | yes | **0** | **valid; the base's `features` table swallowed into a string** | `applied private overlay` |
| 10 | **the same, with `features.goals = false`** | yes | **0** | **valid; `features.goals` is now `false`** | `applied private overlay` |
| 11 | `[features]` with `goals = false` | **no** | **0** | **unparseable document, over the operator's live file** | `applied private overlay`, `skipped TOML validation`, `1 updated` |

Rows 9 and 10 are the defect. `emit_root_settings`/`emit_table_settings` split on
`/^[[:space:]]*\[/`, which is not a TOML lexer, so a line inside a multi-line string is
taken for a table header and the overlay's tail is relocated behind the base's tables —
inside the string the operator opened. Row 9's deployed file parses as
`{'notes': '\n[features]\ngoals = true\n\n[not a table]\n', 'sandbox': {…}}`. Neither row
names a base path, so no check stated over names can see either.

Row 11 is the second exposure: `validate_toml` is the only guard on the concatenation and
it runs only where `python3` can `import tomllib`.

Four further facts. Every failure is a whole-run abort rather than ADR 0049's
withhold-and-continue, so under `--agent all` a bad Codex overlay stops Bob installing.
Every failure message names a temporary file, never the overlay, and carries no remedy.
`install: applied private overlay` prints *before* validation, so it appears on runs that
then fail. And rows 1 and 3 deploy different bytes for the same meaning — `\n[features]…`
versus `\n\n[features]…\n` — so "the base alone" is not one byte sequence today.

TOML has no multi-document concept, so ADR 0052's multi-value verdict has no analogue; a
file holding a bare value is simply invalid TOML. `tomllib` rejects both a NUL byte and a
BOM as invalid TOML (verified), so neither needs the byte-level treatment ADR 0052 gave
jq — with the encoding caveat in R10 below.

## Requirements

- R1 Every path the base defines is present in the merged document with an equal value.
  An overlay that erases or changes one is refused before deployment and each path is
  named. (ADR 0057 rule 1)
- R2 A merged result built from an overlay is deployed only after a parser has accepted it
  and R1 has been checked. Where no parser is available the overlay is refused and the
  base alone is what may be deployed. (rule 2)
- R3 With no overlay, the base is copied verbatim; the ADR 0049 rule 4 fill uses the same
  copy, so both are byte-identical to `config.base.toml`. (rule 3)
- R4 A refusal withholds `config.toml` and nothing else: the rest of the Codex tree and
  the remaining agents install, and the run exits non-zero naming the withheld path.
- R5 A destination holding no `config.toml` gets the base alone on a refusal; one holding
  a file is left byte-for-byte as it is. (ADR 0049 rules 4, 5)
- R6 The withheld path stays in the manifest, so `prune_removed` does not delete it.
  (rule 3)
- R7 The merged temporary file is removed on refusal. (rule 2)
- R8 A refusal is the only condition that returns. Every fallible command in the merge is
  individually status-tested; anything else exits. A comparison that did not run is never
  read as one that found nothing. (ADR 0049 rule 1, ADR 0057 rule 4)
- R9 `install: applied private overlay` prints only once the result is accepted.
- R10 Every message about the operator's file names that file. No message carries a
  temporary path or a Python traceback.
- R11 The JSON overlay path's verdicts are unchanged.
- R12 `README.md` states both overlay contracts accurately, including what rule 2 costs an
  operator without a parser.

## Design

### `render_base_toml <base> <output>`

`cp` the base to the output, guarded. Used by the no-overlay branch and by the ADR 0049
fill, so one byte sequence is "the base alone" (R3). Replaces the `emit_root_settings` +
`emit_table_settings` pair on the no-overlay branch; the splitter stays for the overlay
branch, where the hoist is what it is for.

### `require_valid_base_toml <base>`

Called once at the top of `merge_toml_config`, so every route the base takes to a
destination is covered by one check. Without it the base is parsed only as part of a merged
document, which leaves the default route — no overlay, a straight copy — shipping an
unparseable `config.toml` under a green run, and makes an overlay-present run blame the
operator's file for this repository's. A malformed base is a hard exit naming the base, the
same split `render_base` makes for JSON: it is a defect here, not a mistake the operator can
fix. Where no parser exists the base is trusted unread, which is what rule 2 already says
about it.

### `validate_toml <path>`

Returns 0 accepted, 1 rejected, 2 no parser, 3 the validator itself failed. Prints the
parser's diagnostic on rejection
**without** the file path, so the caller supplies the operator's path (R10). Today it
exits on rejection and prints a skip line; both go, because `merge_toml_config` now
decides what each answer means. The skip line is deleted rather than kept — under R2 it
would print on a branch that then refuses, saying "skipped" and "refused" in one run.

Reads bytes, not text: `tomllib.load(open(path, 'rb'))` rather than
`tomllib.loads(path.read_text())`, so the decode follows TOML 1.0's mandated UTF-8 rather
than the locale's encoding.

Every way operator bytes can defeat the parser is a rejection, not a machine failure, and
`TOMLDecodeError` is only the well-formed half of that set. Because `load` decodes the file
itself, a file saved as latin-1 raises `UnicodeDecodeError`, and a pathologically nested one
raises `RecursionError` or `MemoryError`. Each gets a verdict: the encoding one names UTF-8
and the offending byte, the nesting one says the document nests too deeply. Left uncaught,
all three printed a traceback and exited the run — R10 broken, and the whole-run abort R4
forbids, reached from a file the operator can fix. Anything else — an `OSError` on the
temporary file — stays a machine failure and exits (R8).

### `erased_base_toml_paths <base> <merged>`

Prints one dotted path per line for every path the base defines that the merged document
does not carry with an equal value; prints nothing when everything survived. Reached only
after `require_valid_base_toml` and `validate_toml` have both accepted their inputs, so
neither parse here is expected to fail; the call is still status-guarded, because empty
stdout means both "nothing erased" and "I could not tell".

Comparison walks the base's tree, and the walk is what makes "outermost" fall out rather
than needing a separate ancestor-trimming pass:

- the merged document has no value at this key — report this path, do not descend;
- the base's value is a table and the merged document holds a table there — descend;
- the base's value is a table and the merged document holds something else — report this
  path, do not descend;
- otherwise compare value **and** type, and report on mismatch. Type is compared because
  `True == 1` in Python, so `goals = 1` would otherwise pass as `goals = true`.

So a swallowed `[features]` — absent from the merged parse entirely — reports `features`,
while an overridden `features.goals`, where the table survives, reports `features.goals`.
Both are the outermost differing node. Stating the rule over leaves is also what keeps an
additive `[features.sub]` legal: comparing `features` as a whole would refuse it for
extending the base.

Dotted-path rendering is the base's key names joined by `.`, matching `erased_base_paths`'
output shape.

Like `erased_base_paths`, empty stdout means both "nothing erased" and "I could not tell",
so the call is status-guarded and a failure exits (R8).

### `merge_toml_config <base> <overlay> <output>`

Returns 0 on success, 1 on refusal, and exits on anything else (R8).

1. No overlay file: `render_base_toml`, print `no private overlay at <path>`, return 0.
   Not parsed — R2 gates the overlay-applied result only, and this branch is a copy of a
   file this repository ships.
2. Otherwise concatenate as today. Each `emit_*` call and the redirection are status-tested;
   a failure exits, naming the file it could not read. This is the `awk`-on-an-unreadable-
   overlay path, which must not fall through as an empty contribution.
3. `validate_toml` the result:
   - 2 (no parser) — refuse: name the overlay, state that the overlay cannot be applied
     without a `python3` that can `import tomllib`, and say the base alone is what the
     installer can deploy here.
   - 1 (rejected) — refuse: name the overlay, carry the parser's diagnostic, and say the
     offsets index the merged document rather than the overlay, because the overlay may
     parse cleanly on its own and be mangled by the hoist (row 8).
   - 0 — continue.
4. `erased_base_toml_paths`; if non-empty, refuse naming the overlay and each path, with
   the sentence that an overlay may add tables and keys but may not erase or change what
   the base defines (ADR 0057).
5. Print `applied private overlay`, return 0 (R9).

Every refusal unlinks `$output` before returning (R7).

### `install_merged_toml <dest_dir> <base> <overlay> <rel>`

The TOML twin of `install_merged_json`, over a single destination path — Codex has one and
no TOML document feeds two, so ADR 0049's whole-set handling has nothing to range over
here. On success, `install_managed_path`. On refusal: record the overlay in
`REFUSED_OVERLAYS`; if the destination holds nothing, `render_base_toml` into a fresh
`new_temp_file` (0600, not a redirection under the umask) and install that; otherwise
`retain_managed_path` and `report_deployed_toml_state`.

### `retain_managed_path <dest_dir> <rel>`

Loses its `base` argument and its `report_deployed_state` call, becoming bookkeeping only:
`ensure_safe_rel`, `RETAINED`, `MANIFEST_ENTRIES`, `WITHHELD_PATHS`. `install_merged_json`
calls `report_deployed_state` itself immediately afterwards. It prints nothing of its own,
so the JSON path's output and its order are unchanged (R11).

### `report_deployed_toml_state <dest_dir> <base> <rel>`

Says what is live, in the terms a possibly-parser-free check supports: a symlink whose
target was not checked; a directory occupying the path; no file deployed; a file
byte-identical to the base (`cmp`), so no overlay has ever applied there; or a file that
differs, left exactly as it is, with `.agent-config-backups/` named. It never claims a
differing file does or does not carry base values — without a parser it cannot know, and
ADR 0057's Consequences record the asymmetry with the JSON report.

## Threat model

**Boundaries.** One, and not new: `config.overlay.toml`, an out-of-repo file under
`${AGENT_CONFIG_PRIVATE_DIR}`, read by `install.sh` and concatenated into a file deployed
to `~/.codex/config.toml`. This change **narrows** it — content that previously reached the
destination unchecked now passes a parse and a preservation comparison — and adds none.

**Actors.** The local operator, who owns both the overlay and the destination and is the
only party who can write either. The installer runs by hand, as that operator, over that
operator's files. There is no remote or multi-tenant actor, so the trust placed in the
overlay is trust in the operator's own editor and the failure addressed is a mistake, not
an attack. Row 9 is nonetheless the shape a hostile overlay would use, and rule 1 closes
it for both readings.

**Controls.** The overlay's *content* is not sanitised and is not meant to be — a TOML
config is data Codex parses and the installer's job is to deliver it intact. What is
controlled is its *effect on the base*: R1 over the merged parse, R2 over what may be
deployed at all. Path handling is unchanged (`ensure_safe_rel`); the merged file stays a
0600 `new_temp_file` and is unlinked on refusal (R7). Messages carry the overlay's path
and the parser's diagnostic. The diagnostic does echo overlay content, narrowly: `tomllib`
interpolates *key names* into some messages — `Cannot declare ('svc', 'TOKEN') twice`,
`Duplicate inline table key 'X'` — and never values, which was checked against its message
catalogue. Since the README tells operators to keep secrets in private overlays, that is
worth stating rather than denying: a key name from the operator's own file can reach their
own terminal, and any log that captures it. It is accepted because the diagnostic is what
makes the verdict actionable, and because the JSON path already prints jq's diagnostics on
the same terms. `erased_base_toml_paths` prints only names walked from the base, which is
this repository's file.

**Out of scope.** An operator who hand-edits `~/.codex/config.toml` — reported, never
rewritten (ADR 0049). A hostile `AGENT_CONFIG_PRIVATE_DIR`: the installer already trusts
that variable for every agent and narrowing it is not this issue. The `[features]` value
carries no privilege, so there is no escalation to bound. `python3` itself is trusted; it
is already invoked for validation today.

## Test plan

All cases live in `install-test.sh` as section 37 onward, using the existing overlay
harness. Two mechanisms it already carries do the awkward work: the fixture-repo pattern
used by cases 6, 16/17 and 22 (`cp -pR install.sh content agents docs/licenses` into a temp
tree, then mutate the copy) reaches a base the suite may not change, and a PATH shim in the
style of `run_overlay_case_jq` hides `tomllib` from one run. Every case asserts a message on
the stream that carries it, not only an exit status, so a refusal for an unrelated reason
cannot satisfy it.

The suite covers, in order: the swallowing overlay and the `features.goals` override that
motivated the record; an additive `[features.sub]` that must still install; a base table
replaced by a scalar in a document that parses; a retyped scalar (`goals = 1`); a non-UTF-8
overlay and one nested past the parser's recursion limit, both under `--agent all` so the
later agents are shown installing; the two duplicate-declaration routes; a malformed and a
bare-value overlay; the verbatim base copy and its convergence on a second run; an empty
overlay; the no-parser refusal over a live deployment, into an empty destination, and with
no overlay at all; the three remaining deployed-state verdicts (differs, symlink,
directory); a malformed base on both routes it reaches a destination by; an unreadable
overlay; an overlay path `awk` would read as an assignment; the absence of a merged
artifact after a refusal; a refusal under `--agent all`; an empty base table; and a base
root key.

The JSON nine-case protected-key battery is unchanged and still runs over a destination
built by a real install.

### Evidence the tests bite

Each guarantee was reverted in turn and the suite re-run. Every mutation reddened the case
that owns it:

| Mutation | Case that reddened |
|---|---|
| drop the preservation comparison | swallowed base table — installed at exit 0 |
| no-parser returns "accepted" instead of refusing | no parser over a deployment |
| move `report_deployed_state` out of `install_merged_json` | the JSON battery's refusal-over-a-deployment case |
| drop the `UnicodeDecodeError` verdict | non-UTF-8 overlay — traceback |
| drop the recursion/memory verdict | overlay nested past the parser limit — traceback |
| drop `require_valid_base_toml` | malformed base without an overlay — installed at exit 0 |
| drop the type comparison | base scalar retyped — installed at exit 0 |
| `awk` reads its operand instead of stdin | overlay path `awk` reads as an assignment |
| stub out `report_deployed_toml_state` | no parser over a deployment |

### Two consequences the suite carries

`install-test.sh` writes a Codex overlay fixture and runs `--agent all`, so under R2 the
suite now needs a `python3` that can `import tomllib` where before it degraded to skipping
validation. That turns an optional tool into a hard prerequisite of `just verify`. The
suite states it as a precondition with the version and the reason, rather than failing
somewhere in the middle with a refusal verdict about a fixture. `install-tools.sh` does not
check for it; issue #172 tracks that, and `README.md` records the gap meanwhile.

A directory or other non-regular file at the overlay path still reads as "no overlay",
because the guard is `[[ -f "$overlay" ]]`. That is unchanged and is what the JSON path
does at the same point, so it stays consistent rather than becoming a second contract; it
is recorded here as known rather than addressed.

### Two verdicts that read oddly, and are left alone

After an ADR 0049 rule-4 fill, a second refused run reports the deployed `config.toml` as
"the base alone; no overlay of yours has ever been applied there" about a file this
installer just wrote. That is true as stated — no overlay was applied to it — and ADR 0049
already records the same shape for JSON.

Upgrading from a pre-0057 installer, a `config.toml` written by the old no-overlay path
differs from the base by one leading newline, so the first refused run after the upgrade
says it "differs from the base". One successful run converges it, after which the verdict
is accurate. Both are reporting artefacts of a byte comparison chosen because the refusal
may be a refusal for want of a parser.
