# SDLC workflow README overview

## Goal

Help new readers understand how this repository's workflow skills support the software
development lifecycle before they encounter the repository layout and installation details.

## README overview

Add an `SDLC workflows` section immediately before `## Layout`. The section will:

- describe the repository as an installable workflow toolkit for Claude Code, Codex, and IBM
  Bob;
- show a Mermaid flowchart with the phases Discover, Plan, Build, Review, Ship, and Operate &
  learn;
- name a small set of representative skills in each phase;
- show feedback from review and operations into earlier lifecycle phases;
- summarize the phases in a compact table; and
- link to `content/skills/` as the canonical full skill inventory.

The overview will describe skills, not repository-defined commands. Agent-native command
sources are intentionally forbidden in this repository, while installed skills may be invoked
through the supported agents' native skill interfaces.

## Representative workflows

The diagram and summary will favor recognizable end-to-end examples over an exhaustive list:

- Discover: `groom`, `issue`, `triage-issues`, and `scope`
- Plan: `brainstorming`, `epic`, `design`, and `writing-plans`
- Build: `work-issue`, `build-tdd`, `test-driven-development`, and
  `systematic-debugging`
- Review: `challenge`, `review-loop`, `threat-scan`, and `simplify-changes`
- Ship: `ship-pr` and `merge-cleanup`
- Operate & learn: `recover-orphans`, `retro`, `compound`, and `campaign`

The Mermaid diagram will use two representative skills per phase to keep its labels readable.
The table will include the full representative sets above. The link to the canonical directory
will provide access to every installed skill without duplicating a maintained inventory in the
README.

## Licensing

Add a top-level `LICENSE` containing the standard MIT license text with:

`Copyright (c) 2026 agent-config contributors`

Add a short `License` section to the README linking to that file. It will also state that
third-party and derived components retain their applicable notices, linking to the existing
Superpowers attribution inventory under `docs/licenses/`.

## Verification

- Inspect the Markdown placement and Mermaid source for readable labels and valid flow syntax.
- Confirm every named skill has a canonical `content/skills/<name>/SKILL.md` package.
- Run `just verify`, the repository's required local guardrail suite.
