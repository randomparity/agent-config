# 0050 — Deployed Content Is UTF-8 Text, and the Gate Enforces It Rather Than Guessing

## Status

Accepted (2026-08-10)

## Context

`scripts/check-skill-layout.sh` reads the bytes of every file the installer delivers,
to enforce ADR 0004's deployment rule: deployed content must resolve its own assets
rather than name an installed client's config root. It scans `content/skills` (minus
the `testdata` entries `stage_skills` drops, ADR 0028 superseding ADR 0025) plus
`content/languages` and `content/references`, which `install_common_content` copies
verbatim to all three agents.

Only one file in that set had a declared encoding. `validate_utf8` checks each
`SKILL.md`, because a skill's frontmatter is parsed and a malformed byte there is a
parse failure. Everything else the scan walks — `content/languages`,
`content/references`, and every non-`SKILL.md` file under `content/skills` — had no
encoding rule at all.

A pattern rule cannot answer correctly about a file whose encoding it does not know,
and issue #101 is what that cost. ripgrep's default `--encoding auto` sniffs a leading
byte-order mark and transcodes on the strength of two bytes, so a UTF-8 file that
merely *began* `\xFF\xFE` was decoded as UTF-16 and the forbidden reference inside it
came out as mojibake matching nothing — the gate printed ok over a real violation. PR
#131 fixed that by passing `--encoding none` and reading raw bytes.

That fix was a trade, and the trade is this record's subject. Reading raw bytes is
right for the reachable case (a UTF-8 file with a BOM-shaped prefix) and wrong for its
mirror (a file under those roots that genuinely is UTF-16, which was transcoded and
scanned before and is opaque afterwards). `--text`, added in the same change so a
single NUL byte could not make rg skip a file as binary, carries the same shape of
trade. Neither flag can be set correctly, because the rule has no way to know which
kind of file it is holding. The flag is asking an encoding question the gate has no
authority to answer.

No such file exists today: every regular file under the three roots reads as `us-ascii`
or `utf-8`. This record closes the gap before it opens rather than fixing a live defect.

## Decision

**The deployed content payload is UTF-8 text.** Every regular file the deployment scan
walks — `content/languages`, `content/references`, and the non-`SKILL.md` payload under
`content/skills`, honouring the `testdata` exclusion — must be well-formed UTF-8 and
must contain no NUL byte. The gate enforces it, and enforces it *before* the pattern
rules run, so that by the time a pattern rule reads a file there is no unknown encoding
left for a flag to be wrong about.

The alternative contract — declare that the gate scans bytes and stop there — was
rejected. These trees install verbatim into every user's agent directories, so their
encoding is a property of what this repository *delivers*, not an implementation detail
of one scanner. Declaring "we read bytes" leaves the delivered artifact's encoding
unspecified and pushes the same unanswerable question onto the next tool that reads it.

**Two rules, because well-formedness alone does not decide it.**

- The UTF-8 rule reuses `validate_utf8`'s acceptor verbatim. That grammar was
  differential-tested against a strict decoder and rejects overlong encodings,
  surrogates, and scalars above U+10FFFF; a second copy written to a different shape is
  how two readings of the same question drift apart. It catches a UTF-16 file carrying a
  BOM, since `\xFF` and `\xFE` appear in no well-formed sequence.
- The NUL rule catches what the grammar cannot. UTF-16LE text drawn from ASCII is a run
  of bytes in `[\x00-\x7F]`, so it satisfies the acceptor exactly as written — and
  ripgrep would not have transcoded it either, because BOM sniffing needs a BOM. That
  file is *unscannable* rather than misread, and no reading of it is safe. U+0000 is a
  well-formed scalar and a legitimate thing for a binary to hold, but this payload is
  prose, code and configuration, so a NUL in it means the delivery is not text.

  Stated exactly, because the Consequences below depend on the bound: the NUL rule
  reaches every UTF-16 file holding a code unit with a zero byte, which is every UTF-16
  document containing a space, a newline, or any other ASCII character. It is not a
  decision procedure for UTF-16 in general, and this record does not claim one.

