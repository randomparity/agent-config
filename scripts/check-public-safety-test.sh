#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECKER="$ROOT/scripts/check-public-safety.sh"

# The cases below hand the gate a hostile RIPGREP_CONFIG_PATH one invocation at
# a time. Unsetting it here keeps the value this suite inherited from steering
# the baseline cases, which assert the gate stays green (record 0051).
unset RIPGREP_CONFIG_PATH

SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/public-safety-test.XXXXXX")"

cleanup() {
	case "$SCRATCH" in
	"${TMPDIR:-/tmp}"/public-safety-test.*) rm -R "$SCRATCH" ;;
	*) printf 'public-safety-test: refusing cleanup outside scratch root: %s\n' "$SCRATCH" >&2 ;;
	esac
}
trap cleanup EXIT

mkdir -p "$SCRATCH/repo"
printf 'gitdir: /Vol%s/Private Disk/repo/.git/worktrees/example\n' 'umes' >"$SCRATCH/repo/.git"
printf 'public content\n' >"$SCRATCH/repo/README.md"

if ! "$CHECKER" "$SCRATCH/repo" >"$SCRATCH/output" 2>&1; then
	printf 'public-safety-test: Git metadata should be excluded\n' >&2
	cat "$SCRATCH/output" >&2
	exit 1
fi

printf 'private path: /Us%s/example-user/project\n' 'ers' >"$SCRATCH/repo/private.txt"
if "$CHECKER" "$SCRATCH/repo" >"$SCRATCH/output" 2>&1; then
	printf 'public-safety-test: repository content leak should fail\n' >&2
	exit 1
fi

if ! grep -qF 'public-safety: denied pattern matched' "$SCRATCH/output"; then
	printf 'public-safety-test: failure should identify the denied pattern\n' >&2
	cat "$SCRATCH/output" >&2
	exit 1
fi

rm -f "$SCRATCH/repo/private.txt"

# A tenant hostname is host-specific identity, which AGENTS.md bars from tracked
# files in this public repo. Assembled at runtime so this test file is not
# itself a match.
printf 'see acme-corp.%s for the board\n' 'atlassian.net' >"$SCRATCH/repo/tenant.md"
if "$CHECKER" "$SCRATCH/repo" >"$SCRATCH/output" 2>&1; then
	printf 'public-safety-test: tenant hostname leak should fail\n' >&2
	exit 1
fi
rm -f "$SCRATCH/repo/tenant.md"

# Atlassian's own public API domain is not tenant identity and must not match,
# or every design doc citing the REST endpoint fails the gate.
printf 'call api.%s/ex/jira/{cloudId}/rest/api/3\n' 'atlassian.com' \
	>"$SCRATCH/repo/endpoint.md"
if ! "$CHECKER" "$SCRATCH/repo" >"$SCRATCH/output" 2>&1; then
	printf 'public-safety-test: public API domain should not be denied\n' >&2
	cat "$SCRATCH/output" >&2
	exit 1
fi
rm -f "$SCRATCH/repo/endpoint.md"

# An Atlassian API token is a credential shape, like the GitHub, OpenAI, AWS and
# Slack shapes beside it. Assembled at runtime so this test file is not itself a
# match for the scan it exercises.
printf 'token = %s%s\n' 'ATATT' '3xFfGF0T00000000000000000000000000000000' \
	>"$SCRATCH/repo/token.md"
if "$CHECKER" "$SCRATCH/repo" >"$SCRATCH/output" 2>&1; then
	printf 'public-safety-test: Atlassian API token leak should fail\n' >&2
	exit 1
fi
rm -f "$SCRATCH/repo/token.md"

