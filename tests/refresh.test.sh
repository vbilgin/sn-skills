#!/bin/sh
# Staleness and refresh: the Cache maintains itself, and always says its age.
set -u
. "$SNDOCS_TEST_LIB/harness.sh"

# Every case here works against a private copy of the fixture, because these
# are the cases in which upstream moves on or goes away.
sync_private() {
	PRIVATE_UPSTREAM=$(private_upstream)
	run_sndocs_at 0 sync --family australia --upstream "$PRIVATE_UPSTREAM"
	assert_equals 0 "$RUN_STATUS" "sync should exit zero: $RUN_ERR"
}

cached_commit() {
	run_sndocs_at 0 status --family australia
	assert_equals 0 "$RUN_STATUS" "status should exit zero: $RUN_ERR"
	json_field "$RUN_OUT" commit
}

test_a_cache_inside_the_window_is_used_without_re_fetching() {
	sync_private
	before=$(cached_commit)
	advanced=$(upstream_advance australia)

	run_sndocs_at "$((6 * DAY_SECONDS))" sync \
		--family australia --upstream "$PRIVATE_UPSTREAM"
	assert_equals 0 "$RUN_STATUS" "sync should exit zero: $RUN_ERR"

	assert_equals "$before" "$(cached_commit)" \
		'a cache inside the staleness window should not re-fetch'
	[ "$before" != "$advanced" ] || fail 'the fixture should have moved on, or this proves nothing'
}

test_a_cache_past_the_window_re_fetches_before_answering() {
	sync_private
	advanced=$(upstream_advance australia)

	run_sndocs_at "$((8 * DAY_SECONDS))" sync \
		--family australia --upstream "$PRIVATE_UPSTREAM"
	assert_equals 0 "$RUN_STATUS" "sync should exit zero: $RUN_ERR"

	assert_equals "$advanced" "$(cached_commit)" \
		'a cache past the staleness window should re-fetch before answering'
	assert_contains "$(cat "$(cache_root)/australia/repo/markdown/platform-security/index.md")" \
		'Login rules' 'the re-fetched content should be on disk, not just the commit'
}

test_a_stale_cache_still_serves_content_and_reports_its_age() {
	sync_private
	run_sndocs_at "$((9 * DAY_SECONDS))" status --family australia
	assert_equals 0 "$RUN_STATUS" "status should exit zero on a stale cache: $RUN_ERR"

	assert_equals true "$(json_field "$RUN_OUT" stale)"
	assert_equals "$((9 * DAY_SECONDS))" "$(json_field "$RUN_OUT" age_seconds)"
	assert_equals 'api-reference' "$(json_array "$RUN_OUT" publications)" \
		'a stale cache should still report what it holds'
	assert_file_exists "$(cache_root)/australia/repo/markdown/api-reference/index.md"
}

test_a_fresh_cache_reports_that_it_is_not_stale() {
	sync_private
	run_sndocs_at "$((2 * DAY_SECONDS))" status --family australia
	assert_equals 0 "$RUN_STATUS" "status should exit zero: $RUN_ERR"
	assert_equals false "$(json_field "$RUN_OUT" stale)"
	assert_equals "$((2 * DAY_SECONDS))" "$(json_field "$RUN_OUT" age_seconds)"
}

test_refresh_on_demand_updates_the_commit_and_the_timestamp() {
	sync_private
	run_sndocs_at 0 status --family australia
	before_fetched_at=$(json_field "$RUN_OUT" fetched_at)
	advanced=$(upstream_advance australia)

	# Well inside the staleness window: on-demand refresh exists so a user is
	# never waiting for a window after a release ships.
	run_sndocs_at 3600 refresh --family australia
	assert_equals 0 "$RUN_STATUS" "refresh should exit zero: $RUN_ERR"

	run_sndocs_at 3600 status --family australia
	assert_equals "$advanced" "$(json_field "$RUN_OUT" commit)" \
		'refresh should record the commit it fetched'
	[ "$(json_field "$RUN_OUT" fetched_at)" != "$before_fetched_at" ] ||
		fail 'refresh should record a new fetch timestamp'
	assert_equals 0 "$(json_field "$RUN_OUT" age_seconds)" \
		'a just-refreshed cache should be reported as new'
}