**`--text` and `--encoding none` stay, and stop being a trade.** They are now what the
encoding rules themselves require: a NUL byte is unmatchable without `--text` (ripgrep
refuses the pattern and exits 2, saying so), and a BOM is transcoded away without
`--encoding none`, which would hide a UTF-16 file from both encoding rules at once. One
flag list serves all four rules, so the encoding rules and the pattern rules see the
same bytes over the same file set by construction rather than by two lists agreeing.

**The contract is scoped to issue #127's payload: the three `content/` roots.**
`agents/*/shared` is not covered, and the config-root rules' reason for skipping it does
not transfer — that reason is about which *patterns* may legitimately appear in an
agent's own instructions, and says nothing about which *bytes* a file may be made of.
`install_managed_path` copies those ten files verbatim into every user's tree, so they
are delivery by the same argument as the three roots above; the exclusion here is scope,
not principle, and the Consequences record it as unguarded. `testdata` entries under
`content/skills` are excluded, exactly as `stage_skills` excludes them (ADR 0028,
superseding ADR 0025's stale inventory) — a file that is never deployed cannot violate a
delivery rule, and fixtures for these very gates have to be able to hold bytes the gates
reject. That exclusion stays scoped to
`content/skills`, the one root the installer filters: `content/languages` and
`content/references` deploy verbatim, so a `testdata` entry under either really does
ship and is held to the contract.

`install_common_content` delivers one further path, `docs/licenses/superpowers.LICENSE`,
and it is outside the contract for the reason ADR 0028 left it outside the deployment
scan: it is a single vendored file rather than an author-extensible tree, and a gate that
invites editing a verbatim license is worse than what it would catch. The contract covers
the trees a contributor adds files to.

## Consequences

- A content author cannot add a non-UTF-8 or NUL-carrying file under the three roots.
  Nothing needs one today, and a genuine future need — a binary asset a skill has to
  ship — is a decision to record here, not a flag to flip. The gate names the file and,
  for a malformed sequence, the line, so the message is actionable rather than a
  verdict.
- **A stray `.DS_Store` under `content/languages` or `content/references` now fails
  `just verify`, and that is intended.** Those are the two roots `validate_portable_tree`
  does not cover, so the NUL rule is the first to guard them; under `content/skills` the
  same file already failed on the portable-ASCII path rule. `install_common_content`
  copies both roots with `cp -pR`, so the file really would be delivered into every
  user's tree. It is reachable in normal use — Finder writes one into any directory a
  developer opens, macOS is a CI leg and this repository's bash floor, and the name is
  gitignored so `git status` offers the reader no lead. `.DS_Store` is the example, not
  the class: a vim swap file (`.python.md.swp`, since vim's default `directory` starts
  with `.`), `.orig`/`.rej` patch residue, and any other tool-dropped artifact under
  those two roots read the same way, and a swap file makes `just verify` red for the
  length of an editing session. Narrowing the traversal is not the answer — that
  reopens the scanned-narrower-than-delivered hole this record exists to close — so the
  answer is a message that names the remedy. Both encoding rules carry the same one, and
  they have to: which rule fires is decided by whether the file happens to hold a byte
  outside the acceptor, so a UTF-16 document with a BOM fails the UTF-8 rule and the
  same document without one fails the NUL rule. It offers conversion first, because the
  other way to reach either rule is an author's own document written in UTF-16, for whom
  "delete it" is the wrong instruction. The required `content/skills/<name>/SKILL.md` is the
  one file that gets no remedy clause: it is required, so its bytes are the only thing
  that can change, and "delete it" would send the next run to `required regular file is
  missing`. The qualifier is load-bearing — a *nested* `SKILL.md`, say under a skill's
  `assets/`, is ordinary payload that nothing requires, and it gets the remedy from both
  rules.

  The two rules reach that exemption differently, and neither states it twice. The NUL
  rule tests the required path explicitly, because a `SKILL.md` carrying a NUL satisfies
  the acceptor (U+0000 is a well-formed scalar) and so lands there rather than on the
  UTF-8 rule. The UTF-8 rule needs no test: `validate_frontmatter` runs before the
  payload scan and passes no remedy, so a required `SKILL.md` with a malformed sequence
  has already failed by the time the payload rule could add one. That is an ordering
  property rather than a check, which is why the NUL rule cannot borrow it. The prek
  hook runs `commit-check`, not `skills-check` (ADR 0039), so a commit is unaffected;
  this is the local full run and CI.
- **`agents/*/shared` is delivered and unguarded, and this record does not close it.**
  Ten files install verbatim there, including a shell script and three JSON/TOML
  configs, and a NUL byte planted in any of them passes every gate today. Widening the
  rule is outside issue #127, whose subject is the three `content/` roots, and would
  mean changing the scan roots rather than adding a rule. Named here rather than left
  for a reader to discover, on the same terms as the portability gap below.
- ADR 0028's coordination inventory still reads correctly, and this record says so
  rather than leaving the claim to decay, which is the obligation 0028 exists to impose.
  Its row for the deployment gates — "skip matches only below `content/skills`" — is
  unchanged in substance: `scan_deployed_payload` applies the exclusion to four rules
  instead of two, and applies it in one place rather than at each call site, but the
  boundary it draws is the same one, and it still stops at `content/skills`. No row
  moves, and no site is added or removed.
- The traversal flags that decide *which* files the contract covers — `--hidden` and
  `--no-ignore` — are pinned by fixtures too, though they predate this change. The
  contract is only as wide as the traversal carrying it, and the live tree holds no
  dot-prefixed or ignored file under the three roots, so a fixture is the only place the
  property can be shown at all.
- **What the pair actually decides, and the residual worth naming.** The two rules
  together prove a file is well-formed UTF-8 and free of NUL bytes. That is not the same
  as proving it *is* UTF-8: any 7-bit-clean encoding clears both by construction, UTF-7
  being the named instance, since a UTF-7 file is pure ASCII. No evasion has been
  demonstrated end to end — a UTF-7 encoding of a forbidden reference leaves the ASCII
  path literal, so the pattern rules still fire on it — and accidental UTF-7 in a
  Markdown tree is not a thing that happens. This is a bound on the claim, not an
  exposure.

  The residual worth naming is the UTF-16 one. A UTF-16 file whose every code unit has
  both bytes in `[\x01-\x7F]` satisfies the acceptor and holds no NUL, so it passes both
  rules and the pattern rules read it as mojibake. The bytes `30 04 31 04 32 04`
  (Cyrillic) are such a file, and the gate reports ok on it. That bound is deliberately
  narrower than "no ASCII anywhere": it also excludes the Latin-1 supplement (`é` is
  `E9 00`) and every scalar U+xx00, each of which reintroduces a zero byte. The reachable
  instance is a single-line non-ASCII document with no trailing newline; anything longer
  acquires a newline and fails. Closing it would mean a byte-frequency heuristic — a
  guess about encoding, which is the thing this record exists to retire. Recorded rather
  than fixed, and rather than left implied by a completeness claim of the kind this
  record set out to stop making.
- `--encoding none` and `--text` are load-bearing in a way that is now directly pinned.
  Removing either turns `scripts/check-skill-layout-test.sh` red through the encoding
  cases, and removing `--text` does so loudly: ripgrep exits 2 rather than quietly
  matching less. Before this change both flags were pinned only through the
  config-root rules, where a weakened flag under-reports silently.
- The two fixtures that pinned those flags now fail on the encoding rule instead of the
  config-root rule, because the encoding rule runs first. Each keeps a forbidden
  reference in its body, so reverting the encoding rule alone leaves them failing on the
  config-root message rather than passing.
- `scan_config_roots` is renamed `run_content_scan` and gains a caller,
  `scan_deployed_payload`, which owns the two-call traversal of the delivered set. The
  four rules previously repeated that traversal at each call site; a fifth and sixth
  would have repeated it twice more, and a traversal that drifts between rules is a
  scan set narrower than the delivery set — the failure mode `--hidden --no-ignore`
  already exists to prevent.
- Gate messages naming a scanned file are now repo-relative. They were absolute, so a
  finding printed the checkout path into CI logs of a public repository; the paths this
  gate prints elsewhere were already relative, and one convention is what
  `read_scan_hit` exists to hold.
- The payload rule is deliberately *not* folded into `validate_frontmatter`. A skill's
  frontmatter contract is per-file and structural — four lines, a name matching its
  directory, a JSON description — and is checked while walking skill directories. The
  payload's encoding contract is a property of the delivered file set and is checked
  over the same traversal the delivery rules use. They share exactly one thing, the
  acceptor, and sharing more would mean one rule's file set deciding the other's.
- Issue #106 is adding a membership gate over the same wholesale-installed trees. The
  two are complements — membership decides which files ship, this record decides what
  bytes they may contain — and neither infers its file set from the other.
- `content/languages` and `content/references` still have no portability check
  (`validate_portable_tree` covers `content/skills` and the project-review examples
  only), so a symlink, a FIFO, or a non-ASCII path component under either is unguarded.
  Out of scope here and noted rather than fixed: it is a membership question, which is
  #106's subject.

## Considered & rejected

- **Declare that the gate scans bytes and leave the payload's encoding unspecified.**
  Coherent, and cheaper — a comment rather than a rule. Rejected because these trees are
  installed verbatim into users' agent directories: their encoding is a delivery
  guarantee, and the unanswerable question would simply move to the next tool that reads
  them. It also leaves criterion 2 of issue #127 unmet by construction, since a UTF-16
  delivery would still pass unscanned.
- **Extend `validate_frontmatter` to walk the whole payload.** Rejected as conflating two
  contracts with different subjects and different file sets, per the consequence above.
  The acceptor is shared; the traversal is not.
- **Enforce the UTF-8 grammar only, without the NUL rule.** Rejected because it does not
  meet the requirement it was written for. A BOM-less UTF-16LE file of ASCII text
  satisfies the grammar byte-for-byte, so the gate would report ok on a delivery no
  pattern rule can read — the exact state this record set out to end. Verified against
  ripgrep 14.1.1 rather than reasoned about. The NUL rule closes that class; the
  residual above is what it does not close.
- **Scope the encoding rules to the git-tracked set,** leaving the pattern rules'
  traversal alone. It would drop the entire tool-artifact false positive above at a
  stroke — a swap file, a `.DS_Store` and patch residue are all untracked, and an
  untracked non-UTF-8 file is delivered to nobody but its own author, so the delivery
  argument that justifies `--no-ignore` for the pattern rules is genuinely weaker for
  these two. Rejected because it splits the file set the four rules share, which is the
  property the whole design rests on: one flag list, one traversal, so the set the
  encoding rules cover cannot drift from the set the deployment rules cover. Buying back
  some editing-session friction with the drift this record exists to prevent is the wrong
  trade, and a two-traversal gate is a second thing to keep in agreement forever.
- **Forbid `\x00` by narrowing the acceptor's first alternative to `[\x01-\x7F]`.** One
  character, and it would fold both rules into one pattern. Rejected because that
  acceptor is `SKILL.md`'s too, and it is a UTF-8 grammar — U+0000 is a well-formed
  scalar, and a grammar that quietly rejects it is no longer the thing it was
  differential-tested to be. Two rules with two messages also tell an author which
  problem they have.
- **Run the encoding rules after the pattern rules,** so the two existing flag fixtures
  keep failing on their original message. Rejected as ordering the gate around its test
  suite: the encoding rule is the pattern rules' precondition, and a verdict about a file
  whose encoding is unknown is the thing this record removes.
- **Validate each file with its own `validate_utf8` call, in a loop over the tree.**
  Rejected for reading the delivery set a second way. `scan_deployed_payload` reuses the
  traversal the delivery rules already use — same globs, same `--hidden --no-ignore`,
  same roots — so the set the encoding rule covers cannot drift from the set the
  deployment rules cover. It also costs one ripgrep process per rule rather than one per
  file. `validate_utf8` is still called, on the one file the scan names, to recover the
  line number `-l` does not report.
