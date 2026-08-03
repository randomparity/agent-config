# Tracker Contract and GitHub Profile Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development (recommended) or executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Put a tracker contract behind the issue pipeline's `gh` calls, with a
GitHub profile that changes no observable behavior.

**Architecture:** An engine (`tracker.sh`) that holds no tracker knowledge,
dispatching to a profile (`profiles/github.sh`) that holds all of it, mirroring
`check-records.sh` + `profiles/{adr,debt}.sh`. A contract suite runs every
operation against every profile with no network. `create-verified-issue.sh`
becomes the first caller.

**Tech Stack:** Bash 3.2-compatible, `gh`, `jq`, `rg`. Tested by PATH
interposition of a fixture `bin`.

Implements sub-project 1 of
`docs/superpowers/specs/2026-08-01-tracker-agnostic-issue-pipeline-design.md`.
Governed by ADR 0021 (abstraction shape) and ADR 0022 (canonical state).
Closes #43.

## Global Constraints

- **Bash 3.2 compatible.** macOS ships it as `/bin/bash`. `"${arr[@]}"` on an
  empty array is fatal under `set -u`; guard with `((${#arr[@]}))`.
- **All new assets live under `content/skills/github-tracking/assets/`.** Not
  `issue-tracking/` — `scripts/check-skill-layout.sh` fails any `content/skills`
  child lacking a `SKILL.md`, and `skills-check` gates `just verify`.
- **`git diff` must touch no `SKILL.md`.** Verify before every commit.
- **`content/skills/issue/scripts/create-verified-issue-test.sh` must pass
  unmodified.** It is the primary regression signal. Never edit it.
- **No operation retries, ever.** The engine never re-issues an underlying
  command on any exit class.
- **`shfmt` style:** tabs for `content/skills/issue/scripts/`, two spaces
  (`-i 2`) for `.github/scripts/`. New assets use **tabs**, matching the
  `content/skills` tree they join, and are added to the tab-style `shfmt` list.
- **Exit taxonomy:** `0` success, `1` usage, `2` not-found, `3` auth,
  `4` transport, `5` partial.
- **Structured errors go to stderr.** `die` emits its JSON error object with
  `>&2`. Success payloads go to stdout. Callers capture stdout for data and read
  stderr for diagnosis; every test assertion on an error reads the stderr file.
- **No bare `ADR NNNN` or `issue #N` in any file under `content/skills/`.**
  `references-check` — a `just verify` dependency via
  `scripts/check-deployed-references.sh` — fails on
  `\bADR[[:space:]]+#?[0-9]{1,4}\b`, case-insensitive, across the whole
  `content/skills` tree; only `decision-records/assets/` is exempt. Cite a
  decision by name ("the tracker abstraction record"), never by number. This
  applies to code comments, which is where it is easiest to trip.
- **Guardrail:** `just verify` after every task. Run it **bare** — a pipe
  masks the exit code.

---

### Task 1: Engine skeleton — dispatch, resolution, exit taxonomy

**Files:**
- Create: `content/skills/github-tracking/assets/tracker.sh`
- Create: `content/skills/github-tracking/assets/tracker-test.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: `tracker.sh <operation> [--target T] [--profile P] [args…]`.
  Sources `profiles/<name>.sh` and calls `profile_<operation>`. Exports
  `TRACKER_TARGET`. Profiles define `profile_<op>` functions and a
  `PROFILE_DECLARES` newline-delimited list of `<op>:implemented` or
  `<op>:degraded=<value>`.

- [ ] **Step 1: Write the failing test**

Create `content/skills/github-tracking/assets/tracker-test.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
tracker="$script_dir/tracker.sh"
fixture=$(mktemp -d "${TMPDIR:-/tmp}/tracker-test.XXXXXX")
trap 'rm -rf -- "$fixture"' EXIT

fail() {
	printf 'tracker-test: %s\n' "$*" >&2
	exit 1
}

assert_exit() {
	local expected=$1 actual=$2 label=$3
	[[ $actual == "$expected" ]] ||
		fail "$label: expected exit $expected, got $actual"
}

assert_contains() {
	local needle=$1 file=$2
	rg -F -- "$needle" "$file" >/dev/null || fail "missing '$needle' in $file"
}

# A repo whose AGENTS.md declares nothing resolves to github.
mkdir -p "$fixture/norepo"
status=0
(cd "$fixture/norepo" && "$tracker" resolve) >"$fixture/out" 2>"$fixture/err" ||
	status=$?
assert_exit 0 "$status" 'resolve with no declaration'
assert_contains 'github' "$fixture/out"

# A malformed declaration is an error, not an absence.
mkdir -p "$fixture/badrepo"
git -C "$fixture/badrepo" init -q
printf 'issue-tracker: NotValid!\n' >"$fixture/badrepo/AGENTS.md"
status=0
(cd "$fixture/badrepo" && "$tracker" resolve) >"$fixture/out" 2>"$fixture/err" ||
	status=$?
