#!/bin/sh
# Drift verification: `verify` diffs the curated routing table against the
# upstream structure the cache already holds.
set -u
. "$DOCS_TEST_LIB/harness.sh"

sync_australia() {
	run_docs sync --family australia --upstream "$(fixture_upstream)"
	assert_equals 0 "$RUN_STATUS" "sync should exit zero: $RUN_ERR"
}

# write_test_routing <file> — a small routing table, tab-separated, deliberately
# diverged from the fixture upstream's actual structure: one entry that lines
# up cleanly, one naming a publication the fixture does not publish, one
# naming a real publication but a file it does not hold, and one naming a
# real file that exists but is not linked from its own publication's index.
write_test_routing() {
	_file=$1
	{
		printf '# test routing table\n'
		printf 'acl-evaluation\tplatform-security\tacl-rules.md\tbaseline entry that should verify clean\n'
		printf 'dead-publication\tintegrate-applications\tsomething.md\tpublication removed upstream\n'
		printf 'moved-topic\tplatform-security\tmoved-topic.md\tfile relocated or removed upstream\n'
		printf 'orphan-topic\tplatform-security\torphan-topic.md\tfile exists but delisted from its index\n'
	} >"$_file"
}

# add_orphan_topic — commits a file to the private upstream copy that exists
# under a real publication but is not linked from that publication's index,
# the structural residue a rename or a resolved collision leaves behind.
add_orphan_topic() {
	_dir=$(private_upstream_path)
	git -C "$_dir" checkout -q australia
	mkdir -p "$_dir/markdown/platform-security"
	cat >"$_dir/markdown/platform-security/orphan-topic.md" <<'EOF'
---
title: Orphan topic
locale: en-US
release: australia
bundle: australia
doc_type: concept
product_area: Platform security
last_updated: 2026-01-15
canonical_url: https://www.servicenow.com/docs/bundle/australia/page/platform-security/concept/orphan-topic.html
---

# Orphan topic

Not linked from the publication index.
EOF
	git -C "$_dir" add -A
	git -C "$_dir" \
		-c user.name='docs fixture' \
		-c user.email='fixture@example.invalid' \
		-c commit.gpgsign=false \
		commit -qam 'docs: add orphan topic'
}

# add_collision_topics — commits two files sharing a basename in different
# subdirectories of the same publication, and links only one from the
# publication's index. The unlinked one is the resolved-filename-collision
# shape a basename-only link check would wrongly wave through.
add_collision_topics() {
	_dir=$(private_upstream_path)
	git -C "$_dir" checkout -q australia
	mkdir -p "$_dir/markdown/platform-security/legacy" \
		"$_dir/markdown/platform-security/access-control"
	cat >"$_dir/markdown/platform-security/legacy/access-control-rules.md" <<'EOF'
---
title: Access control rules (legacy)
locale: en-US
release: australia
bundle: australia
doc_type: concept
product_area: Platform security
last_updated: 2026-01-15
canonical_url: https://www.servicenow.com/docs/bundle/australia/page/platform-security/concept/legacy-access-control-rules.html
---

# Access control rules (legacy)
EOF
	cat >"$_dir/markdown/platform-security/access-control/access-control-rules.md" <<'EOF'
---
title: Access control rules
locale: en-US
release: australia
bundle: australia
doc_type: concept
product_area: Platform security
last_updated: 2026-01-15
canonical_url: https://www.servicenow.com/docs/bundle/australia/page/platform-security/concept/access-control-rules.html
---

# Access control rules
EOF
	printf '\n- [Access control rules (legacy)](legacy/access-control-rules.md)\n' \
		>>"$_dir/markdown/platform-security/index.md"
	git -C "$_dir" add -A
	git -C "$_dir" \
		-c user.name='docs fixture' \
		-c user.email='fixture@example.invalid' \
		-c commit.gpgsign=false \
		commit -qam 'docs: add colliding-basename topics'
}

test_reports_a_publication_that_no_longer_exists_upstream() {
	sync_australia
	routing="$DOCS_TEST_TMP/routing.tsv"
	write_test_routing "$routing"

	run_docs verify --family australia --routing "$routing"
	[ "$RUN_STATUS" -ne 0 ] || fail 'verify should exit non-zero when drift is found'
	assert_contains "$RUN_OUT" '"type":"publication-missing"'
	assert_contains "$RUN_OUT" '"concept":"dead-publication"'
	assert_contains "$RUN_OUT" '"publication":"integrate-applications"'
}

test_reports_an_entry_topic_that_has_moved_or_disappeared() {
	sync_australia
	routing="$DOCS_TEST_TMP/routing.tsv"
	write_test_routing "$routing"

	run_docs verify --family australia --routing "$routing"
	assert_contains "$RUN_OUT" '"type":"entry-missing"'
	assert_contains "$RUN_OUT" '"concept":"moved-topic"'
	assert_contains "$RUN_OUT" '"entry_path":"moved-topic.md"'
}

test_reports_a_routing_target_absent_from_upstreams_own_index() {
	upstream=$(private_upstream)
	add_orphan_topic
	run_docs sync --family australia --upstream "$upstream"
	assert_equals 0 "$RUN_STATUS" "sync should exit zero: $RUN_ERR"

	routing="$DOCS_TEST_TMP/routing.tsv"
	write_test_routing "$routing"

	run_docs verify --family australia --routing "$routing"
	assert_contains "$RUN_OUT" '"type":"unlinked-from-index"'
	assert_contains "$RUN_OUT" '"concept":"orphan-topic"'
	assert_contains "$RUN_OUT" '"entry_path":"orphan-topic.md"'
}