test_refresh_keeps_the_cone_the_caller_had_widened_to() {
	sync_private
	run_sndocs_at 0 widen --family australia --publication platform-security
	assert_equals 0 "$RUN_STATUS" "widen should exit zero: $RUN_ERR"
	upstream_advance australia >/dev/null

	run_sndocs_at 0 refresh --family australia
	assert_equals 0 "$RUN_STATUS" "refresh should exit zero: $RUN_ERR"

	run_sndocs_at 0 status --family australia
	expected='api-reference
platform-security'
	assert_equals "$expected" "$(json_array "$RUN_OUT" publications)"
	assert_file_exists "$(cache_root)/australia/repo/markdown/platform-security/acl-rules.md"
}

test_with_no_network_and_a_cache_commands_succeed_and_report_the_age() {
	sync_private
	before=$(cached_commit)
	take_upstream_offline

	run_sndocs_at "$((9 * DAY_SECONDS))" sync \
		--family australia --upstream "$PRIVATE_UPSTREAM"
	assert_equals 0 "$RUN_STATUS" \
		"an unreachable upstream should degrade, not fail: $RUN_ERR"
	assert_contains "$RUN_ERR" '9 days'

	run_sndocs_at "$((9 * DAY_SECONDS))" status --family australia
	assert_equals 0 "$RUN_STATUS" "status should exit zero offline: $RUN_ERR"
	assert_equals true "$(json_field "$RUN_OUT" stale)"
	assert_equals "$before" "$(json_field "$RUN_OUT" commit)" \
		'an unreachable upstream should leave the recorded snapshot alone'
	assert_file_exists "$(cache_root)/australia/repo/markdown/api-reference/index.md"
}

test_on_demand_refresh_with_no_network_keeps_the_cache_and_reports_its_age() {
	sync_private
	take_upstream_offline

	run_sndocs_at "$((3 * DAY_SECONDS))" refresh --family australia
	assert_equals 0 "$RUN_STATUS" \
		"refresh against an unreachable upstream should degrade, not fail: $RUN_ERR"
	assert_contains "$RUN_ERR" '3 days'
	assert_file_exists "$(cache_root)/australia/repo/markdown/api-reference/index.md"
}

test_with_no_network_and_no_cache_the_failure_is_clear_and_non_zero() {
	run_sndocs_at 0 sync --family australia --upstream 'file:///nonexistent/upstream'
	[ "$RUN_STATUS" -ne 0 ] || fail 'sync with no cache and no upstream should exit non-zero'
	# Clear means it names what failed, which family, and where it was
	# looking — not merely that something went wrong.
	assert_contains "$RUN_ERR" 'could not clone'
	assert_contains "$RUN_ERR" 'australia'
	assert_contains "$RUN_ERR" '/nonexistent/upstream'
	assert_path_missing "$(cache_root)/australia/repo" 'a failed first sync should leave no cache'

	run_sndocs_at 0 refresh --family australia
	[ "$RUN_STATUS" -ne 0 ] || fail 'refresh with no cache should exit non-zero'
	assert_contains "$RUN_ERR" 'sndocs sync'
}

run_tests \
	test_a_cache_inside_the_window_is_used_without_re_fetching \
	test_a_cache_past_the_window_re_fetches_before_answering \
	test_a_stale_cache_still_serves_content_and_reports_its_age \
	test_a_fresh_cache_reports_that_it_is_not_stale \
	test_refresh_on_demand_updates_the_commit_and_the_timestamp \
	test_refresh_keeps_the_cone_the_caller_had_widened_to \
	test_with_no_network_and_a_cache_commands_succeed_and_report_the_age \
	test_on_demand_refresh_with_no_network_keeps_the_cache_and_reports_its_age \
	test_with_no_network_and_no_cache_the_failure_is_clear_and_non_zero