# The token is not always held in plaintext: the documented form here is
# base64(email:token) in an ATLASSIAN_-prefixed variable, which contains no
# literal ATATT at any alignment and does not carry the `Basic ` header word
# either, so neither shape above sees it.
# A credential reaches a file in whatever syntax its container uses, so the
# bare assignment is the least likely of the four rather than the only one.
b64=ZXhhbXBsZUBleGFtcGxlLmNvbTpub3RhcmVhbHRva2Vu
while IFS= read -r form; do
	printf '%s\n' "$form" >"$SCRATCH/repo/env.md"
	if "$CHECKER" "$SCRATCH/repo" >"$SCRATCH/output" 2>&1; then
		printf 'public-safety-test: Atlassian credential leak should fail: %s\n' \
			"$form" >&2
		exit 1
	fi
done <<FORMS
$(printf '%s_MCP_BASIC_AUTH=%s' 'ATLASSIAN' "$b64")
$(printf 'export %s_MCP_BASIC_AUTH="%s"' 'ATLASSIAN' "$b64")
$(printf "%s_MCP_BASIC_AUTH='%s'" 'ATLASSIAN' "$b64")
$(printf '  "%s_MCP_BASIC_AUTH": "%s",' 'ATLASSIAN' "$b64")
$(printf '  %s_MCP_BASIC_AUTH: %s' 'ATLASSIAN' "$b64")
FORMS
rm -f "$SCRATCH/repo/env.md"

# Naming the variable is not disclosing its value; the setup docs have to.
printf 'set %s_MCP_BASIC_AUTH in your shell profile\n' 'ATLASSIAN' \
	>"$SCRATCH/repo/setup.md"
if ! "$CHECKER" "$SCRATCH/repo" >"$SCRATCH/output" 2>&1; then
	printf 'public-safety-test: naming the variable should not be denied\n' >&2
	cat "$SCRATCH/output" >&2
	exit 1
fi
rm -f "$SCRATCH/repo/setup.md"

# The prefix alone is not a credential. Prose naming the token format must not
# fail the gate, or the design docs describing it cannot be committed.
printf 'Atlassian API tokens begin %s.\n' 'ATATT' >"$SCRATCH/repo/prose.md"
if ! "$CHECKER" "$SCRATCH/repo" >"$SCRATCH/output" 2>&1; then
	printf 'public-safety-test: token prefix in prose should not be denied\n' >&2
	cat "$SCRATCH/output" >&2
	exit 1
fi
rm -f "$SCRATCH/repo/prose.md"

# A credential shape the scan is meant to catch, assembled at runtime so this
# suite is not itself a match for the gate that scans it.
planted="token: $(printf '%s%s' 'ghp' '_abcdefghijklmnopqrstuvwxyz01')"

# ripgrep applies the contents of RIPGREP_CONFIG_PATH as arguments ahead of the
# ones the gate passes, so whoever sets that variable chooses what the secret
# scanner matches. Each directive below was reproduced against the unhardened
# gate: the planted token went unreported and the gate exited 0 -- the same
# answer it gives for a clean tree, which is the worst shape a security gate can
# fail in. Record 0051.
printf '%s\n' "$planted" >"$SCRATCH/repo/planted.md"
while IFS= read -r directive; do
	printf -- '%s\n' "$directive" >"$SCRATCH/rgconfig"
	if RIPGREP_CONFIG_PATH="$SCRATCH/rgconfig" "$CHECKER" "$SCRATCH/repo" \
		>"$SCRATCH/output" 2>&1; then
		printf 'public-safety-test: a ripgrep config of %s hid a planted secret\n' \
			"$directive" >&2
		exit 1
	fi
done <<'DIRECTIVES'
--fixed-strings
--glob=!*.md
--max-count=0
--encoding=utf-16le
DIRECTIVES
rm -f "$SCRATCH/repo/planted.md" "$SCRATCH/rgconfig"

# ripgrep judges a file binary on a single NUL byte and skips it during
# directory traversal, so a secret in a file carrying one anywhere is not
# scanned at all. --text is what keeps it in view.
printf '%s\n\000trailing\n' "$planted" >"$SCRATCH/repo/nul.md"
if "$CHECKER" "$SCRATCH/repo" >"$SCRATCH/output" 2>&1; then
	printf 'public-safety-test: a NUL byte hid a planted secret\n' >&2
	exit 1
