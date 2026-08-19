#!/bin/sh
# Family resolution: the right Family is chosen without being thought about,
# and a Family withdrawn upstream is reported rather than mis-answered.
set -u
. "$DOCS_TEST_LIB/harness.sh"

# ------------------------------------------------------------------ precedence

test_an_explicit_argument_overrides_every_configured_source() {
	write_user_config 'family=zurich'
	write_project_config "$(pwd)" 'family=zurich'

	run_family --family australia
	assert_equals australia "$(json_field "$RUN_OUT" family)"
	assert_equals argument "$(json_field "$RUN_OUT" family_source)"
}

test_a_project_configuration_overrides_user_configuration() {
	write_user_config 'family=australia'
	write_project_config "$(pwd)" 'family=zurich'

	run_family
	assert_equals zurich "$(json_field "$RUN_OUT" family)"
	assert_equals project "$(json_field "$RUN_OUT" family_source)"
	assert_equals "$(pwd)/.docs" "$(json_field "$RUN_OUT" family_source_path)"
}

test_user_configuration_is_used_when_no_project_file_exists() {
	write_user_config 'family=zurich'

	run_family
	assert_equals zurich "$(json_field "$RUN_OUT" family)"
	assert_equals user "$(json_field "$RUN_OUT" family_source)"
	assert_equals "$XDG_CONFIG_HOME/docs/config" "$(json_field "$RUN_OUT" family_source_path)"
}

test_the_newest_family_is_used_with_a_warning_when_nothing_is_configured() {
	run_family
	assert_equals australia "$(json_field "$RUN_OUT" family)"
	assert_equals default "$(json_field "$RUN_OUT" family_source)"

	# The warning is the point: falling back is a guess, and a guess about the
	# family is the one guess this project exists to prevent going unnoticed.
	assert_contains "$RUN_ERR" 'no family configured'
	assert_contains "$RUN_ERR" 'australia'
}

test_a_project_file_above_the_working_directory_is_found() {
	write_project_config "$(pwd)/repo" 'family=zurich'
	mkdir -p "$(pwd)/repo/src/deep"
	cd "$(pwd)/repo/src/deep" || fail 'could not enter the working directory'

	run_family
	assert_equals zurich "$(json_field "$RUN_OUT" family)"
	assert_equals project "$(json_field "$RUN_OUT" family_source)"
}

test_the_nearest_project_file_wins() {
	root=$(pwd)
	write_project_config "$root/repo" 'family=australia'
	write_project_config "$root/repo/nested" 'family=zurich'
	cd "$root/repo/nested" || fail 'could not enter the working directory'

	assert_resolves_to zurich
}

test_changing_directory_between_projects_changes_the_resolved_family() {
	root=$(pwd)
	write_project_config "$root/newest-client" 'family=australia'
	write_project_config "$root/older-client" 'family=zurich'

	# No other action: the same command, from a different directory.
	cd "$root/newest-client" || fail 'could not enter the working directory'
	assert_resolves_to australia

	cd "$root/older-client" || fail 'could not enter the working directory'
	assert_resolves_to zurich
}

test_configuration_ignores_comments_blank_lines_and_other_keys() {
	write_project_config "$(pwd)" \
		'# the client runs Zurich' \
		'' \
		'something_else=ignored' \
		'family = zurich'

	assert_resolves_to zurich
}

test_a_present_but_empty_configured_family_is_refused_not_skipped() {
	# The key is present, so an empty value is this file's mistake to report —
	# never a reason to fall through to the next source as though the file had
	# said nothing at all.
	write_project_config "$(pwd)" 'family='

	run_docs family
	[ "$RUN_STATUS" -ne 0 ] || fail 'an empty configured family should exit non-zero'
	assert_contains "$RUN_ERR" 'family name'
	assert_contains "$RUN_ERR" "$(pwd)/.docs"
}

test_a_configuration_file_with_an_unusable_family_is_refused() {
	write_project_config "$(pwd)" 'family=../../elsewhere'

	run_docs family
	[ "$RUN_STATUS" -ne 0 ] || fail 'an unusable configured family should exit non-zero'
	assert_contains "$RUN_ERR" 'family name'
	# Naming the file, because the value came from a file the user has to find.
	assert_contains "$RUN_ERR" "$(pwd)/.docs"
}

# ------------------------------------------------------------- what it applies to

test_the_resolved_family_and_its_source_are_both_reported() {
	write_project_config "$(pwd)" 'family=zurich'

	run_docs sync --upstream "$(fixture_upstream)"
	assert_equals 0 "$RUN_STATUS" "sync should exit zero: $RUN_ERR"
	assert_contains "$RUN_ERR" 'zurich'
	assert_contains "$RUN_ERR" "$(pwd)/.docs"

	run_docs status
	assert_equals 0 "$RUN_STATUS" "status should exit zero: $RUN_ERR"
	assert_equals zurich "$(json_field "$RUN_OUT" family)"
	assert_equals project "$(json_field "$RUN_OUT" family_source)"
	assert_equals "$(pwd)/.docs" "$(json_field "$RUN_OUT" family_source_path)"
}

test_an_explicit_argument_is_also_reported_not_just_configured_sources() {
	run_docs sync --family australia --upstream "$(fixture_upstream)"
	assert_equals 0 "$RUN_STATUS" "sync should exit zero: $RUN_ERR"
	assert_contains "$RUN_ERR" 'australia'
	assert_contains "$RUN_ERR" '--family'
}

