---
name: docs
description: >
  Consult real ServiceNow product documentation before stating a Glide API signature, an ACL/
  Business Rule/Flow Designer/Client Script behaviour, or any other version-dependent ServiceNow
  platform fact. Triggers on unambiguous ServiceNow platform identifiers — GlideRecord,
  GlideSystem, or another Glide* API; ACL; Business Rule; Client Script; UI Policy; Data Policy;
  Flow Designer; Script Include; Update Set; ATF; Service Portal widget; a ServiceNow table or
  field name such as sys_id, incident, or sys_user — not on ambient service-management words like
  "ticket" or "workflow" used on their own. Does not trigger for general programming questions
  that don't touch the ServiceNow platform.
---

# sn-skills/docs — cited retrieval over ServiceNow product documentation

You are about to say something about the ServiceNow platform that could be wrong in a way the
person can't easily catch: an API signature, an ACL/Business Rule/Flow evaluation order, a
"this is available since" claim, anything that differs by release. Don't answer that from
memory. Consult the real documentation, on the release family the project is pinned to, and cite
it. If the documentation doesn't say, say that instead of guessing.

## The six correctness contracts

Every answer this skill produces obeys these. They are the reason it exists.

1. **Never state a Glide API signature, ACL behaviour, or version-dependent fact from memory.**
   If the question is in scope for this skill, an answer with no consulted topic behind it is a
   defect, not a shortcut.
2. **When retrieval finds nothing, say so.** No fallback to model priors, hedged or otherwise.
3. **Always cite the `canonical_url`** of every topic the answer draws from, so it can be
   verified on servicenow.com/docs in one click.
4. **"Not checked out" is not "not documented."** Before concluding a topic isn't covered, check
   whether it's merely outside the current cone (see Widening below) and widen before giving up.
5. **An empty or truncated upstream file is an upstream defect, not silence.** Report it as
   such, by name, with its `canonical_url` when the record has one — never as "not covered."
6. **A withdrawn family is out of support, stated plainly** — never silently answered from a
   different family.

## Procedure

Every command below is `bin/docs` inside this skill's own directory tree, not whatever
`bin/docs` might mean relative to the current working directory — a retrieval question can come
up in the middle of unrelated project work anywhere, and the working directory is never this
skill's own. Resolve the root once, in the same shell session as the rest of this procedure, and
reuse it as `DOCS_ROOT`:

1. `CLAUDE_PLUGIN_ROOT`, if set — Claude Code, loaded from an installed plugin.
2. `PLUGIN_ROOT`, if set — Codex, loaded from an installed plugin.
3. Otherwise, this file's own location. This invocation reported a base directory for this skill
   — it ends in `skills/docs`; strip that suffix and you have `DOCS_ROOT`. Use that literal,
   resolved path in the commands below. Never fall back to a bare `.` or a relative path: nothing
   guarantees the working directory is this skill's root, and a wrong guess fails silently as
   "command not found" rather than loudly.

Every command in this procedure is `"$DOCS_ROOT/bin/docs"`, and the routing table and synonym
reference live under `"$DOCS_ROOT/skills/docs/"`.

### 0. Decide whether this needs retrieval at all

The description's trigger list is a keyword proxy; the real gate is contract 1, above. If nothing
in the question could differ by release or version, don't retrieve — a general programming
question mid-session should cost nothing. When in doubt because the question mixes ServiceNow and
generic code, retrieve only for the ServiceNow-specific part.

### 1. Resolve the family and make sure the cache is current

```
"$DOCS_ROOT/bin/docs" family
"$DOCS_ROOT/bin/docs" sync --family <family>
```

`sync` is cheap when the cache is already fresh — it's a no-op, not a re-clone. `family` and
`status` (below) both report the resolution as `family`/`family_source`/`family_source_path` on
their JSON. State both the family and where it came from in the answer: an answer nobody knows
the family of is not attributable. If this exits reporting a family as out of support, stop and
relay that verbatim — it is not a bug to route around.

Run `"$DOCS_ROOT/bin/docs" status --family <family>` to get the cache's age and staleness as
JSON. If `stale` is `true`, state the cache's age on the answer; don't refresh proactively past
what `sync` already does; a stale cache still answers.

Installed-app (Store) content lives on a separate, unversioned `store` branch, not inside any
family's cache — `"$DOCS_ROOT/bin/docs" sync --family store` caches it independently. Consult it for
questions about a Store-installed application; it's always current for "the newest published
Store docs" rather than pinned to a release, which is exactly what to say when citing it.

### 2. Normalize the query against the synonym reference

ServiceNow ships a synonym reference — 234 canonical-term-to-synonym groups — specifically to
bridge queries like "ATF" or "AWA" to the term the documentation actually uses. It is **absent
from `llms.txt`**, so it is not part of the default cone and must be pulled in deliberately:

```
"$DOCS_ROOT/bin/docs" widen --family <family> --publication vocabulary
```

Then read `markdown/vocabulary/sn-docs-synonym-terms-enus.md` from the cache (small; fine to read
whole) and grep it for the term the person used. If it appears as a synonym, search using the
preferred term it maps to, not the term the person typed — the documentation itself uses the
preferred term, and search precision depends on matching that vocabulary.

### 3. Route: routing table first, then the heading index, then full text as fallback

