#!/usr/bin/env bash
set -euo pipefail

fail() {
	printf 'install-identity-test: %s\n' "$*" >&2
	exit 1
}

assert_eq() {
	local expected="$1"
	local actual="$2"

	[[ "$actual" == "$expected" ]] ||
		fail "expected $expected, got $actual"
}

assert_fails() {
	local expected="$1"
	shift
	local output
	local status

	set +e
	output="$("$@" 2>&1)"
	status="$?"
	set -e
	[[ "$status" -ne 0 ]] || fail "expected failure: $*"
	printf '%s\n' "$output" | rg -Fq "$expected" ||
		fail "expected failure output to contain: $expected"
}

filesystem_kind_with_test_kind() {
	local kind="$1"
	local path="$2"

	AGENT_CONFIG_TEST_FILESYSTEM_KIND="$kind" filesystem_kind "$path"
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The test finds the sibling implementation independently of the current directory.
# shellcheck disable=SC1091
# shellcheck source=install-identity.sh
source "$script_dir/install-identity.sh"

fixture="$(mktemp -d "${TMPDIR:-/tmp}/agent-config-identity-test.XXXXXX")"
trap 'rm -R "$fixture"' EXIT
bad_name=$'bad\nname'
invalid_utf8_name=$'\377'

mkdir "$fixture/empty" "$fixture/unicode" "$fixture/case" "$fixture/controls"
mkdir "$fixture/invalid-utf8"
mkdir -p "$fixture/with-empty/empty"
printf 'plain\n' >"$fixture/regular"
printf 'run\n' >"$fixture/executable"
chmod 755 "$fixture/executable"
printf 'utf8\n' >"$fixture/unicode/café"
ln -s regular "$fixture/symlink"
mkfifo "$fixture/socket"
printf 'case upper\n' >"$fixture/case/Name"
printf 'case lower\n' >"$fixture/case/name"
printf 'bad\n' >"$fixture/controls/$bad_name"
printf 'invalid\n' >"$fixture/invalid-utf8/$invalid_utf8_name"

assert_eq "sha1" "$(identity_object_format)"
assert_eq "absent" "$(identity_absent)"
assert_eq "absent" "$(identity_path "$fixture/absent")"
assert_eq \
	"tree-v1-git-blob:sha1:e69de29bb2d1d6434b8b29ae775ad8c2e48c5391" \
	"$(identity_path "$fixture/empty")"
assert_eq \
	"tree-v1-git-blob:sha1:032fcea913880cdeb5176f78c7e65fb0ef4c7c29" \
	"$(identity_path "$fixture/with-empty")"
assert_eq \
	"tree-v1-git-blob:sha1:763249706dbffad6c1946c80a4ec4f87df5012fe" \
	"$(identity_path "$fixture/regular")"
assert_eq \
	"tree-v1-git-blob:sha1:bb09d0895d0dd0a25e70f2fe29dffb78ce9a5d34" \
	"$(identity_path "$fixture/executable")"
assert_eq \
	"tree-v1-git-blob:sha1:7482f48d523c9381336df90dc9f6e8a0efcfd8a8" \
	"$(identity_path "$fixture/unicode")"
assert_eq \
	"tree-v1-git-blob:sha1:59e98b15e2c3d60e9be2a58e84a98d203bb45a82" \
	"$(identity_path "$fixture/symlink")"

assert_fails 'identity: unsupported special file' identity_path "$fixture/socket"
assert_fails 'identity: control character in path' identity_path "$fixture/controls"
assert_fails 'identity: invalid UTF-8 path' identity_path "$fixture/invalid-utf8"
assert_fails 'identity: case-fold collision' identity_path "$fixture/case"

require_portable_rel 'nested/file-1.txt'
assert_fails 'identity: path must be relative' require_portable_rel '/absolute'
assert_fails 'identity: unsafe path component' require_portable_rel 'one/../two'
assert_fails 'identity: unsafe path component' require_portable_rel 'name.'
assert_fails 'identity: non-ASCII path component' require_portable_rel 'café'
assert_fails 'identity: path component exceeds 100 bytes' \
	require_portable_rel "$(printf 'a%.0s' {1..101})"

assert_eq 'ext4' "$(filesystem_kind_with_test_kind ext4 "$fixture")"
for unsupported_kind in nfs nfs4 smbfs cifs afpfs fuse.sshfs mysteryfs; do
	assert_fails "identity: unsupported filesystem: $unsupported_kind" \
		filesystem_kind_with_test_kind "$unsupported_kind" "$fixture"
done

printf 'install-identity-test: ok\n'