test_two_families_are_cached_without_interfering() {
	run_docs sync --family australia --upstream "$(fixture_upstream)"
	assert_equals 0 "$RUN_STATUS" "australia sync should exit zero: $RUN_ERR"
	run_docs sync --family zurich --upstream "$(fixture_upstream)"
	assert_equals 0 "$RUN_STATUS" "zurich sync should exit zero: $RUN_ERR"

	run_docs status --family australia
	assert_equals australia "$(json_field "$RUN_OUT" family)"
	australia_commit=$(json_field "$RUN_OUT" commit)

	run_docs status --family zurich
	assert_equals zurich "$(json_field "$RUN_OUT" family)"
	zurich_commit=$(json_field "$RUN_OUT" commit)

	[ "$australia_commit" != "$zurich_commit" ] ||
		fail 'the two families should be cached at their own commits'
	assert_equals "$(git -C "$DOCS_TEST_FIXTURE" rev-parse zurich)" "$zurich_commit"

	# Coexisting, with one active: which one is active is resolution's business,
	# and the other is still there to be asked for.
	write_project_config "$(pwd)" 'family=zurich'
	assert_resolves_to zurich
	run_docs status --family australia
	assert_equals 0 "$RUN_STATUS" 'the inactive family should still be cached'
}

# --------------------------------------------------------------- out of support

test_a_family_withdrawn_upstream_is_reported_as_out_of_support() {
	upstream=$(private_upstream)
	upstream_delete_family zurich
	write_project_config "$(pwd)" 'family=zurich'

	run_docs sync --upstream "$upstream"
	[ "$RUN_STATUS" -ne 0 ] || fail 'a withdrawn family should exit non-zero'
	assert_contains "$RUN_ERR" 'zurich'
	assert_contains "$RUN_ERR" 'out of support'
}

test_a_withdrawn_family_never_falls_back_to_the_newest_family() {
	upstream=$(private_upstream)
	upstream_delete_family zurich
	write_project_config "$(pwd)" 'family=zurich'

	run_docs sync --upstream "$upstream"
	[ "$RUN_STATUS" -ne 0 ] || fail 'a withdrawn family should exit non-zero'

	# The silent fallback this forbids would look exactly like a cache for the
	# newest family appearing where the pinned one was asked for.
	assert_path_missing "$(cache_root)/australia"
	assert_not_contains "$RUN_ERR" 'cached australia'
	assert_resolves_to zurich
}

test_a_family_named_on_the_command_line_and_never_published_is_not_out_of_support() {
	# A misspelling is not a release withdrawal. Sending someone to check
	# whether their instance is supported because they typed 'zurcih' would be
	# its own confidently-wrong answer.
	run_docs sync --family zurcih --upstream "$(fixture_upstream)"
	[ "$RUN_STATUS" -ne 0 ] || fail 'an unpublished family should exit non-zero'
	assert_contains "$RUN_ERR" 'zurcih'
	assert_contains "$RUN_ERR" 'not published'
	assert_not_contains "$RUN_ERR" 'out of support'
}

test_a_family_withdrawn_after_caching_is_reported_on_refresh() {
	upstream=$(private_upstream)
	run_docs_at 0 sync --family zurich --upstream "$upstream"
	assert_equals 0 "$RUN_STATUS" "sync should exit zero: $RUN_ERR"

	upstream_delete_family zurich

	run_docs_at "$((8 * DAY_SECONDS))" refresh --family zurich
	[ "$RUN_STATUS" -ne 0 ] || fail 'a withdrawn family should exit non-zero'
	assert_contains "$RUN_ERR" 'zurich'
	assert_contains "$RUN_ERR" 'out of support'
}

test_an_unreachable_upstream_is_not_reported_as_out_of_support() {
	# Offline is a degraded mode; out of support is a fact about the release.
	# Confusing the two would send someone to migrate their instance because
	# their wifi dropped.
	upstream=$(private_upstream)
	run_docs_at 0 sync --family zurich --upstream "$upstream"
	assert_equals 0 "$RUN_STATUS" "sync should exit zero: $RUN_ERR"

	take_upstream_offline

	run_docs_at "$((8 * DAY_SECONDS))" refresh --family zurich
	assert_equals 0 "$RUN_STATUS" 'an unreachable upstream should keep the cache'
	assert_not_contains "$RUN_ERR" 'out of support'
	assert_contains "$RUN_ERR" 'could not reach upstream'
}

run_tests \
	test_an_explicit_argument_overrides_every_configured_source \
	test_a_project_configuration_overrides_user_configuration \
	test_user_configuration_is_used_when_no_project_file_exists \
	test_the_newest_family_is_used_with_a_warning_when_nothing_is_configured \
	test_a_project_file_above_the_working_directory_is_found \
	test_the_nearest_project_file_wins \
	test_changing_directory_between_projects_changes_the_resolved_family \
	test_configuration_ignores_comments_blank_lines_and_other_keys \
	test_a_present_but_empty_configured_family_is_refused_not_skipped \
	test_a_configuration_file_with_an_unusable_family_is_refused \
	test_the_resolved_family_and_its_source_are_both_reported \
	test_an_explicit_argument_is_also_reported_not_just_configured_sources \
	test_two_families_are_cached_without_interfering \
	test_a_family_withdrawn_upstream_is_reported_as_out_of_support \
	test_a_withdrawn_family_never_falls_back_to_the_newest_family \
	test_a_family_named_on_the_command_line_and_never_published_is_not_out_of_support \
	test_a_family_withdrawn_after_caching_is_reported_on_refresh \
	test_an_unreachable_upstream_is_not_reported_as_out_of_support
