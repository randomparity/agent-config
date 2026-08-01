# 0017 — The CHARTER Label Is a Parsing Boundary

## Status

Accepted (2026-08-01)

## Context

Review invocations combine target arguments with a trailing scope charter. Paths and
flag-like text inside that charter describe authority; parsing them as targets or options
can silently narrow or redirect the review.

This records the final policy inherited from the predecessor's
[ADR 0010](https://github.com/randomparity/claude-config/blob/main/docs/adr/0010-charter-label-is-a-parsing-boundary.md).

## Decision

The first line whose first content token is the case-sensitive label `CHARTER` is a hard
parsing boundary. Leading whitespace, Markdown list markers, and emphasis are ignored, as
are trailing punctuation and emphasis; a mid-line occurrence is not a boundary. The label
and everything after it are focus text only. Callers append the block after explicit target
arguments and preserve its line boundary.

If stripping the block leaves no explicit target or mode, target resolution fails rather
than defaulting to the working tree. An unresolved pre-boundary target is named as the
cause. Structured mode emits neither a verdict nor an artifact on this failure, preventing
a caller from consuming a failed review as an ordinary result.

## Consequences

Charter paths and flags cannot become accidental review inputs, and swallowed or missing
targets fail visibly. Claude and Codex must preserve the boundary through their native
invocation transport. Bob follows it only for installed workflows that accept the same
argument form.

## Considered & rejected

- **Parse all invocation text uniformly.** Scope prose can be mistaken for executable
  targeting instructions.
- **Fall back to the working tree after stripping.** A malformed invocation would review
  an unintended target and still return a plausible verdict.
- **Return a synthetic structured error verdict.** The result schema has no error member,
  and callers could mistake it for completed review evidence.
