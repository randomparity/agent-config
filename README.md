# Multi-Agent Configuration Tools

Public shared configuration for Claude Code, Codex, and IBM Bob.

This repository combines common development standards, language references,
one shared workflow-skill inventory, and agent-native settings without
committing host-specific configuration.

## Layout

- `content/` holds agent-neutral instructions, language references,
  orchestration references, and the canonical `skills/` tree installed for all
  supported agents.
- `agents/claude/shared/` holds Claude-native `CLAUDE.md`, settings, and status
  line configuration.
- `agents/codex/shared/` holds Codex-native `AGENTS.md` and config.
- `agents/bob/shared/` holds Bob-native `AGENTS.md`, settings, MCP config,
  custom modes, and rules.
- `examples/hosts/` shows private overlay shapes with placeholder values only.
- `examples/bob-project/` shows Bob project-local `.bob/` conventions.

## Vendored software

Selected agent skills are maintained forks of MIT-licensed Superpowers 6.1.1. See the
[attribution inventory](docs/licenses/superpowers.md) and
[license](docs/licenses/superpowers.LICENSE) for the exact source snapshot and covered
roots.

By submitting a change below a covered root, a contributor offers that change under the
canonical MIT terms and represents that they have authority to grant those rights.

## Install

Bootstrap local tooling:

```sh
./install-tools.sh
just setup
```

`./install-tools.sh` is the first-run path for clones that do not have `just`
yet. It checks and installs `just`, `jq`, `rg`, `shellcheck`, `shfmt`, `gh`,
`prek`, `actionlint`, and `zizmor`.

If a fallback installer places tools in a directory that was not already on your
shell `PATH`, start a new shell or add the printed tool directory before running
`just`. To install tools and enable hooks in one bootstrap step, run:

```sh
AGENT_CONFIG_SETUP_HOOKS=1 ./install-tools.sh
```

Check local tooling without installing anything:

```sh
./install-tools.sh --check
```

The tool installer supports macOS with Homebrew and Linux via `/etc/os-release`
family detection for Ubuntu/Debian, Fedora, and RHEL-family systems. It uses
package managers first, then pinned fallbacks only when the required runtime is
already installed. The zizmor wheel fallback uses 1.28.0; the Cargo source
fallback uses 1.27.0 so it remains buildable with Rust 1.88 and newer.

Set up or refresh local git hooks:

```sh
just hooks
```

Install one agent:

```sh
./install.sh --agent claude
./install.sh --agent codex
./install.sh --agent bob
```

Install all supported agents:

```sh
./install.sh --agent all
```

To test install output without touching live config directories:

```sh
tmpdir="$(mktemp -d)"
HOME="$tmpdir/home" \
CLAUDE_CONFIG_DIR="$tmpdir/home/.claude" \
CODEX_CONFIG_DIR="$tmpdir/home/.codex" \
BOB_CONFIG_DIR="$tmpdir/home/.bob" \
AGENT_CONFIG_PRIVATE_DIR="$tmpdir/private" \
AGENT_CONFIG_HOST=example-host \
./install.sh --agent all
```

Claude MCP registration is opt-in because it writes through the Claude CLI to
user-scope MCP state outside the selected config directory:

```sh
AGENT_CONFIG_REGISTER_CLAUDE_MCP=1 ./install.sh --agent claude
```

## Project-local review skills

Examples under `examples/project-review-skills/` are deliberately not globally
installed. They depend on the reviewed project's targets and declared policy, so a
project adopts the example it needs instead of adding an unfamiliar review workflow to
every agent installation.

Place a selected review skill in the project's agent-native directory:

- Claude: `.claude/skills/`
- Codex: `.agents/skills/`
- Bob: `.bob/skills/`

For example, a project instruction can integrate the accessibility reviewer as follows:

```text
For UI-affecting changes, invoke accessibility-reviewer after normal branch review.
Disposition defensible findings, rerun the reviewer after behavioral fixes, and treat
unresolved manual checks according to this project's accessibility policy.
```

## Private Overlays

Host overlays stay outside this public repository:

```text
${AGENT_CONFIG_PRIVATE_DIR:-$HOME/.config/agent-config}/hosts/<host>/<agent>/
```

Supported overlay files:

- Claude: `settings.overlay.json`
- Codex: `config.overlay.toml`
- Bob: `settings.overlay.json`, `mcp.overlay.json`

