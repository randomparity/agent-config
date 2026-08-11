# 0045 — Installed trees declare their membership

## Status

Accepted (2026-08-10)

## Context

`install.sh` delivers most of its payload one named file at a time, but `install_managed_path`
ends in `cp -pR`, so a call whose source is a directory ships that whole subtree into the
agent's configuration directory verbatim. Four directory sources reach it, across six call
sites: `agents/bob/shared/rules` for Bob, `content/languages` and `content/references` for all
three agents through `install_common_content`, and the staged skills tree once per agent.

Nothing counts what is in those directories. `scripts/check-shared-standards.sh` names one
file inside the rules tree and asserts it holds exactly one shared block; a file beside it
carrying no marker is invisible to that gate and installs anyway.
`scripts/check-deployed-references.sh` scans the same trees for what a deployed file may
*say* — its comment even records that the rules tree "is copied whole" — and never asks how
many files are in one. Record 0041 disclosed the residual in as many words: the gate narrows
the ungated surface, it does not close it.

So adding a file to one of these directories deploys it to every user's global agent
configuration, with nothing asking whether it belongs. That is the class of change that most
wants a machine check, because the file need not be edited by anyone afterwards to keep
having effect.

## Decision

**The gate covers the trees whose every file is deployed content in its own right —
`agents/bob/shared/rules`, `content/languages` and `content/references` — and not just the one
tree the issue names.** All three reach a user through the same `cp -pR`, and the two content
trees reach three agents rather than one.

`content/skills` is excluded because its unit of delivery is the skill directory, not the
file, and a per-file manifest over it would gate assets while churning on ordinary work: 96
files across eleven adding commits, against seven files and one commit in the three covered
trees. That is a cost argument and not a risk one, and it points the other way on risk —
eleven adding commits is a higher rate of exactly the change the Context describes than one.
Excluding the tree leaves a residual rather than covering it, in both directions. The loose
`docs/licenses/superpowers.LICENSE` stays out too: a named file is already a deliberate edit.

**The gate is its own script.** `scripts/check-deployed-membership.sh` holds the manifest,
`scripts/check-deployed-membership-test.sh` is its suite, and a `membership-check` recipe puts
it in the `verify` chain. The manifest is a literal inside the script, following
`check-shared-standards.sh` rather than the separate data file
`scripts/reserved-skill-names.txt` uses, because it is short and means nothing apart from the
comparison that consumes it.

**Membership is enumerated with `find`, not ripgrep.** Every entry under a declared tree that
is not a directory is a member — symlinks and dot-prefixed files included, because `cp -pR`
copies all of them. `find` is total by construction: it reads no ignore file and no
`RIPGREP_CONFIG_PATH`, so there are no flags for a later edit to drop. Ignore rules are not a
merely local concern here, because ripgrep applies `.gitignore` to tracked files too.

**A member that is not a regular file is a finding whatever the manifest says.** Enumerating
symlinks is not the same as permitting them: `cp -pR` preserves a symlink and `find` does not
descend one, so a link to a directory would pass as a single declared path while deploying
whatever its target resolves to on the user's machine. Declaring a path may not admit an
unbounded subtree behind it. `check-skill-layout.sh` refuses non-regular files under the
skills tree for the same reason.

**A disagreement in either direction is a finding, exit 1, and the fault class may never
swallow one.** A declared file that is absent and an undeclared file that is present are the
two answers the comparison exists to produce, and a declared tree that is not there is
therefore not a fault either: it contributes no members, so every file declared under it
reports as missing. That case is reachable — two of the three trees hold one file, and Git
does not track empty directories — though not urgent, since `install_managed_path` already
exits on a missing source, so the installer fails on such a deletion before this gate speaks.

Exit 2 is left with the inputs the gate cannot make sense of at all: a bad argument, an
unusable repository root, an enumeration that fails on a tree that is present, and a member
path holding a newline, which a line-delimited comparison cannot represent and which can
otherwise collapse into declared entries and leave the gate green over a file that ships.
Here the gate parts company with
`check-shared-standards.sh` and `check-deployed-references.sh`, which both fault on a missing
scan root; neither compares membership, so for neither is the root's absence itself an answer.

## Consequences

- Adding a file to one of the three trees is now two edits: the file, and the manifest line
  that admits it. What the gate proves is that an undeclared file cannot land silently — CI
  refuses it whether or not anyone reads the diff, including the file nobody meant to add. It
  does not make the manifest line more conspicuous in a diff than the file addition beside it.
- A branch that adds such a file without the manifest line fails `just verify` and CI. In a
  parallel wave this can turn a sibling branch red after this one merges; the remedy is the
  one-line manifest edit, and the alternative is the deployment nobody reviewed.
- Nothing declares the expected set of skills. A file added inside an existing
  `content/skills` skill directory installs to every user with no membership check, and so
  does a whole new top-level skill directory — `check-skill-layout.sh` constrains what a skill
  must look like, and `scripts/reserved-skill-names.txt` is a forbidden list rather than an
  expected one. It is left open here despite being the surface that moves most — eleven
  adding commits against one across the three covered trees.
