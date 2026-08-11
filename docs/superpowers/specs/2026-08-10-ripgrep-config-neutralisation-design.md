# Neutralising `RIPGREP_CONFIG_PATH` across the gate scripts

Issue: [119](https://github.com/randomparity/agent-config/issues/119).
Record: [0051](../../adr/0051-gate-scripts-neutralise-the-ripgrep-config.md).

## Problem

`rg` reads the file named by `RIPGREP_CONFIG_PATH` and applies its contents as
arguments *before* the ones the caller passes. Any flag the caller does not
itself specify is therefore chosen by whoever set that variable — a developer's
personal ripgreprc, a shell profile, a CI job's environment, or a `.envrc`
someone accepted.

Every gate in the `verify` chain that decides its verdict from a ripgrep exit
status or output therefore has an input nobody declared. `check-skill-layout.sh`
was hardened for this in #101 (PR #131); its siblings were outside that change's
declared surface.

### Demonstrated exposure

Reproduced against the tree at `db78af6`, each with a two-line config file and a
planted violation the gate catches when the variable is unset.

| Gate | Steering | Result |
| --- | --- | --- |
| `check-public-safety.sh` | `--fixed-strings` | planted `ghp_…` token missed, **exit 0** |
| `check-public-safety.sh` | `--glob !*.md` | planted token missed, **exit 0** |
| `check-public-safety.sh` | `--max-count 0` | planted token missed, **exit 0** |
| `check-public-safety.sh` | `--encoding utf-16le` | planted token missed, **exit 0** |
| `check-deployed-references.sh` | `--fixed-strings` | planted `ADR 0021` and `docs/adr/0021-thing.md` missed, **exit 0** |
| `check-deployed-references.sh` | `--glob !*.md` | both missed, **exit 0** |
| `check-carrier-drift.sh` | `--max-count 1` | scan finds no dispatch carrier, spurious failure |
| `check-carrier-drift.sh` | `--files-without-match` | arithmetic error on a path used as a line number, crash |
| suite assertions (`rg -q -F … `) | `--invert-match` | `assert present` passes on an absent needle, **exit 0** |
| suite assertions | `--glob !*`, `--max-count 0` | `assert present` fails on a present needle |

The first four rows are the finding that matters. `check-public-safety.sh` is
the gate that keeps credentials, host paths, and tenant names out of a public
repository; steered, it prints nothing and exits 0, which is indistinguishable
from a clean tree.

`check-carrier-drift.sh` is fail-closed — its expected-site manifest counts
carriers per file, so a scan steered to find fewer fails rather than passes — but
its verdict still depends on the environment, and a developer with a personal
ripgreprc gets a red `just verify` with no usable diagnostic.

`check-shared-standards.sh` is **not** exposed, contrary to the issue body:
commit `b27788d` already added `unset RIPGREP_CONFIG_PATH` at its top with a
written rationale. Verified: all four hostile configs above leave its verdict
unchanged. `check-deployed-membership.sh` invokes no ripgrep at all — record 0045
chose `find` for this exact reason.

### Two blind spots that are not about the config

Both were closed in `check-skill-layout.sh` by #101 and both are still open in
`check-public-safety.sh`:

- **A NUL byte.** ripgrep judges a file binary on one NUL and skips it during
  directory traversal. A file holding `token: ghp_…` and a NUL anywhere is not
  scanned. Reproduced: exit 0.
- **A spoofed byte-order mark.** A `\xFF\xFE` prefix makes ripgrep transcode the
  rest as UTF-16LE, garbling ASCII content so the pattern cannot match.
  Reproduced: exit 0. `--encoding none` disables the sniffing.

## Scope

In: every tracked shell source reached by `just verify` that invokes `rg`.
Enumerated from the tree rather than from the issue's list:

| Source | ripgrep call sites | State |
| --- | --- | --- |
| `scripts/check-public-safety.sh` | 1 | exposed |
| `scripts/check-deployed-references.sh` | 2 | exposed |
| `scripts/check-carrier-drift.sh` | 1 | exposed |
| `scripts/check-shared-standards.sh` | 2 | already `unset`-hardened |
| `scripts/check-skill-layout.sh` | 4 | already `--no-config`-hardened; **excluded**, owned by #127 |
| `scripts/check-shared-standards-test.sh` | 6 | exposed |
| `scripts/check-deployed-references-test.sh` | 1 | exposed |
| `scripts/check-skill-layout-test.sh` | 6 | already hardened; **excluded**, owned by #127 |
| `install-tools-test.sh` | 2 | exposed |
| `install-test.sh` | 1 | exposed |

Out: `scripts/check-deployed-membership.sh` and its suite (no ripgrep);
`Justfile`'s `hooks` recipe (a real but distinct exposure — `rg -qxF` deciding
whether a pre-push hook is the managed one — recorded as follow-up work because
`hooks` is not a gate and not in the `verify` chain); the encoding contract for
the installed content trees, owned by #127; what any gate's scan set is.