If an overlay is absent, the installer uses the public base and reports that no
private overlay was applied. Secrets should stay in environment variables or in
private overlay files outside this repo.

## IBM Bob Notes

Bob has separate global paths for some IDE and Shell settings. The installer
copies the public custom mode to both:

- `~/.bob/settings/custom_modes.yaml`
- `~/.bob/custom_modes.yaml`

It also writes MCP config to both:

- `~/.bob/mcp.json`
- `~/.bob/mcp_settings.json`

Bob project-local examples live under `examples/bob-project/.bob/`.

## Verification

Run the full local guardrail suite:

```sh
just verify
```

Run `just format` to apply shell formatting. CI runs `just ci`, which runs
`just verify` and then `prek run --all-files` to prove the hook configuration.

`./install-test.sh` installs every agent into temporary directories, applies
private overlay fixtures, verifies every installed skill tree against
`content/skills/` including executable modes, checks generated files, verifies
manifest pruning, and verifies managed-file drift backup.

`./scripts/check-skill-layout.sh` rejects agent-native workflow copies and
validates the portable structure of the canonical skill packages.

`./scripts/check-public-safety.sh` scans for denied host-specific paths, local
network addresses, auth headers, and common secret token shapes.

### Required `verify` branch check

GitHub protects `main` with the lowercase check context `verify`, bound to the
GitHub Actions app (ID `15368`). The workflow display name is `Verify`; branch
protection uses the job/check name, including its case, rather than that display
name. Administrators are subject to the same required check.

If a workflow edit renames the job or a stale required context leaves a pull
request waiting indefinitely, first run the replacement check on a real pull
request. It does not need to merge. Copy the emitted name and producer only after
the replacement succeeds:

```sh
repo_name=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
pr_number=19 # replace with the real pull request that emitted the replacement
gh pr checks "$pr_number" --json name,state,link,workflow
head_sha=$(gh pr view "$pr_number" --json headRefOid --jq .headRefOid)
gh api "repos/$repo_name/commits/$head_sha/check-runs" \
  --jq '.check_runs[] | {name, app_id: .app.id, app_slug: .app.slug, conclusion}'
```

The update endpoint replaces the entire required-check list. Preserve every
unrelated check when replacing the stale context, and stop if policy changes
between the read and write:

```bash
set -euo pipefail

required_url="repos/$repo_name/branches/main/protection/required_status_checks"
current_required=$(gh api "$required_url")
stale_context=verify
replacement_context=verify # replace with the successful run's exact name
replacement_app_id=15368    # replace with that run's app_id

if ! jq -e --arg stale "$stale_context" \
  --arg replacement "$replacement_context" \
  '([.checks[] | select(.context == $stale)] | length == 1) and
   ([.checks[] | select(
      .context == $replacement and .context != $stale)] | length == 0)' \
  <<<"$current_required"; then
  printf '%s\n' 'stale or replacement context is ambiguous; inspect and retry' >&2
  exit 1
fi
if ! replacement=$(jq \
  --arg stale "$stale_context" \
  --arg context "$replacement_context" \
  --argjson app_id "$replacement_app_id" \
  '{
    strict,
    checks: [.checks[] |
      if .context == $stale
      then {context: $context, app_id: $app_id}
      else .
      end]
  }' <<<"$current_required"); then
  printf '%s\n' 'could not build the replacement policy; nothing was written' >&2
  exit 1
fi

live_required=$(gh api "$required_url")
current_snapshot=$(jq -cS '{strict, checks}' <<<"$current_required")
live_snapshot=$(jq -cS '{strict, checks}' <<<"$live_required")
if [[ "$live_snapshot" != "$current_snapshot" ]]; then
  printf '%s\n' 'required checks changed during recovery; inspect and retry' >&2
  exit 1
fi

gh api --method PATCH "$required_url" --input - <<<"$replacement"
updated_required=$(gh api "$required_url")
updated_snapshot=$(jq -cS '{strict, checks}' <<<"$updated_required")
expected_snapshot=$(jq -cS . <<<"$replacement")
if [[ "$updated_snapshot" != "$expected_snapshot" ]]; then
  printf '%s\n' 'required-check read-back differs; inspect before another write' >&2
  exit 1
fi
```

