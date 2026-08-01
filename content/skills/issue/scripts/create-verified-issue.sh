#!/usr/bin/env bash
set -euo pipefail

usage() {
	printf 'usage: %s --repo OWNER/NAME --title TITLE --body-file PATH [--label LABEL]... [--parent NUMBER]\n' "${0##*/}" >&2
	exit 2
}

repo=
title=
body_file=
parent=
labels=()

while (($#)); do
	case $1 in
	--repo)
		(($# >= 2)) || usage
		repo=$2
		shift 2
		;;
	--title)
		(($# >= 2)) || usage
		title=$2
		shift 2
		;;
	--body-file)
		(($# >= 2)) || usage
		body_file=$2
		shift 2
		;;
	--label)
		(($# >= 2)) || usage
		labels+=("$2")
		shift 2
		;;
	--parent)
		(($# >= 2)) || usage
		parent=$2
		shift 2
		;;
	*) usage ;;
	esac
done

[[ -n $repo && -n $title && -n $body_file ]] || usage
[[ -f $body_file && -s $body_file ]] || {
	printf 'body file must be a populated regular file: %s\n' "$body_file" >&2
	exit 2
}
[[ -z $parent || $parent =~ ^[0-9]+$ ]] || usage

create_args=(issue create --repo "$repo" --title "$title" --body-file "$body_file")
for label in "${labels[@]}"; do
	create_args+=(--label "$label")
done
if [[ -n $parent ]]; then
	create_args+=(--parent "$parent")
fi

created_output=$(gh "${create_args[@]}")
issue_url=$(printf '%s\n' "$created_output" | rg -o 'https://[^/[:space:]]+/[^/[:space:]]+/[^/[:space:]]+/issues/[0-9]+' | tail -n 1 || true)
if [[ -z $issue_url ]]; then
	printf 'issue was created but its durable issue URL could not be resolved; creation was not retried\n' >&2
	exit 1
fi
issue_number=${issue_url##*/}
issue_path=${issue_url#https://}
issue_path=${issue_path#*/}
if [[ $issue_path != "$repo/issues/$issue_number" ]]; then
	printf 'created issue URL does not match repository %s: %s; creation was not retried\n' \
		"$repo" "$issue_url" >&2
	exit 1
fi

if ! issue_json=$(gh issue view "$issue_number" --repo "$repo" \
	--json number,title,body,labels,parent,state,url); then
	printf '%s: read-back failed; creation was not retried\n' "$issue_url" >&2
	exit 1
fi
require_parent=false
[[ -n $parent ]] && require_parent=true
if ! jq -e --argjson require_parent "$require_parent" '
	type == "object"
	and (.number | type == "number")
	and (.title | type == "string")
	and (.body | type == "string")
	and (.labels | type == "array")
	and all(.labels[]; type == "object" and (.name | type == "string"))
	and (.url | type == "string")
	and (($require_parent | not) or
		((.parent | type == "object") and (.parent.number | type == "number")))
' \
	>/dev/null 2>&1 <<<"$issue_json"; then
	printf '%s: read-back returned malformed or incomplete JSON\n' "$issue_url" >&2
	exit 1
fi

observed_title=$(jq -r '.title' <<<"$issue_json")
observed_body=$(jq -r '.body' <<<"$issue_json")
observed_parent=$(jq -r '.parent.number // "none"' <<<"$issue_json")
observed_labels=$(jq -r '.labels[].name' <<<"$issue_json")
mismatches=()

if [[ $observed_title != "$title" ]]; then
	mismatches+=("title: expected '$title', observed '$observed_title'")
fi
if [[ -z $observed_body ]]; then
	mismatches+=("body: expected non-empty, observed empty")
fi
for section in 'Problem' 'Evidence' 'Expected' 'Proposed approach'; do
	if ! rg -q "^## ${section}\r?$" <<<"$observed_body"; then
		mismatches+=("body: missing section '$section'")
	fi
done
for label in "${labels[@]}"; do
	found=false
	while IFS= read -r observed_label; do
		if [[ $observed_label == "$label" ]]; then
			found=true
			break
		fi
	done <<<"$observed_labels"
	if [[ $found == false ]]; then
		mismatches+=("label: missing '$label'")
	fi
done
if [[ -n $parent && $observed_parent != "$parent" ]]; then
	if [[ $observed_parent == none ]]; then
		mismatches+=("parent: expected #$parent, observed none")
	else
		mismatches+=("parent: expected #$parent, observed #$observed_parent")
	fi
fi

if ((${#mismatches[@]})); then
	printf '%s: verification failed\n' "$issue_url" >&2
	printf '  - %s\n' "${mismatches[@]}" >&2
	exit 1
fi

printf '%s\n' "$issue_url"
