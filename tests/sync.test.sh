#!/bin/sh
# Cache creation: `sync` turns nothing into a usable Cache.
set -u
. "$DOCS_TEST_LIB/harness.sh"

test_creates_a_cache_from_nothing() {
	run_docs sync --family australia --upstream "$(fixture_upstream)"
	assert_equals 0 "$RUN_STATUS" "sync should exit zero: $RUN_ERR"
	assert_file_exists "$(cache_root)/australia/repo/markdown/api-reference/index.md"
}

test_initial_cone_holds_the_api_reference_and_every_publication_index() {
	run_docs sync --family australia --upstream "$(fixture_upstream)"
	assert_equals 0 "$RUN_STATUS" "sync should exit zero: $RUN_ERR"

	repo="$(cache_root)/australia/repo"
	actual=$(cd "$repo" && find markdown -type f | LC_ALL=C sort)
	expected='markdown/administer/index.md
markdown/api-reference/c_GlideRecordAPI.md
markdown/api-reference/c_GlideSystemAPI.md
markdown/api-reference/index.md
markdown/platform-security/index.md
markdown/vocabulary/index.md'
	assert_equals "$expected" "$actual" 'initial cone should hold the API reference and every publication index, and nothing else'

	# The Repository index is not a Publication index; it is not checked out.
	assert_path_missing "$repo/llms.txt"
}

test_records_the_resolved_commit_and_fetch_timestamp() {
	run_docs sync --family australia --upstream "$(fixture_upstream)"
	assert_equals 0 "$RUN_STATUS" "sync should exit zero: $RUN_ERR"

	expected=$(git -C "$DOCS_TEST_FIXTURE" rev-parse australia)
	run_docs status --family australia
	assert_equals "$expected" "$(json_field "$RUN_OUT" commit)" 'recorded commit should be the resolved upstream commit'
}

test_a_second_sync_on_a_fresh_cache_is_a_no_op() {
	# On a fixed clock, because a reported snapshot includes the cache's age
	# and would otherwise differ by however long the case took to run.
	run_docs_at 0 sync --family australia --upstream "$(fixture_upstream)"
	assert_equals 0 "$RUN_STATUS" "first sync should exit zero: $RUN_ERR"

	run_docs_at 0 status --family australia
	before=$RUN_OUT
	marker="$(cache_root)/australia/repo/.git/docs-not-a-re-clone"
	: >"$marker"

	run_docs_at 0 sync --family australia --upstream "$(fixture_upstream)"
	assert_equals 0 "$RUN_STATUS" "second sync should exit zero: $RUN_ERR"

	assert_file_exists "$marker" 'a fresh cache should not be re-cloned'
	run_docs_at 0 status --family australia
	assert_equals "$before" "$RUN_OUT" 'the recorded snapshot should survive a second sync'
}

test_syncs_each_family_into_its_own_cache() {
	run_docs sync --family australia --upstream "$(fixture_upstream)"
	assert_equals 0 "$RUN_STATUS" "australia sync should exit zero: $RUN_ERR"
	run_docs sync --family zurich --upstream "$(fixture_upstream)"
	assert_equals 0 "$RUN_STATUS" "zurich sync should exit zero: $RUN_ERR"

	australia=$(cat "$(cache_root)/australia/repo/markdown/api-reference/index.md")
	zurich=$(cat "$(cache_root)/zurich/repo/markdown/api-reference/index.md")
	assert_contains "$australia" 'release: australia'
	assert_contains "$zurich" 'release: zurich'
}

test_takes_the_upstream_override_from_the_environment() {
	DOCS_UPSTREAM=$(fixture_upstream)
	export DOCS_UPSTREAM
	run_docs sync --family australia
	assert_equals 0 "$RUN_STATUS" "sync should exit zero: $RUN_ERR"
	assert_file_exists "$(cache_root)/australia/repo/markdown/api-reference/index.md"
}

test_fails_clearly_when_the_family_is_not_published_upstream() {
	run_docs sync --family nonesuch --upstream "$(fixture_upstream)"
	[ "$RUN_STATUS" -ne 0 ] || fail 'sync should exit non-zero for an unpublished family'
	assert_contains "$RUN_ERR" 'nonesuch'
	assert_path_missing "$(cache_root)/nonesuch/repo" 'a failed sync should leave no half-built cache'
}

test_refuses_a_family_name_that_would_escape_the_cache_location() {
	run_docs sync --family ../../elsewhere --upstream "$(fixture_upstream)"
	[ "$RUN_STATUS" -ne 0 ] || fail 'sync should reject a family name containing a path'
	assert_contains "$RUN_ERR" 'family name'
	assert_equals '.' "$(tree_of "$HOME")" 'a rejected family name should create nothing at all'
}

test_refuses_a_cache_built_from_a_different_upstream() {
	run_docs sync --family australia --upstream "$(fixture_upstream)"
	assert_equals 0 "$RUN_STATUS" "sync should exit zero: $RUN_ERR"

	run_docs sync --family australia --upstream 'file:///nowhere/else'
	[ "$RUN_STATUS" -ne 0 ] || fail 'sync should not hand back a cache from a different upstream'
	assert_contains "$RUN_ERR" '/nowhere/else'
}

test_creates_nothing_outside_its_own_cache_location() {
	fixture_before=$(git -C "$DOCS_TEST_FIXTURE" rev-parse australia)

	run_docs sync --family australia --upstream "$(fixture_upstream)"
	assert_equals 0 "$RUN_STATUS" "sync should exit zero: $RUN_ERR"

	assert_equals '.' "$(tree_of "$PWD")" 'sync should write nothing into the working directory'
	assert_equals '.' "$(tree_of "$HOME" | grep -v '^\./\.cache')" \
		'sync should touch nothing in HOME outside the cache location'

	assert_equals "$fixture_before" "$(git -C "$DOCS_TEST_FIXTURE" rev-parse australia)" \
		'sync should not modify the upstream repository'
}

run_tests \
	test_creates_a_cache_from_nothing \
	test_initial_cone_holds_the_api_reference_and_every_publication_index \
	test_records_the_resolved_commit_and_fetch_timestamp \
	test_a_second_sync_on_a_fresh_cache_is_a_no_op \
	test_syncs_each_family_into_its_own_cache \
	test_takes_the_upstream_override_from_the_environment \
	test_fails_clearly_when_the_family_is_not_published_upstream \
	test_refuses_a_family_name_that_would_escape_the_cache_location \
	test_refuses_a_cache_built_from_a_different_upstream \
	test_creates_nothing_outside_its_own_cache_location
