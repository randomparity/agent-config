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
# Emits "<exit-code> <class>" so the JSON error object's class always agrees
# with the exit code. Passing a hardcoded class alongside a computed code is how
# a 401 comes to report itself as a transport failure.
github_classify() {
	local output=$1
	case $output in
	*'Could not resolve'* | *'not found'* | *'no such'*)
		printf '%s %s' "$EXIT_NOT_FOUND" not-found
		;;
	*'authentication'* | *'HTTP 401'* | *'HTTP 403'* | *'gh auth login'*)
		printf '%s %s' "$EXIT_AUTH" auth
		;;
	*) printf '%s %s' "$EXIT_TRANSPORT" transport ;;
	esac
}

# Single exit path for a failed gh call, so code and class cannot disagree.
github_die() {
	local output=$1 code class
	read -r code class <<<"$(github_classify "$output")"
	die "$code" "$class" "$output"
}

profile_target_url() {
	github_require_target
	local out status=0 url
	out=$(gh repo view "$TRACKER_TARGET" --json url --jq .url 2>&1) || status=$?
	((status == 0)) ||
		github_die "$out"
	url=${out%/}
	printf '%s\n' "$url"
}

profile_view() {
	github_require_target
	(($# >= 1)) || die "$EXIT_USAGE" usage 'view needs an issue id'
	local id=$1 out status=0
	out=$(gh issue view "$id" --repo "$TRACKER_TARGET" \
		--json number,title,body,labels,parent,state,url 2>&1) || status=$?
	((status == 0)) ||
		github_die "$out"
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
	(($# >= 1)) || die "$EXIT_USAGE" usage 'comment-list needs an issue id'
	local id=$1 out status=0
	out=$(gh issue view "$id" --repo "$TRACKER_TARGET" --json comments 2>&1) ||
		status=$?
	((status == 0)) ||
		github_die "$out"
	jq '[.comments[].body]' <<<"$out"
}

# GitHub exposes a label timeline. A tracker without one declares label_history
# degraded to "unknown" rather than guessing, which the tracking conventions
# already define a behavior for.
profile_label_history() {
	github_require_target
	(($# >= 2)) || die "$EXIT_USAGE" usage 'label-history needs an issue id and a label'
	local id=$1 label=$2 out status=0
	# --slurp aggregates pages before filtering. Without it gh applies --jq to
	# each page separately and a paginated timeline yields one line per page.
	out=$(gh api "repos/$TRACKER_TARGET/issues/$id/timeline" --paginate --slurp \
		--jq "[.[][] | select(.event==\"labeled\" and .label.name==\"$label\")] | last | .created_at // \"unknown\"" \
		2>&1) || status=$?
	((status == 0)) ||
		github_die "$out"
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
		github_die "$out"
	printf '%s\n' "$out"
}

# One gh invocation, never retried. A failed create may still have landed, so it
# exits partial carrying whatever URL was observed rather than claiming the
# write did not happen: a retry here produces duplicate live issues, and a live
# tenant has no undo.
profile_create() {
	github_require_target
	local title='' body_file='' parent='' status=0 out url
	local -a labels=()
	while (($#)); do
		case $1 in
		--title)
			(($# >= 2)) || die "$EXIT_USAGE" usage '--title needs a value'
			title=$2
			shift 2
			;;
		--body-file)
			(($# >= 2)) || die "$EXIT_USAGE" usage '--body-file needs a value'
			body_file=$2
			shift 2
			;;
		--label)
			(($# >= 2)) || die "$EXIT_USAGE" usage '--label needs a value'
			labels+=("$2")
			shift 2
			;;
		--parent)
			(($# >= 2)) || die "$EXIT_USAGE" usage '--parent needs a value'
			parent=$2
			shift 2
			;;
		*) die "$EXIT_USAGE" usage "unknown create argument: $1" ;;
		esac
	done
	[[ -n $title && -n $body_file ]] ||
		die "$EXIT_USAGE" usage 'create needs --title and --body-file'
	[[ -f $body_file && -s $body_file ]] ||
		die "$EXIT_USAGE" usage "body file must be a populated regular file: $body_file"

	local -a args=(issue create --repo "$TRACKER_TARGET" --title "$title"
		--body-file "$body_file")
	if ((${#labels[@]})); then
		local label
		for label in "${labels[@]}"; do args+=(--label "$label"); done
	fi
	[[ -z $parent ]] || args+=(--parent "$parent")

	out=$(gh "${args[@]}" 2>&1) || status=$?
	url=$(printf '%s\n' "$out" |
		rg -o 'https://[^/[:space:]]+/[^/[:space:]]+/[^/[:space:]]+/issues/[0-9]+' |
		tail -n 1 || true)
	if ((status != 0)); then
		jq -Rrn --arg m "$out" --arg u "$url" \
			'{error: "partial", message: $m, partial: {url: $u}}' >&2
		exit "$EXIT_PARTIAL"
	fi
	[[ -n $url ]] ||
		die "$EXIT_TRANSPORT" transport 'created issue URL could not be resolved'
	jq -n --arg u "$url" '{id: ($u | split("/") | last), url: $u}'
}

# Adds and removes travel together. Splitting them breaks the canonical-state
# record's single-active-status invariant in both possible orders: add-then-
# remove leaves two status labels if the second call fails, remove-then-add
# leaves none.
profile_label_edit() {
	github_require_target
	(($# >= 1)) || die "$EXIT_USAGE" usage 'label-edit needs an issue id'
	local id=$1 status=0 out
	shift
	local -a args=(issue edit "$id" --repo "$TRACKER_TARGET")
	local -a applied=()
	while (($#)); do
		case $1 in
		--add)
			(($# >= 2)) || die "$EXIT_USAGE" usage '--add needs a value'
			args+=(--add-label "$2")
			applied+=("$2")
			shift 2
			;;
		--remove)
			(($# >= 2)) || die "$EXIT_USAGE" usage '--remove needs a value'
			args+=(--remove-label "$2")
			shift 2
			;;
		*) die "$EXIT_USAGE" usage "unknown label-edit argument: $1" ;;
		esac
	done
	out=$(gh "${args[@]}" 2>&1) || status=$?
	if ((status != 0)); then
		# partial names what was requested, so a caller can repair rather than
		# guess which half of the delta landed.
		printf '%s\n' "${applied[@]+"${applied[@]}"}" |
			jq -Rrn --arg m "$out" \
				'{error: "partial", message: $m, partial: {requested_adds: [inputs | select(. != "")]}}' >&2
		exit "$EXIT_PARTIAL"
	fi
	printf '{}\n'
}

profile_label_ensure() {
	github_require_target
	(($# >= 3)) || die "$EXIT_USAGE" usage 'label-ensure needs a name, colour and description'
	local name=$1 color=$2 description=$3 status=0 out
	out=$(gh label create "$name" --repo "$TRACKER_TARGET" --color "$color" \
		--description "$description" 2>&1) || status=$?
	((status == 0)) && {
		printf '{}\n'
		return 0
	}
	# An already-existing label is the ordinary case, not a failure. Masking a
	# no-scope failure as success is what this distinction exists to prevent.
	case $out in
	*'already exists'*)
		printf '{}\n'
		return 0
		;;
	esac
	github_die "$out"
}

profile_comment_add() {
	github_require_target
	(($# >= 2)) || die "$EXIT_USAGE" usage 'comment-add needs an issue id and a body file'
	local id=$1 body_file=$2 status=0 out
	[[ -f $body_file && -s $body_file ]] ||
		die "$EXIT_USAGE" usage "body file must be a populated regular file: $body_file"
	out=$(gh issue comment "$id" --repo "$TRACKER_TARGET" \
		--body-file "$body_file" 2>&1) || status=$?
	((status == 0)) || die "$EXIT_PARTIAL" partial "$out"
	printf '{}\n'
}

profile_state_set() {
	github_require_target
	(($# >= 2)) || die "$EXIT_USAGE" usage 'state-set needs an issue id and a state'
	local id=$1 state=$2 status=0 out verb
	case $state in
	open) verb=reopen ;;
	closed) verb=close ;;
	*) die "$EXIT_USAGE" usage "state must be open or closed: $state" ;;
	esac
	out=$(gh issue "$verb" "$id" --repo "$TRACKER_TARGET" 2>&1) || status=$?
	((status == 0)) || die "$EXIT_PARTIAL" partial "$out"
	printf '{}\n'
}

profile_link_parent() {
	github_require_target
	(($# >= 2)) || die "$EXIT_USAGE" usage 'link-parent needs a child and a parent id'
	local child=$1 parent=$2 status=0 out
	out=$(gh api "repos/$TRACKER_TARGET/issues/$parent/sub_issues" \
		-f "sub_issue_id=$child" 2>&1) || status=$?
	((status == 0)) || github_die "$out"
	printf '{}\n'
}

# GitHub has no typed dependency edge, so a body line is the record. That is
# exactly why this is profile detail rather than a convention every skill has to
# know: a tracker with native links implements the same operation differently.
profile_link_blocks() {
	github_require_target
	(($# >= 2)) || die "$EXIT_USAGE" usage 'link-blocks needs a blocker and a blocked id'
	local blocker=$1 blocked=$2 body status=0 out='' tmp
	body=$(gh issue view "$blocked" --repo "$TRACKER_TARGET" --json body \
		--jq .body 2>&1) || status=$?
	((status == 0)) || github_die "$body"
	if ! printf '%s\n' "$body" | rg -q "^Blocked by #$blocker\$"; then
		body="$body
Blocked by #$blocker"
	fi
	tmp=$(mktemp)
	printf '%s\n' "$body" >"$tmp"
	out=$(gh issue edit "$blocked" --repo "$TRACKER_TARGET" --body-file "$tmp" 2>&1) ||
		status=$?
	rm -f -- "$tmp"
	((status == 0)) || die "$EXIT_PARTIAL" partial "$out"
	printf '{}\n'
}
