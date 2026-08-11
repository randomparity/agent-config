# 0052 — An overlay is exactly one JSON object

## Status

Accepted (2026-08-10)

## Context

`merge_json_settings` merges a private overlay into a public base with
`jq -s '.[0] * .[1]'`. `-s` slurps each input's whole **value stream** into an array, so
`.[1]` is the overlay's *first* document. A JSON file is a single document by convention,
not by construction: two objects concatenated in one file — a stray appended block, two
host fragments joined by hand, a generated file written twice — parse fine, and everything
after the first is discarded without a word. The install exits 0 and reports
`applied private overlay`.

A NUL byte is the same loss with the tail hidden further down. jq's lexer stops at one, so
`{"a":1}\0{"b":2}` slurps to a *single* object: a check that asks jq how many documents the
file holds gets the same truncated answer the merge gets, and agrees with it. UTF-16 and
UTF-32 overlays are NUL-dense for the same reason and read as holding no JSON value at all.

The loss is confined to the operator's own overlay. Verified against the base as it stands:
a two-document overlay whose *second* document replaces `hooks.PreToolUse` has that
document dropped, and the deployed file carries the base's hooks intact. So this is not a
route around [ADR 0043](0043-overlays-may-not-replace-a-base-array.md)'s protected set — it
is silent data loss against the operator's stated intent, which is why #110 left it here
rather than absorbing it.

Four further shapes fail rather than lose, but fail badly. An empty or
whitespace-only overlay, a top-level value that is not an object, a file that is not valid
JSON at all, and a file whose only fault is a leading UTF-8 byte-order mark each abort the
run with a raw jq message: `object ({"$schema":...) and null (null) cannot be multiplied`,
or a parse error at a line number in a file it does not name. The message that follows
names both files with equal weight — `could not merge private overlay X into Y` — so it
reads as an installer failure over a pair of inputs rather than as a diagnosis of one of
them, and it offers no remedy. All four then take
`exit 1` inside `merge_json_settings`, which is the whole-run abort
[ADR 0049](0049-a-refused-overlay-withholds-one-file.md) removed for the refusal sitting
four lines below: a bad Claude overlay costs the operator their Codex and Bob installs too.

Both halves are the same defect. The installer treats a malformed overlay as an internal
error, when it is a diagnosable mistake in a file the operator owns and can fix.

## Decision

**An overlay must be exactly one JSON object. Anything else is refused before the merge,
by path, with a remedy, on ADR 0049's refusal terms.**

Four things are normative.

1. **The overlay's shape is a precondition, checked before `.[0] * .[1]` runs.** Six
   verdicts, each with its own message: a NUL byte anywhere in the file; a leading UTF-8
   byte-order mark; not valid JSON; no JSON value at all (empty or whitespace-only); more
   than one JSON value; exactly one value that is not an object. Every message names the
   overlay path — never the base — states which of the six it is, and says what to do about
   it. The base is not the subject of any of them: the operator's file is what is wrong.

   **Two of the six are byte-level, and have to be.** The other four ask jq how many values
   the file holds, and jq is the merge's reader too — so on any input jq misreads
   identically in both places, the check confirms the merge's own blind spot and reports a
   truncated file as sound. A validator sharing a parser with the thing it validates can
   only ever agree with it. The BOM and the NUL are the two known members of that class,
   caught by reading bytes rather than by asking jq: the BOM because jq strips it only at
   offset 0 of its concatenated stream, so the file parses alone and fails as the merge's
   second input; the NUL because jq's lexer stops there, so check and merge agree on a
   document that is missing everything after it. Neither earns its own verdict for the
   diagnosis alone — the BOM's remedy would otherwise be `jq . <overlay>`, which succeeds
   on the file, and the NUL's would be "your file is empty", which contradicts what the
   operator sees in an editor.

   The BOM is a verdict rather than a spelling of "not valid JSON" because jq strips a mark
   only at offset 0 of its concatenated input stream. Such an overlay parses when jq reads
   it alone and fails as the merge's *second* input, so a check that reads it alone passes
   it and the merge aborts the run with the raw parse error — position, not content,
   decides. Folding it in would also print a remedy that disproves itself: `jq . <overlay>`
   succeeds on the file and shows a well-formed object.
2. **A multi-document overlay is refused, not merged.** Merging every document in order is
   the permissive alternative and is rejected below. The contract is one object per file,
   and a file holding two is an accident being reported, not a format being supported.
3. **A shape refusal is a refusal, not an error.** It returns rather than exits, so it
   takes every rule ADR 0049 states over the destination set it feeds: the merged temp file
   is removed so no unguarded artifact is installable, a withheld destination path stays in
   the manifest and is not pruned, a wholly empty destination set gets the base alone, the
   deployed state is reported, and the run continues to the remaining agents and exits
   non-zero having named the withheld paths. A malformed overlay and a guard-erasing
   overlay are the same class of operator mistake, and one class of mistake gets one
   failure regime.
4. **A failure of the shape check itself is read as a bad overlay.** jq's exit status does
   not separate "your file will not parse" from "jq is broken", and the check's whole
   subject is the operator's file. It follows the precedent already set by
   `report_deployed_state`, which reads a failed parse of a *deployed* file as a verdict
   about that file rather than as an installer fault. The direction is safe either way: the
   result is a refusal, so no overlay content is applied and the run still fails. What is
   given up is message accuracy in the case where jq itself is broken: where the refusal
   goes on to fill an empty destination set, `render_base` fails on the very next line and
   says so, but where a destination is occupied by a symlink or a directory nothing else
   calls jq and the operator is told a sound overlay will not parse. That gap is accepted
   rather than closed — distinguishing the two would mean probing jq's health on every
   overlay, and the run fails either way with nothing written.

