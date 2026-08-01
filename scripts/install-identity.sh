#!/usr/bin/env bash
set -euo pipefail

identity_error() {
	printf 'identity: %s\n' "$*" >&2
}

identity_absent() {
	printf 'absent\n'
}

identity_object_format() {
	git rev-parse --show-object-format 2>/dev/null || printf 'sha1\n'
}

write_u64_be() {
	local value="$1"
	local shift
	local byte
	local oct

	for shift in 56 48 40 32 24 16 8 0; do
		byte=$(((value >> shift) & 255))
		printf -v oct '%03o' "$byte"
		printf '%b' "\\$oct"
	done
}

require_portable_rel() {
	local path="${1-}"
	local component
	local remainder
	local LC_ALL=C

	case "$path" in
	'')
		identity_error 'path must be relative'
		return 1
		;;
	/*)
		identity_error 'path must be relative'
		return 1
		;;
	esac

	if ((${#path} > 512)); then
		identity_error 'path exceeds 512 bytes'
		return 1
	fi

	remainder="$path"
	while [[ "$remainder" == */* ]]; do
		component="${remainder%%/*}"
		remainder="${remainder#*/}"
		_identity_require_portable_component "$component" || return 1
	done
	_identity_require_portable_component "$remainder"
}

_identity_require_portable_component() {
	local component="$1"
	local LC_ALL=C

	case "$component" in
	'' | . | ..)
		identity_error 'unsafe path component'
		return 1
		;;
	esac

	if ((${#component} > 100)); then
		identity_error 'path component exceeds 100 bytes'
		return 1
	fi

	if [[ "$component" == *[![:ascii:]]* ]]; then
		identity_error 'non-ASCII path component'
		return 1
	fi

	case "$component" in
	*.)
		identity_error 'unsafe path component'
		return 1
		;;
	esac

	if [[ ! "$component" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
		identity_error 'unsafe path component'
		return 1
	fi
}

filesystem_kind() {
	local path="${1-}"
	local kind

	if [[ -n "${AGENT_CONFIG_TEST_FILESYSTEM_KIND:-}" ]]; then
		kind="$AGENT_CONFIG_TEST_FILESYSTEM_KIND"
	elif [[ "$(uname -s)" == 'Darwin' ]]; then
		kind="$(stat -f '%T' "$path")" || {
			identity_error "could not determine filesystem: $path"
			return 1
		}
	else
		kind="$(stat -f -c '%T' "$path")" || {
			identity_error "could not determine filesystem: $path"
			return 1
		}
	fi

	kind="$(LC_ALL=C printf '%s' "$kind" | tr '[:upper:]' '[:lower:]')"
	case "$kind" in
	apfs | btrfs | ext2 | ext3 | ext4 | hfs | overlayfs | tmpfs | ufs | xfs | zfs)
		printf '%s\n' "$kind"
		;;
	nfs | nfs4 | smbfs | cifs | afpfs | fuse.sshfs)
		identity_error "unsupported filesystem: $kind"
		return 1
		;;
	*)
		identity_error "unsupported filesystem: $kind"
		return 1
		;;
	esac
}

identity_path() {
	local path="${1-}"
	local digest
	local object_format

	if [[ ! -e "$path" && ! -L "$path" ]]; then
		identity_absent
		return 0
	fi

	if digest="$(_identity_stream "$path" | git hash-object --stdin)"; then
		object_format="$(identity_object_format)"
		printf 'tree-v1-git-blob:%s:%s\n' "$object_format" "$digest"
	else
		return 1
	fi
}

_identity_stream() {
	local root="$1"
	local workspace
	local paths
	local sorted_paths
	local folded_paths
	local duplicate_paths
	local path
	local relative_path
	local status

	while [[ ${#root} -gt 1 && "$root" == */ ]]; do
		root="${root%/}"
	done
	_identity_validate_path "$root" || return 1

	workspace="$(mktemp -d "${TMPDIR:-/tmp}/agent-config-identity.XXXXXX")" || {
		identity_error 'could not create identity workspace'
		return 1
	}
	paths="$workspace/paths"
	sorted_paths="$workspace/sorted-paths"
	folded_paths="$workspace/folded-paths"
	duplicate_paths="$workspace/duplicate-paths"
	: >"$paths.list"
	: >"$folded_paths"

	if ! find "$root" -print0 >"$paths"; then
		identity_error "could not walk path: $root"
		command rm -R "$workspace"
		return 1
	fi

	while IFS= read -r -d '' path; do
		if [[ "$path" == "$root" ]]; then
			if [[ -d "$path" && ! -L "$path" ]]; then
				continue
			fi
			relative_path=''
		else
			relative_path="${path#"$root"/}"
		fi
		if ! _identity_validate_path "$relative_path"; then
			command rm -R "$workspace"
			return 1
		fi
		if [[ ! -L "$path" && ! -d "$path" && ! -f "$path" ]]; then
			identity_error "unsupported special file: $path"
			command rm -R "$workspace"
			return 1
		fi
		printf '%s\n' "$relative_path" >>"$paths.list"
		_identity_ascii_lower "$relative_path" >>"$folded_paths"
	done <"$paths"

	if ! LC_ALL=C sort "$paths.list" >"$sorted_paths"; then
		identity_error 'could not sort identity paths'
		command rm -R "$workspace"
		return 1
	fi
	if ! LC_ALL=C sort "$folded_paths" | uniq -d >"$duplicate_paths"; then
		identity_error 'could not check path case collisions'
		command rm -R "$workspace"
		return 1
	fi
	if [[ -s "$duplicate_paths" ]]; then
		identity_error 'case-fold collision in path'
		command rm -R "$workspace"
		return 1
	fi

	while IFS= read -r relative_path || [[ -n "$relative_path" ]]; do
		if _identity_write_entry "$root" "$relative_path"; then
			:
		else
			status="$?"
			command rm -R "$workspace"
			return "$status"
		fi
	done <"$sorted_paths"
	command rm -R "$workspace"
}

_identity_validate_path() {
	local path="$1"
	local LC_ALL=C

	if [[ "$path" == *[[:cntrl:]]* ]]; then
		identity_error 'control character in path'
		return 1
	fi
	if ! printf '%s' "$path" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1; then
		identity_error 'invalid UTF-8 path'
		return 1
	fi
}

_identity_ascii_lower() {
	LC_ALL=C tr '[:upper:]' '[:lower:]' <<<"$1"
}

_identity_write_entry() {
	local root="$1"
	local relative_path="$2"
	local path
	local type
	local executable=0
	local payload_length=0
	local link_target
	local LC_ALL=C

	if [[ -n "$relative_path" ]]; then
		path="$root/$relative_path"
	else
		path="$root"
	fi

	if [[ -L "$path" ]]; then
		type='l'
		link_target="$(readlink "$path")" || {
			identity_error "could not read symlink: $path"
			return 1
		}
		payload_length="${#link_target}"
	elif [[ -d "$path" ]]; then
		type='d'
	elif [[ -f "$path" ]]; then
		type='f'
		if [[ -x "$path" ]]; then
			executable=1
		fi
		payload_length="$(wc -c <"$path")"
	else
		identity_error "unsupported special file: $path"
		return 1
	fi

	printf '%s' "$type"
	write_u64_be "${#relative_path}"
	printf '%s' "$relative_path"
	printf '%s' "$executable"
	write_u64_be "$payload_length"
	case "$type" in
	f)
		cat <"$path"
		;;
	l)
		printf '%s' "$link_target"
		;;
	esac
}