assert_exit 1 "$status" 'resolve with malformed declaration'
assert_contains 'malformed' "$fixture/err"

# A tracker with no profile is an actionable error at the operation boundary,
# never a silent fallback. Tested with --profile so it needs no profiles on
# disk: Task 1 ships none, and the code path is the same one a declaration
# reaches.
status=0
"$tracker" view --profile nosuchtracker 1 >"$fixture/out" 2>"$fixture/err" ||
	status=$?
assert_exit 1 "$status" 'operation with unknown profile'
assert_contains 'nosuchtracker' "$fixture/err"

# An unknown operation is a usage error.
status=0
"$tracker" nosuchop >"$fixture/out" 2>"$fixture/err" || status=$?
assert_exit 1 "$status" 'unknown operation'

printf 'tracker-test: all assertions passed\n'
```

- [ ] **Step 2: Run it to verify it fails**

Run: `./content/skills/github-tracking/assets/tracker-test.sh`
Expected: FAIL — `tracker.sh` does not exist (`No such file or directory`).

- [ ] **Step 3: Write the minimal engine**

Create `content/skills/github-tracking/assets/tracker.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

EXIT_USAGE=1
EXIT_NOT_FOUND=2
EXIT_AUTH=3
EXIT_TRANSPORT=4
EXIT_PARTIAL=5

asset_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)

die() { # exit-code class message
	local code=$1 class=$2 message=$3
	jq -Rrn --arg class "$class" --arg message "$message" \
		'{error: $class, message: $message, partial: {}}' >&2
	exit "$code"
}

available_profiles() {
	local path name
	for path in "$asset_dir"/profiles/*.sh; do
		[[ -f $path ]] || continue
		name=${path##*/}
		printf '%s ' "${name%.sh}"
	done
}

# The repo's tracked AGENTS.md is the only resolution input. No environment
# variable participates: ambient state surviving into a resumed session would
# route a write to the wrong tracker silently, which the tracker abstraction
# record forbids.
resolve_tracker() {
	local root agents matches
	root=$(git rev-parse --show-toplevel 2>/dev/null) || {
		printf 'github\n'
		return 0
	}
	# The invoking repo's declaration, not --target's. --target selects an
	# object within the resolved tracker and never reaches a second one; a
	# target outside that tracker's scope is a usage error.
	agents="$root/AGENTS.md"
	[[ -f $agents ]] || {
		printf 'github\n'
		return 0
	}
	matches=$(rg -c '^issue-tracker: [a-z0-9-]+$' "$agents" || true)
	matches=${matches:-0}
	if ((matches == 0)); then
		# A line that starts the declaration but fails the grammar is a typo,
		# not an absence; treating it as absence is a wrong-tracker write.
		if rg -q '^issue-tracker:' "$agents"; then
			die "$EXIT_USAGE" usage \
				"malformed issue-tracker declaration in $agents"
		fi
		printf 'github\n'
		return 0
	fi
	if ((matches > 1)); then
		die "$EXIT_USAGE" usage \
			"$matches issue-tracker declarations in $agents; expected one"
	fi
	rg -o --replace '$1' '^issue-tracker: ([a-z0-9-]+)$' "$agents"
}

