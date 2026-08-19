#!/bin/sh
# Snapshot reporting: `status` says exactly what the Cache is.
set -u
. "$DOCS_TEST_LIB/harness.sh"

sync_australia() {
	run_docs sync --family australia --upstream "$(fixture_upstream)"
	assert_equals 0 "$RUN_STATUS" "sync should exit zero: $RUN_ERR"
}

test_reports_family_commit_timestamp_and_publications() {
	sync_australia
	run_docs status --family australia
	assert_equals 0 "$RUN_STATUS" "status should exit zero: $RUN_ERR"

	assert_equals australia "$(json_field "$RUN_OUT" family)"
	assert_equals "$(git -C "$DOCS_TEST_FIXTURE" rev-parse australia)" \
		"$(json_field "$RUN_OUT" commit)"
	assert_equals "$(fixture_upstream)" "$(json_field "$RUN_OUT" upstream)"
	assert_equals api-reference "$(json_array "$RUN_OUT" publications)"
	assert_equals "$(cache_root)/australia/repo" "$(json_field "$RUN_OUT" cache)"

	fetched_at=$(json_field "$RUN_OUT" fetched_at)
	case "$fetched_at" in
	[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) ;;
	*) fail "fetched_at should be an ISO 8601 UTC timestamp, got: $fetched_at" ;;
	esac
}

test_names_every_publication_whose_index_is_cached() {
	sync_australia
	run_docs status --family australia

	# Naming them, rather than reporting a bare yes, is what lets a caller
	# tell "not downloaded" from "not documented".
	expected='administer
api-reference
platform-security
vocabulary'
	assert_equals "$expected" "$(json_array "$RUN_OUT" publication_indexes)"
}

test_reports_the_snapshot_unchanged_across_invocations() {
	# On a fixed clock: the cache's age is reported and genuinely does move,
	# so only everything else is being held to not drifting.
	run_docs_at 0 sync --family australia --upstream "$(fixture_upstream)"
	assert_equals 0 "$RUN_STATUS" "sync should exit zero: $RUN_ERR"
	run_docs_at 0 status --family australia
	first=$RUN_OUT
	run_docs_at 0 status --family australia
	assert_equals "$first" "$RUN_OUT" 'the recorded snapshot should not drift between invocations'
}

test_reports_a_missing_cache_clearly_and_exits_non_zero() {
	run_docs status --family australia
	[ "$RUN_STATUS" -ne 0 ] || fail 'status should exit non-zero when there is no cache'
	assert_equals '' "$RUN_OUT" 'status should print no snapshot when there is none'
	assert_contains "$RUN_ERR" 'australia'
	assert_contains "$RUN_ERR" 'docs sync'
}

test_reports_each_family_separately() {
	sync_australia
	run_docs status --family zurich
	[ "$RUN_STATUS" -ne 0 ] || fail 'status should exit non-zero for an unsynced family'

	run_docs sync --family zurich --upstream "$(fixture_upstream)"
	assert_equals 0 "$RUN_STATUS" "zurich sync should exit zero: $RUN_ERR"
	run_docs status --family zurich
	assert_equals 0 "$RUN_STATUS" "status should exit zero: $RUN_ERR"
	assert_equals zurich "$(json_field "$RUN_OUT" family)"
	assert_equals "$(git -C "$DOCS_TEST_FIXTURE" rev-parse zurich)" \
		"$(json_field "$RUN_OUT" commit)"
}

test_documents_the_upstream_override_in_its_own_help() {
	run_docs help
	assert_equals 0 "$RUN_STATUS" "help should exit zero: $RUN_ERR"
	assert_contains "$RUN_OUT" '--upstream'
	assert_contains "$RUN_OUT" 'DOCS_UPSTREAM'
}

test_refuses_a_family_name_that_would_escape_the_cache_location() {
	run_docs status --family ../../elsewhere
	[ "$RUN_STATUS" -ne 0 ] || fail 'status should reject a family name containing a path'
	assert_contains "$RUN_ERR" 'family name'
}

run_tests \
	test_reports_family_commit_timestamp_and_publications \
	test_names_every_publication_whose_index_is_cached \
	test_refuses_a_family_name_that_would_escape_the_cache_location \
	test_reports_the_snapshot_unchanged_across_invocations \
	test_reports_a_missing_cache_clearly_and_exits_non_zero \
	test_reports_each_family_separately \
	test_documents_the_upstream_override_in_its_own_help
