# skill-sndocs

A portable agent skill that gives AI coding agents **family-correct, cited retrieval** over
[`ServiceNow/ServiceNowDocs`](https://github.com/ServiceNow/ServiceNowDocs) — ServiceNow's
~49,000-file documentation repository published for LLM consumption.

> **Status: v0.x, in progress.** The design is settled. The cache executable can create, report,
> and maintain a cache, resolve which family to use, and generate a heading index over it. The
> skill definition, curated routing table, and retrieval procedure live at
> [`skills/sndocs/SKILL.md`](skills/sndocs/SKILL.md), and the skill is now installable by name —
> see [Installation](#installation). Eval results will be published in this README as they land,
> and the cross-agent support claims below are marked untested until they are tested.

## Why

ServiceNow publishes its docs as markdown specifically for agents, and its README advises
"point your AI at `llms.txt`." That is not enough:

- **`llms.txt` under-retrieves.** The synonym reference at
  `markdown/vocabulary/sn-docs-synonym-terms-enus.md` — 234 canonical→synonym groups that
  ServiceNow added explicitly for AI retrieval — is not listed in `llms.txt` at all. An agent
  following the official advice will never find it.
- **The indexes are too big to read.** `markdown/api-reference/index.md` is 2.2 MB. Reading it
  costs roughly 550,000 tokens. All 55 publication indexes together are 21 MB.
- **GitHub code search can't help.** It indexes only the default branch, so it is structurally
  incapable of searching the Zurich, Yokohama, or Xanadu families.
- **Release family is a correctness problem.** Docs are branched per family. Most ServiceNow
  customers are not on the newest release, so answering a Zurich question from Australia docs
  is the single most likely way an agent produces confident, wrong, unfalsifiable output.

## What it does

- Maintains a **blobless sparse clone** of the correct release-family branch, widening the
  sparse cone on demand. Measured: 1.4s to clone, 2.5s to check out `api-reference` (24 MB).
- Routes queries via a **generated heading index** (path, title, product area, canonical URL,
  H1/H2 for every file) plus a small curated concept→publication table.
- Normalizes queries using ServiceNow's own **synonym reference**, read from the clone at
  runtime so it is never stale.
- **Section-slices** large files. `c_GlideRecordAPI.md` is 208 KB with 161 headings; retrieving
  one method costs ~200 tokens instead of ~52,000.

## Installation

The skill definition, the routing table, and `bin/sndocs` all live in this one repository and
ship together — there is nothing to build and nothing to configure beyond optionally pinning a
family (see [Using the cache executable](#using-the-cache-executable) below, or just let it
default).

**Claude Code:**

```bash
claude plugin marketplace add vbilgin/skill-sndocs
claude plugin install sndocs@sndocs
```

Or, from inside a session: `/plugin marketplace add vbilgin/skill-sndocs` then
`/plugin install sndocs@sndocs`.

**Codex:**

```bash
codex plugin marketplace add vbilgin/skill-sndocs
codex plugin add sndocs@sndocs
```

Codex reads the same `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` Claude
Code does — verified against `codex` 0.147.0, see
[`docs/adr/0004-packaging-shares-one-manifest.md`](docs/adr/0004-packaging-shares-one-manifest.md).
There is no separate Codex manifest to fall out of sync with the Claude one.

Both commands install a read-only, updatable copy of this repository; `bin/sndocs` and the skill
definition travel together, and the skill locates its own executable at install time regardless
of which directory you're working in when a ServiceNow question comes up.

**Any other agent that reads `AGENTS.md`:** clone or vendor this repository somewhere the agent
can read it, and its root [`AGENTS.md`](AGENTS.md) points at
[`skills/sndocs/SKILL.md`](skills/sndocs/SKILL.md). This path has been exercised as a file layout
(the plugin installs above materialize exactly this shape) but not against a live non-Claude,
non-Codex agent — treat it as reference until someone reports it working end to end.

Setup after install is one command with no language runtime, virtual environment, or package
manager — `bin/sndocs sync --family <family>` clones a sparse, blobless checkout (measured: 1.4s)
and answers the first question from it; nothing downloads the full 269 MB documentation set.

## Using the cache executable

`bin/sndocs` is dependency-free POSIX shell. `git` and a POSIX userland are the whole
dependency list — no Node, no Python virtual environment, no package manager.

```bash
bin/sndocs sync --family australia
```

That creates a blobless, shallow, sparse clone at `${XDG_CACHE_HOME:-~/.cache}/sndocs/<family>`
holding the API reference publication plus every publication index, and records the resolved
commit and fetch timestamp alongside it. Syncing again while that cache is fresh is a no-op;
syncing a cache older than seven days refreshes it first, so ordinary use keeps it current.

```bash
bin/sndocs widen --family australia --publication platform-security
```

That extends the cache to cover a publication it does not hold yet, pulling only the new
content into the clone that is already there — refreshing first if the cache is stale, so the
widened cone is coherent about which snapshot it holds. A publication upstream does not publish
is refused by name, which is what keeps "not cached" distinguishable from "not documented."

```bash
bin/sndocs refresh --family australia
```

That fetches the family again now and records the new commit and fetch timestamp, so nobody
waits for the staleness window after a release ships. If upstream cannot be reached, the
existing cache is kept and its age reported — offline is a degraded mode, not a failure.

```bash
bin/sndocs family
```

That prints the family every other command would work on and where that family came from, as
JSON on stdout. Resolution, highest wins: `--family` on the invocation; then the nearest
`.sndocs` file at or above the working directory; then `$XDG_CONFIG_HOME/sndocs/config`; then
the newest family, with a warning that no family was configured. Both files are `key=value`
lines with `#` comments, and the key is `family`.

The project file is the documented place to pin one, because family is a property of the
codebase rather than of the machine — an update-set repository for a Zurich client is Zurich
permanently, and committing `family=zurich` means teammates and agents inherit it without being
told. A consultant moving between client repositories changes documentation sets by changing
directory.

Upstream deletes the oldest family branch when a new release reaches general availability, so a
pinned family eventually ceases to exist. When that happens, every command stops and reports
that the release is out of support, exiting non-zero. That is actionable information about the
instance, and specifically not something to paper over by quietly answering from the newest
family.

```bash
bin/sndocs status --family australia
```

That prints the family and where it was resolved from, the commit, fetch timestamp, cache age
and whether it is stale, the
upstream, the cache path, which publications are cached in full, which publications upstream
publishes, and which publications have their index cached, as JSON on stdout. It exits
non-zero if that family has no cache. Naming what is cached — rather than reporting a bare
yes — is what lets "not downloaded" be told apart from "not documented."

```bash
bin/sndocs index --family australia
```

That walks every topic the cache currently holds in one pass and writes a heading index to the
cache: one greppable line per topic, holding its path, title, product area, canonical URL, and
every first- and second-level heading verbatim, including method-level headings inside large API
reference files. A topic that is empty or whose frontmatter never closes is flagged as such,
rather than reported as undocumented. The index is plain text on purpose — finding a heading
needs a grep, not a parser — and it lives inside the cache, outside version control, rebuilt
whole on every run so it can never rot out of sync with what the cone holds.

`--upstream <repository>` (or `SNDOCS_UPSTREAM`) overrides the repository cloned from. It is a
supported part of the interface, and it exists so the test suite can run against a small local
fixture rather than downloading 269 MB of monthly-changing upstream content. `SNDOCS_NOW`
overrides the current time in the same spirit, so the suite can cross the seven-day staleness
window without waiting a week.

Run `bin/sndocs help` for the full interface.

## Tests

```bash
tests/run.sh
```

The suite runs offline. It builds a deterministic fixture repository — two family branches,
realistic frontmatter, one oversized topic, one empty topic — and restricts git to the file
protocol, so a test that reaches for the network fails loudly rather than downloading upstream.

## Correctness contracts

These are the reason the skill exists. Every one of them is an eval case.

1. Never state a Glide API signature, ACL behaviour, or version-dependent fact from memory.
2. When retrieval finds nothing, **say so** — never fall back to model priors.
3. Always cite the `canonical_url` so the answer can be verified against servicenow.com/docs.
4. "Not checked out" is not "not documented." The sparse cone is introspectable so contract 2
   cannot misfire.
5. An empty or truncated upstream file (a known, recurring upstream build defect) is reported
   as such, with the canonical URL — never as "not covered."
6. When a family's branch is deleted upstream, say plainly that the pinned release is
   out of support. Xanadu will disappear.

## Scope

**In:** ServiceNow platform development and admin/configuration work — scripting, Glide APIs,
Business Rules, Flow Designer, ACLs, integrations, table configuration, update sets, plus the
unversioned `store` branch for installed-app documentation.

**Out:** live instance access (this skill is docs-only, by design); the ServiceNow Fluent SDK,
which is covered by ServiceNow's own skills in [`ServiceNow/sdk`](https://github.com/ServiceNow/sdk);
the `mobile`, `nofamily`, and `other` branches; an MCP server.

## Agent support

| Agent | Status |
|---|---|
| Claude Code | Primary target. Installs from the manifest, and a headless `claude -p` session correctly fires the skill on a Glide API question — verified directly (`claude` 2.1.224). Actually running `bin/sndocs` from that session was blocked on Bash approval in this sandbox and not observed to succeed; path resolution and answer accuracy are eval-gated (see [#9](https://github.com/vbilgin/skill-sndocs/issues/9)). |
| Codex | Verified end to end in a live, authenticated `codex exec` session (`codex` 0.147.0): installs from `vbilgin/skill-sndocs`, correctly fires on a Glide API question and stays silent on an unrelated one, resolves its own executable's path from the installed plugin location with no working-directory assumption, runs the full `sync`/`widen`/`index` sequence, slices the target API reference file by heading instead of reading it whole, and answers with the canonical URL and the (defaulted) family stated. |

## Provenance and independence

This is an independent community project. It is **not affiliated with, sponsored by, or
endorsed by ServiceNow, Inc.** ServiceNow, Now Platform, and related marks are trademarks of
ServiceNow, Inc.

This repository **redistributes no ServiceNow documentation.** It fetches Apache-2.0-licensed
markdown from `ServiceNow/ServiceNowDocs` at runtime into a local cache outside version
control, and every answer cites the `canonical_url` back to
[servicenow.com/docs](https://www.servicenow.com/docs). There is no embedded copy of the docs
to go stale, by construction.

## License

Apache License 2.0 — see [LICENSE](LICENSE). This matches the license of the upstream
documentation repository.