## Requirements

R1. No source in the table above lets `RIPGREP_CONFIG_PATH` change its verdict.

R2. `check-public-safety.sh` catches a planted secret under each of the four
demonstrated hostile configs, and in a file carrying a NUL byte or a spoofed
UTF-16 byte-order mark.

R3. Every recursive scan in a touched gate either passes `--text`, or the source
records why the file ripgrep would skip cannot carry a violation.

R4. A guard fails `just verify` when a shell source invokes ripgrep without
neutralising the config, so a gate added later cannot regress R1 silently.

R5. Every hardening has a test that reddens when the hardening is reverted.

R6. `just verify` passes bare.

## Design

### Neutralisation: one `unset` per file

Each affected source gains a single statement near its top:

```sh
unset RIPGREP_CONFIG_PATH
```

This is the idiom `check-shared-standards.sh` already carries. It is preferred
over per-call `--no-config` because the defect being fixed *is* a missing flag at
a call site: a file-scope `unset` covers every ripgrep the source runs, including
the one somebody adds next year. Record 0051 holds the argument and the rejected
alternatives.

`--no-config` remains sound and stays in `check-skill-layout.sh`. The guard in R4
therefore checks the *property* — this invocation cannot read a config file — and
accepts either form. Converging that file on the `unset` idiom is follow-up work;
it is excluded here because #127 is editing it concurrently.

### Suites: `unset` at the top, hostile config per invocation

A suite must be able to set a hostile config *for the gate it runs* while its own
assertions stay immune. So each suite unsets the variable at its top and passes a
hostile value as a one-shot environment assignment on the specific invocation
under test:

```sh
RIPGREP_CONFIG_PATH="$SCRATCH/hostile-rc" "$CHECKER" "$fixture"
```

That form leaves the suite's own environment unchanged, so the assertion that
reads the captured output cannot be steered by the same file.

### Semantic flags, decided per gate

Two threat models are in play and they want different answers, so the flags are
not copied across gates.

**Adversarial input — `check-public-safety.sh`.** Its subject is content someone
may be trying to get past it, and its failure mode is a silent false green on a
public repository. It takes `--text` and `--encoding none`: both bypasses are
reproduced above and both are one line of file content to trigger.

`--encoding none` is a trade. A file genuinely stored as UTF-16 is scanned today
and would not be after the change, because its bytes interleave NULs and the
patterns are ASCII. Accepted: no tracked file in this repository is UTF-16 (every
tracked file reports a text or JSON MIME type), the gate's threat model is a
deliberate prefix rather than an accident, and a scanner with a documented
five-byte bypass is the worse of the two.

`--text` is free here for the same reason — the repository tracks no binary
files, so nothing new enters the scan.

**Drift detection — `check-deployed-references.sh`, `check-carrier-drift.sh`,
`check-shared-standards.sh`.** Their subject is first-party documentation this
repository authors, and the failure they prevent is accidental divergence, not
evasion. They take `--text`, because a stray NUL is a plausible accident (a bad
paste, a truncated write) and a skipped file is an undetected violation.