(($#)) || die "$EXIT_USAGE" usage 'no operation given'
operation=$1
shift

profile_name=
TRACKER_TARGET=
while (($#)); do
	case $1 in
	--profile)
		(($# >= 2)) || die "$EXIT_USAGE" usage '--profile needs a value'
		profile_name=$2
		shift 2
		;;
	--target)
		(($# >= 2)) || die "$EXIT_USAGE" usage '--target needs a value'
		TRACKER_TARGET=$2
		shift 2
		;;
	*) break ;;
	esac
done
export TRACKER_TARGET

[[ -n $profile_name ]] || profile_name=$(resolve_tracker)

# `resolve` is a pure query and prints whatever was declared. Profile existence
# is enforced at the operation boundary below, so a declaration naming an
# unimplemented tracker fails every write with an actionable message rather
# than falling back to GitHub.
if [[ $operation == resolve ]]; then
	printf '%s\n' "$profile_name"
	exit 0
fi

profile_path="$asset_dir/profiles/$profile_name.sh"
[[ -f $profile_path ]] || die "$EXIT_USAGE" usage \
	"no profile for '$profile_name'; available: $(available_profiles)"

# shellcheck source=/dev/null
. "$profile_path"

if ! declare -F "profile_$operation" >/dev/null; then
	die "$EXIT_USAGE" usage "profile '$profile_name' has no operation '$operation'"
fi

"profile_$operation" "$@"
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `./content/skills/github-tracking/assets/tracker-test.sh`
Expected: `tracker-test: all assertions passed`

Note: the `resolve` cases run in `$fixture`, which is outside any git repo, so
`git rev-parse` fails and the no-declaration path is exercised. The bad-repo
case needs the malformed/unknown branch — if `git rev-parse` succeeds because
`$TMPDIR` is inside a repo, add `git init -q` to each fixture repo.

- [ ] **Step 5: Verify the test bites**

Temporarily change `printf 'github\n'` in the `[[ -f $agents ]]` guard to
`printf 'jira\n'`, re-run, and confirm the first assertion fails. Revert.

- [ ] **Step 6: Commit**

```bash
chmod +x content/skills/github-tracking/assets/tracker.sh \
	content/skills/github-tracking/assets/tracker-test.sh
git add content/skills/github-tracking/assets/tracker.sh \
	content/skills/github-tracking/assets/tracker-test.sh
git commit -m "feat: add tracker engine with profile dispatch and resolution"
```

---

### Task 2: GitHub profile — read operations

**Files:**
- Create: `content/skills/github-tracking/assets/profiles/github.sh`
- Modify: `content/skills/github-tracking/assets/tracker-test.sh`

**Interfaces:**
- Consumes: `TRACKER_TARGET`, the `EXIT_*` constants and `die` from Task 1.
- Produces: `profile_view`, `profile_target_url`, `profile_comment_list`,
  `profile_label_history`, `profile_search`, and `PROFILE_DECLARES`.

**Critical:** `profile_view` must issue `gh issue view <n> --repo <target>
--json number,title,body,labels,parent,state,url` — the exact invocation
`create-verified-issue.sh:109-110` issues today. `create-verified-issue-test.sh`
asserts `assert_count 1 '^issue view '`, so any change to the leading tokens
breaks it.

- [ ] **Step 1: Write the failing test**

Append to `tracker-test.sh`, before the final `printf`:

```bash
# --- GitHub profile: reads -----------------------------------------------
mkdir -p "$fixture/bin"
cat >"$fixture/bin/gh" <<'FAKE_GH'
#!/usr/bin/env bash
set -euo pipefail
printf '%q ' "$@" >>"$GH_CALL_LOG"
printf '\n' >>"$GH_CALL_LOG"
if [[ $1 == repo && $2 == view ]]; then
  printf 'https://github.com/example/repo\n'; exit 0
fi
if [[ $1 == issue && $2 == view ]]; then
  cat <<'JSON'
{"number":101,"title":"T","body":"B","labels":[{"name":"status:ready"}],
 "parent":null,"state":"OPEN","url":"https://github.com/example/repo/issues/101"}
JSON
  exit 0
fi
exit 0
FAKE_GH
chmod +x "$fixture/bin/gh"

: >"$fixture/calls"
GH_CALL_LOG="$fixture/calls" PATH="$fixture/bin:$PATH" \
	"$tracker" view --profile github --target example/repo 101 \
	>"$fixture/out" 2>"$fixture/err" || fail 'view exited non-zero'

# Normalized shape, not gh's shape.
jq -e '.id == "101" and .ref == "#101" and .state == "open" and .done == false
	and (.labels | index("status:ready")) != null' \
	>/dev/null <"$fixture/out" || fail 'view did not normalize'

# Exactly the invocation create-verified-issue-test.sh asserts.
rg -q '^issue view ' "$fixture/calls" || fail 'view did not call gh issue view'
```

- [ ] **Step 2: Run it to verify it fails**

Run: `./content/skills/github-tracking/assets/tracker-test.sh`
Expected: FAIL — `no profile for 'github'`.

- [ ] **Step 3: Write the read operations**

Create `content/skills/github-tracking/assets/profiles/github.sh`:

```bash
# shellcheck shell=bash
# GitHub profile for tracker.sh. Sourced, never executed.
# Every value and function below is read by tracker.sh after it sources this
# file; linted standalone, shellcheck cannot see that use.
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

github_target() {
	[[ -n ${TRACKER_TARGET:-} ]] ||
		die "$EXIT_USAGE" usage 'operation needs --target OWNER/NAME'
	printf '%s' "$TRACKER_TARGET"
}

# Maps gh's exit status onto the shared taxonomy. gh does not distinguish
# these, so classification is by message; an unmatched failure is transport,
# the class whose caller behavior is "retry is the caller's decision".
github_classify() {
	local status=$1 output=$2
	((status == 0)) && return 0
	case $output in
	*'Could not resolve'* | *'not found'* | *'no such'*) printf '%s' "$EXIT_NOT_FOUND" ;;
	*'authentication'* | *'HTTP 401'* | *'HTTP 403'*) printf '%s' "$EXIT_AUTH" ;;
	*) printf '%s' "$EXIT_TRANSPORT" ;;
	esac
}

profile_target_url() {
	local url status=0 out
	out=$(gh repo view "$(github_target)" --json url --jq .url 2>&1) || status=$?
	((status == 0)) ||
		die "$(github_classify "$status" "$out")" transport "$out"
	url=${out%/}
	printf '%s\n' "$url"
}

profile_view() {
	local id=$1 out status=0
	out=$(gh issue view "$id" --repo "$(github_target)" \
		--json number,title,body,labels,parent,state,url 2>&1) || status=$?
	((status == 0)) ||
		die "$(github_classify "$status" "$out")" transport "$out"
	# Validate the SOURCE shape before normalizing. The normalizing jq below
	# indexes .parent.number and .labels[].name; a fixture carrying
	# "parent":"bad" or "labels":["bad"] would crash it under set -e and
	# surface as a transport error instead of a malformed-payload one.
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
	local id=$1 out status=0
	out=$(gh issue view "$id" --repo "$(github_target)" --json comments 2>&1) ||
		status=$?
	((status == 0)) ||
		die "$(github_classify "$status" "$out")" transport "$out"
	jq '[.comments[].body]' <<<"$out"
}

# GitHub exposes a label timeline; a tracker without one declares
# label_history degraded to "unknown" instead.
profile_label_history() {
	local id=$1 label=$2 out status=0
	out=$(gh api "repos/$(github_target)/issues/$id/timeline" --paginate \
		--jq "[.[] | select(.event==\"labeled\" and .label.name==\"$label\")] | last | .created_at" \
		2>&1) || status=$?
	((status == 0)) ||
		die "$(github_classify "$status" "$out")" transport "$out"
	[[ -n $out && $out != null ]] || out=unknown
	printf '%s\n' "$out"
}

profile_search() {
	local state=open text= label= parent=
	while (($#)); do
		case $1 in
		--state)
			state=$2
			shift 2
			;;
		--text)
			text=$2
			shift 2
			;;
		--label)
			label=$2
			shift 2
			;;
		--parent)
			parent=$2
			shift 2
			;;
		*) die "$EXIT_USAGE" usage "unknown search predicate: $1" ;;
		esac
	done
	local query="repo:$(github_target)"
	[[ $state == any ]] || query="$query state:$state"
	[[ -z $label ]] || query="$query label:$label"
	[[ -z $parent ]] || query="$query parent-issue:$parent"
	[[ -z $text ]] || query="$query $text"
	local out status=0
	out=$(gh search issues "$query" --json number --jq '[.[].number | tostring]' 2>&1) ||
		status=$?
	((status == 0)) ||
		die "$(github_classify "$status" "$out")" transport "$out"
	printf '%s\n' "$out"
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `./content/skills/github-tracking/assets/tracker-test.sh`
Expected: `tracker-test: all assertions passed`

- [ ] **Step 5: Verify the test bites**

Change `done: ((.state | ascii_downcase) == "closed")` to `done: true`, re-run,
confirm the `view did not normalize` assertion fires. Revert.

- [ ] **Step 6: Commit**

```bash
git add content/skills/github-tracking/assets/profiles/github.sh \
	content/skills/github-tracking/assets/tracker-test.sh
git commit -m "feat: add GitHub profile read operations"
```

---

### Task 3: GitHub profile — write operations

**Files:**
- Modify: `content/skills/github-tracking/assets/profiles/github.sh`
- Modify: `content/skills/github-tracking/assets/tracker-test.sh`

**Interfaces:**
- Consumes: `github_target`, `github_classify` from Task 2.
- Produces: `profile_create`, `profile_label_edit`, `profile_label_ensure`,
  `profile_comment_add`, `profile_state_set`, `profile_link_parent`,
  `profile_link_blocks`.

**Critical invariants:**
- `profile_create` issues **exactly one** `gh issue create` and never retries.
- On non-zero create status it exits `5` (partial) carrying any URL observed,
  because the write may have landed.
- `profile_label_edit` issues **exactly one** `gh issue edit` carrying every
  `--add-label` and `--remove-label` together. Two calls can leave an issue with
  two `status:` labels or none, and the pipeline reads that label to choose its
  next write.

- [ ] **Step 1: Write the failing test**

Append to `tracker-test.sh`, before the final `printf`:

```bash
# --- GitHub profile: writes ----------------------------------------------
# label-edit is atomic: one invocation carrying adds and removes.
: >"$fixture/calls"
GH_CALL_LOG="$fixture/calls" PATH="$fixture/bin:$PATH" \
	"$tracker" label-edit --profile github --target example/repo 101 \
	--add status:in-progress --remove status:ready \
	>"$fixture/out" 2>"$fixture/err" || fail 'label-edit exited non-zero'
edits=$(rg -c '^issue edit ' "$fixture/calls" || true)
[[ ${edits:-0} == 1 ]] || fail "label-edit made ${edits:-0} calls, expected 1"
assert_contains 'add-label' "$fixture/calls"
assert_contains 'remove-label' "$fixture/calls"

# create does not retry on transport failure.
cat >"$fixture/bin/gh" <<'FAKE_GH'
#!/usr/bin/env bash
set -euo pipefail
printf '%q ' "$@" >>"$GH_CALL_LOG"
printf '\n' >>"$GH_CALL_LOG"
if [[ $1 == issue && $2 == create ]]; then
  printf 'boom\n' >&2; exit 1
fi
exit 0
FAKE_GH
chmod +x "$fixture/bin/gh"
: >"$fixture/calls"
printf 'body\n' >"$fixture/body.md"
status=0
GH_CALL_LOG="$fixture/calls" PATH="$fixture/bin:$PATH" \
	"$tracker" create --profile github --target example/repo \
	--title T --body-file "$fixture/body.md" \
	>"$fixture/out" 2>"$fixture/err" || status=$?
assert_exit 5 "$status" 'create on failed write'
creates=$(rg -c '^issue create ' "$fixture/calls" || true)
[[ ${creates:-0} == 1 ]] || fail "create retried: ${creates:-0} invocations"
```

- [ ] **Step 2: Normalize hyphens to underscores in the engine**

This is a required engine change, not an incidental note. `tracker.sh` resolves
`label-edit` to `profile_label-edit`, which is not a legal Bash function name,
so dispatch fails before the profile is consulted.

In `content/skills/github-tracking/assets/tracker.sh`, immediately after
`operation=$1; shift`, add:

```bash
operation_fn=${operation//-/_}
```

and replace both uses of `profile_$operation` with `profile_$operation_fn` — in
the `declare -F` guard and in the final dispatch call.

- [ ] **Step 3: Run the test to verify it fails for the right reason**

Run: `./content/skills/github-tracking/assets/tracker-test.sh`
Expected: FAIL — `profile 'github' has no operation 'label_edit'`, i.e. dispatch
now resolves and the operation is genuinely missing.

- [ ] **Step 4: Write the write operations**

Append to `profiles/github.sh`:

```bash
# One gh invocation, never retried. A failed create may still have landed, so
# it exits partial (5) carrying any URL observed rather than claiming failure.
profile_create() {
	local title= body_file= parent= status=0 out url
	local -a labels=()
	while (($#)); do
		case $1 in
		--title)
			title=$2
			shift 2
			;;
		--body-file)
			body_file=$2
			shift 2
			;;
		--label)
			labels+=("$2")
			shift 2
			;;
		--parent)
			parent=$2
			shift 2
			;;
		*) die "$EXIT_USAGE" usage "unknown create argument: $1" ;;
		esac
	done
	[[ -n $title && -n $body_file ]] ||
		die "$EXIT_USAGE" usage 'create needs --title and --body-file'
	[[ -f $body_file && -s $body_file ]] ||
		die "$EXIT_USAGE" usage "body file must be populated: $body_file"

	local -a args=(issue create --repo "$(github_target)" --title "$title"
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
			'{error: "partial", message: $m, partial: {url: $u}}'
		exit "$EXIT_PARTIAL"
	fi
	[[ -n $url ]] ||
		die "$EXIT_TRANSPORT" transport 'created issue URL could not be resolved'
	jq -rn --arg u "$url" '{id: ($u | split("/") | last), url: $u}'
}

# Adds and removes travel together. Splitting them breaks the canonical-state
# record's single-active-status invariant in both possible orders.
profile_label_edit() {
	local id=$1 status=0 out
	shift
	local -a args=(issue edit "$id" --repo "$(github_target)")
	while (($#)); do
		case $1 in
		--add)
			args+=(--add-label "$2")
			shift 2
			;;
		--remove)
			args+=(--remove-label "$2")
			shift 2
			;;
		*) die "$EXIT_USAGE" usage "unknown label-edit argument: $1" ;;
		esac
	done
	out=$(gh "${args[@]}" 2>&1) || status=$?
	((status == 0)) || {
		jq -Rrn --arg m "$out" '{error: "partial", message: $m, partial: {applied: []}}'
		exit "$EXIT_PARTIAL"
	}
	printf '{}\n'
}

profile_label_ensure() {
	local name=$1 color=$2 description=$3 status=0 out
	out=$(gh label create "$name" --repo "$(github_target)" --color "$color" \
		--description "$description" 2>&1) || status=$?
	((status == 0)) && {
		printf '{}\n'
		return 0
	}
	case $out in
	*'already exists'*)
		printf '{}\n'
		return 0
		;;
	esac
	die "$(github_classify "$status" "$out")" transport "$out"
}

profile_comment_add() {
	local id=$1 body_file=$2 status=0 out
	out=$(gh issue comment "$id" --repo "$(github_target)" \
		--body-file "$body_file" 2>&1) || status=$?
	((status == 0)) || die "$EXIT_PARTIAL" partial "$out"
	printf '{}\n'
}

profile_state_set() {
	local id=$1 state=$2 status=0 out verb
	case $state in
	open) verb=reopen ;;
	closed) verb=close ;;
	*) die "$EXIT_USAGE" usage "state must be open or closed: $state" ;;
	esac
	out=$(gh issue "$verb" "$id" --repo "$(github_target)" 2>&1) || status=$?
	((status == 0)) || die "$EXIT_PARTIAL" partial "$out"
	printf '{}\n'
}

