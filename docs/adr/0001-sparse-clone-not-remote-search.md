# Retrieve from a local sparse clone, not a remote search API

The obvious way to search 49,000 upstream topics is to call a search API rather than put the
corpus on disk. We instead maintain a local sparse clone per Family and search it with the host
agent's own tools, because GitHub code search — the only remote full-text option — **indexes
only the repository's default branch**, and therefore cannot see any Family except the newest.
Since answering a Zurich question from Australia documentation is this project's single most
damaging failure mode, a search that silently reads from the wrong Family is worse than no
search at all.

## Considered options

- **GitHub code search.** Rejected: default-branch-only indexing makes every non-newest Family
  invisible, and it is rate-limited to 10 requests per minute. Verified by querying for a
  string unique to a non-default branch and getting zero results.
- **Walking Publication indexes over raw URLs.** Family-correct and needs no disk, but the
  indexes are far too large to read — the API reference index alone is measured in megabytes —
  so navigation degrades into guessing from titles.
- **Local sparse clone (chosen).** Family-correct, exact, offline after the first sync, and fast
  enough that the initial checkout is a couple of seconds.

## Consequences

Retrieval depends on `git` being present and on local disk, and the Cache must be introspectable
so that a publication merely absent from the Cone is never mistaken for absent documentation.
Expect this decision to be re-proposed: a remote API looks strictly simpler until you check
which branches it can see.
