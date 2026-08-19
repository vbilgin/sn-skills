#!/bin/sh
# Cone widening: the Cache extends to cover a Publication it does not hold.
set -u
. "$DOCS_TEST_LIB/harness.sh"

sync_australia() {
	run_docs sync --family australia --upstream "$(fixture_upstream)"
	assert_equals 0 "$RUN_STATUS" "sync should exit zero: $RUN_ERR"
}

cached_publications() {
	run_docs status --family australia
	assert_equals 0 "$RUN_STATUS" "status should exit zero: $RUN_ERR"
	json_array "$RUN_OUT" publications
}

test_adds_a_publication_and_leaves_the_existing_cone_intact() {
	sync_australia
	assert_equals 'api-reference' "$(cached_publications)"

	run_docs widen --family australia --publication platform-security
	assert_equals 0 "$RUN_STATUS" "widen should exit zero: $RUN_ERR"

	expected='api-reference
platform-security'
	assert_equals "$expected" "$(cached_publications)" \
		'widening should add the publication without dropping what was already cached'

	# The content, not just the pattern: widening that does not bring the
	# topics down has not widened anything.
	assert_file_exists "$(cache_root)/australia/repo/markdown/platform-security/acl-rules.md"
	assert_file_exists "$(cache_root)/australia/repo/markdown/api-reference/c_GlideRecordAPI.md"

	# Every publication index is the fragile half of the cone under widening,
	# because it is a glob across directories rather than a directory prefix.
	indexes='administer
api-reference
platform-security
vocabulary'
	run_docs status --family australia
	assert_equals "$indexes" "$(json_array "$RUN_OUT" publication_indexes)" \
		'widening should not cost the publication indexes'
}

test_reads_the_cone_back_from_git_rather_than_from_a_manifest() {
	sync_australia

	# Widened behind the executable's back. If the reported cone came from
	# anything the executable maintains itself, this addition would be
	# invisible — and a second source of truth is exactly what would let the
	# report and the cache disagree.
	git -C "$(cache_root)/australia/repo" sparse-checkout add '/markdown/administer/'

	expected='administer
api-reference'
	assert_equals "$expected" "$(cached_publications)" \
		'the cone should be read back from git sparse-checkout state'
}

test_pulls_only_the_new_content_rather_than_re_cloning() {
	sync_australia
	marker="$(cache_root)/australia/repo/.git/docs-not-a-re-clone"
	: >"$marker"

	run_docs widen --family australia --publication platform-security
	assert_equals 0 "$RUN_STATUS" "widen should exit zero: $RUN_ERR"

	assert_file_exists "$marker" 'widening should extend the clone in place, not replace it'
}

test_widening_to_a_publication_already_cached_changes_nothing() {
	sync_australia
	before=$(cached_publications)

	run_docs widen --family australia --publication api-reference
	assert_equals 0 "$RUN_STATUS" "widen should exit zero for a publication already cached: $RUN_ERR"
	assert_equals "$before" "$(cached_publications)"
}

test_adds_several_publications_in_one_widening() {
	sync_australia
	run_docs widen --family australia \
		--publication platform-security --publication administer
	assert_equals 0 "$RUN_STATUS" "widen should exit zero: $RUN_ERR"

	expected='administer
api-reference
platform-security'
	assert_equals "$expected" "$(cached_publications)"
}

test_reports_what_upstream_publishes_separately_from_what_is_cached() {
	sync_australia
	run_docs status --family australia
	assert_equals 0 "$RUN_STATUS" "status should exit zero: $RUN_ERR"

	# The contract that stops a gap in the cache being reported as a gap in
	# the documentation: platform-security exists upstream and is simply not
	# checked out yet.
	available='administer
api-reference
platform-security
vocabulary'
	assert_equals "$available" "$(json_array "$RUN_OUT" available_publications)"
	assert_equals 'api-reference' "$(json_array "$RUN_OUT" publications)"
}

test_refuses_a_publication_upstream_does_not_publish() {
	sync_australia
	run_docs widen --family australia --publication nonesuch
	[ "$RUN_STATUS" -ne 0 ] || fail 'widen should exit non-zero for a publication that does not exist upstream'

	# Distinguishable from "not checked out": the wording has to say the
	# publication is not published, not that it is missing locally.
	assert_contains "$RUN_ERR" 'nonesuch'
	assert_contains "$RUN_ERR" 'not published'
	assert_equals 'api-reference' "$(cached_publications)" \
		'a refused widening should leave the cone untouched'
}