They do **not** take `--encoding none`. Under an accident model it is the wrong
direction: a file mistakenly saved as UTF-16 is scanned correctly today, and
`--encoding none` would make it invisible. This is the R3 escape clause used
deliberately, and it also keeps the encoding contract for the content trees where
#127 is settling it.

`check-shared-standards.sh`'s `marker_lines` reads one explicitly named file, not
a directory, and ripgrep does not skip an explicit argument — it prints
`binary file matches (found "\0" byte around offset N)` instead of the numbered
lines the caller parses, which the caller's `sed 's/:.*//'` then turns into a
bogus line number. `--text` fixes the parse, so it applies to that call too.

### The guard: `scripts/check-ripgrep-config.sh`

For every tracked shell source (`scripts/list-shell-sources.sh --all -z`, the
same discovery `just lint` uses, so a new script is covered with no edit here):

1. Strip comments and quoted spans, and join backslash continuations, so a
   ripgrep *mentioned* in a message or a test fixture is not read as one run.
   Two such mentions exist today and both must stay green:
   `scripts/claude-settings-hooks-test.sh` embeds `'just ci | rg -n error'` as
   hook test data, and `scripts/check-carrier-drift.sh` writes
   `"could not scan $skills (rg exit $status)"`.
2. Find every logical line that starts a command with `rg`, allowing leading
   `VAR=value` assignments and the usual command separators.
3. The file passes when it contains a bare `unset RIPGREP_CONFIG_PATH`
   statement, or when every such logical line carries `--no-config`.

Exit 0 clean, 1 on a finding naming `file:line`, 2 on a fault (discovery failed,
a source is unreadable). No exemption list: a file that genuinely never runs
ripgrep produces no invocation and is never asked for the statement.

Wired as a `ripgrep-config-check` recipe on `commit-check`, beside `lint` and
`format-check` — it is a static source check, it costs one `git ls-files` and one
`awk` pass, and record 0039 puts the static gates on the recipe the pre-commit
hook runs. `verify` depends on `commit-check`, so CI gates it too.

## Verification

Each row reddens when its hardening is reverted; that is the acceptance test, and
each is run against the reverted source before the change is called done.

| Test | Reddens when |
| --- | --- |
| public-safety catches a planted token under each of the four hostile configs | the `unset` is removed |
| public-safety catches a token in a file holding a NUL byte | `--text` is removed |
| public-safety catches a token in a file prefixed `\xFF\xFE` | `--encoding none` is removed |
| deployed-references reports a planted bare ADR reference under a hostile config | the `unset` is removed |
| deployed-references reports one in a NUL-carrying file | `--text` is removed |
| carrier-drift's verdict is unchanged under a hostile `--max-count 1` config | the `unset` is removed |
| shared-standards reports drift in a NUL-carrying mirror | `--text` is removed |
| the guard fails a fixture invoking `rg` with neither form | the guard is removed |
| the guard passes a fixture using `unset`, and one using per-call `--no-config` | either branch is dropped |
| the guard passes a fixture mentioning `rg` only in a comment, a single-quoted string, and a double-quoted message | the stripping is dropped |
| the guard fails a fixture whose `rg` call is split across a `\` continuation with no `--no-config` | continuation joining is dropped |
| the guard reports exit 2 when source discovery fails | the fault path is dropped |

Suite fixtures are created under each suite's existing `mktemp -d` scratch
directory and removed by its existing `trap`, so no test leaves temporary state.

## Security

This change only removes an attacker's and a bystander's influence over a gate's
verdict. It adds no entry point, reads no new input, and grants no permission.

Trust boundary touched: the process environment of a gate run. Actors: a
developer's own shell (a misconfigured ripgreprc, the accidental case), and
anything that can set an environment variable for a `just verify` or CI run (the
deliberate case). The control is that the gates stop reading that variable.

Out of scope: `.gitignore` and `.ignore` still remove files from
`check-public-safety.sh`'s scan, and `.git` is excluded by an explicit glob.
Changing the scan set is a different decision from removing the config input, and
this change does not make it.
