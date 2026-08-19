#!/bin/sh
#
# evals/run.sh — drives a real agent non-interactively against the golden question set in
# evals/questions.tsv and asserts on its tool-call stream, per skills/docs/SKILL.md's
# correctness contracts.
#
# The gate is retrieval-only: did the agent open the expected topic(s), on the expected family,
# and cite a canonical_url — never whether the prose answer is good. jq is used to parse the
# agent's own JSON tool-call stream; it is a widely available system tool, not a project
# dependency the way a Node or Python package would be, and this script is a dev/eval tool, not
# part of the shipped skill.
#
# Each case runs the agent with its working directory set to a fresh, empty temp directory (with
# a .docs file when the case pins a family) — so a pass can never be explained by proximity to
# this repository's own working tree.

set -eu

: "${DOCS_ROOT:=$(cd "$(dirname "$0")/.." && pwd)}"
EVALS_ROOT="$DOCS_ROOT/evals"

AGENT=''
QUESTIONS="$EVALS_ROOT/questions.tsv"
OUT_DIR=''
ONLY_CASE=''
CASE_TIMEOUT=300

die() {
	printf 'run.sh: %s\n' "$1" >&2
	exit 1
}

usage() {
	cat <<'EOF'
Usage: evals/run.sh --agent claude|codex [--questions FILE] [--out DIR] [--case ID]

Drives the named agent non-interactively, one subprocess per golden question in
evals/questions.tsv, and asserts on its tool-call stream and final answer. Prints a per-case
PASS/FAIL line, a summary count, and exits non-zero on any failure.

  --agent claude|codex   Which agent to drive. Required.
  --questions FILE       Golden question set. Defaults to evals/questions.tsv.
  --out DIR              Where to write results.json. Defaults to evals/runs/<agent> (gitignored
                          — a local run record, not a committed artifact).
  --case ID              Run only the named case (for iterating on one question).
EOF
}

while [ "$#" -gt 0 ]; do
	case $1 in
	--agent)
		AGENT=${2:?--agent needs a value}
		shift 2
		;;
	--questions)
		QUESTIONS=${2:?--questions needs a value}
		shift 2
		;;
	--out)
		OUT_DIR=${2:?--out needs a value}
		shift 2
		;;
	--case)
		ONLY_CASE=${2:?--case needs a value}
		shift 2
		;;
	-h | --help)
		usage
		exit 0
		;;
	*) die "unknown option: $1" ;;
	esac
done

case "$AGENT" in
claude | codex) ;;
'') die '--agent is required (claude or codex)' ;;
*) die "unknown agent: $AGENT (must be claude or codex)" ;;
esac

[ -f "$QUESTIONS" ] || die "no question set at $QUESTIONS"
[ -n "$OUT_DIR" ] || OUT_DIR="$EVALS_ROOT/runs/$AGENT"
mkdir -p "$OUT_DIR"

# Each case's working directory is created outside this repository's own working tree, in
# whatever the platform considers scratch space (CLAUDE_JOB_DIR/tmp when set, else TMPDIR, else
# /tmp) — never under $OUT_DIR. An agent's own sandbox (e.g. codex's workspace-write bubblewrap
# sandbox) can conflict with a host harness's sandboxing of this repository's own tree, and that
# conflict surfaces as an opaque "No such file or directory" from the agent, not as a permission
# error — running cases from a path nobody else sandboxes sidesteps it entirely.
WORK_ROOT="${CLAUDE_JOB_DIR:+$CLAUDE_JOB_DIR/tmp}"
: "${WORK_ROOT:=${TMPDIR:-/tmp}}"
mkdir -p "$WORK_ROOT"

command -v jq >/dev/null 2>&1 || die 'jq is required (a widely available system tool, not vendored)'
command -v "$AGENT" >/dev/null 2>&1 || die "$AGENT is not on PATH"

# --------------------------------------------------------------------------- agent adapters
#
# Every agent's stream is reduced to the same two artifacts before any assertion runs: a
# "corpus" (every command run and every file path read/written, one per line — what the agent
# actually touched) and an "answer" (the final natural-language text). Assertions are then
# agent-agnostic.

