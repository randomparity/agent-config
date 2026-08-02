# shellcheck shell=bash
# GitHub profile for tracker.sh. Sourced, never executed.
#
# It supplies the tracker knowledge the engine deliberately lacks: which command
# to run, how to read its output, and how to map its failures onto the shared
# exit taxonomy.
#
# Every value and function below is read by tracker.sh after it sources this
# file. Linted standalone, shellcheck cannot see that use.
# shellcheck disable=SC2034

PROFILE_DECLARES="view:implemented
target_url:implemented
comment_list:implemented
label_history:implemented
search:implemented
create:implemented
label_edit:implemented
label_ensure:implemented
comment_add:implemented
state_set:implemented
link_parent:implemented
link_blocks:implemented"

# Validates rather than echoes. A die inside $(github_target) would exit only
# the command substitution's subshell, letting an empty target reach gh and be
# misclassified as a transport failure.
github_require_target() {
	[[ -n ${TRACKER_TARGET:-} ]] ||
		die "$EXIT_USAGE" usage 'operation needs --target OWNER/NAME'
}

# gh does not expose a machine-readable failure class, so classification is by
# message. An unmatched failure is transport, the class whose contract is "the
# caller decides whether to retry" — never the engine.
github_classify() {
	local status=$1 output=$2
	((status == 0)) && {
		printf '%s' 0
		return 0
	}
	case $output in
	*'Could not resolve'* | *'not found'* | *'no such'*)
		printf '%s' "$EXIT_NOT_FOUND"
		;;
	*'authentication'* | *'HTTP 401'* | *'HTTP 403'* | *'gh auth login'*)
		printf '%s' "$EXIT_AUTH"
		;;
	*) printf '%s' "$EXIT_TRANSPORT" ;;
	esac
}

profile_target_url() {
	github_require_target
	local out status=0 url
	out=$(gh repo view "$TRACKER_TARGET" --json url --jq .url 2>&1) || status=$?
	((status == 0)) ||
		die "$(github_classify "$status" "$out")" transport "$out"
	url=${out%/}
	printf '%s\n' "$url"
}

profile_view() {
	github_require_target
	local id=$1 out status=0
	out=$(gh issue view "$id" --repo "$TRACKER_TARGET" \
		--json number,title,body,labels,parent,state,url 2>&1) || status=$?
	((status == 0)) ||
		die "$(github_classify "$status" "$out")" transport "$out"
	# Validate the source shape before normalizing. The jq below indexes
	# .parent.number and .labels[].name; a payload carrying "parent":"bad" or
	# "labels":["bad"] would crash it and surface as a transport error rather
	# than the malformed-payload error a caller can act on.
	jq -e '
		type == "object"
		and (.number | type == "number")
		and (.title | type == "string")
		and (.body | type == "string")
		and (.labels | type == "array")
		and all(.labels[]; type == "object" and (.name | type == "string"))
		and (.url | type == "string")
		and ((.parent == null) or
			((.parent | type == "object") and (.parent.number | type == "number")))
	' >/dev/null 2>&1 <<<"$out" ||
		die "$EXIT_NOT_FOUND" malformed \
			'read-back returned malformed or incomplete JSON'
	jq '{
		id: (.number | tostring),
		ref: ("#" + (.number | tostring)),
		url: .url,
		title: .title,
		body: .body,
		labels: [.labels[].name],
		state: (.state | ascii_downcase),
		done: ((.state | ascii_downcase) == "closed"),
		parent: (if .parent == null then null else (.parent.number | tostring) end),
		updated: (.updatedAt // null)
	}' <<<"$out"
}

profile_comment_list() {
	github_require_target
	local id=$1 out status=0
	out=$(gh issue view "$id" --repo "$TRACKER_TARGET" --json comments 2>&1) ||
		status=$?
	((status == 0)) ||
		die "$(github_classify "$status" "$out")" transport "$out"
	jq '[.comments[].body]' <<<"$out"
}

# GitHub exposes a label timeline. A tracker without one declares label_history
# degraded to "unknown" rather than guessing, which the tracking conventions
# already define a behavior for.
profile_label_history() {
	github_require_target
	local id=$1 label=$2 out status=0
	out=$(gh api "repos/$TRACKER_TARGET/issues/$id/timeline" --paginate \
		--jq "[.[] | select(.event==\"labeled\" and .label.name==\"$label\")] | last | .created_at" \
		2>&1) || status=$?
	((status == 0)) ||
		die "$(github_classify "$status" "$out")" transport "$out"
	[[ -n $out && $out != null ]] || out=unknown
	printf '%s\n' "$out"
}

# Named predicates, not an opaque query string: a query string is
# tracker-native, so accepting one would leave a per-tracker branch in every
# calling skill.
profile_search() {
	github_require_target
	local state=open text='' label='' parent='' query out status=0
	while (($#)); do
		case $1 in
		--state)
			(($# >= 2)) || die "$EXIT_USAGE" usage '--state needs a value'
			state=$2
			shift 2
			;;
		--text)
			(($# >= 2)) || die "$EXIT_USAGE" usage '--text needs a value'
			text=$2
			shift 2
			;;
		--label)
			(($# >= 2)) || die "$EXIT_USAGE" usage '--label needs a value'
			label=$2
			shift 2
			;;
		--parent)
			(($# >= 2)) || die "$EXIT_USAGE" usage '--parent needs a value'
			parent=$2
			shift 2
			;;
		*) die "$EXIT_USAGE" usage "unknown search predicate: $1" ;;
		esac
	done
	query="repo:$TRACKER_TARGET"
	[[ $state == any ]] || query="$query state:$state"
	[[ -z $label ]] || query="$query label:$label"
	[[ -z $parent ]] || query="$query parent-issue:$parent"
	[[ -z $text ]] || query="$query $text"
	out=$(gh search issues "$query" --json number \
		--jq '[.[].number | tostring]' 2>&1) || status=$?
	((status == 0)) ||
		die "$(github_classify "$status" "$out")" transport "$out"
	printf '%s\n' "$out"
}
