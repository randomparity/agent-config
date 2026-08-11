# 0057 — A Codex overlay may not erase a base value

## Status

Accepted (2026-08-10)

## Context

`install.sh` builds `~/.codex/config.toml` by concatenation rather than merge:
`merge_toml_config` emits the base's root settings, the overlay's root settings, the
base's tables, then the overlay's tables, and never compares the two. Issue #123 reports
this as the ADR 0043 gap — a private overlay able to erase a value the public base defines
— and asks for a comparable guarantee.

The gap is real, and worse than the issue describes. The split is done by `awk` on
`/^[[:space:]]*\[/`, which is not a TOML lexer, so a line inside a multi-line string
counts as a table header. This overlay is legal TOML, names nothing the base defines, and
is accepted today:

```toml
notes = """
[not a table]
"""

[sandbox]
mode = "danger-full-access"
```

`notes = """` is emitted as a root setting, the rest of the overlay is emitted after the
base's tables, and the string the operator opened swallows everything between. Measured:
the deployed file parses cleanly as
`{'notes': '\n[features]\ngoals = true\n\n[not a table]\n', 'sandbox': {…}}`. The base's
`features` table is gone, `install.sh` exits 0, and the summary reads
`6 added` beneath `install: applied private overlay`. Substituting
`features.goals = false` for the `[sandbox]` table turns the same shape into a silent
*override* of the base value.

So the TOML path has ADR 0043's defect — an overlay silently erasing what the base defines
— reachable without naming a base path at all. There is a second exposure behind it.
`validate_toml` is the only thing standing between a mangled concatenation and the
operator's disk, and it runs only where `python3` can `import tomllib`. Stock macOS ships
Python 3.9; `tomllib` arrived in 3.11. Measured on such a host with an overlay setting
`goals = false`: the concatenated, unparseable document is deployed over the operator's
live `config.toml`, `install.sh` exits 0, the summary reads `1 updated`, and Codex then
loads no configuration at all. The previous file is under
`.agent-config-backups/<timestamp>/drift/`, and nothing says so.

`agents/codex/shared/config.base.toml` is two lines — one table, one boolean. ADR 0043's
selector takes the base's non-empty arrays and objects, so ported here it yields
`features`, and it would refuse the swallowing overlay above. What it would not refuse is
the override: `features` is still an object afterwards, holding a `goals` that is now
`false`. 0043 can leave scalars alone because jq's `*` cannot drop a base key; a
concatenation reconciles nothing, so the rule has to cover every value the base defines
rather than the subtree shapes one merge tool happens to replace.

## Decision

**Every value the base defines must survive into the merged document unchanged. The
merged result is parsed and compared against the parsed base before it is deployed; an
overlay that erased or changed a base value, or that produced a document no parser
accepts, is refused on ADR 0049's terms. Where no parser is available, no overlay is
applied.**

Four things are normative.

1. **The rule is stated over the merged document's parse, not over the overlay's text.**
   Every *leaf* the base defines must be present in the merged result with an equal value
   and an equal type; a base table is descended when the merged document holds a table
   there, and reported by its own path when it does not. Stated over leaves rather than
   over every path, an overlay adding `[features.sub]` would otherwise make `features`
   unequal and be refused for extending the base — which is the thing an overlay is for.
   This is ADR 0043's rule with its selector widened to every base value, because the two
   merges fail differently: jq's `*` can only replace a path the overlay names, so 0043
   could protect arrays and objects and leave scalars to `*`'s own key-preserving
   behaviour; concatenation reconciles nothing and can drop or change a scalar the overlay
   never mentions. Checking the parse rather than the text is what makes the guarantee hold
   against the `awk` splitter, whose mangling is invisible to any check over names.

2. **No parser, no overlay.** The guarantee *is* a parse, so a host that cannot parse
   cannot have it, and the measured alternative is a silently destroyed `config.toml`. The
   overlay is refused by path, naming the interpreter requirement rather than blaming the
   file. A host with no overlay is unaffected, and one whose destination is empty gets the
   base — emitted verbatim, so it needs no parser to be trustworthy. A parser-less host
   that *already* has a `config.toml` gets neither: rule 4 retains it untouched, so it
   stays at whatever vintage it had while the rest of the Codex tree keeps updating. That
   is ADR 0049's stale-pairing residual, and here it lasts until the interpreter is
   upgraded rather than until the overlay is fixed.

3. **With no overlay, nothing is split.** The splitter exists to hoist the overlay's root
   keys above the base's table headers; with no overlay there is nothing to hoist, so the
   base is copied verbatim. The empty-destination fill of ADR 0049 rule 4 uses the same
   copy. One rendering, byte-identical to the base file, so a no-overlay run converges,
   the fill converges with it, and the refusal report can recognise "the base alone" by
   comparing bytes.

4. **A TOML refusal is a refusal, not an error — and nothing else returns.** It takes every
   rule ADR 0049 states over the destination path it feeds: the merged temporary file is
   removed, the withheld path stays in the manifest and is not pruned, a destination
   holding no file gets the base alone, the deployed state is reported, the run continues
   to the remaining agents, and it exits non-zero having named the withheld path. ADR 0049
   rule 1 applies with its full force: testing a function's status at the call site
   suppresses `set -e` for its whole body, so every fallible command inside the merge is
   individually guarded and any failure that is not a refusal exits. A comparison that did
   not run must never be read as one that found nothing — the same trap `erased_base_paths`
   carries, and `awk` failing on an unreadable overlay is the way it is reached here.

