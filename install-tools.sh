#!/usr/bin/env bash
set -euo pipefail

MODE="${1:---install}"
JUST_VERSION="1.57.0"
SHFMT_VERSION="v3.13.1"
ACTIONLINT_VERSION="v1.7.12"
PREK_VERSION="0.4.11"
ZIZMOR_VERSION="1.28.0"

usage() {
	cat >&2 <<'EOF'
Usage: ./install-tools.sh [--install|--check]

Checks or installs local tools used by this repository:
  just, jq, rg, shellcheck, shfmt, gh, prek, actionlint, zizmor
EOF
}

required_commands() {
	printf '%s\n' \
		just \
		jq \
		rg \
		shellcheck \
		shfmt \
		gh \
		prek \
		actionlint \
		zizmor
}

is_dry_run() {
	[[ "${AGENT_CONFIG_DRY_RUN:-0}" == "1" ]]
}

skip_package_manager() {
	[[ "${AGENT_CONFIG_SKIP_PACKAGE_MANAGER:-0}" == "1" ]]
}

fake_missing() {
	local command_name="$1"
	local fake

	for fake in ${AGENT_CONFIG_FAKE_MISSING:-}; do
		[[ "$fake" == "$command_name" ]] && return 0
	done

	return 1
}

command_exists() {
	local command_name="$1"

	if fake_missing "$command_name"; then
		return 1
	fi

	command -v "$command_name" >/dev/null 2>&1
}

runtime_available() {
	local command_name="$1"

	is_dry_run || command -v "$command_name" >/dev/null 2>&1
}

host_uname() {
	printf '%s\n' "${AGENT_CONFIG_TEST_UNAME:-$(uname -s)}"
}

os_release_file() {
	printf '%s\n' "${AGENT_CONFIG_OS_RELEASE_FILE:-/etc/os-release}"
}

normalize_os_value() {
	printf '%s\n' "$1" | tr -d '"' | tr '[:upper:]' '[:lower:]'
}

linux_family() {
	local file
	local id
	local id_like
	local values

	file="$(os_release_file)"
	[[ -f "$file" ]] || return 1

	id="$(awk -F= '$1 == "ID" {print $2}' "$file")"
	id_like="$(awk -F= '$1 == "ID_LIKE" {print $2}' "$file")"
	values="$(normalize_os_value "$id $id_like")"

	case " $values " in
	*" ubuntu "* | *" debian "*)
		printf 'debian\n'
		;;
	*" rhel "* | *" centos "* | *" rocky "* | *" almalinux "* | *" ol "*)
		printf 'rhel\n'
		;;
	*" fedora "*)
		printf 'fedora\n'
		;;
	*) return 1 ;;
	esac
}

detect_package_manager() {
	local family

	case "$(host_uname)" in
	Darwin)
		if is_dry_run || command -v brew >/dev/null 2>&1; then
			printf 'brew\n'
			return 0
		fi
		return 1
		;;
	Linux)
		if ! family="$(linux_family)"; then
			printf 'install-tools: unsupported Linux distribution family\n' >&2
			return 2
		fi

		case "$family" in
		debian)
			if is_dry_run || command -v apt-get >/dev/null 2>&1; then
				printf 'apt\n'
				return 0
			fi
			;;
		fedora)
			if is_dry_run || command -v dnf >/dev/null 2>&1; then
				printf 'dnf\n'
				return 0
			fi
			;;
		rhel)
			if command -v dnf >/dev/null 2>&1; then
				printf 'dnf\n'
				return 0
			fi
			if command -v yum >/dev/null 2>&1; then
				printf 'yum\n'
				return 0
			fi
			if is_dry_run; then
				printf 'yum\n'
				return 0
			fi
			;;
		esac

		printf 'install-tools: no supported package manager found for %s\n' "$family" >&2
		return 1
		;;
	*)
		return 1
		;;
	esac
}

missing_commands() {
	local command_name

	while IFS= read -r command_name; do
		if ! command_exists "$command_name"; then
			printf '%s\n' "$command_name"
		fi
	done < <(required_commands)
}

package_name() {
	local package_manager="$1"
	local command_name="$2"

	case "$package_manager:$command_name" in
	brew:rg | apt:rg | dnf:rg | yum:rg)
		printf 'ripgrep\n'
		;;
	dnf:shellcheck | yum:shellcheck)
		printf 'ShellCheck\n'
		;;
	*)
		printf '%s\n' "$command_name"
		;;
	esac
}

