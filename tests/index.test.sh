#!/bin/sh
# Heading index: `index` makes the cache's topics greppable without reading
# publication indexes.
set -u
. "$DOCS_TEST_LIB/harness.sh"

sync_australia() {
	run_docs sync --family australia --upstream "$(fixture_upstream)"
	assert_equals 0 "$RUN_STATUS" "sync should exit zero: $RUN_ERR"
}

index_path() {
	printf '%s/australia/index.jsonl\n' "$(cache_root)"
}

test_produces_one_record_per_cached_topic() {
	sync_australia
	run_docs index --family australia
	assert_equals 0 "$RUN_STATUS" "index should exit zero: $RUN_ERR"

	assert_file_exists "$(index_path)"
	repo="$(cache_root)/australia/repo"
	expected=$(cd "$repo" && find markdown -type f -name '*.md' | wc -l | tr -d '[:space:]')
	actual=$(wc -l <"$(index_path)" | tr -d '[:space:]')
	assert_equals "$expected" "$actual" \
		'the index should hold exactly one record per cached markdown topic'
}

test_records_carry_path_title_product_area_and_canonical_url() {
	sync_australia
	run_docs index --family australia
	assert_equals 0 "$RUN_STATUS" "index should exit zero: $RUN_ERR"

	record=$(grep 'c_GlideSystemAPI.md' "$(index_path)")
	assert_contains "$record" '"path":"markdown/api-reference/c_GlideSystemAPI.md"'
	assert_contains "$record" '"title":"GlideSystem API"'
	assert_contains "$record" '"product_area":"Now Platform"'
	assert_contains "$record" '"canonical_url":"https://www.servicenow.com/docs'
}

test_records_are_greppable_as_plain_text() {
	sync_australia
	run_docs index --family australia

	# No JSON tooling required: a heading is found by grepping for its text.
	assert_contains "$(grep -F 'GlideSystem - getUserID()' "$(index_path)")" \
		'c_GlideSystemAPI.md'
}

test_method_level_headings_inside_large_api_files_appear_individually() {
	sync_australia
	run_docs index --family australia

	record=$(grep 'c_GlideRecordAPI.md' "$(index_path)")
	assert_contains "$record" '## GlideRecord - method01(String name, Object value)'
	assert_contains "$record" '## GlideRecord - method60(String name, Object value)'

	# One entry per method, not a single collapsed heading.
	count=$(printf '%s' "$record" | grep -o 'GlideRecord - method[0-9]*(' | wc -l | tr -d '[:space:]')
	assert_equals 60 "$count" 'each API method should appear as its own heading entry'
}

test_captures_first_and_second_level_headings_only() {
	sync_australia
	run_docs index --family australia

	record=$(grep '"path":"markdown/api-reference/index.md"' "$(index_path)")
	assert_contains "$record" '"# API reference"'
}

test_flags_an_empty_file_rather_than_reporting_it_as_undocumented() {
	sync_australia
	run_docs widen --family australia --publication administer
	assert_equals 0 "$RUN_STATUS" "widen should exit zero: $RUN_ERR"

	run_docs index --family australia
	assert_equals 0 "$RUN_STATUS" "index should exit zero: $RUN_ERR"

	record=$(grep 'empty-topic.md' "$(index_path)")
	assert_contains "$record" '"status":"empty"'
	assert_contains "$record" '"headings":[]'
}

test_missing_frontmatter_fields_produce_a_usable_record() {
	upstream=$(private_upstream)
	upstream_dir=$(private_upstream_path)
	git -C "$upstream_dir" checkout -q australia
	printf -- '---\ntitle: No Product Area\nlocale: en-US\ncanonical_url: https://example.invalid/x\n---\n\n# No Product Area\n' \
		>"$upstream_dir/markdown/api-reference/c_NoProductArea.md"
	git -C "$upstream_dir" add -A
	git -C "$upstream_dir" -c user.name='t' -c user.email='t@example.invalid' \
		-c commit.gpgsign=false commit -qam 'docs: a topic missing product_area'

	run_docs sync --family australia --upstream "$upstream"
	assert_equals 0 "$RUN_STATUS" "sync should exit zero: $RUN_ERR"
	run_docs index --family australia
	assert_equals 0 "$RUN_STATUS" "index should exit zero even with missing frontmatter: $RUN_ERR"

	record=$(grep 'c_NoProductArea.md' "$(index_path)")
	assert_contains "$record" '"title":"No Product Area"'
	assert_contains "$record" '"product_area":""'
}

test_crlf_line_endings_do_not_break_frontmatter_or_headings() {
	upstream=$(private_upstream)
	upstream_dir=$(private_upstream_path)
	git -C "$upstream_dir" checkout -q australia
	printf -- '---\r\ntitle: CRLF Topic\r\nlocale: en-US\r\nproduct_area: Now Platform\r\ncanonical_url: https://example.invalid/crlf\r\n---\r\n\r\n# CRLF Topic\r\n\r\nBody text.\r\n' \
		>"$upstream_dir/markdown/api-reference/c_CRLFTopic.md"
	git -C "$upstream_dir" add -A
	git -C "$upstream_dir" -c user.name='t' -c user.email='t@example.invalid' \
		-c commit.gpgsign=false commit -qam 'docs: a CRLF-terminated topic'

	run_docs sync --family australia --upstream "$upstream"
	assert_equals 0 "$RUN_STATUS" "sync should exit zero: $RUN_ERR"
	run_docs index --family australia
	assert_equals 0 "$RUN_STATUS" "index should exit zero: $RUN_ERR"

	record=$(grep 'c_CRLFTopic.md' "$(index_path)")
	assert_contains "$record" '"status":"ok"'
	assert_contains "$record" '"title":"CRLF Topic"'
	assert_contains "$record" '"headings":["# CRLF Topic"]'
}