The merge is `.[0] * .[1]` as before, now guarded by the same one-object test over the
base. `-s` slurps *both* files into one array, so the overlay's index depends on the base
as well: a two-document base would merge the base with itself and leave the whole overlay
unread, under a green `applied private overlay`. The precondition above pins one side and
this test pins the other, which together are what make `.[1]` correct rather than
accidentally correct. A base failing it is a defect in this repository rather than a
mistake the operator can fix, so it takes the merge's existing hard failure and not a
refusal. Every ADR 0043 verdict over the merged result is reached by the same product as
before.

## Consequences

- An overlay that installed cleanly before — two concatenated objects, first one applied —
  now refuses. That is the point, and it is the only behaviour change visible to an
  operator whose file was previously accepted. There is no in-repo or published example
  overlay in that shape; `examples/hosts/example-host/` ships single objects.
- The four failing shapes stop aborting the run. An operator with an empty Claude overlay
  now gets their Codex and Bob trees, their Claude skills and instructions, and a named
  withheld `settings.json` — where before they got nothing and a jq type error. It inherits
  ADR 0049's cost too: the refusal is no longer the last thing on the screen, and the
  operator reads it from the withheld-path summary at the tail.
- Invalid JSON moves from a hard exit to a refusal, so a run whose only fault is an
  unparseable overlay now writes to the operator's home directory where it previously did
  not. It writes only what ADR 0049 already permits on a refusal: the rest of the managed
  tree, and the base alone into a destination set that holds no file. Nothing derived from
  the overlay is written, and nothing deployed is replaced.
- One extra `jq` invocation and one `head -c 3` per JSON overlay per run — three of each
  in an `--agent all` run, on the success path as well as the refusal path. They read a
  file the merge is about to read anyway, though not from the position the merge reads it
  from, which is the whole of the byte-order-mark case above.
- A base file that is not exactly one JSON object now fails the merge, and the message
  says so in as many words; before, a two-document base merged the base with itself and
  reported the operator's overlay as applied, and a non-object base printed the same raw
  multiplication error this record removes elsewhere. No base in this repository is in
  either shape, and the test costs no extra process — it rides in the merge's own filter.
  What the message cannot fix is jq's own location prefix, which names the last input it
  read and so points at the overlay for a fault in the base. Correcting that would mean a
  second bash-side check duplicating one the merge already makes; the sentence carries the
  attribution instead.
- An overlay containing a NUL byte is refused whatever else is true of it, so a UTF-16 or
  UTF-32 file is named as the wrong encoding rather than as an empty one. The cost is two
  more processes per overlay — `wc` and `tr` — and a rule stated over bytes rather than over
  JSON, which is a layer this record otherwise stays out of. Taken because the alternative
  is a check that agrees with the reader it is checking.
- The overlay file format is now a stated contract rather than whatever jq tolerates. A
  future relaxation — JSON with comments, a document array — is an ADR, not a patch.
- `install.sh` grows a second refusal reporter. The protected-key refusal keeps its own
  message shape, which is longer and names paths inside the document; the two are near each
  other and could drift.

## Considered & rejected

- **Merge every document in order** (`reduce .[1:][] as $d (.[0]; . * $d)`). The permissive
  reading, and it does not defeat ADR 0043: `erased_base_paths` runs on the final result, so
  a guard erased by document 2 is caught exactly as one erased by document 1. Rejected on
  what it makes true rather than on what it breaks. It defines a file format nobody asked
  for — a JSON value stream with left-to-right merge semantics — that the installer would
  then owe support for, and it silently repairs the accident that produced the file instead
  of reporting it. An operator who appended a block to the wrong file gets a working install
  and no reason to look. It also widens what the protected-key rules must be reasoned about
  over, from one object to a stream of arbitrary length, for a case that has no legitimate
  instance.
- **Keep merging the first document and warn.** Rejected for the reason ADR 0043 rejected
  warn-and-continue: the deployed file is not what the operator's file says, and a warning
  mid-log is not a stop. It also leaves the deployed result dependent on document order,
  which nothing in the file expresses.
- **Refuse only the multi-document case and leave the other four as hard exits.** The
  minimal reading of the issue title. Rejected because the issue's own comment puts the
  empty and non-object shapes in this scope, and because it would leave one class of
  operator mistake with two failure regimes — a guard-erasing overlay withholds one file
  while an empty one freezes the whole run, decided by nothing the operator can see.
- **Validate the overlay against a JSON schema.** Rejected: it answers a question nobody
  asked. What an overlay may contain is ADR 0043's rule, enforced over the merged result
  where it belongs; what this record fixes is that the installer could not say the file was
  the wrong *shape*. A schema is a dependency and a maintenance surface for a check that
  four lines of jq make exactly.
- **Report jq's own parse error alongside the diagnostic.** Tempting, since jq names a line
  and column. Rejected because relaying a raw jq message is the specific thing this record
  removes, and the remedy carries `jq . <overlay>` — the same detail, on demand, from a
  command the operator can also run before installing.
- **Exit rather than refuse, on the ground that an unparseable file is not a considered
  overlay.** Rejected: it re-splits one class of mistake into two regimes for a distinction
  the operator cannot act on differently. Fixing an empty overlay and fixing a
  guard-erasing one are the same task, and both are worth less than the operator's other
  two agents.
