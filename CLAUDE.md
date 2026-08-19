# skill-sndocs

Building an agent skill for retrieval over [`ServiceNow/ServiceNowDocs`](https://github.com/ServiceNow/ServiceNowDocs).
Read [README.md](README.md) for why this exists and what the correctness contracts are.

## Non-obvious facts about upstream

Verified 2026-08-06 against the `australia` branch. Re-verify before relying on any of it.

- Default branch is **`australia`**, not `main`. Branches are families: `australia`,
  `zurich`, `yokohama`, `xanadu`, plus unversioned `store`, `mobile`, `nofamily`, `other`.
  The oldest family branch is **deleted** when a new release goes GA.
- 48,998 files / 269 MB on `australia`. Median file 3.3 KB; 293 files exceed 40 KB.
- Layout is `markdown/{publication}/[{product}/]{file}.md`, max depth 3. 55 publications.
- Frontmatter: `title`, `locale`, `release`, `bundle`, `doc_type`, `product_area`,
  `last_updated`, `canonical_url`.
- `markdown/api-reference/index.md` is **2.2 MB**. Never read a publication index whole.
- API reference files carry one `## Class - method(...)` heading per method. Slice by heading.
- **GitHub code search indexes only the default branch.** It cannot search non-Australia
  families. Do not use it.
- `markdown/vocabulary/sn-docs-synonym-terms-enus.md` (234 synonym groups) is **absent from
  `llms.txt`**. Read it from the clone; never vendor it.
- ~15 files are empty from upstream build bugs. Treat empty as broken, not as absent content.
- Do not fetch from `servicenow.com/docs` — it is a JS SPA and returns nothing readable.

## Constraints

- **Never vendor documentation content into this repo.** Runtime fetch only — the provenance
  claim in the README depends on it.
- The sync script is dependency-free POSIX shell. No Node, no Python venv, no `npx`.
- Search belongs to the host agent's native tools. Do not wrap grep.
- This skill is **docs-only**. It never touches a live ServiceNow instance.

## Agent skills

### Issue tracker

Issues live in GitHub Issues at `vbilgin/skill-sndocs`, via the `gh` CLI.
See `docs/agents/issue-tracker.md`.

### Triage labels

Default canonical vocabulary — label strings match role names exactly.
See `docs/agents/triage-labels.md`.

### Domain docs

Single-context — `CONTEXT.md` and `docs/adr/` at the repo root.
See `docs/agents/domain.md`.
