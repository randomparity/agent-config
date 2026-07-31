#!/usr/bin/env bash
set -euo pipefail

fail() {
	printf 'install-tools-test: %s\n' "$*" >&2
	exit 1
}

assert_contains() {
	local haystack="$1"
	local needle="$2"

	printf '%s\n' "$haystack" | rg -q --fixed-strings "$needle" ||
		fail "expected output to contain: $needle"
}

assert_not_contains() {
	local haystack="$1"
	local needle="$2"

	if printf '%s\n' "$haystack" | rg -q --fixed-strings "$needle"; then
		fail "expected output not to contain: $needle"
	fi
}

assert_success() {
	local status="$1"
	local context="$2"

	[[ "$status" -eq 0 ]] || fail "$context failed with status $status"
}

assert_failure() {
	local status="$1"
	local context="$2"

	[[ "$status" -ne 0 ]] || fail "$context unexpectedly succeeded"
}

write_os_release() {
	local path="$1"
	local body="$2"

	printf '%s\n' "$body" >"$path"
}

run_plan() {
	local uname_s="$1"
	local os_release="$2"
	local missing="${3:-just jq rg shellcheck shfmt gh prek actionlint zizmor}"
	local status
	local captured

	set +e
	captured="$(
		AGENT_CONFIG_DRY_RUN=1 \
			AGENT_CONFIG_TEST_UNAME="$uname_s" \
			AGENT_CONFIG_OS_RELEASE_FILE="$os_release" \
			AGENT_CONFIG_FAKE_MISSING="$missing" \
			./install-tools.sh 2>&1
	)"
	status="$?"
	set -e
	printf '%s\n%s\n' "$status" "$captured"
}

capture_status() {
	printf '%s\n' "$1" | sed -n '1p'
}

capture_output() {
	printf '%s\n' "$1" | sed '1d'
}

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/agent-config-tools-test.XXXXXX")"
trap 'rm -R "$tmpdir"' EXIT

ubuntu_release="$tmpdir/ubuntu-os-release"
debian_release="$tmpdir/debian-os-release"
fedora_release="$tmpdir/fedora-os-release"
rhel_release="$tmpdir/rhel-os-release"
unknown_release="$tmpdir/unknown-os-release"

write_os_release "$ubuntu_release" 'ID=ubuntu
ID_LIKE=debian'
write_os_release "$debian_release" 'ID=debian'
write_os_release "$fedora_release" 'ID=fedora'
write_os_release "$rhel_release" 'ID="rocky"
ID_LIKE="rhel centos fedora"'
write_os_release "$unknown_release" 'ID=example'

set +e
check_output="$(AGENT_CONFIG_FAKE_MISSING="just" ./install-tools.sh --check 2>&1)"
check_status="$?"
set -e
assert_failure "$check_status" "fake missing check mode"
assert_contains "$check_output" "missing required tools"
assert_contains "$check_output" "just"

captured="$(run_plan Darwin "$ubuntu_release")"
status="$(capture_status "$captured")"
plan_output="$(capture_output "$captured")"
assert_success "$status" "macOS dry-run plan"
assert_contains "$plan_output" "install-tools: would run: brew install"
assert_contains "$plan_output" "ripgrep"
assert_contains "$plan_output" "prek"

captured="$(run_plan Linux "$ubuntu_release")"
status="$(capture_status "$captured")"
plan_output="$(capture_output "$captured")"
assert_success "$status" "Ubuntu dry-run plan"
assert_contains "$plan_output" "install-tools: would run: sudo apt-get update"
assert_contains "$plan_output" "install-tools: would run: sudo apt-get install -y"
assert_contains "$plan_output" "ripgrep"
assert_contains "$plan_output" "shellcheck"

captured="$(run_plan Linux "$debian_release")"
status="$(capture_status "$captured")"
plan_output="$(capture_output "$captured")"
assert_success "$status" "Debian dry-run plan"
assert_contains "$plan_output" "install-tools: would run: sudo apt-get install -y"

captured="$(run_plan Linux "$fedora_release")"
status="$(capture_status "$captured")"
plan_output="$(capture_output "$captured")"
assert_success "$status" "Fedora dry-run plan"
assert_contains "$plan_output" "install-tools: would run: sudo dnf install -y"
assert_contains "$plan_output" "ShellCheck"

fake_bin="$tmpdir/bin"
mkdir -p "$fake_bin"
printf '#!/usr/bin/env bash\nexit 0\n' >"$fake_bin/dnf"
chmod +x "$fake_bin/dnf"
captured="$(
	PATH="$fake_bin:$PATH" run_plan Linux "$rhel_release"
)"
status="$(capture_status "$captured")"
plan_output="$(capture_output "$captured")"
assert_success "$status" "RHEL dnf dry-run plan"
assert_contains "$plan_output" "install-tools: would run: sudo dnf install -y"