5. **The overlay is parsed on its own before the hoist reads it.** `awk` is locale-sensitive
   where `tomllib` is not: the awk on macOS aborts with `towc: multibyte conversion failure`
   on a byte sequence invalid in the current locale and exits non-zero, so a latin-1 overlay
   never reached the parser there and took the whole run down as an unreadable file, while
   the same file on Linux reached `tomllib` and got a verdict. A guarantee that changes
   shape with the platform's awk is not one. This is ADR 0052's lesson pointed the other
   way: there the check had to be byte-level because it shared jq with the merge; here it
   has to run *ahead* of a reader that cannot express the answer. It also sharpens the two
   verdicts that follow — everything reaching the merge parses on its own, so a merged
   document that fails to parse, or that lost a base value, is the hoist's doing and is
   reported as that rather than as a fault in the operator's file.

## Consequences

`install: applied private overlay` prints after the result is accepted rather than before
it is checked, so it stops appearing on runs that go on to fail.

An operator whose `python3` predates 3.11 stops receiving their Codex overlay, and the run
exits non-zero on every invocation until they install one that can `import tomllib`. A
wrapper or scheduled job that reads that status is red until then. This is a withdrawal of
behaviour that appeared to work, and it is the sharpest cost here: the file being refused
is sound, and the message says so. It is taken because the same host is the one measured
replacing its own `config.toml` with an unparseable file at exit 0, and because a
guarantee that silently does not apply is the thing ADR 0052 already refused to ship.

The no-overlay rendering loses its leading blank line, so the first run after this change
reports `1 updated` for `config.toml` and takes a drift backup of a file the installer
itself wrote. One run, then it converges.

The Codex overlay becomes add-only, which is stricter than the JSON contract: ADR 0043
lets an overlay override a base scalar, and this does not. Two of the three routes to
`features.goals` — redefining `[features]`, and a `features.goals` root key — were already
duplicate declarations no TOML parser accepts. The third worked, and it is the mangling
this record closes; an operator relying on it was relying on the defect. ADR 0043 leaves
the same limit on `hooks.PreToolUse` and #118 tracks the JSON half. For Codex the pressure
is lower, and if it bites it bites as a request to change the public base.

An overlay that is legal TOML on its own can still be refused, when the splitter's hoist
moves a base table inside a multi-line string the overlay opened at its root. That file is
not at fault, so the verdict says the merge split it and names the remedy — put the value
in a table — rather than accusing the overlay of erasing anything.

The refusal's deployed-state report is weaker than the JSON one. ADR 0049 rule 5 promises
a verdict of base-alone, carries-every-protected-path, or missing-some; without a parser —
the case rule 2 exists for — only base-alone is decidable, by byte comparison. The TOML
report says which of symlink, directory, absent, base-alone or differs, and claims nothing
about a differing file's contents.

## Considered & rejected

**Do nothing.** The issue itself calls the gap "not a regression". But the measured
behaviour is a legal overlay silently deleting the base's table at exit 0, and on a
supported host a legal overlay silently replacing the whole file with an unparseable one.
Neither is discoverable from the installer's output, and the second breaks Codex outright.

**Port ADR 0043's protected set unchanged** — the base's non-empty arrays and objects.
Ported here it yields `features` and it does refuse the swallowing overlay, so this is the
closest alternative rather than an empty one. It does not refuse the override: `features`
survives as an object holding a changed `goals`, and it would not cover any scalar a future
base adds at the root. The selector is shaped to jq's failure mode — replacing a path the
overlay named — and concatenation's is losing one it did not.

**Refuse by name: compare the table headers and root keys the two files declare, without a
parser.** This was the first decision here and it is wrong. It is defeated by the measured
overlay above, which names nothing the base defines and erases it anyway, and by a
`features.goals` root key, whose first segment a name reader would have to know to split.
It is also a false-refusal generator in the other direction, since a `key = value` line
inside a multi-line string reads as a declaration. A line reader cannot decide a question
about a parse.

**Record concatenation as the contract and pin the duplicate-key result with a test** —
issue #123's second option. There is no result to pin: TOML has no last-wins rule, so a
duplicate is a parse error rather than a resolution, and on a host without `tomllib` the
behaviour to pin is "deploy the broken file". Recording that documents the defect instead
of closing it.

**Drop the splitter and emit the overlay verbatim, then the base.** It removes the mangling
at its source and is genuinely simpler. It breaks on the next base that grows a root key,
which would land inside the overlay's last table — a silent misplacement of a public value
by a private file, the same class of defect one layer down, and invisible until it
happened. The check in rule 1 catches that too, so the splitter is contained rather than
trusted; removing it is a change worth making on its own evidence, not folded in here.

**Merge properly with a TOML library.** Same parser requirement as rule 2, and a real merge
must either round-trip the operator's comments and formatting or silently discard them.
It is the option that would give overrides back, which is a larger question than the defect
here — it changes what an overlay may do, where this record changes what it may break.

**Keep validation optional and name the drift backup when it is skipped.** It keeps the
overlay working on an old interpreter and closes the silence about recovery. It does not
close the loss: the operator is told where a backup is, after their Codex configuration
has been replaced by a file that does not parse, by a run that exited 0. A message about a
backup is not a control over what gets written.
