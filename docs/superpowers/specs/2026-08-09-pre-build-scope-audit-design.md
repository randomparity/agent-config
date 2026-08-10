# Pre-build scope audit design

Issue: [#94](https://github.com/randomparity/agent-config/issues/94)

ADR: [0037](../../adr/0037-audit-reviewed-designs-before-build.md)

## Scope and authority

This design implements the reduced-scope recommendation on issue #94. The external charter
is the issue's latest complete `WORK:SCOPE` annotation, identified by the issue URL and token
`45e545fc-e02b-4e37-91ec-ed025dc4cb6d`. The outcome is a small, reusable installed audit that
checks the aggregate reviewed design before implementation and constrains branch review to
the approved surface.

The permitted product surface is `content/skills/scope-audit/`, the canonical
`content/skills/work-issue/` workflow, and directly coupled contract and installation tests.
This design also adds its governing ADR and design artifacts. Bookkeeping-only debt records
and tracker issues are permitted only for independently verified adjacent concerns; they do
not authorize implementing those concerns.

The design explicitly excludes formal schemas, identifier graphs, content hashes, new
parser/runtime code, transactional consistency for prose artifacts, live-model evaluation,
and implementation of adjacent issues. Issues #77 and #78 and closed PR #92 are evidence of
the failure mode, not authority for their behavior.

## Approaches considered

### One independent prose audit — selected

Add one short skill whose only product is a human-readable report. `work-issue` dispatches a
fresh agent after the ADR, specification, and plan have passed their existing reviews. The
agent reads those artifacts collectively with the frozen charter and linked ownership,
writes its report to a pre-minted per-worktree path under `.agent/scope-audit/`, and the
caller reads that exact report as the sole result. This is the smallest approach that is both
reusable and independent.

### Inline proportionality checklist — rejected

Adding questions directly to `work-issue` would be smaller in file count, and it could still
dispatch a fresh independent agent. It would not provide the reusable audit entry point that
issue #94 requires for other design workflows.

### Structured audit protocol — rejected

A machine-validated graph of artifact, promise, criterion, component, and contract identities
could detect stale or inconsistent references. It recreates the subsystem-sized failed design
and is explicitly excluded. A visible artifact edit simply invalidates the prose report and
causes another audit.

### Keep post-build review only — rejected

This adds no latency or surface, but retains the reported failure: aggregate scope is not
challenged until implementation cost is sunk. Issue #94 explicitly requires the decision point
before TDD.

## Workflow placement and inputs

`work-issue` gains one mandatory phase for non-trivial changes:

1. Finish the existing design phase, including ADR, specification, and plan reviews.
2. Ensure the worktree's `.agent/` root is self-ignored under ADR 0027, verify that
   `.agent/scope-audit/` is ignored, and mint a unique, never-created report pathname there
   without touching the file. The path includes the issue and branch identity so concurrent
   runs do not share a report.
3. Dispatch one fresh subagent to run `scope-audit` over:
   - the unchanged eight-field frozen charter;
   - explicit paths to every reviewed ADR, specification, and plan associated with the run;
   - the base branch needed to inspect the design-artifact diff; and
   - linked issue, dependency, debt-record, and tracker ownership relevant to findings.
4. Open the exact pre-minted path, require the completion sentinel and one explicit valid
   verdict, and disposition the report before TDD. The subagent completion message carries no
   second verdict or alternative path.
5. Preserve the report path and compact approved-surface section as the design-to-build
   context checkpoint.

The caller enumerates the complete expected artifact set. The independent auditor cross-checks
that list against changed design-artifact paths in the branch diff and links in the supplied
work evidence; it does not invent a discovery registry. A missing or unresolved expected
artifact, an unexplained extra design artifact, or uncertainty about completeness produces
`needs-attention` and stops before TDD.

The audit is one pass over an unchanged artifact set, not another review loop. An unchanged
`needs-attention` result is never retried merely to seek approval. A new pass is warranted
only after a design artifact changes through the existing design/review cycle or linked
ownership changes through a verified disposition. If the workflow changes a reviewed design
artifact, or observes that one changed after approval and before TDD, `work-issue` reruns the
audit. The prose workflow does not guarantee detection of arbitrary out-of-band edits; doing
so would require the excluded artifact-identity machinery.

The observable trigger is the full design path: every run that produces or consumes reviewed
design artifacts runs this phase before TDD. Trivial bugfixes and governed small changes retain
their existing design-skip paths and do not run it. Contract fixtures exercise both the design
path and the two skip paths so the exemption cannot expand silently.

## Audit behavior

The skill is read-only with respect to reviewed artifacts, Git state, debt records, and
tracker state. Its sole write is the requested report under `.agent/scope-audit/`. The
caller owns ADR 0027's fail-closed ignore setup before dispatch; the auditor does not create
or modify ignore files. The report uses this minimal Markdown envelope:

- first nonblank line, exactly once: `**Verdict:** approve` or
  `**Verdict:** needs-attention`;
- `## Promise to provenance`: every normative design guarantee and its external authority or
  necessary-consequence reasoning;
- `## Component to criterion`: every proposed component, file group, test group, or runtime
  behavior and the criterion that needs it;
- `## Smallest viable alternative`: the selected approach compared with a materially smaller
  implementation, including why the smaller option fails or should replace the proposal;
- `## Approved surface`: components, contracts, complexity budget, exclusions, and verified
  owned deferrals that branch review must use;
- `## Findings`: evidence, impact, recommendation, uncertainty, and one classification per
  concern; and
- final nonblank line: `<!-- SCOPE-AUDIT:COMPLETE -->`.

The five headings occur once in that order and each section contains at least one content
line; `none` is explicit when a section has no entries. A missing, duplicate, or out-of-order
envelope element, or a sentinel before the final nonblank line, is incomplete and stops.

This is a prose contract, not a formal schema. The caller reads it as a document and does not
add a result parser or identifier cross-reference engine.

The report at the caller's exact pre-minted path is the sole audit result. The caller ensures
that path did not already exist before dispatch, ignores any alternative path or verdict in a
completion message, and stops before TDD when the expected file is missing, the sentinel is
absent, the verdict is missing or not one of the two allowed words, or the document is otherwise
incomplete. This detects ordinary reuse of a pre-existing path under the intended single-writer
workflow. It does not prove provenance against concurrent creation or replacement; concurrent
runs must use distinct paths, and detecting an exact-path replacement would require the excluded
reservation machinery. The fail-closed read is a document check, not a new result parser.

The auditor challenges the combined proposal for unsupported guarantees, behavior owned by
another issue, unnecessary persistence/authentication/schema/permission/concurrency or
operational contracts, disproportionate components/files/tests/runtime, a materially smaller
viable approach, and dependencies on exclusions. It uses four classifications:

- `in-scope-required`: an apparent expansion is a necessary direct dependency and its
  criterion/provenance mapping demonstrates why;
- `scope-checkpoint`: the proposal materially expands authority, absorbs another issue,
  depends on an exclusion, or remains disproportionate when a smaller viable approach exists;
- `defer-candidate`: a real adjacent concern appears independent of the change and needs
  verification plus an existing or new owner; and
- `unsupported`: the suspected concern is not supported by the artifacts or external evidence,
  with the rejection evidence recorded.

`approve` requires complete mappings, a defensible smallest-alternative comparison, no
`scope-checkpoint` finding, and no unowned `defer-candidate`. A narrow charter paired with a
subsystem-sized plan therefore returns `needs-attention`; a necessary direct dependency with
an explicit criterion mapping can pass. Behavior owned by another issue is a checkpoint or
split, never an `in-scope-required` shortcut.

Uncertainty in provenance, ownership, or dependency classification stays explicit. A linked
or plausible tracker is evidence to investigate, not proof of independent ownership, and it
cannot make a concern eligible for deferral. Only a verified independent owner appears in the
approved surface as an owned deferral.

The audit cannot authorize scope. A `scope-checkpoint` finding returns the interactive root
to the existing `SCOPE CHECKPOINT` before code is written. A `defer-candidate` is input to the
existing review-loop disposition semantics: verify it, preserve uncertainty honestly, and
give a verified independent concern a `docs/debt/` owner plus tracker pointer where supported.
A concern the proposed change depends on or worsens cannot be deferred. Unsupported concerns
are rejected with evidence rather than converted into requirements.

## Approved surface and branch review

The report's `Approved surface` section is deliberately compact and human-readable. It names
only components/files, changed contracts, an `S`/`M`/`L` complexity budget with a short
rationale, exclusions, and verified owned deferrals. It does not duplicate the full design.

The branch review invocation includes that exact summary in its focus and asks the reviewer
to flag unexplained divergence: new components, contracts, files, tests, runtime behavior, or
complexity that the summary does not account for. The summary does not forbid implementation
details within an approved component; it makes additions and aggregate growth explainable.
The diff cannot use its implementation or successful tests as authority to widen the summary.

## AI surface and evaluation plan

**AI-SPEC.** The user is an operator running `work-issue`; the trigger is completion of a
non-trivial design and plan review; inputs are the frozen public-safe charter, explicit local
design artifact paths, and linked ownership; output is a human-readable audit report and an
`approve` or `needs-attention` verdict within that report. Allowed sources are those inputs
and repository evidence needed to verify ownership. Disallowed behavior is editing targets
or Git state, authorizing
scope, inventing certainty, absorbing adjacent work, or repeatedly rerunning unchanged input.
On incomplete inputs or an incomplete report, the workflow stops before TDD. The latency/cost
budget is one fresh model pass per unchanged artifact set. Success means the deterministic
prompt-contract suite proves the load-bearing instructions and an independent review finds the
design proportionate; no live-model quality claim is made.

| Failure mode | Severity | Deterministic evidence |
|---|---:|---|
| Audit treats its target or verdict as authority | 5 | Operative no-authority clause and mutation fixture |
| Narrow issue approves a subsystem-sized plan | 4 | Proportionality rule and mutation fixture |
| Another issue's behavior is treated as required | 4 | Ownership/checkpoint rule and mutation fixture |
| Depended-on or worsened concern is deferred | 5 | Non-deferrable rule and mutation fixture |
| Suspected concern is stated as verified fact | 4 | Uncertainty-preservation rule and mutation fixture |
| Incomplete charter or artifact set reaches TDD | 5 | Complete-input and phase-order rules with mutation fixtures |
| Missing, pre-existing, partial, or misdirected report reaches TDD | 5 | Sole-result path and completion rules with mutation fixtures |
| A known or observed design change skips another pass | 4 | Change-invalidation rule and mutation fixture |
| Audit loops on unchanged input | 4 | One-pass latency rule and mutation fixture |
| Branch diff grows beyond the approved surface | 4 | Branch-review comparison rule and mutation fixture |

The eval cases are the corresponding contract-test mutations. They include the happy path of
a necessary direct dependency; an ambiguous or incomplete input that stops; a forbidden scope
claim that checkpoints; stale/conflicting evidence through visible design change; the
issue-ownership boundary; the no-repeat cost cap; and PR #92's regression shape of a narrow
request paired with a subsystem-sized plan. The repository does not add an LLM judge. The
tests prove that deployed prompts retain these requirements, while adversarial review supplies
the human-readable quality check.

Report-envelope mutations cover a pre-existing expected path, a missing or duplicated verdict,
missing or reordered headings, an empty section, a sentinel that is absent or not final, and
output written only to a different path.

## Trust boundaries

The design adds no permission, network, credential, or executable parser boundary. It does add
an agent tool-use boundary: a fresh local agent reads operator-selected repository artifacts and
writes one operator-selected scratch report. The local operator and existing agent sandbox remain
trusted; issue and artifact prose may be mistaken or adversarial and therefore supplies evidence,
never authority. The complete external charter controls authority, explicit artifact paths bound
reads, and ADR 0027's verified self-ignore keeps the per-worktree report out of Git while
preserving it across a session boundary. The auditor may not edit Git or external state. Error
output names missing inputs without copying secrets or host-specific values into GitHub comments.
Threats outside the existing local-agent permission model are not addressed.

## Files and verification

Implementation is limited to:

- `content/skills/scope-audit/SKILL.md` — reusable audit instructions;
- `content/skills/work-issue/SKILL.md` — phase placement, dispositions, context checkpoint,
  and branch-review comparison;
- `scripts/check-workflow-scope-contract-test.sh` — structural prompt-contract checks and
  mutation fixtures; and
- this ADR, specification, and the transient implementation plan.

`install-test.sh` already compares the canonical skill tree with every installed projection,
so a new skill is covered without adding another projection mechanism. `just verify` is the
full local and CI-equivalent guardrail. The branch is `feat/scope-audit-94`, the base is `main`,
and `just verify` is the recorded guardrail command.
