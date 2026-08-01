# Verify Created GitHub Issues

## Scope and authority

This dispatched design implements issue #33 under scope identity
`https://github.com/randomparity/agent-config/issues/33; scope-33-20260801-a1`.
The public issue and campaign dispatch require every newly created issue and sub-issue to
be read back before success is reported. The read-back must verify the confirmed title,
a non-empty body with `Problem`, `Evidence`, `Expected`, and `Proposed approach`
sections, every intended label, and the intended native parent for sub-issues. A mismatch
must report the durable URL and exact differences without creating a replacement.

The permitted implementation surface is `content/skills/issue/`, its tests, and minimal
guardrail registration. ADRs, migrations, unrelated issue workflow behavior, and GitHub
state repair are excluded. There are no unresolved ambiguities. Interaction is unattended.

## Approaches considered

### Recommended: a small shell verifier called by the skill

Add a focused script that accepts the repository, issue reference, expected title, body
file, labels, and optional parent. It performs explicit-field GitHub reads, compares the
durable result with the confirmed draft, and returns a precise failure report. The skill
invokes it immediately after each creation. This makes the behavior executable and allows
the required failure modes to be tested without live GitHub writes.

### Inline checks in `SKILL.md`

The workflow could document a sequence of `gh` and `jq` commands directly. This keeps the
file count low, but the partial-decomposition and malformed-response cases would be hard to
test, and agents could reproduce the sequence inconsistently.

### One end-to-end creator script

A larger script could own both creation and verification. That would make creation
transaction-like, but it duplicates the skill's confirmation, triage, recovery, and
decomposition policy. It is more surface than the defect requires.

## Design

`verify-created-issue.sh` is a postcondition checker, not a creator. It reads the issue
using `gh issue view` with explicit JSON fields. For sub-issues it separately enumerates
the intended parent's native sub-issues and confirms that the created issue number is
present. Expected labels are supplied as repeated arguments so spaces and colons remain
literal. The populated body file is retained by the caller and supplies the confirmed
body contract without standard-input shortcuts.

The verifier accumulates all mismatches before failing. It always includes the durable
issue URL when GitHub returned one and identifies each failed property: title, empty body,
missing mandatory section, label, or parent. It never calls `gh issue create`, edits an
issue, or retries creation.

The skill's create and decompose paths capture the URL returned by `gh issue create`, then
invoke the verifier before printing or otherwise treating that URL as success. During
decomposition, verification runs after each child. If child N fails, the workflow reports
the partial result and stops; earlier children remain durable and no replacement child is
created.

## Error handling and safety

Malformed or incomplete GitHub JSON is a verification failure. A missing URL falls back to
the supplied issue reference in the diagnostic, while a returned URL is always preferred.
The script treats all external strings as data, uses arrays for `gh` arguments, and never
evaluates generated shell. GitHub read failure propagates as failure with an actionable
message. These guarantees trace to issue #33's requirement that malformed creations never
be reported as successful or duplicated.

## Tests

A shell test supplies a fake `gh` executable and fixtures for successful issue and
sub-issue verification. It covers empty body, missing section, wrong title, missing label,
wrong parent, malformed read-back data, and successful verification. A workflow contract
test exercises partial decomposition failure by verifying that the documented loop stops
at the failed child, reports its durable URL, and does not create a replacement. Tests also
assert that the skill retains populated temporary body files and uses `--body-file`, and
that every create path invokes read-back verification before success.

`just verify` remains the aggregate local and CI gate.
