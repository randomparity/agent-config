# 0038 — Prompt prose is gated for consistency, not wording

## Status

Accepted (2026-08-09)

## Context

`scripts/check-workflow-scope-contract-test.sh` byte-compared sentences inside nine
workflow `SKILL.md` files against strings hardcoded in the suite, delimited by
`<!-- SCOPE-RULE|CARRIER|ORDER -->` marker scaffolding embedded in the prose itself, and
re-ran the same assertions against 25 mutated fixture copies. The suite was 571 lines —
larger than most of the skills it watched — and it pinned wording, not meaning: any copy
edit to a rule sentence turned the gate red, so improving prose required synchronized
edits in two places, while the behavior the prose directs remained untestable by string
match. `docs/debt/0005` records that even on the one label the suite did pin, the gate
was one-sided: it asserted review-loop's emitted `CHARTER` label and could not see
challenge's parsing boundary.

The genuine protocol inside that prose is the eight-line scope charter carrier duplicated
across seven call sites in five skills. Agents parse that block; it must not drift.
Everything around it — rule sentences, ordering of sections, headings — is read by
humans and models, both of which tolerate rewording.

## Decision

Prompt prose is gated for the consistency of its machine-read blocks and never for the
wording of its sentences.

`scripts/check-carrier-drift.sh` finds every occurrence of the carrier's first line under
`content/skills` and requires the eight-line window at each occurrence to equal the
canonical template byte for byte. The review-dispatch carrier — identified by its
trailing `focus:` line, in `review-loop/SKILL.md` — must be immediately preceded by the
exact canonical `CHARTER` label, because `content/skills/challenge` stops target
classification on that literal: an unlabelled dispatch block turns charter paths into
review targets. The binding is to that specific occurrence, so relocating the label onto
review-loop's other carrier fails the gate even though every count is preserved — this is
the emitter side of `docs/debt/0005`, preserved. First-line
discovery alone has a false negative — editing or deleting a copy's first line would make
that copy invisible to the scan — so the gate also carries an expected-site manifest
(file, carrier count): every listed file must contain exactly its listed number of
carriers, and a first-line mutation or deleted block fails the gate naming the file.
Carriers added to new files are found by the scan and window-checked without a manifest
edit. The gate fails closed on zero occurrences.

The scope-contract suite is deleted and the `SCOPE-*` markers are stripped from the nine
`SKILL.md` files that carried them.

## Consequences

- Copy edits to skill prose no longer break the build; the wording of rules is reviewed
  by humans at review time, not by `rg` at commit time.
- The carrier stays pinned where it matters: an edit to any of the seven copies fails
  `carrier-check` naming the file and line.
- Lost with the suite: the ordering assertions (a section must precede another) and the
  exact-wording rule assertions. Accepted as not load-bearing — document layout is
  visible to every reader, and the wording pins had never caught a real defect; their
  two recorded catches were the suite's own fixtures.
- `docs/debt/0005` stays open: its consumer-side concern (challenge's parsing boundary
  is ungated) is unchanged. Its body names the deleted suite and is append-only, so the
  pointer correction lives here: the gate it describes is now `check-carrier-drift.sh`,
  which keeps the same emitter-side label requirement.
- The `github-tracking` cleared-dependency recipe moves from a fenced block in `SKILL.md`
  to `assets/cleared-dependencies.sh`, so the normal lint and format gates cover it
  directly and its suite sources the file instead of awk-extracting a marker-delimited
  region from prose.

## Considered & rejected

- **Keep `SCOPE-CARRIER` markers only, drop `RULE` and `ORDER`.** Rejected: the
  first-line scan finds every carrier without scaffolding, so the markers would be
  ceremony the check does not read.
- **Pin keywords or sentence prefixes instead of whole sentences.** Rejected: still
  wording-coupled, still red on rephrasing, and a weaker assertion — the worst of both.
- **Drop the CHARTER label assertion with the rest.** Rejected: challenge parses on that
  literal, and the emitter-side check costs six lines in the drift gate. `docs/debt/0005`
  tracks the remaining consumer side.
- **Keep the recipe embedded in `SKILL.md` and keep the extraction test.** Rejected:
  executable code maintained inside prose re-implements the lint and format gates inside
  its own suite and still gets them at two-space indent the repository default forbids
  for that tree.