test_a_basename_collision_does_not_mask_an_unlinked_entry() {
	upstream=$(private_upstream)
	add_collision_topics
	run_docs sync --family australia --upstream "$upstream"
	assert_equals 0 "$RUN_STATUS" "sync should exit zero: $RUN_ERR"

	routing="$DOCS_TEST_TMP/routing.tsv"
	printf 'collision-topic\tplatform-security\taccess-control/access-control-rules.md\tthe unlinked twin of legacy/access-control-rules.md\n' \
		>"$routing"

	run_docs verify --family australia --routing "$routing"
	[ "$RUN_STATUS" -ne 0 ] || fail 'verify should report drift when only the same-basename sibling is linked'
	assert_contains "$RUN_OUT" '"type":"unlinked-from-index"'
	assert_contains "$RUN_OUT" '"concept":"collision-topic"'
	assert_contains "$RUN_OUT" '"entry_path":"access-control/access-control-rules.md"'
}

test_exits_non_zero_when_any_discrepancy_is_found_zero_when_clean() {
	sync_australia
	routing="$DOCS_TEST_TMP/routing.tsv"
	write_test_routing "$routing"
	run_docs verify --family australia --routing "$routing"
	[ "$RUN_STATUS" -ne 0 ] || fail 'verify should exit non-zero with three known discrepancies'

	clean="$DOCS_TEST_TMP/clean-routing.tsv"
	printf 'acl-evaluation\tplatform-security\tacl-rules.md\tbaseline entry\n' >"$clean"
	run_docs verify --family australia --routing "$clean"
	assert_equals 0 "$RUN_STATUS" "verify should exit zero when nothing has drifted: $RUN_ERR"
	assert_not_contains "$RUN_OUT" '"type"' 'a clean routing table should report no discrepancies'
}

test_names_each_discrepancy_specifically_enough_to_act_on() {
	sync_australia
	routing="$DOCS_TEST_TMP/routing.tsv"
	write_test_routing "$routing"
	run_docs verify --family australia --routing "$routing"

	# Every record carries concept, publication, entry_path and a human detail
	# — enough to find and fix the row without opening the routing table.
	assert_contains "$RUN_OUT" "\"detail\":\"publication 'integrate-applications' no longer exists upstream for family 'australia'\""
	assert_contains "$RUN_OUT" "\"detail\":\"entry topic 'moved-topic.md' has moved or disappeared from publication 'platform-security'\""
}

test_runs_against_the_cache_without_a_network_round_trip_per_entry() {
	sync_australia
	routing="$DOCS_TEST_TMP/routing.tsv"
	write_test_routing "$routing"

	# platform-security has not been widened — only its index is in the
	# initial cone — yet its entries resolve correctly, proving verify reads
	# tree structure the blobless clone already fetched rather than pulling
	# each entry's blob on demand.
	run_docs status --family australia
	assert_equals 'api-reference' "$(json_array "$RUN_OUT" publications)" \
		'platform-security should not be widened for this case'

	# There is no other upstream left reachable: the whole suite restricts
	# git to the file protocol, and the only fixture upstream configured for
	# this family is the one already cloned from. A command that needed a
	# further round trip per entry would have nothing left to reach.
	run_docs verify --family australia --routing "$routing"
	assert_equals 1 "$RUN_STATUS" "verify should exit 1 for known discrepancies, not fail some other way: $RUN_ERR"
	assert_contains "$RUN_OUT" '"type":"publication-missing"'
	assert_contains "$RUN_OUT" '"type":"entry-missing"'
}

test_states_the_structural_only_limitation_in_its_own_output() {
	sync_australia
	routing="$DOCS_TEST_TMP/routing.tsv"
	write_test_routing "$routing"
	run_docs verify --family australia --routing "$routing"
	assert_contains "$RUN_ERR" 'structure only'

	run_docs help
	assert_equals 0 "$RUN_STATUS" "help should exit zero: $RUN_ERR"
	assert_contains "$RUN_OUT" 'verify'
	assert_contains "$RUN_OUT" 'Structural drift only'
}

test_reports_a_missing_cache_clearly_and_exits_non_zero() {
	routing="$DOCS_TEST_TMP/routing.tsv"
	write_test_routing "$routing"
	run_docs verify --family australia --routing "$routing"
	[ "$RUN_STATUS" -ne 0 ] || fail 'verify should exit non-zero when there is no cache'
	assert_contains "$RUN_ERR" 'docs sync'
}

test_refuses_a_routing_file_that_does_not_exist() {
	sync_australia
	run_docs verify --family australia --routing "$DOCS_TEST_TMP/nonesuch.tsv"
	[ "$RUN_STATUS" -ne 0 ] || fail 'verify should exit non-zero for a missing routing file'
	assert_contains "$RUN_ERR" 'nonesuch.tsv'
}

run_tests \
	test_reports_a_publication_that_no_longer_exists_upstream \
	test_reports_an_entry_topic_that_has_moved_or_disappeared \
	test_reports_a_routing_target_absent_from_upstreams_own_index \
	test_a_basename_collision_does_not_mask_an_unlinked_entry \
	test_exits_non_zero_when_any_discrepancy_is_found_zero_when_clean \
	test_names_each_discrepancy_specifically_enough_to_act_on \
	test_runs_against_the_cache_without_a_network_round_trip_per_entry \
	test_states_the_structural_only_limitation_in_its_own_output \
	test_reports_a_missing_cache_clearly_and_exits_non_zero \
	test_refuses_a_routing_file_that_does_not_exist