Check `"$DOCS_ROOT/skills/docs/routing.tsv"` for the (normalized) concept. It's a small, curated,
diffable table — a handful of high-traffic concepts mapped to the one publication that's
authoritative for them, because several publications can plausibly mention a concept (ACLs show
up in application-development too) and only one is the entry point. If the concept isn't in the
table, that's expected — most queries won't be — fall through to the heading index.

If the routing table names a publication not yet in the cone, widen it before concluding
anything (contract 4):

```
"$DOCS_ROOT/bin/docs" widen --family <family> --publication <publication>
```

A publication upstream doesn't publish for this family fails loudly by name — that failure is
itself informative (the family doesn't have this content), distinct from "not cached yet."

Then consult the generated heading index at `index.jsonl`, written next to (not inside) the
checkout `docs status`'s `cache` field points at — i.e. `$(dirname <cache>)/index.jsonl`.
Regenerate it with `"$DOCS_ROOT/bin/docs" index --family <family>` if it's missing, or if it has no record
whose `path` starts with `markdown/<publication>/` for a publication you just widened to — that's
the sign the widen actually grew the cone rather than finding the publication already cached
(`widen` is a no-op when nothing changed, so don't regenerate on the strength of having merely
called it). Regeneration rebuilds the whole file from whatever the cone currently holds, so it
can't rot out of sync. It's one JSON object per line — `path`, `title`,
`product_area`, `canonical_url`, `status`, `headings` — and it's plain text on purpose: grep it
for the term, don't parse it with a script. A record's `status` field tells you which of the
remaining contracts applies before you even open the file:

- `status: "empty"` or `status: "truncated"` — contract 5. Report the upstream defect by path,
  and cite `canonical_url` if the record has one (a truncated file may still have working
  frontmatter above the cut; a fully empty file has none — say so rather than guessing at a URL
  from the file's path, since the two don't follow the same pattern). Don't open the file;
  there's nothing in it, or the frontmatter never closed.
- `status: "unreadable"` — a *local* problem (the file didn't open when the index was built,
  typically a sparse checkout that didn't actually materialize it), not an upstream defect. Don't
  report this as contract 5 — that would blame ServiceNow for a local cache fault. Re-run
  `"$DOCS_ROOT/bin/docs" sync --family <family>` and `"$DOCS_ROOT/bin/docs" index --family <family>`; if the record is
  still `unreadable` after that, say retrieval failed locally, not that the topic is undocumented.
- `status: "ok"` — proceed to read discipline, below.

If nothing in the routing table or the heading index matches, full-text search over whatever
`docs status` currently reports as cached (its `publications` field) with your own grep/search
tools is the fallback. If that also finds nothing, that's contract 2: say so, plainly, and stop —
don't go widen more publications on a hunch first. A concept absent from the routing table, with
no heading match and no full-text match in the cone you already have, is exactly what "documented
nowhere reachable from here" looks like; broadening into model knowledge because search came up
empty is the one thing this skill exists to prevent.

### 4. Read discipline

**Never read a publication index whole.** `markdown/<publication>/index.md` exists to be listed
by the heading index, not opened directly — some are megabytes. Never read any file over roughly
40 KB whole either; a meaningful fraction of upstream's non-index files exceed that. (Current
sizes are dated facts, not stable ones — see CLAUDE.md's "Non-obvious facts about upstream" for
the last-verified numbers and re-verify before quoting them.)

For anything past that size, slice by heading instead of reading start to finish:

1. Grep the target file for its heading lines (`^# ` / `^## `) with line numbers
   (`grep -n '^#'`) to find where the section you need starts and where the next heading begins.
2. Read only that line range.

API reference files are the sharpest case: they carry one `## ClassName - methodName(...)`
heading per method. A GlideRecord method lookup is one heading match plus a bounded read — about
200 tokens — never the whole 208 KB, 52,000-token class file. This is not an optimization to
skip under time pressure; reading a whole API reference file is the specific failure mode this
rule exists to prevent.

### 5. Answer, citing the canonical URL

State: the family (and its source — pinned vs. defaulted), the cache's age if stale, and the
`canonical_url` of every topic drawn from. If a topic came from the unversioned `store` branch,
say so explicitly — it isn't family-pinned, and citing it the same way as a family-pinned topic
would misstate its provenance.

## Cache commands reference

The cache is owned entirely by `bin/docs`; never read, reuse, or write to any other clone.
Full interface: `"$DOCS_ROOT/bin/docs" help`. The commands this procedure uses (`docs` below
is shorthand for `"$DOCS_ROOT/bin/docs"`, resolved once at the top of this procedure):

| Command | Used for |
| --- | --- |
| `docs family` | Which family and where it was resolved from, without touching the network. |
| `docs sync --family <f>` | Create or refresh the cache; a no-op when already fresh. |
| `docs widen --family <f> --publication <p>` | Extend the cone to a publication not yet cached; fails by name if upstream doesn't publish it. |
| `docs status --family <f>` | Cache age, staleness, cache path, and what's cached vs. what upstream publishes — as JSON. |
| `docs index --family <f>` | (Re)generate `index.jsonl` from whatever the cone currently holds. |

Never wrap these, or grep, in another layer of tooling — the host agent's own search and read
tools are the retrieval mechanism; this skill only tells you where and how to point them.
