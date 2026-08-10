# 0045 — Installed trees declare their membership

## Status

Accepted (2026-08-10)

## Context

`install.sh` delivers most of its payload one named file at a time, but `install_managed_path`
ends in `cp -pR`, so a call whose source is a directory ships that whole subtree into the
agent's configuration directory verbatim. Four call sites pass a directory:
`agents/bob/shared/rules` for Bob, `content/languages` and `content/references` for all three
agents through `install_common_content`, and the staged skills tree.

Nothing counts what is in those directories. `scripts/check-shared-standards.sh` names one
file inside the rules tree and asserts it holds exactly one shared block; a file beside it
carrying no marker is invisible to that gate and installs anyway.
`scripts/check-deployed-references.sh` scans the same trees for what a deployed file may
*say* — its comment even records that the rules tree "is copied whole" — and never asks how
many files are in one. Record 0041 disclosed the residual in as many words: the gate narrows
the ungated surface, it does not close it.

So adding a file to one of these directories deploys it to every user's global agent
configuration, and the only thing standing between that and review is that somebody notices.
That is the class of change that most wants a machine check, because the file need not be
edited by anyone afterwards to keep having effect.

The skills tree is the exception, though a weaker one than it first looks.
`scripts/check-skill-layout.sh` requires every *top-level* child of `content/skills` to be a
skill directory, and separately walks the whole tree forbidding symlinks and non-regular
files and constraining every path component. What it never asks is which files may exist
inside a skill directory. It is also the one tree whose growth is the routine act the
repository exists for.

## Decision

**The gate covers the wholesale-installed trees whose membership is fixed —
`agents/bob/shared/rules`, `content/languages` and `content/references` — and not just the
one tree the issue names.** All three reach a user through the same `cp -pR`, and the two
content trees reach three agents rather than one. `content/skills` and the loose
`docs/licenses/superpowers.LICENSE` stay out.

**The gate is its own script.** `scripts/check-deployed-membership.sh` holds the manifest,
`scripts/check-deployed-membership-test.sh` is its suite, and a `membership-check` recipe puts
it in the `verify` chain. The manifest is a literal inside the script, following
`check-shared-standards.sh` rather than the separate data file
`scripts/reserved-skill-names.txt` uses, because it is short and its meaning is unreadable
apart from the comparison that consumes it.

**Membership is enumerated with `find`, not ripgrep.** Every entry under a declared tree that
is not a directory is a member — symlinks and dot-prefixed files included, because `cp -pR`
copies all of them. `find` is total by construction: it reads no ignore file and no
`RIPGREP_CONFIG_PATH`, so there are no flags for a later edit to drop.

**Both directions of disagreement are findings, exit 1; only an inability to compare is a
fault, exit 2.** A declared file that is absent and an undeclared file that is present are the
two answers the comparison exists to produce. Faults are the cases where there is no
comparison to make: a missing tree, an unusable repository root, a bad argument, or a manifest
entry under no declared tree. That rule also explains `check-shared-standards.sh` exiting 2
when a manifested block site is missing, which stays as it is — there the file is an input to
a byte comparison that then cannot run, not an answer.

## Consequences

- Adding a file to one of the three trees is now two edits: the file, and the manifest line
  that admits it. What the gate proves is that an undeclared file cannot land silently; it
  does not make the manifest line more conspicuous in a diff than the file addition beside it.
- A branch that adds such a file without the manifest line fails `just verify` and CI. In a
  parallel wave this can turn a sibling branch red after this one merges; the remedy is the
  one-line manifest edit, and the alternative is the deployment nobody reviewed.
- A file added *inside* an existing `content/skills` skill directory still installs into every
  user's configuration with no membership check. That residual is left open deliberately, on
  the grounds above, and it is the larger tree.
- Untracked debris under one of the three trees — an editor swap file, a `*.orig` from a
  merge, a scratch draft — now turns a local `just verify` red, because the enumeration reads
  no ignore rules. Neither gating environment sees it: `scripts/verify-push.sh` rehearses in a
  detached worktree of the pushed objects, and CI runs on a clean checkout. The remedy is to
  keep scratch work outside the three trees.
