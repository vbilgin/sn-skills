# The curated routing table is kept, on eval evidence, not on design intuition

The routing table (`skills/docs/routing.tsv`) was designed on the premise that several
publications can plausibly mention a concept — ACLs show up in both `platform-security` and
`application-development` — and only one is the entry point a heading-index grep alone won't
reliably surface. That premise was never tested against a real agent; it was the reason the table
was built in the first place, which makes it exactly the kind of claim its own author is
unqualified to verify (see `evals/questions.tsv`'s header on drafting golden questions).

The eval suite (#9) settles it empirically instead: five golden questions
(`routing-business-rule`, `routing-update-set`, `routing-service-portal`, `routing-notification`,
`routing-acl`) are drawn directly from the table's rows, phrased in full English with no
abbreviation, so the only way to land on the correct publication is either heading-index luck or
the table.

## Evidence

Every routing-category case's tool-call transcript, for both agents, shows `routing.tsv` read
before the agent settled on a publication — not consulted and discarded, but actually the step
that resolved the concept to a publication. Sampled by grepping each case's corpus for
`routing.tsv`:

| Case | Claude Code | Codex |
|---|---|---|
| routing-business-rule | consulted | consulted |
| routing-update-set | consulted | consulted |
| routing-service-portal | consulted | consulted |
| routing-notification | consulted | consulted |
| routing-acl | consulted | consulted |

All five pass, on two independent runs per agent (see [README's Eval
results](../../README.md#eval-results)).

## Decision

**Keep the table.** The evals it exists to justify are exactly the ones that would fail without
it, and both agents demonstrably route through it rather than around it. This decision is
reversible the same way it was reached: if a future publication restructuring or a wider eval set
shows the heading index alone resolving these concepts correctly, the table is deleted then, on
the same kind of evidence — not restored to on the strength of the design argument that motivated
it originally.

## Consequences

The table stays small and diffable by design (`bin/docs verify` catches drift against upstream
structure). Every row exists because a golden question exercises it; a row that stops being able
to point at a passing eval case is a candidate for deletion, not a row to keep for symmetry.
