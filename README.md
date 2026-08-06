# skill-sndocs

A portable agent skill that gives AI coding agents **family-correct, cited retrieval** over
[`ServiceNow/ServiceNowDocs`](https://github.com/ServiceNow/ServiceNowDocs) — ServiceNow's
~49,000-file documentation repository published for LLM consumption.

> **Status: v0.x, scaffold only.** The design is settled; the skill is not yet implemented.
> Nothing here retrieves anything yet. Eval results will be published in this README as they
> land, and the cross-agent support claims below are marked untested until they are tested.

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
| Claude Code | Primary target. Eval-gated. |
| Codex | Manifest planned. **Untested** — the claim will be dropped rather than hedged if it goes unverified. |

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
