#!/bin/sh
# The fixture upstream repository every other test file depends on.
set -u
. "$DOCS_TEST_LIB/harness.sh"
. "$DOCS_TEST_LIB/fixture.sh"

test_builds_deterministically() {
	fixture_build "$DOCS_TEST_TMP/a"
	fixture_build "$DOCS_TEST_TMP/b"

	for branch in australia zurich; do
		assert_equals \
			"$(git -C "$DOCS_TEST_TMP/a" rev-parse "$branch")" \
			"$(git -C "$DOCS_TEST_TMP/b" rev-parse "$branch")" \
			"two builds should produce the same commit on $branch"
	done
}

test_publishes_one_branch_per_family() {
	branches=$(git -C "$DOCS_TEST_FIXTURE" for-each-ref --format='%(refname:short)' refs/heads | LC_ALL=C sort | tr '\n' ' ')
	assert_equals 'australia zurich ' "$branches"
}

test_carries_a_topic_above_the_size_threshold() {
	path="$DOCS_TEST_FIXTURE/markdown/api-reference/c_GlideRecordAPI.md"
	size=$(wc -c <"$path" | tr -d ' ')
	[ "$size" -gt 40960 ] || fail "large topic should exceed 40 KB, got $size bytes"

	headings=$(grep -c '^## GlideRecord - ' "$path")
	[ "$headings" -gt 1 ] || fail 'large topic should carry one heading per method'
}

test_carries_an_empty_topic() {
	path="$DOCS_TEST_FIXTURE/markdown/administer/empty-topic.md"
	assert_file_exists "$path"
	assert_equals 0 "$(wc -c <"$path" | tr -d ' ')" 'empty topic should be zero bytes'
}

test_omits_the_synonym_reference_from_the_repository_index() {
	assert_file_exists "$DOCS_TEST_FIXTURE/markdown/vocabulary/sn-docs-synonym-terms-enus.md"
	assert_not_contains "$(cat "$DOCS_TEST_FIXTURE/llms.txt")" 'synonym' \
		'the repository index should omit the synonym reference, as upstream does'
}

test_carries_realistic_frontmatter() {
	head=$(head -11 "$DOCS_TEST_FIXTURE/markdown/platform-security/acl-rules.md")
	for key in title locale release bundle doc_type product_area last_updated canonical_url; do
		assert_contains "$head" "$key:" "frontmatter should carry $key"
	done
}

run_tests \
	test_builds_deterministically \
	test_publishes_one_branch_per_family \
	test_carries_a_topic_above_the_size_threshold \
	test_carries_an_empty_topic \
	test_omits_the_synonym_reference_from_the_repository_index \
	test_carries_realistic_frontmatter
