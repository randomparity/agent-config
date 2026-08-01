# Vendored Superpowers Attribution and Ownership Design

Issue: [#6](https://github.com/randomparity/agent-config/issues/6)

ADR: [0004. Own vendored Superpowers skills as maintained agent projections][adr-0004]

## Goal

Restore the license and attribution omitted when Superpowers-derived skills were imported,
and state the repository's present ownership, update, and dispatched-mode policy for all
applicable Claude, Codex, and IBM Bob projections.

## Requirements and assumptions

- Preserve the upstream MIT license text from Superpowers 6.1.1, copyright Jesse Vincent.
- Attribute every file in each current derived skill root, including local additions and
  modifications beneath those roots.
- Treat the predecessor repository's ADRs 0015 and 0018 as provenance, not as policy to
  copy. This repository has native multi-agent projections and no dependency on the old
  Claude plugin arrangement.
- Keep the change to repository documentation and attribution. It does not re-vendor skill
  contents, add a generator, or change installation behavior.
- Use the issue acceptance criteria as the approved requirement in dispatched design mode.

## Provenance audit

The upstream source is [obra/superpowers at v6.1.1][superpowers-611].
Its `LICENSE` blob is identical to the predecessor's
`docs/licenses/superpowers.LICENSE`. Repository history shows all current derived roots
arrived in the initial public agent-payload commit. The predecessor's ADR 0015 identifies
the eleven selected skill families; the current tree projects those eleven to Claude and
Codex and projects the two applicable skills to Bob.

The attribution notice will define coverage by directory root. That makes every current
file below a listed root covered even when an agent projection has local helper files or
differs from the upstream snapshot.

## Approaches considered

### Repository license plus root inventory — selected

Add the exact upstream license once, add a notice that names the source snapshot and every
covered projection root, and link both from the README and ADR 0004. This is explicit,
keeps the license authoritative, and handles locally added files beneath derived roots.

### Per-directory license copies

Place a license beside every projected skill. This is locally visible but repeats the
same legal text across 24 roots and creates unnecessary drift and review noise.

### Canonical vendored tree with generated projections

Move derived files into one canonical tree and generate per-agent copies. This might
simplify future attribution, but it changes the repository's ownership and installation
architecture and is not required to restore the missing records.

## Design

Create `docs/licenses/superpowers.LICENSE` as a byte-for-byte copy of the upstream
Superpowers 6.1.1 MIT license. Create `docs/licenses/superpowers.md` as the human-readable
notice. It records the upstream project, version and copyright; distinguishes original
work from local modifications; links the license and predecessor provenance; and lists
the covered skill roots by agent and skill name.

Add a short README section that points readers to the notice and license rather than
duplicating the inventory. ADR 0004 owns the durable policy:

- native projection directories are maintained forks owned by this repository;
- updates are deliberate upstream diffs that preserve and review local adaptations;
- all applicable projections are considered together, without requiring byte identity;
- a caller explicitly asserts dispatched mode, which returns control without integration;
- only lifecycle skills with interactive gates carry the dispatched-mode adaptation.

No skill body or installer path changes. The existing directory layout remains the source
of deployable agent-native files.

## Failure handling and maintenance

- A missing or altered license is visible as a normal repository diff and fails review;
  the implementation copies the source blob already verified against upstream and the
  predecessor repository.
- A future derived root not present in the notice is an incomplete re-vendor change under
  ADR 0004. Its author must update the inventory in the same change.
- Agent-specific differences are reviewed for semantic policy coverage. They are not
  normalized merely to make files match.
- If upstream changes license terms, the re-vendor change must retain the terms applying
  to existing material and add the new terms required by the incoming snapshot.

## Verification

- Compare `docs/licenses/superpowers.LICENSE` byte-for-byte with the verified upstream
  v6.1.1 license blob.
- Enumerate the current derived roots and confirm each appears in the attribution notice.
- Run the decision-record checker for ADR 0004.
- Run `just verify`, including public-safety, documentation-adjacent record checks, install
  tests, shell lint and formatting, and workflow checks.
- Review the final diff to ensure it contains no host-specific or private material and no
  skill or installer behavior change.

## Scope and decomposition

This is one small documentation and provenance change. The license, notice, README link,
ADR, and design/plan artifacts are one consistency unit and should ship in one pull
request. No decomposition is needed.

[adr-0004]: ../../adr/0004-own-vendored-superpowers-skills.md
[superpowers-611]: https://github.com/obra/superpowers/tree/v6.1.1