test_refuses_a_publication_name_that_would_escape_the_cache_location() {
	sync_australia
	run_docs widen --family australia --publication ../../elsewhere
	[ "$RUN_STATUS" -ne 0 ] || fail 'widen should reject a publication name containing a path'
	assert_contains "$RUN_ERR" 'publication name'
	assert_equals 'api-reference' "$(cached_publications)"
}

test_widening_a_stale_cache_refreshes_it_first() {
	upstream=$(private_upstream)
	run_docs_at 0 sync --family australia --upstream "$upstream"
	assert_equals 0 "$RUN_STATUS" "sync should exit zero: $RUN_ERR"
	advanced=$(upstream_advance australia)

	# Widening is a use of the cache, so it crosses the staleness window the
	# same way answering does — pulling a publication down at a snapshot the
	# rest of the cache has moved past would make the cone incoherent.
	run_docs_at "$((8 * DAY_SECONDS))" widen \
		--family australia --publication platform-security
	assert_equals 0 "$RUN_STATUS" "widen should exit zero: $RUN_ERR"

	run_docs_at "$((8 * DAY_SECONDS))" status --family australia
	assert_equals "$advanced" "$(json_field "$RUN_OUT" commit)" \
		'widening a stale cache should refresh it first'
	assert_contains "$(cat "$(cache_root)/australia/repo/markdown/platform-security/index.md")" \
		'Login rules' 'the widened content should be at the refreshed snapshot'
}

test_widening_that_cannot_reach_upstream_leaves_the_cone_where_it_was() {
	# Unlike answering from a cache, widening genuinely needs the content it
	# does not have yet, so it fails rather than half-extending the cone.
	upstream=$(private_upstream)
	run_docs sync --family australia --upstream "$upstream"
	assert_equals 0 "$RUN_STATUS" "sync should exit zero: $RUN_ERR"
	take_upstream_offline

	run_docs widen --family australia --publication platform-security
	[ "$RUN_STATUS" -ne 0 ] || fail 'widen should exit non-zero when the new content cannot be fetched'
	assert_equals 'api-reference' "$(cached_publications)" \
		'a failed widening should leave the cone where it was'
	assert_file_exists "$(cache_root)/australia/repo/markdown/api-reference/index.md"
}

test_reports_a_missing_cache_clearly_and_exits_non_zero() {
	run_docs widen --family australia --publication platform-security
	[ "$RUN_STATUS" -ne 0 ] || fail 'widen should exit non-zero when there is no cache'
	assert_contains "$RUN_ERR" 'docs sync'
}

test_widens_each_family_independently() {
	sync_australia
	run_docs sync --family zurich --upstream "$(fixture_upstream)"
	assert_equals 0 "$RUN_STATUS" "zurich sync should exit zero: $RUN_ERR"

	run_docs widen --family zurich --publication platform-security
	assert_equals 0 "$RUN_STATUS" "widen should exit zero: $RUN_ERR"

	assert_equals 'api-reference' "$(cached_publications)" \
		'widening one family should not widen another'

	zurich=$(cat "$(cache_root)/zurich/repo/markdown/platform-security/acl-rules.md")
	assert_contains "$zurich" 'field first' 'the widened content should come from the widened family'
}

run_tests \
	test_adds_a_publication_and_leaves_the_existing_cone_intact \
	test_pulls_only_the_new_content_rather_than_re_cloning \
	test_widening_to_a_publication_already_cached_changes_nothing \
	test_adds_several_publications_in_one_widening \
	test_reports_what_upstream_publishes_separately_from_what_is_cached \
	test_reads_the_cone_back_from_git_rather_than_from_a_manifest \
	test_widening_a_stale_cache_refreshes_it_first \
	test_refuses_a_publication_upstream_does_not_publish \
	test_refuses_a_publication_name_that_would_escape_the_cache_location \
	test_widening_that_cannot_reach_upstream_leaves_the_cone_where_it_was \
	test_reports_a_missing_cache_clearly_and_exits_non_zero \
	test_widens_each_family_independently
