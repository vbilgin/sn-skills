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

# The clock a case runs against. Fixed rather than derived from the real one,
# so an age assertion is exact instead of racing however long a git operation
# happened to take.
TEST_EPOCH=1800000000 # 2027-01-15T08:00:00Z
DAY_SECONDS=86400

# run_sndocs_at <seconds-after-TEST_EPOCH> <args...> — runs the executable at a
# chosen point on that clock, for exercising the staleness window without
# waiting a week. Sets the same RUN_* variables as run_sndocs.
run_sndocs_at() {
	_offset=$1
	shift
	SNDOCS_NOW=$((TEST_EPOCH + _offset))
	export SNDOCS_NOW
	run_sndocs "$@"
	unset SNDOCS_NOW
}

# The upstream override, pointed at the fixture rather than the real upstream.
fixture_upstream() {
	printf 'file://%s\n' "$SNDOCS_TEST_FIXTURE"
}

# private_upstream — a per-case copy of the fixture, printed as an upstream
# override. The suite's fixture is shared and must stay pristine; a case that
# needs upstream to move on, or to become unreachable, mutates a copy.
private_upstream() {
	cp -R "$SNDOCS_TEST_FIXTURE" "$SNDOCS_TEST_TMP/upstream"
	printf 'file://%s\n' "$SNDOCS_TEST_TMP/upstream"
}

# private_upstream_path — where private_upstream put its copy.
private_upstream_path() {
	printf '%s\n' "$SNDOCS_TEST_TMP/upstream"
}

# upstream_advance <family> — adds a commit to the private upstream copy, so a
# refresh has something to pull.
upstream_advance() {
	_dir=$(private_upstream_path)
	git -C "$_dir" checkout -q "$1"
	printf '\n- [Login rules](login-rules.md)\n' \
		>>"$_dir/markdown/platform-security/index.md"
	git -C "$_dir" \
		-c user.name='sndocs fixture' \
		-c user.email='fixture@example.invalid' \
		-c commit.gpgsign=false \
		commit -qam 'docs: a later snapshot'
	git -C "$_dir" rev-parse "$1"
}

# upstream_delete_family <family> — removes a family branch from the private
# upstream copy, the way upstream deletes the oldest family when a new release
# reaches general availability.
upstream_delete_family() {
	git -C "$(private_upstream_path)" branch -q -D "$1"
}

# take_upstream_offline — removes the private upstream copy, so every later
# git operation against it fails the way an unreachable network does.
take_upstream_offline() {
	rm -rf "$(private_upstream_path)"
}

# The cache location the sandbox HOME resolves to. Spelled out here rather
# than asked of the executable, so that a change to the cache layout fails a
# test instead of silently moving what the tests assert against.
cache_root() {
	printf '%s/sndocs\n' "$XDG_CACHE_HOME"
}

# ---------------------------------------------------------- family resolution

# write_user_config <line...> — the user-level configuration file, at the
# location the sandbox XDG_CONFIG_HOME resolves to. Spelled out here rather
# than asked of the executable, for the same reason as cache_root.
write_user_config() {
	mkdir -p "$XDG_CONFIG_HOME/sndocs"
	printf '%s\n' "$@" >"$XDG_CONFIG_HOME/sndocs/config"
}

# write_project_config <dir> <line...> — a project-level configuration file in
# a working directory, the way a repository commits one.
write_project_config() {
	_dir=$1
	shift
	mkdir -p "$_dir"
	printf '%s\n' "$@" >"$_dir/.sndocs"
}

# run_family <args...> — resolves the family from wherever the case has left
# the working directory. Sets the usual RUN_* variables, so both the resolved
# family and the source it came from can be asserted on.
run_family() {
	run_sndocs family "$@"
	assert_equals 0 "$RUN_STATUS" "family should exit zero: $RUN_ERR"
}

# assert_resolves_to <family> <args...>
assert_resolves_to() {
	_expected=$1
	shift
	run_family "$@"
	assert_equals "$_expected" "$(json_field "$RUN_OUT" family)" \
		'the wrong family was resolved'
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
			XDG_CONFIG_HOME="$SNDOCS_TEST_TMP/home/.config"
			export HOME XDG_CACHE_HOME XDG_CONFIG_HOME
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
