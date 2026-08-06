# Documentation is fetched at runtime and never vendored

Committing a copy of the upstream documentation into this repository would make the Skill faster,
offline by default, and free of any cold start. We deliberately don't: the Skill fetches
documentation at runtime into a Cache outside version control, and this repository redistributes
none of it. The property being protected is that **there is no embedded copy that can go stale** —
upstream republishes at least monthly, and a vendored corpus would drift silently while
continuing to look authoritative.

## Considered options

- **Vendor a snapshot.** Fastest and simplest, and rejected: a stale copy that answers
  confidently is exactly the failure this project exists to prevent, and it would put us in the
  business of redistributing someone else's documentation.
- **Vendor a curated subset.** Same staleness problem on the subset, plus a second problem —
  someone must decide and maintain what the subset is.
- **Runtime fetch into a Cache (chosen).** Accepts a network dependency and a cold start in
  exchange for content that is always attributable to a known upstream snapshot.

## Consequences

First use requires network access, and every answer must state which snapshot it came from so
staleness is visible rather than assumed. The rule extends to derived artifacts: the synonym
reference is read from the Cache rather than copied in, so it updates for free. This also
underwrites the provenance claim in the README, so weakening it is not a local change — ignore
rules enforce it rather than relying on intent.
