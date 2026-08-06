# shellcheck shell=sh
#
# Shell test harness.
#
# Drives the executable as a subprocess and asserts on its machine-readable
# output and on the resulting filesystem state — never on internal functions.
#
# Each test runs in its own subshell with a sandbox HOME and cache location, so
# a test can neither see another test's cache nor touch anything real.
#
# Test files register their cases explicitly:
#
#     . "$SNDOCS_TEST_LIB/harness.sh"
#     test_something() { ... }
#     run_tests test_something

: "${SNDOCS_BIN:?harness must be run through tests/run.sh}"
: "${SNDOCS_TEST_FIXTURE:?harness must be run through tests/run.sh}"

# ---------------------------------------------------------------- assertions

fail() {
	printf '    %s\n' "$1" >&2
	exit 1
}

assert_equals() {
	if [ "$1" != "$2" ]; then
		fail "${3:-values differ}
      expected: $1
      actual:   $2"
	fi
}

assert_contains() {
	case "$1" in
	*"$2"*) ;;
	*) fail "${3:-expected output to contain \"$2\"}
      actual: $1" ;;
	esac
}

assert_not_contains() {
	case "$1" in
	*"$2"*) fail "${3:-expected output not to contain \"$2\"}
      actual: $1" ;;
	esac
}

assert_file_exists() {
	[ -f "$1" ] || fail "${2:-expected file to exist: $1}"
}

assert_path_missing() {
	[ -e "$1" ] && fail "${2:-expected path not to exist: $1}"
	return 0
}

# ------------------------------------------------------------- running sndocs

# run_sndocs <args...> — sets RUN_STATUS, RUN_OUT (stdout), RUN_ERR (stderr).
# Never fails the test itself; assert on RUN_STATUS.
run_sndocs() {
	RUN_STATUS=0
	"$SNDOCS_BIN" "$@" >"$SNDOCS_TEST_TMP/stdout" 2>"$SNDOCS_TEST_TMP/stderr" ||
		RUN_STATUS=$?
	RUN_OUT=$(cat "$SNDOCS_TEST_TMP/stdout")
	RUN_ERR=$(cat "$SNDOCS_TEST_TMP/stderr")
}

# The upstream override, pointed at the fixture rather than the real upstream.
fixture_upstream() {
	printf 'file://%s\n' "$SNDOCS_TEST_FIXTURE"
}

# The cache location the sandbox HOME resolves to. Spelled out here rather
# than asked of the executable, so that a change to the cache layout fails a
# test instead of silently moving what the tests assert against.
cache_root() {
	printf '%s/sndocs\n' "$XDG_CACHE_HOME"
}

# json_field <json> <key> — reads one scalar field without a JSON dependency.
# Adequate because the executable's output is generated, not arbitrary.
json_field() {
	printf '%s\n' "$1" |
		sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\{0,1\}\([^\",]*\)\"\{0,1\}.*/\1/p" |
		head -1
}

# json_array <json> <key> — one element per line, in order.
json_array() {
	printf '%s\n' "$1" |
		tr '\n' ' ' |
		sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\[\([^]]*\)\].*/\1/p" |
		tr ',' '\n' |
		sed -e 's/[[:space:]]//g' -e 's/"//g' -e '/^$/d'
}

# tree_of <dir> — sorted relative paths, for asserting nothing else changed.
tree_of() {
	if [ -d "$1" ]; then
		(cd "$1" && find . | LC_ALL=C sort)
	fi
}

# ---------------------------------------------------------------- test runner

run_tests() {
	_failed=0
	for _case in "$@"; do
		_name=$(printf '%s\n' "$_case" | sed -e 's/^test_//' -e 's/_/ /g')

		# One sandbox per case: fresh HOME, fresh cache, fresh cwd.
		SNDOCS_TEST_TMP=$(mktemp -d "${TMPDIR:-/tmp}/sndocs-case.XXXXXX")
		export SNDOCS_TEST_TMP
		(
			HOME="$SNDOCS_TEST_TMP/home"
			XDG_CACHE_HOME="$SNDOCS_TEST_TMP/home/.cache"
			export HOME XDG_CACHE_HOME
			mkdir -p "$HOME" "$SNDOCS_TEST_TMP/cwd"
			cd "$SNDOCS_TEST_TMP/cwd" || exit 1
			"$_case"
		)
		if [ $? -eq 0 ]; then
			printf '  ok   %s\n' "$_name"
		else
			printf '  FAIL %s\n' "$_name"
			_failed=$((_failed + 1))
		fi
		rm -rf "$SNDOCS_TEST_TMP"
	done

	[ "$_failed" -eq 0 ] || exit 1
}
