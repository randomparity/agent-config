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

The skills tree is the exception. `scripts/check-skill-layout.sh` already requires every
child of `content/skills` to be a skill directory, forbids symlinks and non-regular files
anywhere under it, and constrains every path component. Its membership is shape-gated rather
than enumerated, which is the right trade for the one tree whose growth is the routine act
the repository exists for.

## Decision

**A single gate covers the set of wholesale-installed trees whose membership is fixed —
`agents/bob/shared/rules`, `content/languages` and `content/references` — not the one tree
the issue names.** All three reach a user through the same `cp -pR`, and the two content
trees reach three agents rather than one, so a gate over the narrower surface would leave the
wider one open while reporting the defect closed. `content/skills` stays out: its membership
is the thing that is supposed to change, and `check-skill-layout.sh` already gates the shape
of every entry in it. `docs/licenses/superpowers.LICENSE` stays out because it is a named
file, not a tree, and a named file is already a deliberate edit.

**The gate is its own script.** `scripts/check-deployed-membership.sh` carries the manifest,
`scripts/check-deployed-membership-test.sh` is its suite, and a `membership-check` recipe puts
it in the `verify` chain. Extending `check-shared-standards.sh` was the cheaper edit and is
rejected: that gate's subject is the identity of one block across the files that carry it, its
manifest means "these files must each hold a block", and a second list meaning "these files
may exist" inside it would leave the reader of either list guessing which question it answers.
Two of the three trees are not even scan roots there.

**Membership is enumerated with `find`, not ripgrep.** Every entry that is not a directory
counts as a member, symlinks and dot-prefixed files included, because `cp -pR` copies all of
them. `find` is chosen over the repository's usual `rg` for the property that it has no ignore
logic at all: a `.gitignore` or `.ignore` entry beside a deployed file cannot subtract it from
the enumeration, and neither can a developer's `RIPGREP_CONFIG_PATH`. Record 0041's gate needs
`--hidden --no-ignore` to reach the same place, and needs a test to keep them there; this gate
has nothing to remember.

**Both directions of disagreement are findings, exit 1; only an inability to compare is a
fault, exit 2.** A declared file that is absent and an undeclared file that is present are the
two answers the comparison exists to produce, and neither stops it. Faults are the cases where
there is no comparison to make: a missing tree, an unusable repository root, a bad argument, or
a manifest entry under no declared tree. That rule also explains `check-shared-standards.sh`
exiting 2 when a manifested block site is missing, which stays as it is — there the file is an
input to a byte comparison that then cannot run, not an answer.

## Consequences

- Adding a file to one of the three trees is now two edits: the file, and the manifest line
  that admits it. That is the point — the second edit is where a reviewer sees that something
  new is about to install into every user's configuration.
- A branch that adds such a file without the manifest line fails `just verify` and CI. In a
  parallel wave this can turn a sibling branch red after this one merges; the remedy is the
  one-line manifest edit, and the alternative is the deployment nobody reviewed.
- The gate proves the tree matches the list. It says nothing about whether a listed file
  should be deployed at all, or what it contains — `check-deployed-references.sh` and
  `check-shared-standards.sh` keep their own subjects.
- A new wholesale-installed tree added to `install.sh` is not covered until it is added to
  this manifest, and nothing detects that omission. The manifest is source, so this gate
  cannot defend against edits to itself; a comment at each `install.sh` call site names the
  manifest, which is the whole of the coupling.
- A file name containing a newline splits into two lines and reports as two unexpected
  members. The verdict is still red, which is the property that matters.
- Three trees in one gate means one recipe and one suite rather than three, and the cost is
  that the manifest mixes an agent tree with two content trees. They are grouped by how they
  are delivered, which is what the gate is about.

## Considered & rejected

- **Gate only `agents/bob/shared/rules`, as the issue frames it.** Rejected: the same `cp -pR`
  ships `content/languages` and `content/references` to three agents instead of one, so this
  closes the narrower hole and leaves the wider one, having declared the defect fixed.
- **Extend `scripts/check-shared-standards.sh` and its manifest.** Rejected above: one list
  would answer two questions, and two of the three trees are outside that gate's scan roots.
- **Enumerate with `rg --files --hidden --no-ignore`.** Rejected: it reaches the same set only
  as long as two flags stay put and `RIPGREP_CONFIG_PATH` is neutralised, and `find` needs
  none of that to be total.
- **Treat an unexpected member as a fault (exit 2).** Rejected: it is the finding the gate was
  written to produce, and reporting it as "could not run" would tell a reader the opposite of
  what happened.
- **Generate the manifest from the tree, or from `git ls-files`.** Rejected: a list derived
  from what is there agrees with whatever is there, so it would pass on exactly the change it
  exists to catch — and `git ls-files` would miss the gitignored files `cp -pR` still ships.
- **Have `install.sh` install only manifested files instead of copying trees whole.**
  Rejected for this change: it moves the installer from `cp -pR` to a per-file walk for three
  trees, which is a delivery change rather than a detection one, and the manifest would then
  have no reviewer between it and the user. Detection first; if the manifest proves stable,
  making it the installer's input is the obvious follow-up.
- **Do nothing and rely on review.** Rejected: 0041 already left this open once on that
  reasoning, and a file added to a directory shows up in a diff as an addition with no
  reviewer prompt that it deploys globally.