- Ignore rules are not merely a local concern, which is why the enumeration must defeat them
  rather than merely tolerate them: ripgrep applies `.gitignore` to *tracked* files too, so a
  tracked file the repository also ignores is shipped by `cp -pR` and skipped by a default
  ripgrep scan, in CI as much as locally.
- A new wholesale-installed tree added to `install.sh` is not covered until it is added to
  this manifest, and nothing detects that omission. The manifest is source, so this gate
  cannot defend against edits to itself; a comment at each `install.sh` call site names the
  manifest, which is the whole of the coupling. Making that detectable is tracked separately.
- The repository now holds two lists of installer-copied roots — this manifest's trees and
  `check-deployed-references.sh`'s `scan_paths` — that mean different things and nothing
  compares. See the first rejected alternative for why they are not one list.
- The gate proves the tree matches the list. It says nothing about whether a listed file
  should be deployed at all, or what it contains.
- A file name containing a newline splits into two lines and reports as two unexpected
  members. The verdict is still red, which is the property that matters.

## Considered & rejected

- **Site the check in `scripts/check-deployed-references.sh`, whose `scan_paths` already
  claims to be "every *directory* root the installer copies".** The closest existing home, and
  rejected on two grounds. Its subject is what a deployed file may *say*, not which files
  exist, so the root list is a scan surface rather than a membership claim — and it is
  demonstrably a superset used that way, since it also scans `agents/claude/shared`,
  `agents/codex/shared` and `content/skills`, from which the installer takes named files or a
  filtered copy rather than the whole directory. Reusing the array would mean gating
  membership of trees whose membership does not matter; scoping a subset out of it would put
  two meanings in one list. The cost of the split is a Consequences bullet above.
- **Gate only `agents/bob/shared/rules`, as the issue frames it.** Rejected: the same `cp -pR`
  ships `content/languages` and `content/references` to three agents instead of one, so this
  closes the narrower hole and leaves the wider one, having declared the defect fixed.
- **Extend `scripts/check-shared-standards.sh` and its manifest.** Rejected: that gate's
  subject is the identity of one block across the files that carry it, and its manifest means
  "these files must each hold a block". A second list meaning "these files may exist" would
  leave a reader of either guessing which question it answers, and two of the three trees are
  not scan roots there.
- **Discover the covered trees instead of enumerating them**, as record 0037 did for shell
  sources when it replaced an enumeration whose omissions had no signal. Rejected on the
  difference between the two sources: 0037 discovers from Git, which is an index of what
  exists, whereas discovering these trees means deciding which `install_managed_path` calls
  have a directory source — and the sources are shell expressions, several of them variables
  holding temporary files. That is parsing shell to find out, and a heuristic that misreads
  one call site fails silently in the same direction the manifest does. A list file that
  `install.sh` itself read would remove the guess, but that changes what the installer
  consumes, which this change deliberately does not touch. The residual is recorded above and
  tracked as follow-up work.
- **Enumerate with `rg --files --hidden --no-ignore`.** Rejected: it reaches the same set only
  as long as both flags stay put and `RIPGREP_CONFIG_PATH` is neutralised — three things
  record 0041's gate has to remember and test — where `find` needs none of them.
- **Treat an unexpected member as a fault (exit 2).** Rejected: it is the finding the gate was
  written to produce, and reporting it as "could not run" would tell a reader the opposite of
  what happened.
- **Generate the manifest from the tree, or from `git ls-files`.** Rejected: a list derived
  from what is there agrees with whatever is there, so it would pass on exactly the change it
  exists to catch — and `git ls-files` would miss the ignored files `cp -pR` still ships.
- **Have `install.sh` install only manifested files instead of copying trees whole.**
  Rejected for this change: it moves the installer to a per-file walk for three trees, which
  is a delivery change rather than a detection one, and the manifest would then have no
  reviewer between it and the user. Detection first; if the manifest proves stable, making it
  the installer's input is the obvious follow-up.
- **Do nothing and rely on review.** Rejected: 0041 already left this open once on that
  reasoning, and a file added to a directory shows up in a diff as an addition with no
  reviewer prompt that it deploys globally.
