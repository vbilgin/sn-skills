#!/bin/sh
#
# Runs the whole suite offline against a local fixture repository.
#
# Offline is enforced, not assumed: git is restricted to the file protocol, so
# any test that reaches for the network fails loudly instead of downloading
# 269 MB of monthly-changing upstream content.
#
# Usage: tests/run.sh [test-file...]

set -eu

root=$(cd "$(dirname "$0")/.." && pwd)

SNDOCS_BIN="$root/bin/sndocs"
SNDOCS_TEST_LIB="$root/tests/lib"
export SNDOCS_BIN SNDOCS_TEST_LIB

GIT_ALLOW_PROTOCOL=file
GIT_TERMINAL_PROMPT=0
export GIT_ALLOW_PROTOCOL GIT_TERMINAL_PROMPT

[ -x "$SNDOCS_BIN" ] || {
	printf 'not executable: %s\n' "$SNDOCS_BIN" >&2
	exit 1
}

work=$(mktemp -d "${TMPDIR:-/tmp}/sndocs-suite.XXXXXX")
trap 'rm -rf "$work"' EXIT INT TERM

# The suite's own git operations must not read the developer's global config.
HOME="$work/suite-home"
mkdir -p "$HOME"
export HOME

. "$SNDOCS_TEST_LIB/fixture.sh"

SNDOCS_TEST_FIXTURE="$work/upstream"
export SNDOCS_TEST_FIXTURE
fixture_build "$SNDOCS_TEST_FIXTURE"

if [ "$#" -eq 0 ]; then
	set -- "$root"/tests/*.test.sh
fi

failed=0
for file in "$@"; do
	printf '%s\n' "$(basename "$file" .test.sh)"
	if sh "$file"; then :; else
		failed=$((failed + 1))
	fi
done

if [ "$failed" -ne 0 ]; then
	printf '\n%d test file(s) failed\n' "$failed" >&2
	exit 1
fi

printf '\nall tests passed\n'