Confirm the replacement PR becomes unblocked. Do not clear all required checks as
a workaround: that recreates the unprotected merge path. Patching this endpoint
preserves other branch-protection features; constructing and asserting the complete
required-check list preserves other required checks when one administrator owns the
write window. The endpoint has no conditional-write step verified by this workflow,
so coordinate a short maintenance window and do not run this recipe concurrently with
another policy edit. The before/after snapshots detect observed drift but cannot make
an unconditional PATCH race-free; retain them for reconciliation if another edit occurs.

## Decision Records

Architecture decisions live in `docs/adr/`; explicitly deferred work lives in
`docs/debt/`. Number the two directories independently: list the numbered files
in the relevant directory and increment its highest four-digit prefix. Do not
maintain a hand-written index.

An ADR is named `NNNN-slug.md`, starts with `# NNNN — Title`, and has non-empty
`## Status`, `## Context`, `## Decision`, `## Consequences`, and
`## Considered & rejected` sections. Its status is `Proposed`, `Deferred`, or
`Accepted`, `Rejected`, or `Superseded` followed by an ISO date in parentheses.
Record supersession in the old ADR with this status banner, pointing to the new
ADR:

```markdown
> **Superseded by [NNNN](NNNN-slug.md)** (YYYY-MM-DD)
```

A debt record uses the same file and title convention. It has non-empty
`## Status`, `## Concern`, `## Why deferred`, `## Non-regression boundary`,
`## What would resolve it`, and `## Provenance` sections. Open records use an
`Open` status followed by `review-by: YYYY-MM-DD`. Provenance includes at least
one `target: path` line. Resolve a record in place by removing `review-by:` and
replacing `Open` with:

```markdown
> **Resolved by <what>** (YYYY-MM-DD)
```

Merged records are append-only except for their lifecycle markers. Create a new
ADR instead of rewriting an accepted decision; supersede the old one when the
new decision is accepted. Resolve debt in place when its stated condition is
met.

If a numbering collision or mistake requires renumbering a merged record, move it
to an unused four-digit number and update the H1 number in the same change. Do
not alter substantive text. The gate accepts the move only when the destination
did not exist at the base commit and canonicalized content is identical;
marker-only normalization may accompany it. New records still increment the
highest current number in their own directory.

For legacy records, preview marker-only migrations before writing them:

```sh
RECORD_PROFILES="adr debt" ./.github/scripts/migrate-records.sh
RECORD_PROFILES="adr debt" ./.github/scripts/migrate-records.sh --write
```

Review every item the dry run leaves for a human. For a missing lifecycle date,
inspect repository history:

```sh
git log --follow --format=%cs -- <record>
```

Add the date of the commit that established the lifecycle state; do not invent
the current date. Apply the marker rewrites with `--write`, then make the
evidenced Status or required-section completion in the same dedicated migration
commit without rewriting existing prose.

Include every printed `Migrated-markers:` trailer; those trailers enumerate the
automatic marker rewrites, not the required human completions. Run `just verify`
after creating, superseding, resolving, or migrating a record.

The root package under `.github/scripts/` owns the repository gate. Its checker,
suite, migrator, and `adr` and `debt` profiles must remain byte-identical to the
canonical copies under `content/skills/decision-records/assets/`; `just records`
checks that invariant. GitHub requires the producer-bound lowercase `verify` check on
`main`; issue #16 records the failing-PR enforcement proof and recovery procedure.

The ADR profile normally warns when `docs/adr/README.md` contains a hand-maintained
numbered index because the directory is the index. An adopting repository whose own
required CI enforces ADR-to-index agreement sets `ADR_INDEX_POLICY: required` beside
`RECORD_PROFILES` in its records workflow; that declaration suppresses only the
conflicting index warning.

## Source Material

This repo was designed from the existing local Claude Code and Codex config
repositories plus public IBM Bob documentation and examples:

- IBM Bob custom modes: https://bob.ibm.com/docs/ide/configuration/custom-modes
- IBM Bob Shell custom modes:
  https://bob.ibm.com/docs/shell/configuration/custom-modes-bobshell
- IBM Bob skills: https://bob.ibm.com/docs/ide/features/skills
- IBM Bob rules: https://bob.ibm.com/docs/ide/configuration/rules
- IBM Bob IDE MCP: https://bob.ibm.com/docs/ide/configuration/mcp/mcp-in-bob
- IBM Bob Shell MCP: https://bob.ibm.com/docs/shell/configuration/mcp/mcp-bobshell
