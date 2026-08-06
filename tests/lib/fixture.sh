# shellcheck shell=sh
#
# Fixture upstream repository builder.
#
# Builds a small stand-in for ServiceNow/ServiceNowDocs so the suite never
# downloads 269 MB of monthly-changing upstream content. The shape mirrors the
# parts of upstream the Skill depends on: two Family branches, a Repository
# index, Publication indexes, realistic frontmatter, one topic large enough to
# exercise size thresholds, and one empty topic.
#
# The build is deterministic: fixed identity, fixed commit dates, fixed
# content, so the same inputs always produce the same commit identifiers.

FIXTURE_FAMILY_NEWEST='australia'
FIXTURE_FAMILY_PREVIOUS='zurich'

# Fixed so that the same content always produces the same commit identifiers.
FIXTURE_DATE='2026-01-15T09:00:00Z'

# fixture_git <fixture-dir> <git-args...>
fixture_git() {
	_dir=$1
	shift
	GIT_AUTHOR_NAME='sndocs fixture' \
		GIT_AUTHOR_EMAIL='fixture@example.invalid' \
		GIT_AUTHOR_DATE="$FIXTURE_DATE" \
		GIT_COMMITTER_NAME='sndocs fixture' \
		GIT_COMMITTER_EMAIL='fixture@example.invalid' \
		GIT_COMMITTER_DATE="$FIXTURE_DATE" \
		git -C "$_dir" -c commit.gpgsign=false -c core.autocrlf=false "$@"
}

# fixture_frontmatter <title> <release> <doc_type> <product_area> <canonical-slug>
fixture_frontmatter() {
	cat <<EOF
---
title: $1
locale: en-US
release: $2
bundle: $2
doc_type: $3
product_area: $4
last_updated: 2026-01-15
canonical_url: https://www.servicenow.com/docs/bundle/$2/page/$5
---
EOF
}

# fixture_large_topic <release> — an API class reference above the 40 KB
# threshold, carrying one second-level heading per method the way upstream's
# API reference topics do.
fixture_large_topic() {
	fixture_frontmatter 'GlideRecord API' "$1" 'api' 'Now Platform' \
		'app-store/dev_portal/API_reference/GlideRecord/concept/c_GlideRecordAPI.html'
	printf '\n# GlideRecord API\n\nGlideRecord is a class used to perform operations on a table.\n'
	_i=1
	while [ "$_i" -le 60 ]; do
		printf '\n## GlideRecord - method%02d(String name, Object value)\n\n' "$_i"
		printf 'Method %02d of the GlideRecord API.\n\n' "$_i"
		printf '| Name | Type | Description |\n| --- | --- | --- |\n'
		printf '| name | String | The name of the field. |\n'
		printf '| value | Object | The value to compare against. |\n\n'
		_j=1
		while [ "$_j" -le 6 ]; do
			printf 'Filler line %02d for method %02d, present so this topic exceeds the size threshold at which topics must be read by section rather than whole.\n' "$_j" "$_i"
			_j=$((_j + 1))
		done
		_i=$((_i + 1))
	done
}