- Untracked debris under one of the three trees — an editor swap file, a `*.orig` from a
  merge — now turns a local `just verify` red, because the enumeration reads no ignore rules.
  Neither gating environment sees it: `scripts/verify-push.sh` rehearses in a detached
  worktree of the pushed objects, and CI runs on a clean checkout. The remedy is to remove the
  debris, which is what the red is asking for; a `*.orig` lands inside a covered tree by
  construction when the conflict is there, so avoiding it is not open to the developer.
- A new wholesale-installed tree added to `install.sh` is not covered until it is added to
  this manifest, and nothing detects that omission. The manifest is source, so this gate
  cannot defend against edits to itself; a comment in `install_common_content` and one at the
  Bob rules call site name the manifest, which is the whole of the coupling. Making it detectable
  is tracked separately. Narrowing the manifest is the edit a red gate invites, and it is
  mostly caught: deleting a member line while the file is still there makes the file
  undeclared, which is red, and deleting a tree line with its members leaves the checker green
  but fails the suite, whose pass case pins the whole summary against its own tree list and the
  tracked file count. What survives is a coordinated edit to both the checker's lists and the
  suite's — the residual of a gate whose manifest is source.
- The repository now holds three lists of installer-copied roots — this manifest's trees,
  `check-deployed-references.sh`'s `scan_paths`, and the `content/languages` and
  `content/references` pair `check-skill-layout.sh` hardcodes — that mean different things,
  with nothing comparing them.
- The gate proves the tree matches the list. It says nothing about whether a listed file
  should be deployed at all, or what it contains.

## Considered & rejected

- **Site the check in `scripts/check-deployed-references.sh`, whose `scan_paths` already
  claims to be "every *directory* root the installer copies".** The closest existing home.
  Rejected because that array is a scan surface for what a deployed file may *say*, not a
  membership claim — and it is a superset used that way, also scanning `agents/claude/shared`,
  `agents/codex/shared` and `content/skills`, from which the installer takes named files or a
  filtered copy. Reusing it would gate trees whose membership does not matter; scoping a
  subset out of it would put two meanings in one list.
- **Gate only `agents/bob/shared/rules`, as the issue frames it.** Rejected for the reason the
  Decision gives; recorded here because the issue's framing is the obvious scope and a reader
  should find it disposed of rather than overlooked.
- **Declare `content/skills` at directory granularity** — an expected set of top-level skill
  names, which the churn objection does not touch: two commits ever added one. Rejected here
  on shape, not cost: this gate compares one flat set of files, and a tree compared at a
  different granularity puts two comparison rules in one script. `check-skill-layout.sh`
  already enumerates those children and is the natural home. Tracked as follow-up work.
- **Extend `scripts/check-shared-standards.sh` and its manifest.** Rejected: that gate's
  subject is the identity of one block across the files that carry it, and its manifest means
  "these files must each hold a block". A second list meaning "these files may exist" would
  leave a reader of either guessing which question it answers, and two of the three trees are
  not scan roots there.
- **Discover the covered trees instead of enumerating them**, as record 0037 did for shell
  sources when it replaced an enumeration whose omissions had no signal. Rejected on the
  difference between the two sources: 0037 discovers from Git, an index of what exists,
  whereas discovering these trees means deciding which `install_managed_path` calls have a
  directory source — and those sources are shell expressions, several of them variables
  holding temporary files. A heuristic that misreads a call site fails silently in the same
  direction the manifest does. A list file `install.sh` itself read would remove the guess,
  but that changes what the installer consumes.
- **Assert membership in `install-test.sh`, against the installed result.** The strongest
  alternative here: it runs `install.sh` into a `mktemp -d` HOME and asserts on what landed,
  so enumerating the installed set would cover a newly added wholesale tree the moment the
  installer shipped it, closing by construction the residual this record leaves open.
  Rejected because it would make a source-tree question answerable only by running the
  installer, folding membership into a suite whose subject is installer behavior.
- **Generate the manifest from the tree, or from `git ls-files`.** Rejected: a list derived
  from what is there agrees with whatever is there, so it would pass on exactly the change it
  exists to catch.
- **Have `install.sh` install only manifested files instead of copying trees whole.**
  Rejected for this change: it is a delivery change rather than a detection one, and the
  manifest would then have no reviewer between it and the user. Detection first; if the
  manifest proves stable, making it the installer's input is the obvious follow-up.
- **Do nothing and rely on review.** The base rate is genuinely low — one commit ever added a
  file to these trees, and no incident has occurred — and the gate is not free: it accepts the
  false positive in the debris bullet above, on prose files that parallel agent waves edit and
  conflict in. Rejected on the asymmetry of the harms rather than on their frequency: a local
  red costs one deletion, while an undeclared file reaches every user's global configuration
  and need never be edited again to keep acting.
