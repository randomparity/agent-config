# 0051 — Gate scripts neutralise the ripgrep config

## Status

Accepted (2026-08-10)

## Context

`rg` applies the contents of the file named by `RIPGREP_CONFIG_PATH` as arguments ahead of
the ones its caller passes. Every flag the caller does not itself set is therefore chosen
by whoever set that variable: a developer's personal ripgreprc, a shell profile, a
`.envrc`, or a CI job's environment.

Eight gate scripts and suites in the `verify` chain decide their verdict from a ripgrep
exit status or output. `scripts/check-public-safety.sh` is the one that matters: it is the
secret scanner that keeps credentials, host paths, and tenant names out of a public
repository, and a two-line config file containing `--fixed-strings` makes it miss a planted
`ghp_…` token and exit 0 — the same answer it gives for a clean tree. `--glob !*.md`,
`--max-count 0`, and `--encoding utf-16le` each do the same independently.
`scripts/check-deployed-references.sh` reports a false green on the first two.
`scripts/check-carrier-drift.sh` fails closed but still crashes or fails spuriously, so its
verdict is environment-dependent too. The suites' own assertions invert under
`--invert-match`, which would let a suite certify a gate it never exercised.

The repository has already answered this question twice, differently. Record 0045 chose
`find` over ripgrep for membership enumeration partly because `find` "reads no ignore file
and no `RIPGREP_CONFIG_PATH`, so there are no flags for a later edit to drop".
`scripts/check-shared-standards.sh` unsets the variable at its top, with a comment arguing
that "neutralising each flag in turn loses that race". Issue #101 (PR #131) hardened
`scripts/check-skill-layout.sh` by adding `--no-config` to each of its four calls. The
siblings in the same chain were outside that change's declared surface and were left
exposed, which is the drift this record exists to stop repeating.

## Decision

**A shell source that runs ripgrep neutralises `RIPGREP_CONFIG_PATH` once, at file scope,
with `unset RIPGREP_CONFIG_PATH`.** The defect being fixed is a missing flag at a call
site, so the remedy may not itself be a per-call flag: an `unset` covers every ripgrep the
source runs, including the one added later by someone who never read this record. Per-call
`--no-config` is sound and is not being removed from `check-skill-layout.sh`, but it is no
longer how a new call site is written.

**A guard checks the property, not the idiom.** `scripts/check-ripgrep-config.sh` accepts a
file-scope `unset` or `--no-config` on every invocation, because both leave ripgrep unable
to read a config file and because the alternative — requiring one form — would force an
edit to a file another change owns. Checking the property is also what keeps the guard
honest if a third sound form appears.

**The guard reads shell source, so it strips before it matches.** It removes comments and
quoted spans and joins backslash continuations before looking for a command starting with
`rg`. Two mentions in the tree today are not invocations —
`scripts/claude-settings-hooks-test.sh` embeds `'just ci | rg -n error'` as hook test data,
and `scripts/check-carrier-drift.sh` writes `"could not scan $skills (rg exit $status)"` —
and a guard that flagged either would be answered by an exemption list, which is the thing
that rots. It discovers its inputs with `scripts/list-shell-sources.sh`, as record 0037
requires, so a new script is covered without an edit here.

**The semantic flags are decided per gate, against two different threat models.**
`check-public-safety.sh` takes `--text` and `--encoding none`: its subject is content
someone may be trying to get past it, one NUL byte makes ripgrep skip a file during
traversal, and a `\xFF\xFE` prefix makes it transcode ASCII as UTF-16 and match nothing.
Both were reproduced against this tree.

The drift gates — `check-deployed-references.sh`, `check-carrier-drift.sh`,
`check-shared-standards.sh` — take `--text` and **not** `--encoding none`. Their subject is
documentation this repository authors, where a stray NUL is a plausible accident but a
spoofed byte-order mark is not, and where a file genuinely mis-saved as UTF-16 is scanned
correctly today and would become invisible under `--encoding none`. Under an accident model
that flag points the wrong way.

**Neutralisation is sited in the scripts, not in the `Justfile`.** The gates are invoked
directly by their suites, by the pre-commit and pre-push hooks, and by developers, so a
recipe-level `unset` would protect only one of the paths.

## Consequences

- A source that runs ripgrep now carries a line that looks like boilerplate and reads like
  it too. Its justification is one comment in `check-shared-standards.sh` and this record;
  a reader who deletes it as noise gets a red gate from `check-ripgrep-config.sh` rather
  than a silent regression, which is the whole of the protection.
- The repository now holds two forms of the same neutralisation — `check-skill-layout.sh`
  on `--no-config`, everything else on `unset`. That is a defect surface this record
  accepts rather than closes, because that file is concurrently owned by #127. Converging
  it is tracked separately, and until it happens a reader of the guard learns the rule from
  the guard rather than from the sources agreeing.
- `check-public-safety.sh` under `--encoding none` no longer scans a file genuinely stored
  as UTF-16. No tracked file in this repository is one, and the flag is what removes a
  five-byte bypass of the secret scanner, but the trade is real and would need revisiting
  if the repository ever tracked such a file.
- The guard parses shell with a stripper rather than a parser. It will misread constructs
  the stripper does not model — a here-document containing what looks like an `rg`
  invocation is the obvious one — and the failure is a false positive, which is loud, not a
  false negative. It does not attempt to check that the flags a call passes are the right
  ones; that is what each gate's own suite is for.