profile_link_parent() {
	local child=$1 parent=$2 status=0 out
	out=$(gh api "repos/$(github_target)/issues/$parent/sub_issues" \
		-f "sub_issue_id=$child" 2>&1) || status=$?
	((status == 0)) || die "$(github_classify "$status" "$out")" transport "$out"
	printf '{}\n'
}

# GitHub has no typed dependency edge; the body line is the record, which is
# why this is profile detail rather than a convention every skill knows.
profile_link_blocks() {
	local blocker=$1 blocked=$2 body status=0 out=
	body=$(gh issue view "$blocked" --repo "$(github_target)" --json body --jq .body 2>&1) ||
		status=$?
	((status == 0)) || die "$(github_classify "$status" "$body")" transport "$body"
	if ! printf '%s\n' "$body" | rg -q "^Blocked by #$blocker\$"; then
		body="$body
Blocked by #$blocker"
	fi
	local tmp
	tmp=$(mktemp)
	printf '%s\n' "$body" >"$tmp"
	out=$(gh issue edit "$blocked" --repo "$(github_target)" --body-file "$tmp" 2>&1) ||
		status=$?
	rm -f -- "$tmp"
	((status == 0)) || die "$EXIT_PARTIAL" partial "$out"
	printf '{}\n'
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `./content/skills/github-tracking/assets/tracker-test.sh`
Expected: `tracker-test: all assertions passed`

- [ ] **Step 6: Verify the no-retry assertion bites**

Wrap the `gh "${args[@]}"` call in `profile_create` in a two-iteration retry
loop, re-run, and confirm `create retried: 2 invocations` fires. Revert.

- [ ] **Step 7: Commit**

```bash
git add content/skills/github-tracking/assets/profiles/github.sh \
	content/skills/github-tracking/assets/tracker-test.sh \
	content/skills/github-tracking/assets/tracker.sh
git commit -m "feat: add GitHub profile write operations"
```

---

### Task 4: Fixture profile and the declared-degraded gate

**Files:**
- Create: `content/skills/github-tracking/assets/profiles/fixture.sh`
- Modify: `content/skills/github-tracking/assets/tracker.sh`
- Modify: `content/skills/github-tracking/assets/tracker-test.sh`

**Interfaces:**
- Consumes: `PROFILE_DECLARES` from Task 2.
- Produces: `tracker.sh declares <operation>` printing `implemented` or
  `degraded=<value>`, and failing when an operation is neither.

`profiles/github.sh` declares everything implemented, so without a profile that
declares a degradation the mechanism ships untested.

- [ ] **Step 1: Write the failing test**

Append to `tracker-test.sh`:

```bash
# --- declared-degraded gate ----------------------------------------------
"$tracker" declares --profile fixture label-history >"$fixture/out" 2>&1 ||
	fail 'declares exited non-zero'
assert_contains 'degraded=unknown' "$fixture/out"

"$tracker" declares --profile github view >"$fixture/out" 2>&1 ||
	fail 'declares github view exited non-zero'
assert_contains 'implemented' "$fixture/out"

# An operation neither implemented nor declared degraded fails the gate.
status=0
"$tracker" declares --profile fixture undeclared-op >"$fixture/out" 2>&1 ||
	status=$?
assert_exit 1 "$status" 'undeclared operation'
```

- [ ] **Step 2: Run it to verify it fails**

Run: `./content/skills/github-tracking/assets/tracker-test.sh`
Expected: FAIL — `no profile for 'fixture'`.

- [ ] **Step 3: Write the fixture profile and the `declares` operation**

Create `content/skills/github-tracking/assets/profiles/fixture.sh`:

```bash
# shellcheck shell=bash
# Stub profile. Exists so the declared-degraded mechanism has a profile that
# actually declares a degradation — profiles/github.sh implements everything.
# shellcheck disable=SC2034

PROFILE_DECLARES="view:implemented
label_history:degraded=unknown"

profile_view() {
	printf '{"id":"1","ref":"#1","url":"","title":"","body":"","labels":[],'
	printf '"state":"open","done":false,"parent":null,"updated":null}\n'
}

profile_label_history() {
	printf 'unknown\n'
}
```

Add to `tracker.sh`, immediately after sourcing the profile:

```bash
if [[ $operation == declares ]]; then
	(($#)) || die "$EXIT_USAGE" usage 'declares needs an operation name'
	queried=${1//-/_}
	while IFS= read -r entry; do
		[[ -n $entry ]] || continue
		if [[ ${entry%%:*} == "$queried" ]]; then
			printf '%s\n' "${entry#*:}"
			exit 0
		fi
	done <<<"${PROFILE_DECLARES:-}"
	die "$EXIT_USAGE" usage \
		"profile '$profile_name' declares neither implemented nor degraded for '$1'"
fi
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `./content/skills/github-tracking/assets/tracker-test.sh`
Expected: `tracker-test: all assertions passed`

- [ ] **Step 5: Commit**

```bash
git add content/skills/github-tracking/assets/profiles/fixture.sh \
	content/skills/github-tracking/assets/tracker.sh \
	content/skills/github-tracking/assets/tracker-test.sh
git commit -m "feat: gate profiles on per-operation declarations"
```

---

### Task 5: Refactor create-verified-issue.sh onto the contract

**Files:**
- Modify: `content/skills/issue/scripts/create-verified-issue.sh:70,82,109-110`
- Never modify: `content/skills/issue/scripts/create-verified-issue-test.sh`

**Interfaces:**
- Consumes: `tracker.sh` `target-url`, `create`, `view` from Tasks 1–3.
- Produces: unchanged CLI and unchanged stderr diagnostics.

**This is the regression gate**, and identical `gh` invocations are necessary
but *not sufficient*. Two assertions break for reasons the invocations do not
cover, and both must be handled explicitly:

1. **Exit value.** `create-verified-issue-test.sh:214-218` asserts the literal
   string `creation command failed with exit 1`, and
   `create-verified-issue.sh:87-88` prints `$create_status` verbatim. After the
   refactor `create_status` is the *tracker's* class — `5` (partial) on any
   failed create — so the diagnostic would read `exit 5`. The taxonomy is a
   contract-level fact; the caller's message is a caller-level one. Map at the
   call site.
2. **Read-back shape.** The `malformed-parent` and `malformed-label` fixtures
   return `"parent":"bad"` and `"labels":["bad"]`. Task 2's `profile_view` now
   validates the source shape before normalizing and dies with class
   `malformed`, so the caller must map that class to its own
   `malformed or incomplete JSON` branch rather than to `read-back failed`.

- [ ] **Step 1: Run the existing test to establish the baseline**

Run: `./content/skills/issue/scripts/create-verified-issue-test.sh`
Expected: PASS. Record that it passes *before* the refactor.

- [ ] **Step 2: Replace the three `gh` call sites**

Add near the top, after `set -euo pipefail`:

```bash
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
tracker="$script_dir/../../github-tracking/assets/tracker.sh"
```

Replace line 70:

```bash
canonical_url=$("$tracker" target-url --target "$repo")
```

Replace line 82:

```bash
create_status=0
created_output=$("$tracker" create --target "$repo" --title "$title" \
	--body-file "$body_file" "${label_args[@]+"${label_args[@]}"}" \
	"${parent_args[@]+"${parent_args[@]}"}" 2>&1) || create_status=$?
```

building the argument arrays above it:

```bash
label_args=()
for label in "${labels[@]+"${labels[@]}"}"; do
	label_args+=(--label "$label")
done
parent_args=()
[[ -z $parent ]] || parent_args=(--parent "$parent")
```

Delete the now-dead `create_args` block at lines 62-68 — the profile builds
those arguments.

Immediately after the create call, collapse the tracker's exit class onto the
caller's contract, because the test pins the literal digit:

```bash
((create_status == 0)) || create_status=1
```

Replace lines 109-110, capturing the error stream so the class is readable:

```bash
view_status=0
issue_json=$("$tracker" view --target "$repo" "$issue_number" \
	2>"$fixture_err") || view_status=$?
if ((view_status != 0)); then
	if rg -q 'malformed or incomplete JSON' "$fixture_err"; then
		printf '%s: read-back returned malformed or incomplete JSON\n' \
			"$issue_url" >&2
	else
		printf '%s: read-back failed; creation was not retried\n' "$issue_url" >&2
	fi
	exit 1
fi
```

with `fixture_err=$(mktemp)` declared above it and removed on exit.

Then update the read-back validation and extraction to the **normalized** shape:
`.id` is a string, `.labels` is an array of strings (so
`observed_labels=$(jq -r '.labels[]' …)`), and `.parent` is a string or null —
which also means line 136's `jq -r '.parent.number // "none"'` becomes
`jq -r '.parent // "none"'`.

- [ ] **Step 3: Run the existing test — it must pass unmodified**

Run: `./content/skills/issue/scripts/create-verified-issue-test.sh`
Expected: PASS, with no edits to the test file.

If a diagnostic string changed, restore the original wording rather than
editing the test. The test is the specification here.

- [ ] **Step 4: Confirm the test file is untouched**

```bash
git diff --name-only | rg 'create-verified-issue-test' && \
	echo "FAIL: test was modified" || echo "OK: test untouched"
```

- [ ] **Step 5: Confirm no SKILL.md changed**

```bash
git diff --name-only main...HEAD | rg 'SKILL\.md' && \
	echo "FAIL: a SKILL.md changed" || echo "OK: no SKILL.md touched"
```

- [ ] **Step 6: Commit**

```bash
git add content/skills/issue/scripts/create-verified-issue.sh
git commit -m "refactor: route create-verified-issue.sh through the tracker contract"
```

---

### Task 6: Wire the guardrails

**Files:**
- Modify: `Justfile` — `lint` (line 31), `format-check` (36), `format` (41),
  `test` (45)

Note an existing asymmetry: `format-check` checks
`content/skills/issue/scripts/*.sh` but `format` does not write it. Add the new
assets to **both** so the pair stays consistent, and leave the pre-existing gap
alone — fixing it is not this task's scope.

**Interfaces:**
- Consumes: every script from Tasks 1–5.
- Produces: `just verify` covering the tracker layer.

- [ ] **Step 1: Add the contract suite to `test`**

In the `test` recipe, after the `create-verified-issue-test.sh` line:

```
  ./content/skills/github-tracking/assets/tracker-test.sh
```

- [ ] **Step 2: Add the new scripts to `lint`**

Append to the `shellcheck` argument list:

```
    content/skills/github-tracking/assets/*.sh \
    content/skills/github-tracking/assets/profiles/*.sh
```

- [ ] **Step 3: Add the new scripts to `format-check` and `format`**

Append a line to `format-check` (after its `content/skills/issue/scripts` line):

```
  shfmt -d content/skills/github-tracking/assets/*.sh \
    content/skills/github-tracking/assets/profiles/*.sh
```

and the matching write form to `format` (which currently has no
`content/skills` line at all):

```
  shfmt -w content/skills/github-tracking/assets/*.sh \
    content/skills/github-tracking/assets/profiles/*.sh
```

- [ ] **Step 4: Run the full guardrail suite bare**

Run: `just verify`
Expected: exit 0. Run it **bare** — no pipe, no redirect. A pipeline returns the
last command's status and hides the real failure.

- [ ] **Step 5: Verify hermeticity**

```bash
env -u GH_TOKEN -u GITHUB_TOKEN -u ATLASSIAN_MCP_BASIC_AUTH \
	./content/skills/github-tracking/assets/tracker-test.sh
```

Expected: passes. The suite must never need a credential.

- [ ] **Step 6: Commit**

```bash
git add Justfile
git commit -m "build: run the tracker contract suite in just verify"
```

---

## Self-Review

**Spec coverage.** Twelve operations: Task 2 covers five reads, Task 3 covers
seven writes. Exit taxonomy: Task 1 defines the constants, Tasks 2–3 use them,
Task 3 asserts exit 5. No-retry: Task 3, step 5. `label-edit` atomicity: Task 3.
`create` body-file: Task 3. `search` predicates: Task 2. Declaration syntax with
duplicate-line and malformed rules: Task 1. Declared-degraded: Task 4.
`target-url` and `--target`: Tasks 2 and 5. `create-verified-issue-test.sh`
unmodified: Task 5, steps 3–4. Hermeticity: Task 6, step 5. No `SKILL.md`:
Task 5, step 5. Guardrails: Task 6.

**Deferred by design, not missed.** Acceptance criteria 4 (every exit class
asserted) and 6 (proof of no egress) are partially covered — Tasks 2–3 assert
`usage`, `not-found` and `partial`; `auth` and `transport` are classified but
not independently asserted. That gap is `docs/debt/0010`, finding 1, which
records that the stub cannot distinguish those two classes without testing
itself. The implementer should not invent coverage for it here.

**Placeholder scan.** No TBD, no "add error handling", no "similar to Task N".
Every code step carries its code.

**Type consistency.** `PROFILE_DECLARES` uses underscores (`label_history`) in
both Task 2 and Task 4; `tracker.sh` normalizes hyphens to underscores once, in
Task 3 step 2, and Task 4's `declares` applies the same normalization. The
normalized shape's field names in Task 2's `profile_view` match Task 4's fixture
and the spec's shape block. `github_classify` is defined in Task 2 and used in
Tasks 2 and 3.

**Known risk carried into execution.** Task 3 step 2 discovers that `tracker.sh`
needs hyphen-to-underscore normalization, which Task 1 did not include. It is
called out at the point of discovery rather than retrofitted into Task 1, so an
implementer working tasks in order hits a failing test and a stated fix rather
than a silent inconsistency.
