# 0041 — Shared prose is gated for copy identity

## Status

Accepted (2026-08-10)

## Context

The global development standards exist as four near-identical documents:
`content/instructions/global-development-standards.md` (agent-neutral, not deployed),
`agents/claude/shared/CLAUDE.md`, `agents/codex/shared/AGENTS.md`, and Bob's shorter
payload under `agents/bob/shared/`. The first three diverge only where the surface is
agent-native — the name of a project-local instruction file, a config directory in a
reference path, whether a skill is invoked by name or by prefix. Every rule they state is
the same rule.

Nothing enforces that. `scripts/check-carrier-drift.sh` scans `content/skills` only;
`scripts/check-deployed-references.sh` scans the deployed trees for stale record
references and never compares them to each other or to the canonical copy. A rule added
to one copy stays in one copy, which is how three of the repository's operating rules came
to live in Claude's file alone. Adding a fourth rule the same way reproduces the defect
rather than fixing it, so the change that generalizes those rules needs a gate that makes
"every agent got it" checkable.

Record 0038 is the obstacle and also the answer. It decided that prompt prose is gated for
the consistency of its machine-read blocks and never for the wording of its sentences,
after a 571-line suite byte-compared rule sentences against strings hardcoded in the suite
itself. It named section ordering, rule wording, and headings as things human and model
readers tolerate rewording of, and relinquished those assertions as not load-bearing. A
gate asserting that each deployed file contains the literal heading `## CI Verification`
is that relinquished class, returning under a new name.

Two questions follow. What may a gate assert about prose that is duplicated across copies
on purpose? And which of Bob's two deployed instruction files is the copy that has to
carry the shared rules — `agents/bob/shared/AGENTS.md`, which the installer places at the
root of Bob's config directory, or `agents/bob/shared/rules/global-development-standards.md`,
which shares the canonical document's name and title?

## Decision

**Prose duplicated across deployed copies by design is gated for the identity of those
copies against a canonical file in this repository — never against a string held by the
gate.** Record 0038 stands unchanged; this adds a second gated class beside its
machine-read blocks and reopens nothing it settled.

The two properties that distinguish this from the class 0038 rejected are the reason it is
admissible. The gate holds no prose, so rewording is a one-place edit followed by a
mechanical copy rather than a synchronized edit of a document and a suite. And the
assertion is exactly the guarantee being claimed — that every agent receives the same
rules — rather than a proxy for behavior that string matching cannot reach.

The mechanism is a `shared-standards` block, opened by `<!-- shared-standards:begin -->`
and closed by `<!-- shared-standards:end -->`.
`content/instructions/global-development-standards.md` holds the canonical block.
`scripts/check-shared-standards.sh` requires exactly one well-formed block in the
canonical file and in each of the three deployed instruction files, and requires each
deployed block to equal the canonical block byte for byte. It fails closed on a canonical
block carrying fewer than three `###` subsections, so a gutted block cannot leave the gate
green over nothing. It asserts nothing about what those subsections are called or what
their sentences say.

Block content is agent-neutral: no native config path, no invocation syntax, no
agent-specific file name. That constraint is what makes byte identity reachable across
copies whose surrounding prose is deliberately native, and a rule that cannot be stated
agent-neutrally stays outside the block.

**Bob's mirror target is `agents/bob/shared/rules/global-development-standards.md`.** It
carries the canonical document's name and title, which under record 0001 is what a native
projection of a canonical document looks like; the founding plan's deployed-path manifest
lists it in the position it gives `CLAUDE.md` for Claude and `AGENTS.md` for Codex; and
`agents/bob/shared/AGENTS.md` is Bob's orientation file, which Claude and Codex have no
separate rules directory to need. The rules land in one Bob file, not both: two deployed
homes for one rule set is the drift this record exists to close.

## Consequences

- A rule added to the shared block reaches every agent or turns `just verify` red naming
  the file that missed it. That is the machine-checkable form of "generalized to all
  agents".
- Editing a shared rule means editing four files. The gate names each drifted file and
  line, so the sync is mechanical, but it is not free, and it is the price of keeping the
  copies native everywhere else.
- The canonical copy cannot silently drift from the deployed ones even though it is not
  itself deployed and not scanned by the deployed-reference gate: it is the comparison
  source, so an edit there alone fails the gate on all three mirrors.
- The block's text ships to every agent, so it must satisfy the deployed-reference rules
  that `content/instructions/` is exempt from — no bare record number, no bare issue
  number, no concrete record path.
- The gate does not assert that the three rule sets are named or worded any particular
  way. It asserts that all four copies say the same thing and that the canonical block has
  not been reduced below three subsections. A reviewer, not `rg`, is what keeps those
  subsections worth having — which is the division of labor 0038 chose.
- Bob's `agents/bob/shared/AGENTS.md` keeps summarizing the defaults without restating
  them. Its overlap with the rules file is pre-existing and untouched here.
- The block is an HTML comment pair, invisible in rendered Markdown and inert to every
  agent that reads the file as instructions.

## Considered & rejected

- **Assert that each deployed file contains the three literal section headings**, as the
  issue proposed. Rejected: it puts three prose strings inside the gate, which is the
  class 0038 forbids, and it passes on a file whose section is an empty stub — it would
  certify the headings while the rules underneath diverged.
- **Require the markers without comparing block contents.** Rejected: the copies stay free
  to say different things, which is the gap the gate exists to close.
- **Byte-compare the whole file.** Rejected: the copies differ by design where the surface
  is agent-native, and forcing them identical would either strip the native detail or
  ship Claude's paths to Codex.
- **Generate the deployed copies from the canonical file at install time.** Rejected here:
  record 0001 gives root instruction files to the native payloads and defers a renderer
  until the boundaries are proven. A four-file copy-paste the gate points at precisely is
  a smaller thing to own than a transformation layer over every agent's instruction file.
- **Put the shared rules in `agents/bob/shared/AGENTS.md` instead.** Rejected on the
  evidence above. The issue's stated reason for the same conclusion — that AGENTS.md is
  repository-specific — is wrong in the other direction: that file describes itself as
  public defaults for Bob users, while the rules file is the one carrying this
  repository's build commands. The conclusion survives its reason.
- **Add the block to both Bob files.** Rejected: one rule set, one deployed home per
  agent, or the gate has to choose which copy is authoritative for Bob and the drift
  returns inside a single agent's tree.
- **Do nothing and rely on review to keep the copies in step.** Rejected: review is what
  the repository has now, and it produced three rules that reached one agent out of three.
