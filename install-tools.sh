#!/usr/bin/env bash
set -euo pipefail

MODE="${1:---install}"
SHFMT_VERSION="v3.13.1"

usage() {
	cat >&2 <<'EOF'
Usage: ./install-tools.sh [--install|--check]

Checks or installs local tools used by this repository:
  jq, rg, shellcheck, shfmt, gh
EOF
}

brew_package() {
	case "$1" in
	jq) printf 'jq\n' ;;
	rg) printf 'ripgrep\n' ;;
	shellcheck) printf 'shellcheck\n' ;;
	shfmt) printf 'shfmt\n' ;;
	gh) printf 'gh\n' ;;
	*) printf '%s\n' "$1" ;;
	esac
}

missing_commands() {
	local command_name

	for command_name in jq rg shellcheck shfmt gh; do
		if ! command -v "$command_name" >/dev/null 2>&1; then
			printf '%s\n' "$command_name"
		fi
	done
}

install_with_brew() {
	local command_name="$1"
	local package

	if [[ "$(uname -s)" != "Darwin" ]] || ! command -v brew >/dev/null 2>&1; then
		return 1
	fi

	package="$(brew_package "$command_name")"
	brew install "$package"
}

install_with_go() {
	local command_name="$1"

	if ! command -v go >/dev/null 2>&1; then
		return 1
	fi

	case "$command_name" in
	shfmt)
		go install "mvdan.cc/sh/v3/cmd/shfmt@$SHFMT_VERSION"
		;;
	*) return 1 ;;
	esac
}

check_mode() {
	local missing

	missing="$(missing_commands)"
	if [[ -z "$missing" ]]; then
		printf 'install-tools: all required tools are available\n'
		return 0
	fi

	printf 'install-tools: missing required tools:\n' >&2
	printf '%s\n' "$missing" >&2
	return 1
}

install_mode() {
	local missing
	local command_name
	local failed=0

	missing="$(missing_commands)"
	if [[ -z "$missing" ]]; then
		printf 'install-tools: all required tools are available\n'
		return 0
	fi

	while IFS= read -r command_name; do
		[[ -n "$command_name" ]] || continue
		if install_with_brew "$command_name"; then
			continue
		fi
		if install_with_go "$command_name"; then
			continue
		fi
		printf 'install-tools: could not install %s automatically\n' "$command_name" >&2
		failed=1
	done <<<"$missing"

	if [[ "$failed" -ne 0 ]]; then
		printf 'install-tools: install missing tools with your system package manager\n' >&2
		return 1
	fi

	check_mode
}

case "$MODE" in
--install) install_mode ;;
--check) check_mode ;;
--help | -h) usage ;;
*)
	usage
	exit 1
	;;
esac
