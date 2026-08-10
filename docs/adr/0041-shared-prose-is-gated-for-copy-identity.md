# 0041 — Shared prose is gated for copy identity

## Status

Accepted (2026-08-10)

## Context

The global development standards exist as four full or condensed copies —
`content/instructions/global-development-standards.md` (agent-neutral, not deployed),
`agents/claude/shared/CLAUDE.md`, `agents/codex/shared/AGENTS.md`, and
`agents/bob/shared/rules/global-development-standards.md` — beside Bob's root summary at
`agents/bob/shared/AGENTS.md`. The first three run to about 125 lines each and are
near-identical; Bob's is a condensation of about twenty.

They diverge where the surface is agent-native, which is by design, and in at least one
place where a rule simply landed in one copy and stayed there:
`agents/codex/shared/AGENTS.md` carries a rule about where reusable workflow sources live
that neither Claude's copy nor the canonical one has.

The operating rules this change generalizes are spread unevenly too. Exit-code truth, the
destructive-git ban, the deletion warning, and the decision-framing rules are in the three
long copies and in neither of Bob's two deployed files. The untracked-file check, the
`git clean` ban, and the force-delete ban are in none of the five.

Nothing detects any of it. `scripts/check-carrier-drift.sh` scans `content/skills` only.
`scripts/check-deployed-references.sh` scans the deployed trees for stale record
references and never compares a copy to another copy or to the canonical one. So writing
the missing prose into every file fixes the present state and leaves the next rule free to
land in one copy unnoticed, exactly as Codex's has.

Record 0038 is both the obstacle and the answer. It decided that prompt prose is gated for
the consistency of its machine-read blocks and never for the wording of its sentences,
after a 571-line suite byte-compared rule sentences against strings hardcoded in the suite
itself. It named headings, section ordering, and rule wording as things readers tolerate
rewording of. A gate asserting that each file contains the literal heading
`## CI Verification` is that relinquished class returning under a new name.

Two questions follow. What may a gate assert about prose duplicated on purpose? And which
of Bob's two deployed instruction files carries the shared rules?

## Decision

**Prose duplicated across deployed copies by design is gated for the identity of those
copies against a canonical file in this repository — never against a string held by the
gate.** The prohibition 0038 wrote is untouched: the gate holds no prose and asserts
nothing about wording.

The mechanism is a `shared-standards` block, opened by `<!-- shared-standards:begin -->`
and closed by `<!-- shared-standards:end -->`.
`content/instructions/global-development-standards.md` holds the canonical block.
`scripts/check-shared-standards.sh` scans four enumerated roots — that file's directory
and the three `agents/<agent>/shared` trees — for begin markers, and requires every block
it finds to equal the canonical block byte for byte. Beside the scan it carries an
expected-site manifest: the canonical file and the three deployed instruction files each
hold exactly one block, so a deleted or mistyped marker fails naming the file instead of
disappearing from the scan. The gate fails closed when the canonical block carries fewer
than three `###` subsections, and reads none of their text.

Block content is agent-neutral: no native config path, no invocation syntax, no
agent-specific file name. That is what makes byte identity reachable across copies whose
surrounding prose is deliberately native, and a rule that cannot be stated agent-neutrally
stays outside the block. Every rule the block absorbs is removed from where it was, so no
copy states a rule twice.

**Bob's copy is `agents/bob/shared/rules/global-development-standards.md`**, the file the
issue names and the one `install.sh` reaches by copying `agents/bob/shared/rules` whole
into Bob's rules directory. Bob's root summary goes on summarizing the defaults. One
deployed home per agent, or the gate has to decide which of Bob's two copies is
authoritative and the drift returns inside a single agent's tree.

## Consequences

- A rule added to the block reaches every agent, or `just verify` goes red naming the file
  that missed it. That is the machine-checkable form of "generalized to all agents".
- Only rules inside the block get that. A rule that cannot be stated agent-neutrally stays
  outside it and stays ungated, so the divergence this record found in Codex's copy is one
  the gate would not have caught. The gate narrows the ungated surface; it does not close
  it.
- 0038's synchronization cost returns, at four copies rather than two, and the copy is
  manual: nothing here generates or repairs a mirror. What changed is where the second
  copy lives — a file a reader can read, not a string inside the suite that asserts it.
- The canonical copy cannot silently drift from the deployed ones even though it is not
  deployed and not scanned by the deployed-reference gate: it is the comparison source, so
  an edit there alone fails the gate on all three mirrors.
- The block ships to every agent, so it must satisfy the deployed-reference rules that
  `content/instructions/` is exempt from — no bare record number, no bare issue number, no
  concrete record path.
- Bob's payload stops being a condensation for these rule sets. Accepted: a summarized
  safety rule is a different rule, and Bob is the agent currently receiving none of them.
- Whether Bob loads its rules directory without being asked is not established by anything
  in this repository, which links to the vendor's rules documentation and no further. This
  sits awkwardly beside the rejection above of a linked canonical file, which turns on a
  root instruction file being the one an agent loads unprompted: if Bob's rules directory
  is not loaded that way, Bob gets these rules on the weaker footing that argument
  rejects. The uncertainty applies equally to the file this record did not choose, so it
  does not decide between them; the issue's naming does. Confirming it against the vendor
  documentation is tracked as follow-up work, and moving the block to Bob's root file is
  the remedy if the answer is no.
- The gate proves the copies agree, not that they are worth agreeing on. Three empty
  subsections would satisfy it. Review keeps them worth having, which is the division of
  labor 0038 chose.

## Considered & rejected

- **Assert that each deployed file contains the three literal section headings**, as the
  issue proposed. Rejected: three prose strings inside the gate is the class 0038 forbids.
- **Require the markers without comparing block contents.** Rejected: the copies stay free
  to say different things, which is the gap the gate exists to close.
- **Byte-compare whole files.** Rejected: the copies differ by design where the surface is
  agent-native, so this would either strip that detail or ship Claude's paths to Codex.
- **Deploy `content/instructions/` to every agent through `install_common_content` and
  link to it from each root instruction file** — one copy, no gate, and the pattern
  `content/languages` and `content/references` already use. Rejected: the root instruction
  file is the one an agent loads without being asked. A rule the agent must first decide
  to open is a reference, not a guardrail, and these rules exist to bind the agent that
  was about to skip them.
- **Splice the block into the deployed copies at install time.** Record 0001 permits this
  — it defers a renderer to a later record rather than forbidding one — and it would
  remove drift instead of detecting it. Rejected anyway: the source tree would stop
  carrying what the agent receives, so a reader of `agents/codex/shared/AGENTS.md` would
  no longer be reading Codex's instructions, and review would cover an artifact that is
  not the deployed one.
- **Add a repository-side recipe that copies the canonical block into the mirrors.** Not
  the install-time splice above: it writes the tracked files, so each copy still is what
  the agent receives and review still covers the deployed artifact. Rejected for now
  because it is not needed to reach the outcome — the gate names the drifted file and its
  line, and the edit is rare — and it would be a second thing to keep correct. If the
  four-file sync proves burdensome in practice it is the obvious follow-up.
- **Exempt Bob and gate the two full-length copies.** Rejected: Bob is the copy actually
  missing the rules, so this would gate the pair that already agree.
- **Do nothing and rely on review.** The history is more favorable to review than it first
  looks: Bob's copy was authored as a condensation on day one rather than drifting, and the
  one rule added to these files since then was propagated to all five by the commit that
  introduced it. Rejected anyway, on two grounds review did not catch — Codex's copy holds
  a rule the others do not, and nobody chose a condensation as the right form for a safety
  rule, which is what Bob's file makes it.