invoke_claude() {
	# invoke_claude <question> <cwd> <corpus_out> <answer_out> <raw_out>
	_q=$1 _cwd=$2 _corpus=$3 _answer=$4 _raw=$5

	# </dev/null on the agent process is load-bearing: this function runs inside a `while
	# read` loop over the question file, sharing fd 0 with it, and an agent that reads stdin
	# for anything (codex does, to check whether a prompt continues) would otherwise consume
	# the loop's own input and silently truncate the run to one case.
	(
		cd "$_cwd"
		timeout "$CASE_TIMEOUT" claude -p "$_q" \
			--plugin-dir "$DOCS_ROOT" \
			--allowedTools "Bash Read Grep Glob Skill" \
			--output-format stream-json --verbose </dev/null
	) >"$_raw" 2>"$_raw.err" || true

	# Corpus is both sides of every tool call: what the agent asked for (a command, a file
	# path) and what came back (a grep hit, a file's contents) — SKILL.md explicitly tells the
	# agent to learn an empty/truncated file's status from a grep of index.jsonl rather than
	# opening the file itself, so "was this topic consulted" has to include command output,
	# not only command input.
	jq -r '
		select(.type=="assistant") | .message.content[]? | select(.type=="tool_use") |
		[(.input.command // ""), (.input.file_path // ""), (.input.skill // ""), (.input.args // "")] | .[]
	' "$_raw" >"$_corpus" 2>/dev/null || : >"$_corpus"
	jq -r '
		select(.type=="user") | .message.content[]? | select(.type=="tool_result") |
		if (.content|type)=="string" then .content else (.content[]?.text // "") end
	' "$_raw" >>"$_corpus" 2>/dev/null || true

	jq -r 'select(.type=="result") | .result // empty' "$_raw" >"$_answer" 2>/dev/null || : >"$_answer"
}

invoke_codex() {
	# invoke_codex <question> <cwd> <corpus_out> <answer_out> <raw_out>
	_q=$1 _cwd=$2 _corpus=$3 _answer=$4 _raw=$5

	# </dev/null: see the note in invoke_claude — without it codex reads from the question
	# loop's own stdin and truncates the run after one case.
	(
		cd "$_cwd"
		timeout "$CASE_TIMEOUT" codex exec --json \
			--sandbox workspace-write \
			--skip-git-repo-check \
			-C "$_cwd" \
			"$_q" </dev/null
	) >"$_raw" 2>"$_raw.err" || true

	jq -r '
		select(.type=="item.completed" and .item.type=="command_execution") |
		.item.command, .item.aggregated_output
	' "$_raw" >"$_corpus" 2>/dev/null || : >"$_corpus"

	jq -rs '
		[.[] | select(.type=="item.completed" and .item.type=="agent_message") | .item.text] | last // empty
	' "$_raw" >"$_answer" 2>/dev/null || : >"$_answer"
}

# ------------------------------------------------------------------------------- assertions

contains_all() {
	# contains_all <file> <substring...> — every substring must appear somewhere in the file.
	_file=$1
	shift
	for _s in "$@"; do
		[ -n "$_s" ] || continue
		grep -qF -- "$_s" "$_file" || return 1
	done
	return 0
}

cites_a_url() {
	grep -qF 'servicenow.com/docs' "$1"
}

# The answer text is free-form prose, so these read it flattened to one line (newlines ->
# spaces) and match loosely — this is a pattern check for a required *statement*, not a grade
# of the prose, and it has to tolerate however an agent happens to phrase a negative.
flatten() {
	tr '\n' ' ' <"$1"
}

says_nothing_found() {
	flatten "$1" | grep -qiE \
		'no such|not a real|is.{0,4}t (a real|real|documented)|does.{0,4}t exist|not (find|found|documented|covered|exist)|no (documentation|result|matches|mention|reference|evidence)|could not (find|locate)|couldn.{0,3}t (find|locate)|nothing (was )?found|no method (named|called)|fictional|does not appear|\bno\b.{0,80}exists?\b'
}

says_it_was_absent_not_broken() {
	flatten "$1" | grep -qiE 'not covered|not documented|nothing found|does not exist'
}

reports_upstream_defect() {
	flatten "$1" | grep -qiE 'empty|blank|broken|defect|truncated|build (issue|bug|defect)'
}

mentions_docs() {
	grep -qi 'docs' "$1"
}

# ------------------------------------------------------------------------------- case runner

TOTAL=0
PASSED=0
RESULTS_JSON="$OUT_DIR/results.json"
: >"$RESULTS_JSON.rows"

run_case() {
	_id=$1 _category=$2 _family_pin=$3 _question=$4 _expect_topics=$5 _expect_url=$6 _mode=$7

	TOTAL=$((TOTAL + 1))
	# Deliberately not named anything containing "docs": the no-retrieval assertion greps
	# the tool-call corpus for that string, and an agent that writes an output file echoes its
	# own absolute path — including this directory's name — into that corpus. A directory named
	# after the skill would poison every no-retrieval case with a false positive.
	_casedir=$(mktemp -d "$WORK_ROOT/eval-case-$AGENT-$_id.XXXXXX")

	if [ "$_family_pin" != '-' ]; then
		printf 'family=%s\n' "$_family_pin" >"$_casedir/.docs"
	fi

	_corpus="$_casedir/corpus.txt"
	_answer="$_casedir/answer.txt"
	_raw="$_casedir/raw.jsonl"

	case "$AGENT" in
	claude) invoke_claude "$_question" "$_casedir" "$_corpus" "$_answer" "$_raw" ;;
	codex) invoke_codex "$_question" "$_casedir" "$_corpus" "$_answer" "$_raw" ;;
	esac

	[ -f "$_corpus" ] || : >"$_corpus"
	[ -f "$_answer" ] || : >"$_answer"

	_ok=1
	_reason=''

	case "$_mode" in
	found)
		_topics=$(printf '%s' "$_expect_topics" | tr ',' ' ')
		if ! contains_all "$_corpus" $_topics; then
			_ok=0
			_reason='expected topic(s) not opened'
		elif ! cites_a_url "$_answer"; then
			_ok=0
			_reason='no canonical_url cited'
		elif [ "$_expect_url" != '-' ] && ! grep -qF -- "$_expect_url" "$_answer"; then
			_ok=0
			_reason="answer did not cite a URL containing $_expect_url"
		fi
		;;
	absent)
		# A citation here is not itself a failure: reporting "I checked X and it
		# isn't there" is compliant, arguably stronger than a bare "not found" —
		# the acceptance criterion is that the agent explicitly says nothing was
		# found, not that it withholds where it looked.
		if ! says_nothing_found "$_answer"; then
			_ok=0
			_reason='did not explicitly state nothing was found'
		fi
		;;
	empty)
		# Defect language wins ties: an answer that says "this is an upstream defect, not a
		# 'not covered' gap" legitimately contains the disqualifying phrase while explicitly
		# rejecting it — reports_upstream_defect is checked first so that phrasing is not
		# penalized for contrasting itself with the wrong conclusion.
		_topics=$(printf '%s' "$_expect_topics" | tr ',' ' ')
		if ! contains_all "$_corpus" $_topics; then
			_ok=0
			_reason='the empty upstream topic was never opened or consulted'
		elif reports_upstream_defect "$_answer"; then
			:
		elif says_it_was_absent_not_broken "$_answer"; then
			_ok=0
			_reason='reported as absent rather than as an upstream defect'
		else
			_ok=0
			_reason='did not report the upstream defect'
		fi
		;;
	no-retrieval)
		if mentions_docs "$_corpus"; then
			_ok=0
			_reason='retrieval was triggered when it should not have been'
		elif cites_a_url "$_answer"; then
			_ok=0
			_reason='cited a docs URL despite no retrieval expected'
		fi
		;;
	*) die "unknown mode '$_mode' for case $_id" ;;
	esac

	if [ "$_ok" -eq 1 ]; then
		PASSED=$((PASSED + 1))
		printf 'PASS  %-32s %s\n' "$_id" "$_category"
	else
		printf 'FAIL  %-32s %s -- %s\n' "$_id" "$_category" "$_reason" >&2
	fi

	printf '{"id":"%s","category":"%s","mode":"%s","pass":%s,"reason":"%s"}\n' \
		"$_id" "$_category" "$_mode" \
		"$([ "$_ok" -eq 1 ] && echo true || echo false)" \
		"$(printf '%s' "$_reason" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')" \
		>>"$RESULTS_JSON.rows"
}