- The guard locates a bare `rg`, one behind a keyword or assignment, one behind a wrapper
  (`xargs`, `env`, `timeout`, `sudo`, `nice`, `stdbuf`, `nohup`, `ionice`), one named by
  absolute path, and one after `find -exec`. It does not see a quoted command word
  (`"rg"`), one reached through a variable, an escaped spelling, or anything inside `eval`
  or `bash -c`; those need a shell. It is a backstop for the idiomatic shapes, not a proof
  that no exposed ripgrep exists.
- `--no-config` is accepted per logical line, not per invocation: two calls on one line
  where only the first carries the flag satisfy the guard. Splitting a logical line into
  its commands needs the invocation boundary parsed rather than located. The `unset` form
  has no such gap, which is why it is the one the gates use.
- A `unset RIPGREP_CONFIG_PATH` at column 0 counts for the calls below it. Column 0 is a
  legibility rule and not a scope proof — the scanner does not track blocks, so an `unset`
  inside a function body or an `if false` branch still counts. Confirming it executes needs
  a shell; what the rule buys is that the statement is greppable in the file it governs.
- `Justfile`'s `hooks` recipe still runs `rg -qxF` to decide whether an existing pre-push
  hook is the managed one, and a steered config makes it overwrite a foreign hook. It is
  not a gate and not in the `verify` chain, so the guard does not see it. Tracked
  separately.
- `check-public-safety.sh` names its tracked files explicitly in addition to walking the
  tree, because `.gitignore` and `.ignore` apply to tracked files too: `git add -f` on an
  ignored path produced a file that ships to every clone and that the walk never opened,
  and the gate answered 0. `--no-ignore` would have closed it by also scanning ignored
  files that are *untracked* and therefore never ship — `CLAUDE.local.md` among them —
  which fails the gate on the host-specific content that file exists to hold. Naming the
  tracked files covers what ships under every ignore mechanism, not `.gitignore` alone.
- The other gates' scan sets are unchanged: they still walk with ignore rules applied.
  Their subject is the repository's own content rather than credential exposure, and a
  tracked-but-ignored file is visible to them through the membership and layout manifests.
  Removing the config as an input does not make any of those scans total.

## Considered & rejected

- **Add `--no-config` to every call, as issue #119's acceptance criteria and PR #131 both
  say.** The obvious answer and the one the issue asks for. Rejected because it reproduces
  the failure mode: the exposure exists precisely because a call site was added — or left —
  without the flag, and N flags across N files is N chances to miss one. The guard would
  then have to verify a flag on every invocation, which needs the invocation boundary
  parsed rather than merely located, and gets harder with each continuation and pipeline.
  The `unset` reduces the guard's question to one it can answer from the file.
- **`unset RIPGREP_CONFIG_PATH` in the `verify` recipe, or in `set shell` for the
  `Justfile`.** One edit, covers every gate at once. Rejected because it covers only runs
  that go through `just`: the suites run the gates directly, `scripts/pre-push-hook` and
  the prek pre-commit hook reach some of them by path, and a developer running
  `./scripts/check-public-safety.sh` gets nothing. A control that protects the CI path and
  not the local one protects the path that was not at risk.
- **`env -u RIPGREP_CONFIG_PATH rg …` at each call, or a `rg()` shell wrapper function.**
  A wrapper is the tidiest form and covers every call in the file. Rejected because it puts
  a function named after a program between the reader and what runs, in scripts whose
  entire job is being obviously correct, and because `env -u` is per-call again with worse
  ergonomics. The `unset` gets the same coverage with no indirection.
- **A shared `scripts/lib/ripgrep.sh` the gates source, holding one hardened invocation.**
  The answer to "duplicated flag lists across N scripts is how this drift happened".
  Rejected on what is actually duplicated: after this change it is one `unset` per file, not
  a flag list, and the semantic flags legitimately differ per gate — `--encoding none`
  belongs to the secret scanner and to no other. A shared invocation would either take
  every difference as a parameter, which is the flag list again with more indirection, or
  flatten differences this record deliberately keeps. The repository also has no `scripts/`
  library today, and introducing one to hold a single statement is the abstraction the
  third repetition has not yet earned.
- **No guard; fix the eight sources and rely on review.** Rejected on the evidence in the
  Context: this is the second time the question has been answered in this repository and
  the first fix did not reach the siblings. Review is what let that happen, and the failure
  is silent — a steered secret scanner prints nothing and exits 0.
- **Have the guard run each gate under a hostile config and compare verdicts, instead of
  reading source.** Strictly better evidence: it tests the property rather than a proxy for
  it. Rejected as the guard because it needs a known-answer fixture per gate, so a newly
  added gate — the case the guard exists for — would not be covered until someone wrote its
  fixture, which is the omission the guard is supposed to detect. It is the right shape for
  a per-gate suite, and that is where this change puts it: the behavioural tests live in
  each gate's own `-test.sh`, and the guard covers the sources no suite exercises.
- **Fix only `check-public-safety.sh`, the one with a demonstrated false green.** Rejected:
  `check-deployed-references.sh` has one too, and a gate that fails closed under steering
  still has a verdict that depends on a developer's home directory. Leaving the siblings is
  how this issue was written in the first place.
- **Do nothing.** No incident has occurred, and the deliberate case needs an attacker who
  can already set an environment variable in the build. Rejected on the accidental case
  being enough on its own: `--fixed-strings` and `-i` are ordinary things to put in a
  personal ripgreprc, one of them silently disables the secret scanner on a public
  repository, and nothing in the output says so.