# fixture_populate <fixture-dir> <release> — writes one Family's whole tree.
fixture_populate() {
	_dir=$1
	_release=$2

	rm -rf "$_dir/markdown" "$_dir/llms.txt"
	mkdir -p \
		"$_dir/markdown/api-reference" \
		"$_dir/markdown/platform-security" \
		"$_dir/markdown/administer" \
		"$_dir/markdown/vocabulary"

	# Repository index. Deliberately omits the synonym reference, the way
	# upstream's does — that omission is a fact the Skill relies on.
	cat >"$_dir/llms.txt" <<EOF
# ServiceNow product documentation ($_release)

- [API reference](markdown/api-reference/index.md)
- [Platform security](markdown/platform-security/index.md)
- [Administer](markdown/administer/index.md)
EOF

	{
		fixture_frontmatter 'API reference' "$_release" 'index' 'Now Platform' \
			'app-store/dev_portal/API_reference/index.html'
		printf '\n# API reference\n\n- [GlideRecord API](c_GlideRecordAPI.md)\n- [GlideSystem API](c_GlideSystemAPI.md)\n'
	} >"$_dir/markdown/api-reference/index.md"

	fixture_large_topic "$_release" >"$_dir/markdown/api-reference/c_GlideRecordAPI.md"

	{
		fixture_frontmatter 'GlideSystem API' "$_release" 'api' 'Now Platform' \
			'app-store/dev_portal/API_reference/glideSystem/concept/c_GlideSystemAPI.html'
		printf '\n# GlideSystem API\n\n## GlideSystem - getUserID()\n\nReturns the sys_id of the current user.\n'
	} >"$_dir/markdown/api-reference/c_GlideSystemAPI.md"

	{
		fixture_frontmatter 'Platform security' "$_release" 'index' 'Platform security' \
			'platform-security/index.html'
		printf '\n# Platform security\n\n- [ACL rules](acl-rules.md)\n'
	} >"$_dir/markdown/platform-security/index.md"

	# The one topic whose content diverges between Families, so family
	# correctness can be proven rather than hoped for.
	{
		fixture_frontmatter 'ACL rules' "$_release" 'concept' 'Platform security' \
			'platform-security/concept/access-control-rules.html'
		printf '\n# ACL rules\n\n## Evaluation order\n\n'
		if [ "$_release" = "$FIXTURE_FAMILY_NEWEST" ]; then
			printf 'ACL rules are evaluated table first, then field, then record.\n'
		else
			printf 'ACL rules are evaluated field first, then table.\n'
		fi
	} >"$_dir/markdown/platform-security/acl-rules.md"

	{
		fixture_frontmatter 'Administer' "$_release" 'index' 'Now Platform administration' \
			'administer/index.html'
		printf '\n# Administer\n\n- [System properties](empty-topic.md)\n'
	} >"$_dir/markdown/administer/index.md"

	# Empty from an upstream build defect, not because the topic is absent.
	: >"$_dir/markdown/administer/empty-topic.md"

	{
		fixture_frontmatter 'Vocabulary' "$_release" 'index' 'Now Platform' \
			'vocabulary/index.html'
		printf '\n# Vocabulary\n\n- [Synonym terms](sn-docs-synonym-terms-enus.md)\n'
	} >"$_dir/markdown/vocabulary/index.md"

	{
		fixture_frontmatter 'Synonym terms' "$_release" 'reference' 'Now Platform' \
			'vocabulary/reference/sn-docs-synonym-terms-enus.html'
		printf '\n# Synonym terms\n\n'
		printf '| Preferred term | Synonyms |\n| --- | --- |\n'
		printf '| Automated Test Framework | ATF, automated testing |\n'
		printf '| Advanced Work Assignment | AWA |\n'
		printf '| Access control rule | ACL, access control list |\n'
	} >"$_dir/markdown/vocabulary/sn-docs-synonym-terms-enus.md"
}

# fixture_build <fixture-dir> — creates the fixture upstream repository.
fixture_build() {
	_dir=$1
	rm -rf "$_dir"
	mkdir -p "$_dir"

	git init -q "$_dir"
	git -C "$_dir" symbolic-ref HEAD "refs/heads/$FIXTURE_FAMILY_NEWEST"

	fixture_populate "$_dir" "$FIXTURE_FAMILY_NEWEST"
	fixture_git "$_dir" add -A
	fixture_git "$_dir" commit -q -m "docs: $FIXTURE_FAMILY_NEWEST"

	fixture_git "$_dir" checkout -q -b "$FIXTURE_FAMILY_PREVIOUS"
	fixture_populate "$_dir" "$FIXTURE_FAMILY_PREVIOUS"
	fixture_git "$_dir" add -A
	fixture_git "$_dir" commit -q -m "docs: $FIXTURE_FAMILY_PREVIOUS"

	fixture_git "$_dir" checkout -q "$FIXTURE_FAMILY_NEWEST"

	# Partial clone over file:// only works if the serving side allows it.
	git -C "$_dir" config uploadpack.allowFilter true
}