print_command() {
	local arg

	printf 'install-tools: would run:'
	for arg in "$@"; do
		printf ' %s' "$arg"
	done
	printf '\n'
}

run_command() {
	if is_dry_run; then
		print_command "$@"
		return 0
	fi

	"$@"
}

run_with_sudo() {
	if is_dry_run; then
		run_command sudo "$@"
		return 0
	fi

	if [[ "$(id -u)" -eq 0 ]]; then
		run_command "$@"
		return "$?"
	fi

	if ! command -v sudo >/dev/null 2>&1; then
		printf 'install-tools: sudo is required to run %s\n' "$1" >&2
		return 1
	fi

	run_command sudo "$@"
}

install_package() {
	local package_manager="$1"
	local command_name="$2"
	local package

	package="$(package_name "$package_manager" "$command_name")"
	case "$package_manager" in
	brew)
		run_command brew install "$package"
		;;
	apt)
		run_with_sudo apt-get install -y "$package"
		;;
	dnf)
		run_with_sudo dnf install -y "$package"
		;;
	yum)
		run_with_sudo yum install -y "$package"
		;;
	*) return 1 ;;
	esac
}

install_with_package_manager() {
	local package_manager="$1"
	local missing="$2"
	local command_name
	local failed=0

	if [[ "$package_manager" == "apt" ]]; then
		run_with_sudo apt-get update || return 1
	fi

	while IFS= read -r command_name; do
		[[ -n "$command_name" ]] || continue
		if ! install_package "$package_manager" "$command_name"; then
			printf 'install-tools: package manager could not install %s\n' \
				"$command_name" >&2
			failed=1
		fi
	done <<<"$missing"

	return "$failed"
}

install_with_fallback() {
	local command_name="$1"

	case "$command_name" in
	shfmt)
		runtime_available go ||
			return 1
		run_command go install "mvdan.cc/sh/v3/cmd/shfmt@$SHFMT_VERSION"
		;;
	actionlint)
		runtime_available go ||
			return 1
		run_command go install \
			"github.com/rhysd/actionlint/cmd/actionlint@$ACTIONLINT_VERSION"
		;;
	just)
		runtime_available cargo ||
			return 1
		run_command cargo install --locked just --version "$JUST_VERSION"
		;;
	prek)
		if runtime_available cargo; then
			run_command cargo install --locked prek --version "$PREK_VERSION"
		elif runtime_available uv; then
			run_command uv tool install "prek==$PREK_VERSION"
		elif runtime_available pipx; then
			run_command pipx install "prek==$PREK_VERSION"
		else
			return 1
		fi
		;;
	zizmor)
		if runtime_available cargo; then
			run_command cargo install --locked zizmor --version "$ZIZMOR_VERSION"
		elif runtime_available uv; then
			run_command uv tool install "zizmor==$ZIZMOR_VERSION"
		elif runtime_available pipx; then
			run_command pipx install "zizmor==$ZIZMOR_VERSION"
		else
			return 1
		fi
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
	local package_manager
	local package_manager_status
	local command_name
	local failed=0

	missing="$(missing_commands)"
	if [[ -z "$missing" ]]; then
		printf 'install-tools: all required tools are available\n'
		return 0
	fi

	if ! skip_package_manager; then
		set +e
		package_manager="$(detect_package_manager)"
		package_manager_status="$?"
		set -e

		if [[ "$package_manager_status" -eq 2 ]]; then
			return 1
		fi

		if [[ "$package_manager_status" -eq 0 ]]; then
			if ! install_with_package_manager "$package_manager" "$missing"; then
				:
			fi
			if is_dry_run; then
				return 0
			fi
			missing="$(missing_commands)"
		fi
	fi

	while IFS= read -r command_name; do
		[[ -n "$command_name" ]] || continue
		if install_with_fallback "$command_name"; then
			continue
		fi
		printf 'install-tools: could not install %s automatically\n' "$command_name" >&2
		failed=1
	done <<<"$missing"

	if is_dry_run; then
		return "$failed"
	fi

	if [[ "$failed" -ne 0 ]]; then
		printf 'install-tools: install missing tools manually and re-run --check\n' >&2
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
