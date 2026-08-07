# One plugin manifest serves Claude Code and Codex; there is no `.codex-plugin`

Packaging needs to make the Skill installable in Claude Code and in Codex without forking the
retrieval procedure per agent — `skills/sndocs/SKILL.md` is the one copy, referenced by every
packaging form. The open question was whether that same rule extends to the *manifest* JSON, or
whether each ecosystem needs its own.

Verified against `claude` 2.1.224 and `codex` 0.147.0 (Linux x86_64, 2026-08-07): a Codex binary
extracted for manifest-discovery strings shows its plugin loader checks, in order,
`.codex-plugin/plugin.json`, `.claude-plugin/plugin.json`, then `.cursor-plugin/plugin.json`, and
the same three-way fallback for `marketplace.json`. Tested directly — `codex plugin marketplace
add <path>` against a repository holding only `.claude-plugin/plugin.json` and
`.claude-plugin/marketplace.json` resolved the plugin, and `codex plugin add sndocs@sndocs`
installed it, materializing `bin/sndocs` and `skills/sndocs/SKILL.md` intact (executable bit
preserved; Codex clones the source rather than copying it, so nothing here depends on symlinks
surviving install). No `.codex-plugin` directory was present for either step.

## Considered options

- **A `.codex-plugin/plugin.json` mirroring the Claude one.** This is what a sibling project
  (mattpocock/skills) ships, per its own ADR — but that project needed Codex's manifest to name a
  single directory excluding several unpromoted sibling directories, which forced its own file.
  This repository has no such bucketing: one skill, one directory. Shipping a second manifest
  here would be pure duplication with no behavioural difference, and a second file is a second
  place for the `version` and `skills` fields to drift out of sync.
- **A symlink from `.codex-plugin/plugin.json` to the Claude manifest.** Avoids drift but adds a
  file whose only job is to exist, against measured evidence that Codex does not require it.
- **No `.codex-plugin` directory at all (chosen).** `.claude-plugin/plugin.json` and
  `.claude-plugin/marketplace.json` are the only manifests. Codex's own fallback chain, not an
  assumption, is what makes this correct.

## Consequences

Two ecosystems' plugin managers point at the same two JSON files and the same `skills/sndocs/`
directory; there is exactly one place that names the version, the skill path, or the marketplace
entry. If a future Codex release drops the `.claude-plugin/plugin.json` fallback, `codex plugin
marketplace add` on this repository starts failing loudly rather than silently serving stale
data, which is preferable to a manifest nobody is testing.

This does not verify that Codex actually *triggers* the skill on a matching query — that requires
an authenticated Codex session, which this environment did not have. Installation and skill
discovery are verified; live triggering is not, and the README states that distinction rather
than rounding it up to "supported."