fi
rm -f "$SCRATCH/repo/nul.md"

# A leading \xFF\xFE makes ripgrep transcode the rest of the file as UTF-16LE,
# so ASCII content is garbled into something the ASCII patterns cannot match --
# a five-byte prefix that bypasses the scanner. --encoding none stops the
# sniffing. The trade is recorded in 0051: no tracked file here is UTF-16.
printf '\377\376%s\n' "$planted" >"$SCRATCH/repo/bom.md"
if "$CHECKER" "$SCRATCH/repo" >"$SCRATCH/output" 2>&1; then
	printf 'public-safety-test: a spoofed UTF-16 mark hid a planted secret\n' >&2
	exit 1
fi
rm -f "$SCRATCH/repo/bom.md"

# A file can be tracked and ignored at once: `git add -f` on a path a .gitignore
# or .ignore names puts it in the index, so it ships to everyone who clones this
# public repo, while ripgrep's walk -- which applies those same rules to tracked
# files -- never opens it. Before the gate named its tracked files explicitly it
# printed nothing and exited 0 here, the same answer it gives for a clean tree.
#
# The suite unsets git's local environment so a caller's GIT_DIR or
# GIT_INDEX_FILE cannot reach these fixtures (ADR 0044).
while IFS= read -r variable; do
	[ -n "$variable" ] || continue
	unset "$variable"
done < <(git rev-parse --local-env-vars)

hidden_secret="token: $(printf '%s%s' 'ghp' '_abcdefghijklmnopqrstuvwxyz01')"

for ignore_file in .gitignore .ignore; do
	fixture="$SCRATCH/hidden-$ignore_file"
	mkdir -p "$fixture/sub"
	git init -q -b main "$fixture"
	git -C "$fixture" config user.name 'Fixture Developer'
	git -C "$fixture" config user.email fixture@example.invalid
	printf '%s\n' "$hidden_secret" >"$fixture/sub/leak.txt"
	printf 'sub/leak.txt\n' >"$fixture/$ignore_file"
	git -C "$fixture" add -f sub/leak.txt "$ignore_file"
	git -C "$fixture" commit -qm 'tracked but ignored'

	# The premise: git ships it. If this stops holding the case proves nothing.
	if ! git -C "$fixture" ls-files | grep -qF sub/leak.txt; then
		printf 'public-safety-test: fixture is not tracked, case is void: %s\n' \
			"$ignore_file" >&2
		exit 1
	fi
	if "$CHECKER" "$fixture" >"$SCRATCH/output" 2>&1; then
		printf 'public-safety-test: %s hid a secret in a tracked file\n' \
			"$ignore_file" >&2
		exit 1
	fi
done

# The other half of the same rule: an ignored file that is *untracked* never
# ships, so scanning it would fail the gate on host-specific content that is
# ignored precisely to keep it out of the tracked tree -- CLAUDE.local.md here.
# This is what a bare --no-ignore would break, and it must stay green.
untracked="$SCRATCH/untracked-ignored"
mkdir -p "$untracked"
git init -q -b main "$untracked"
git -C "$untracked" config user.name 'Fixture Developer'
git -C "$untracked" config user.email fixture@example.invalid
printf 'public content\n' >"$untracked/README.md"
printf 'CLAUDE.local.md\n' >"$untracked/.gitignore"
git -C "$untracked" add README.md .gitignore
git -C "$untracked" commit -qm 'public seed'
printf '%s\n' "$hidden_secret" >"$untracked/CLAUDE.local.md"
if ! "$CHECKER" "$untracked" >"$SCRATCH/output" 2>&1; then
	printf 'public-safety-test: an untracked ignored file must not fail the gate\n' >&2
	cat "$SCRATCH/output" >&2
	exit 1
fi

printf 'public-safety-test: ok\n'
