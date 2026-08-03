# 0024 — Test-Only Assets Are Filtered Out of the Installed Payload

## Status

Accepted (2026-08-03)

## Context

The tracker contract suite (ADR 0021) needs a profile that declares a degraded
operation. `profiles/github.sh` implements every operation it declares, so
without a second profile the declared-degraded gate ships with no case
exercising it, and a profile that simply forgot an operation would be
indistinguishable from one that legitimately degrades. A stub profile supplied
that case: `profile_view` returns a hardcoded issue and `profile_label_history`
returns the literal `unknown`.

It lived in `profiles/`, beside the real profile, and `install.sh` copies
`content/skills` wholesale — one `install_managed_path` call per agent, three
agents, resolving to a single `cp -pR` with no per-file filter. The stub
therefore landed in every installed tree. There it was reachable: the engine
resolves a profile by file existence, so `--profile fixture` and an `AGENTS.md`
saying `issue-tracker: fixture` both loaded it, `available_profiles` advertised
it by name in the engine's own error message, and a caller reading the result
got a well-formed normalized payload for an issue that does not exist. Nothing
in the payload distinguishes it from a real read.

Relocating the stub to a test-only directory is necessary but not sufficient on
its own. `cp -pR` of `content/skills` ships whatever is under that tree, so a
path rename alone moves the file inside the installed copy rather than removing
it from it. The tree is also the only delivery mechanism the repository has:
skills are directories of assets, and a suite's fixtures naturally live beside
the code they exercise.

## Decision

The installed payload is a filtered view of `content/skills`, not the tree
itself. Directories named `testdata` are test-only assets and are excluded from
what any agent receives.

`install.sh` stages a copy of `content/skills` into a temporary directory,
removes every `testdata` directory from that copy, and installs the staged tree
for all three agent targets. Filtering happens on the source side, before
`install_managed_path` sees it, rather than by deleting from the destination
afterwards. The destination therefore stays byte-comparable to what was
installed, so the installer's `payload_differs` check reports the skills tree
unchanged on a reinstall; deleting afterwards would leave the destination
permanently different from its source, and every run would read that as drift,
back the tree up, and recopy it.

The stub moves to
`content/skills/github-tracking/assets/testdata/fixture-profile.sh` — outside
`profiles/`, and named so it cannot be reached by the engine's
`profiles/<name>.sh` lookup even if the directory were installed.

`tracker-test.sh` assembles the asset tree it runs against: a temporary
directory holding a copy of `tracker.sh`, `profiles/github.sh`, and the stub
staged as `profiles/fixture.sh`. The engine resolves `$asset_dir` from its own
location, so pointing it at that tree is what keeps the stub loadable for the
suite and only for the suite. The suite consequently stops depending on the
layout of the directory it happens to sit in.

`install-test.sh` asserts the outcome directly for each of the three agent
targets: no `profiles/fixture.sh`, no `testdata` directory anywhere under the
installed skills tree, and the installed `tracker.sh` invoked with
`--profile fixture` exits 1 with the `usage` error class and an available-profile
list that does not name the stub. That last assertion is what ties the file's
absence to the behavior the absence is for — a tree could be clean while the
resolution path still had some other route to a fabricated read.

## Consequences

- The installer's payload is no longer identical to `content/skills`. Anything
  comparing the two — `install-test.sh`'s `assert_canonical_skills`, and any
  future check — has to apply the same exclusion, and it now does so by naming
  `testdata` rather than by loosening the comparison.
- `testdata` becomes a reserved directory name inside `content/skills`: a skill
  cannot ship a directory by that name to agents. Nothing needs one, and the
  rule is stated in one place — the `find` in `stage_skills` — that
  `install-test.sh` asserts against.
- Test fixtures can now live beside the code they exercise without that being a
  delivery decision. That is the property the previous layout lacked, and it is
  why the rule is a directory convention rather than a one-off exclusion of this
  file.
- A fixture only reaches the code under test if a suite stages it, which is a
  visible step in the suite rather than an implicit consequence of where the
  file sits. A suite that forgets to stage its fixture fails immediately.
- The installer now creates one temporary directory per run and removes it in
  its existing `EXIT` trap. Staging costs a full copy of `content/skills` per
  invocation, once for `--agent all` rather than once per agent.
- `just lint` and `just format-check` cover `assets/testdata/*.sh`, so the stub
  stays linted and formatted despite no longer sitting in a directory those
  recipes already globbed.

## Considered & rejected

- **Delete `testdata` from the destination after copying.** Rejected on the
  drift reasoning in the Decision: the destination would never again match its
  source, so `payload_differs` would report the skills tree as changed on every
  run, back up the whole tree, and recopy it — turning a no-op reinstall into a
  full rewrite and filling the backup directory.
- **Teach `install_managed_path` an exclusion parameter.** Rejected as
  speculative surface. One caller needs filtering, and the same parameter would
  have to be threaded through `payload_differs`'s `diff -rq` and its executable
  comparison to stay consistent, spreading the rule across three functions
  instead of holding it in one.
- **Move the stub out of `content/skills` entirely** (to a repository-level test
  directory). Rejected because it separates a skill's fixture from the skill,
  and because the skills tree is where the suite and the asset it exercises both
  live; the delivery problem is the installer's to solve, not a reason to
  relocate the suite's inputs away from it.
- **Keep the stub installed and reject it at resolution time** — a hardcoded
  denylist of profile names in the engine, or a marker variable the engine
  refuses to load. Rejected because it puts knowledge of a test asset into
  production code, and because a file that ships is a file that can be reached:
  the denylist is one more thing to keep in agreement with the directory
  listing, and it does not stop the stub from being read, copied, or edited into
  service.
- **Drop the stub and lose the declared-degraded coverage.** Rejected: the gate
  exists to distinguish a forgotten operation from a declared degradation, and
  with `profiles/github.sh` implementing everything, deleting the stub is
  deleting the only case that exercises it.
