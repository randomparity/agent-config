#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECKER="$ROOT/scripts/check-change-aware-policy.sh"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/change-aware-policy-test.XXXXXX")"
REPO="$SCRATCH/repo"

cleanup() {
	case "$SCRATCH" in
	"${TMPDIR:-/tmp}"/change-aware-policy-test.*) rm -R "$SCRATCH" ;;
	*) printf 'change-aware-policy-test: refusing cleanup: %s\n' "$SCRATCH" >&2 ;;
	esac
}
trap cleanup EXIT

if [[ ! -x "$CHECKER" ]]; then
	printf 'change-aware-policy-test: checker does not exist: %s\n' "$CHECKER" >&2
	exit 127
fi

copy_fixture() {
	rm -R "$REPO" 2>/dev/null || :
	mkdir -p "$REPO"
	cp "$ROOT/Justfile" "$REPO/Justfile"
	cp "$ROOT"/install*.sh "$REPO"
	cp -R "$ROOT/scripts" "$REPO/scripts"
	mkdir -p "$REPO/.github"
	cp -R "$ROOT/.github/scripts" "$REPO/.github/scripts"
	cp -R "$ROOT/content" "$REPO/content"
	cp -R "$ROOT/agents" "$REPO/agents"
}

assert_passes() {
	if ! "$CHECKER" "$REPO" >"$SCRATCH/output" 2>&1; then
		printf 'not ok - %s should pass\n' "$1" >&2
		cat "$SCRATCH/output" >&2
		exit 1
	fi
}

assert_fails() {
	local name=$1 expected=$2
	if "$CHECKER" "$REPO" >"$SCRATCH/output" 2>&1; then
		printf 'not ok - %s should fail\n' "$name" >&2
		exit 1
	fi
	if ! rg -Fq "$expected" "$SCRATCH/output"; then
		printf 'not ok - %s should report %s\n' "$name" "$expected" >&2
		cat "$SCRATCH/output" >&2
		exit 1
	fi
}

refresh_justfile_fingerprints() {
	local justfile_hash public_safety_hash
	justfile_hash=$(git hash-object "$REPO/Justfile")
	public_safety_hash=$(
		cd "$REPO"
		just --dry-run public-safety 2>&1 |
			sed -E '/^[[:space:]]*#/d; /^[[:space:]]*$/d; s/[[:space:]]+/ /g; s/^ //; s/ $//' |
			git hash-object --stdin
	)
	awk -v hash="$justfile_hash" 'BEGIN { FS = OFS = "\t" }
		$1 !~ /^#/ && $3 == "Justfile" { $4 = hash }
		{ print }' "$REPO/scripts/change-aware-observers.tsv" >"$SCRATCH/manifest"
	awk -v hash="$public_safety_hash" 'BEGIN { FS = OFS = "\t" }
		$1 == "public-safety" { $2 = hash }
		{ print }' "$SCRATCH/manifest" >"$REPO/scripts/change-aware-observers.tsv"
}

copy_fixture
assert_passes 'current manifest'

copy_fixture
printf '\n# stale fingerprint mutation\n' >>"$REPO/scripts/check-public-safety.sh"
assert_fails 'changed directly invoked guard script' 'stale implementation fingerprint'

copy_fixture
cat >>"$REPO/Justfile" <<'EOF'

new-observer:
  ./scripts/new-observer.sh
EOF
printf '#!/usr/bin/env bash\nexit 0\n' >"$REPO/scripts/new-observer.sh"
awk '{ sub(/actions-check$/, "actions-check new-observer"); print }' \
	"$REPO/Justfile" >"$SCRATCH/Justfile"
mv "$SCRATCH/Justfile" "$REPO/Justfile"
assert_fails 'new verify dependency' 'verify dependency is unmanifested: new-observer'

copy_fixture
printf '#!/usr/bin/env bash\nexit 0\n' >"$REPO/scripts/unmanifested-dry-run.sh"
awk '{ print; if ($0 == "public-safety:") print "  ./scripts/unmanifested-dry-run.sh" }' \
	"$REPO/Justfile" >"$SCRATCH/Justfile"
mv "$SCRATCH/Justfile" "$REPO/Justfile"
refresh_justfile_fingerprints
assert_fails 'unmanifested dry-run script' 'dry-run script is unmanifested'

printf 'change-aware-policy-test: ok\n'