mv "$fake_bin/dnf" "$fake_bin/dnf.disabled"
printf '#!/usr/bin/env bash\nexit 0\n' >"$fake_bin/yum"
chmod +x "$fake_bin/yum"
captured="$(
	PATH="$fake_bin:$PATH" run_plan Linux "$rhel_release"
)"
status="$(capture_status "$captured")"
plan_output="$(capture_output "$captured")"
assert_success "$status" "RHEL yum dry-run plan"
assert_contains "$plan_output" "install-tools: would run: sudo yum install -y"

captured="$(run_plan Linux "$unknown_release")"
status="$(capture_status "$captured")"
plan_output="$(capture_output "$captured")"
assert_failure "$status" "unknown Linux dry-run plan"
assert_contains "$plan_output" "unsupported Linux distribution family"

set +e
fallback_output="$(
	AGENT_CONFIG_DRY_RUN=1 \
		AGENT_CONFIG_SKIP_PACKAGE_MANAGER=1 \
		AGENT_CONFIG_FAKE_MISSING="shfmt actionlint prek zizmor" \
		./install-tools.sh 2>&1
)"
fallback_status="$?"
set -e
assert_success "$fallback_status" "fallback dry-run plan"
assert_contains "$fallback_output" "go install mvdan.cc/sh/v3/cmd/shfmt@v3.13.1"
assert_contains "$fallback_output" "go install github.com/rhysd/actionlint/cmd/actionlint@v1.7.12"
assert_contains "$fallback_output" "cargo install --locked prek --version 0.4.11"
assert_contains "$fallback_output" "cargo install --locked zizmor --version 1.28.0"

runtime_bin="$tmpdir/runtime-bin"
mkdir -p "$runtime_bin"
for command_name in just jq rg shellcheck shfmt gh actionlint zizmor; do
	cat >"$runtime_bin/$command_name" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
	chmod +x "$runtime_bin/$command_name"
done

cat >"$runtime_bin/cargo" <<'EOF'
#!/usr/bin/env bash
exit 17
EOF
cat >"$runtime_bin/uv" <<'EOF'
#!/usr/bin/env bash
bin_dir="$(cd "$(dirname "$0")" && pwd)"
printf '#!/usr/bin/env bash\nexit 0\n' >"$bin_dir/prek"
chmod +x "$bin_dir/prek"
printf 'fake uv installed prek\n'
exit 0
EOF
chmod +x "$runtime_bin/cargo" "$runtime_bin/uv"

set +e
runtime_fallback_output="$(
	PATH="$runtime_bin:/usr/bin:/bin" \
		AGENT_CONFIG_SKIP_PACKAGE_MANAGER=1 \
		./install-tools.sh 2>&1
)"
runtime_fallback_status="$?"
set -e
assert_success "$runtime_fallback_status" "runtime fallback after failed cargo"
assert_contains "$runtime_fallback_output" "install-tools: cargo fallback failed for prek"
assert_contains "$runtime_fallback_output" "fake uv installed prek"
assert_not_contains "$runtime_fallback_output" "could not install prek automatically"

path_bin="$tmpdir/path-bin"
path_home="$tmpdir/path-home"
github_path="$tmpdir/github-path"
mkdir -p "$path_bin" "$path_home"
for command_name in jq rg shellcheck shfmt gh prek actionlint zizmor; do
	cat >"$path_bin/$command_name" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
	chmod +x "$path_bin/$command_name"
done

cat >"$path_bin/cargo" <<'EOF'
#!/usr/bin/env bash
install_dir="$HOME/.cargo/bin"
mkdir -p "$install_dir"
printf '#!/usr/bin/env bash\nexit 0\n' >"$install_dir/just"
chmod +x "$install_dir/just"
printf 'fake cargo installed just\n'
exit 0
EOF
chmod +x "$path_bin/cargo"

set +e
path_fallback_output="$(
	PATH="$path_bin:/usr/bin:/bin" \
		HOME="$path_home" \
		GITHUB_PATH="$github_path" \
		AGENT_CONFIG_SKIP_PACKAGE_MANAGER=1 \
		./install-tools.sh 2>&1
)"
path_fallback_status="$?"
set -e
assert_success "$path_fallback_status" "fallback-installed binary path"
assert_contains "$path_fallback_output" "fake cargo installed just"
assert_contains "$(cat "$github_path")" "$path_home/.cargo/bin"

printf 'install-tools-test: ok\n'
