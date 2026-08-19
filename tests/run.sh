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

DOCS_BIN="$root/bin/docs"
DOCS_TEST_LIB="$root/tests/lib"
export DOCS_BIN DOCS_TEST_LIB

GIT_ALLOW_PROTOCOL=file
GIT_TERMINAL_PROMPT=0
export GIT_ALLOW_PROTOCOL GIT_TERMINAL_PROMPT

[ -x "$DOCS_BIN" ] || {
	printf 'not executable: %s\n' "$DOCS_BIN" >&2
	exit 1
}

work=$(mktemp -d "${TMPDIR:-/tmp}/docs-suite.XXXXXX")
trap 'rm -rf "$work"' EXIT INT TERM

# The suite's own git operations must not read the developer's global config,
# and family resolution must not read the developer's own docs configuration.
HOME="$work/suite-home"
XDG_CONFIG_HOME="$work/suite-home/.config"
mkdir -p "$HOME"
export HOME XDG_CONFIG_HOME

. "$DOCS_TEST_LIB/fixture.sh"

DOCS_TEST_FIXTURE="$work/upstream"
export DOCS_TEST_FIXTURE
fixture_build "$DOCS_TEST_FIXTURE"

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