test_headings_inside_fenced_code_blocks_are_not_captured() {
	upstream=$(private_upstream)
	upstream_dir=$(private_upstream_path)
	git -C "$upstream_dir" checkout -q australia
	printf -- '---\ntitle: Fenced Topic\nlocale: en-US\nproduct_area: Now Platform\ncanonical_url: https://example.invalid/fenced\n---\n\n# Fenced Topic\n\n```bash\n# not a heading\necho hi\n## also not a heading\n```\n\n## Real heading\n' \
		>"$upstream_dir/markdown/api-reference/c_FencedTopic.md"
	git -C "$upstream_dir" add -A
	git -C "$upstream_dir" -c user.name='t' -c user.email='t@example.invalid' \
		-c commit.gpgsign=false commit -qam 'docs: a topic with a fenced code sample'

	run_docs sync --family australia --upstream "$upstream"
	assert_equals 0 "$RUN_STATUS" "sync should exit zero: $RUN_ERR"
	run_docs index --family australia
	assert_equals 0 "$RUN_STATUS" "index should exit zero: $RUN_ERR"

	record=$(grep 'c_FencedTopic.md' "$(index_path)")
	assert_equals '"headings":["# Fenced Topic","## Real heading"]' \
		"$(printf '%s' "$record" | sed -n 's/.*\("headings":\[[^]]*\]\).*/\1/p')" \
		'a heading-shaped line inside a fenced code block should not be indexed'
}

test_an_unreadable_file_is_flagged_distinctly_from_an_empty_one() {
	sync_australia
	target="$(cache_root)/australia/repo/markdown/api-reference/c_GlideSystemAPI.md"
	chmod 000 "$target"

	run_docs index --family australia
	assert_equals 0 "$RUN_STATUS" "index should exit zero even with an unreadable file: $RUN_ERR"

	record=$(grep 'c_GlideSystemAPI.md' "$(index_path)")
	assert_contains "$record" '"status":"unreadable"'
	chmod 644 "$target"
}

test_written_inside_the_cache_not_the_git_working_tree() {
	sync_australia
	run_docs index --family australia
	assert_equals 0 "$RUN_STATUS" "index should exit zero: $RUN_ERR"

	assert_file_exists "$(index_path)"
	assert_path_missing "$(cache_root)/australia/repo/index.jsonl" \
		'the index should live beside the snapshot, not inside the tracked working tree'

	status=$(git -C "$(cache_root)/australia/repo" status --porcelain)
	assert_equals '' "$status" 'the index should leave the git working tree clean'
}

test_rerunning_after_widening_covers_the_newly_added_publication() {
	sync_australia
	run_docs index --family australia
	before=$(wc -l <"$(index_path)" | tr -d '[:space:]')

	run_docs widen --family australia --publication platform-security
	assert_equals 0 "$RUN_STATUS" "widen should exit zero: $RUN_ERR"

	run_docs index --family australia
	assert_equals 0 "$RUN_STATUS" "index should exit zero: $RUN_ERR"
	after=$(wc -l <"$(index_path)" | tr -d '[:space:]')

	[ "$after" -gt "$before" ] || fail 're-indexing after widening should cover the new publication'
	assert_contains "$(grep 'acl-rules.md' "$(index_path)")" 'Evaluation order'
}

test_rerunning_with_no_changes_produces_identical_output() {
	sync_australia
	run_docs index --family australia
	first=$(cat "$(index_path)")

	run_docs index --family australia
	assert_equals 0 "$RUN_STATUS" "index should exit zero: $RUN_ERR"
	second=$(cat "$(index_path)")

	assert_equals "$first" "$second" \
		're-running index with no changes should produce identical output'
}

test_reports_a_missing_cache_clearly_and_exits_non_zero() {
	run_docs index --family australia
	[ "$RUN_STATUS" -ne 0 ] || fail 'index should exit non-zero when there is no cache'
	assert_contains "$RUN_ERR" 'docs sync'
}

run_tests \
	test_produces_one_record_per_cached_topic \
	test_records_carry_path_title_product_area_and_canonical_url \
	test_records_are_greppable_as_plain_text \
	test_method_level_headings_inside_large_api_files_appear_individually \
	test_captures_first_and_second_level_headings_only \
	test_flags_an_empty_file_rather_than_reporting_it_as_undocumented \
	test_missing_frontmatter_fields_produce_a_usable_record \
	test_crlf_line_endings_do_not_break_frontmatter_or_headings \
	test_headings_inside_fenced_code_blocks_are_not_captured \
	test_an_unreadable_file_is_flagged_distinctly_from_an_empty_one \
	test_written_inside_the_cache_not_the_git_working_tree \
	test_rerunning_after_widening_covers_the_newly_added_publication \
	test_rerunning_with_no_changes_produces_identical_output \
	test_reports_a_missing_cache_clearly_and_exits_non_zero
