# Portable Workflow References Design

## Scope charter

- **Interaction:** interactive
- **Scope identity:** issue #14 `WORK:SCOPE` annotation
- **Outcome:** make deployed workflow references understandable outside this checkout and
  prevent the dangling-reference class from returning.
- **Completion criteria:** the seven acceptance criteria in issue #14.
- **Provenance:** issue #14 and the accepted records delivered by dependencies #8–#13.
- **Exclusions:** no runtime semantic changes, unsupported Bob parity, or cleanup outside
  deployable payloads.
- **Surface:** canonical skills, applicable agent-native shared payloads, one guard and its
  tests, Justfile integration, and these workflow design artifacts.
- **Ambiguities:** none.

## Problem

Canonical skills are copied into an agent's configuration directory and then invoked in an
unrelated target repository. A bare source-repository citation such as `ADR 0019`, `issue
#49`, or a concrete `docs/superpowers/specs/...` path is therefore ambiguous or dangling at
the point of use. The target repository may have a different record with the same number,
and the relative design file is not installed with the skill that cites it.

The current inventory contains three categories:

1. **Target-repository inputs:** record directories, next-number patterns, plan/spec output
   locations, and paths supplied by the user. These remain relative but must visibly be a
   directory or template rather than a source-repository citation.
2. **Agent-config provenance:** bare ADR/issue citations currently attached to otherwise
   self-contained rules. The deployed rule must state the behavior directly; optional
   provenance must be a fully qualified stable link.
3. **Examples:** illustrative plan/spec/record paths. These must use visible placeholders,
   globs, or the repository's documented `YYYY-MM-DD`/`NNNN` templates.

## Approaches considered

### Syntax-driven guard — selected

Scan every regular, non-symlink, non-binary deployed file under `content/skills/` and each
`agents/{claude,codex,bob}/shared/` tree, regardless of extension. Reject bare numeric ADR
citations, bare numeric source-issue citations, and unclassified concrete relative file
references beneath the four record/design directories. A concrete ADR/debt path is valid
only when the same line introduces it with the literal natural-language marker
`target-repository`; record templates remain valid without the marker. Plan/spec references
are permitted when their basename is visibly templated with `YYYY-MM-DD`, an angle-bracket
placeholder, or a glob.

The record engine under `content/skills/decision-records/assets/` is a bounded structural
exception for concrete ADR/debt paths: those paths are executable target operands and test
fixtures owned by that component. The exception does not apply to plan/spec paths, bare
numeric citations, other skill assets, or native payloads.

This catches the known stale epic spec, source issue, and conflicting ADR-number forms
without making the checker interpret prose. Valid target inputs and examples express their
classification in the reference syntax itself.

### Explicit classification markers — rejected

Markers on every reference would be exact, but would add a second annotation language
throughout the installed instructions. The selected design uses one narrow exception: the
ordinary phrase `target-repository` classifies a concrete ADR/debt path that syntax cannot
otherwise distinguish. Templates, examples, URLs, and source citations need no marker.

### Central allowlist — rejected

A path-and-line allowlist would minimize edits. It would drift whenever prose moves, hide
why an exception is safe, and let a copied dangling reference pass merely because its text
resembles a historical exception.

## Guard design

`scripts/check-deployed-references.sh` owns discovery and classification. It resolves the
repository root from its own path, requires `rg`, enumerates every regular non-symlink file
from the canonical and native deployment roots, and reports every violation before exiting
nonzero. `rg`'s binary detection excludes binary payloads, which cannot contain deployed
prose; file extensions do not affect inclusion. The guard never follows symlinks or scans
repository-only design records.

The denied forms are:

- case-insensitive `ADR` followed by a concrete number, including a Markdown link label;
- case-insensitive `issue` followed by `#` and a concrete number, including a Markdown link
  label; and
- a concrete relative Markdown file below a governed plan/spec directory; and
- a concrete relative Markdown file below `docs/adr/` or `docs/debt/` unless
  `target-repository` appears earlier on the same line or the file belongs to the bounded
  decision-record engine.

Fully qualified provenance therefore uses a descriptive, nonnumeric Markdown label, such
as `[governing-review decision](https://github.com/owner/repo/blob/<commit>/docs/adr/0019-name.md)`,
or a bare stable URL. The numeric identifier may occur in the URL path, but not as a bare
prose citation. The path rule accepts an exact directory reference or the appropriate
variable marker in the candidate basename: `NNNN` for records, and `YYYY-MM-DD`, `<...>`,
or `*` for plans/specs. An unrelated marker in a parent component cannot exempt a concrete
file. A concrete ADR/debt basename instead requires `target-repository` before the path on
that line, making its classification visible to both readers and the guard. Diagnostics
name the file, line, and reference class.

The decision-record engine exception is path-scoped to
`content/skills/decision-records/assets/`; an executable file elsewhere receives no general
exemption. Tests prove an operational record path in that component passes and the same
unmarked path in another shell asset fails.

The test script creates a minimal temporary repository fixture and proves both sides of each
classification boundary. It includes explicit regressions for the stale epic design path,
the source issue reference, conflicting ADR numbers, descriptive-label and bare-URL forms
of fully qualified ADR/issue provenance, target directories, templated examples, and mixed
paths whose marker is outside the concrete basename. It proves that canonical Markdown, a
non-Markdown canonical asset, and Claude-, Codex-, and Bob-native roots are scanned; a
binary fixture is ignored deliberately.

`just references-check` runs the guard directly. `just test` runs its regression suite, and
`just verify` includes the guard so the required GitHub check blocks a regression.

## Payload remediation

Each deployed behavioral rule remains in place. Bare citations that only explain history
are removed; citations that help provenance become stable fully qualified links. Concrete
examples become placeholder examples. Canonical skills remain the single reusable workflow
source, so Claude and Codex receive identical policy through installation. Bob-native files
change only if the inventory finds the referenced workflow there; absence is not filled in
to manufacture parity.

## Error handling and portability

The guard fails with an actionable diagnostic if `rg` is unavailable or a deployment root
is missing. It accumulates violations so one run shows the complete repair set. The script
uses Bash with `set -euo pipefail`, portable `rg` expressions, and temporary files allocated
by `mktemp`; the tests remove only their owned scratch directory.

## Verification

Development follows red-green TDD: install the failing fixtures first, observe the missing
guard failure, implement the minimum scanner, verify focused tests, then clean the real
payload until the guard passes. `shellcheck`, `shfmt -d`, focused tests, mutation checks for
the three known defects, and `just verify` provide the final evidence.