# --------------------------------------------------------------------------------------- main

grep -v '^[[:space:]]*#' "$QUESTIONS" | grep -v '^[[:space:]]*$' >"$OUT_DIR/.rows" || true

tab=$(printf '\t')
while IFS="$tab" read -r id category family_pin question expect_topics expect_url mode; do
	[ -n "$id" ] || continue
	if [ -n "$ONLY_CASE" ] && [ "$id" != "$ONLY_CASE" ]; then
		continue
	fi
	run_case "$id" "$category" "$family_pin" "$question" "$expect_topics" "$expect_url" "$mode"
done <"$OUT_DIR/.rows"
rm -f "$OUT_DIR/.rows"

printf '{\n  "agent": "%s",\n  "total": %s,\n  "passed": %s,\n  "cases": [\n' \
	"$AGENT" "$TOTAL" "$PASSED" >"$RESULTS_JSON"
sed 's/^/    /' "$RESULTS_JSON.rows" | paste -sd, - >>"$RESULTS_JSON" 2>/dev/null || true
printf '\n  ]\n}\n' >>"$RESULTS_JSON"
rm -f "$RESULTS_JSON.rows"

printf '\n%s: %s/%s passed\n' "$AGENT" "$PASSED" "$TOTAL"

[ "$PASSED" -eq "$TOTAL" ]
