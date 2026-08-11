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

`cp` the base to the output. Used by the no-overlay branch and by the ADR 0049 fill, so
one byte sequence is "the base alone" (R3). Replaces the `emit_root_settings` +
`emit_table_settings` pair on the no-overlay branch; the splitter stays for the
overlay branch, where the hoist is what it is for.

### `validate_toml <path>`

Returns 0 accepted, 1 rejected, 2 no parser. Prints the parser's diagnostic on rejection
**without** the file path, so the caller supplies the operator's path (R10). Today it
exits on rejection and prints a skip line; both go, because `merge_toml_config` now
decides what each answer means. The skip line is deleted rather than kept — under R2 it
would print on a branch that then refuses, saying "skipped" and "refused" in one run.

Reads bytes, not text: `tomllib.load(open(path, 'rb'))` rather than
`tomllib.loads(path.read_text())`. `read_text()` decodes with the locale encoding, so a
legal UTF-8 overlay raises `UnicodeDecodeError` under a non-UTF-8 `LC_ALL` — uncaught
today, and under R2 it would become a permanent false refusal reported with a traceback.
TOML 1.0 mandates UTF-8; the parser decodes it. Any exception that is not
`TOMLDecodeError` is a machine failure and exits (R8).

### `erased_base_toml_paths <base> <merged>`

Prints one dotted path per line for every path the base defines that the merged document
does not carry with an equal value; prints nothing when everything survived. The base's
own parse failure is a hard exit naming the base — it is this repository's file, so a
malformed one is a defect here, not a mistake the operator can fix, exactly as
`render_base` treats a malformed base JSON.

Comparison walks the base's leaves. A base path whose value is a table descends; any other
value — scalar, array, array-of-tables — compares equal or is reported. Only the outermost
path of a mismatch is reported, so a swallowed `[features]` names `features` rather than
`features.goals`. Dotted-path rendering is the base's key names joined by `.`, matching
`erased_base_paths`' output shape.

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
and the parser's diagnostic, both already the operator's own strings on the operator's own
terminal, and no message echoes overlay content beyond a base path name that comes from
this repository's file.

**Out of scope.** An operator who hand-edits `~/.codex/config.toml` — reported, never
rewritten (ADR 0049). A hostile `AGENT_CONFIG_PRIVATE_DIR`: the installer already trusts
that variable for every agent and narrowing it is not this issue. The `[features]` value
carries no privilege, so there is no escalation to bound. `python3` itself is trusted; it
is already invoked for validation today.

## Test plan

All cases live in `install-test.sh`, using the existing overlay harness. Two mechanisms it
already carries do the awkward work: the fixture-repo pattern used by cases 6, 16/17 and
22 (`cp -pR install.sh content agents docs/licenses` into a temp tree, then mutate the
copy) reaches a base the suite may not change, and the PATH-shim pattern of
`run_overlay_case_jq` shadows a tool for one run. Every case asserts a message on the
stream that carries it, not only an exit status.

| # | Case | Asserts | Reddens on revert |
|---|---|---|---|
| T1 | row 9's swallowing overlay | refused; names the overlay and `features`; deployed file unchanged | yes — the reported defect |
| T2 | row 10's `features.goals` override | refused; names `features` | yes |
| T3 | overlay redefines `[features]` | refused; names the overlay, not a temp path; no traceback | yes (R10) |
| T4 | overlay is invalid TOML | refused; names the overlay; carries the parser's diagnostic | yes (R10) |
| T5 | empty overlay | installs; deployed file byte-identical to the base | yes (R3) |
| T6 | bare non-table overlay | refused; names the overlay | yes (R10) |
| T7 | no parser, overlay present, file already deployed | refused; live file byte-identical afterwards; message names the interpreter requirement | yes — row 11 |
| T8 | no parser, no overlay | base installs, exit 0 | regression guard |
| T9 | no parser, overlay present, empty destination | base alone deployed, 0600, exit non-zero | yes |
| T10 | unreadable overlay (`chmod 000`) | run exits; `applied private overlay` absent from stdout; nothing deployed | yes (R8) |
| T11 | refusal over a real prior install, with a stale entry seeded into the destination and its manifest | stale entry pruned **and** `config.toml` retained byte-for-byte | yes (R6 — proves `finish_agent` ran) |
| T12 | refusal under `--agent all` | claude and bob install; Codex's `AGENTS.md`/`skills` install; `config.toml` withheld; `applied private overlay` absent from stdout | yes (R4, R9) |
| T13 | no-overlay run, then a second run | deployed file byte-identical to the base both times; second run reports it unchanged | yes (R3 convergence) |
| T14 | valid additive overlay (new root key + new table) | installs; both present; base's `features` present | regression guard |
| T15 | the JSON nine-case protected-key battery, unchanged | existing assertions pass | R11 |

T11 is what proves R6: today's abort happens before `finish_agent`, so the earlier
install's manifest survives untouched and a bare "the manifest still lists `config.toml`"
assertion passes against the unfixed code. Seeding a stale managed path and asserting it
was pruned in the same run is what shows the manifest was rewritten with the withheld path
still in it.

T5, T8, T13 and T14 pass against the unfixed code in part or whole and are kept as
regression guards; T13's byte-identity clause and T5's do redden, because today's
no-overlay and empty-overlay renderings both differ from the base file.
