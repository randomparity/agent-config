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

### Recommended: a small verified-create shell boundary called by the skill

Add a focused script that accepts the repository, confirmed title, populated body file,
labels, and optional parent. It creates exactly one issue, performs explicit-field GitHub
reads, compares the durable result with the confirmed draft, and returns the URL only after
verification passes. This makes the original create-to-success boundary executable and
allows the required failure modes to be tested without live GitHub writes.

### Inline checks in `SKILL.md`

The workflow could document a sequence of `gh` and `jq` commands directly. This keeps the
file count low, but the partial-decomposition and malformed-response cases would be hard to
test, and agents could reproduce the sequence inconsistently.

### Put the whole issue workflow in one script

A larger script could own confirmation, triage, recovery, decomposition, creation, and
verification. That would duplicate the skill's policy and is more surface than the defect
requires. The selected helper deliberately owns only the single durable write and its
postcondition.

## Design

`create-verified-issue.sh` is the single-create boundary, not the policy workflow. It calls
`gh issue create` exactly once with `--body-file`, captures the returned durable URL, and
reads the issue using `gh issue view` with explicit JSON fields, including the authoritative
native `parent` field. For sub-issues it compares that returned parent number directly with
the intended parent. Expected labels are supplied as repeated
arguments so spaces and colons remain literal. The populated body file is retained by the
caller and supplies the confirmed body contract without standard-input shortcuts.

The verifier accumulates all mismatches before failing. It always includes the durable
issue URL and reports expected versus observed title, every missing mandatory section,
every missing intended label, and the expected versus observed parent relationship. An
empty or malformed body is named precisely. After its one creation call, the helper never
edits, retries, or creates a replacement.

The skill's create and decompose paths invoke the helper only after confirmation and treat
its verified output as the sole success result. During decomposition, the helper runs once
per child. If child N fails verification, the workflow reports that durable URL and exact
mismatches, then stops; earlier children remain durable and no replacement child is
created.

## Error handling and safety

Malformed or incomplete GitHub JSON is a verification failure. If the create call returns
no resolvable URL, the helper reports that the durable artifact could not be identified and
stops without retrying; it cannot invent the issue reference required for read-back.
The script treats all external strings as data, uses arrays for `gh` arguments, and never
evaluates generated shell. GitHub read failure propagates as failure with an actionable
message. These guarantees trace to issue #33's requirement that malformed creations never
be reported as successful or duplicated.

## Tests

A shell integration test supplies a fake `gh` executable and runs the actual helper. It
proves that success is withheld until read-back passes and covers empty body, missing
section, wrong title, missing label, wrong parent, malformed read-back data, and successful
creation. It also runs the documented
decomposition loop against the helper to prove that partial failure stops later creates,
reports the failed child's durable URL, and never creates a replacement. Contract checks
assert that every skill create path uses the helper, retains its populated temporary body
file, and contains no direct successful `gh issue create` bypass.

`just verify` remains the aggregate local and CI gate.

## Threat model

The helper crosses two trust boundaries. First, confirmed operator inputs enter a `gh`
argument vector. The local operator is trusted to choose the repository, title, labels,
body file, and optional parent; the control is strict option parsing, numeric parent
validation, a populated regular body file, and array-based argument construction with no
evaluation or shell command string. GitHub.com and GitHub Enterprise hosts are supported,
but the returned HTTPS URL must resolve to the requested owner/repository and an issue
number before it can drive read-back.

Second, GitHub CLI output enters the verifier. The remote GitHub service and local `gh`
configuration can return missing, malformed, or unexpected data. The control is an
explicit-field read, complete shape validation for every consumed label and parent member,
literal comparisons against the confirmed draft, and fail-closed diagnostics that retain
the durable URL whenever it was resolved. External text is never evaluated or used to form
a shell command. Retry, repair, and replacement writes are out of scope because issue #33
requires a single durable creation attempt whose mismatch is surfaced to the operator.
