# ServiceNow Documentation Retrieval

The language of retrieving ServiceNow product documentation on behalf of an AI coding agent.
Two vocabularies meet here — the one ServiceNow uses for its published documentation, and the
one this project uses for the machinery that searches it — and several words collide across
that boundary. This glossary picks a winner for each.

## The upstream corpus

**Topic**:
One markdown file covering one subject. ServiceNow's own word for the unit of documentation.
_Avoid_: document, page, doc page, article

**Publication**:
A named collection of topics forming one documentation set, such as the API reference or
platform security.

**Publication index**:
A publication's table of contents, maintained upstream. Authoritative for what a publication
contains; far too large to read in full.
_Avoid_: index, TOC

**Repository index**:
The single upstream entry point listing every publication and the family-to-branch mapping.
Incomplete — some publications are absent from it.
_Avoid_: index, llms.txt as a concept

**Family**:
The versioned axis of the documentation. Each family is published as its own branch, named for
a ServiceNow release. Oldest families are eventually withdrawn upstream.
_Avoid_: release, version, branch

**Release**:
A ServiceNow product release, as run by an instance. Distinct from Family: a Family is
documentation, a Release is software. An instance runs a Release; a question is answered from a
Family.

**Out of support**:
A Family whose branch upstream no longer publishes, because ServiceNow withdrew it when a newer
release reached general availability. Reported as a fact about the Release an instance runs, and
fatal — never a reason to answer from a different Family.
_Avoid_: deleted, removed, unsupported, EOL

**Unfamilied source**:
Documentation published outside the versioned families, currently the Store content. Topics
from an unfamilied source are cited without a family and marked as unversioned.

**Canonical URL**:
The upstream-supplied link from a topic to its equivalent on the public documentation site.
Every answer carries one so a claim can be verified.

**Preferred term**:
The head-word of a synonym group in ServiceNow's synonym reference — the form the documentation
actually uses, as opposed to the abbreviation, misspelling, or regional variant a user typed.
_Avoid_: canonical term

## This project

**Skill**:
This project's deliverable: the instructions and supporting executable that an AI coding agent
loads in order to retrieve documentation. Unqualified "skill" always means this one.
_Avoid_: plugin, agent skill, tool

**Now Assist skill**:
A ServiceNow product feature, documented within the corpus this project searches. Always named
in full, never shortened to "skill", because the collision is real and appears in retrieved
content.

**Cache**:
The Skill's own local copy of one Family's documentation, together with the record of which
upstream snapshot it came from and when it was taken. Owned exclusively by the Skill.

**Family resolution**:
Deciding which Family a command works on, from the invocation, the project configuration, the
user configuration, or the newest Family as a warned-about fallback. Always reports both the
Family it chose and the source it came from.

**Pinned family**:
A Family fixed by configuration rather than named on the invocation — a commitment about which
Release an instance runs, which is why its withdrawal upstream is reported as Out of support
rather than treated as a mistyped name.

**Cone**:
Which publications a Cache currently holds. Maintainer-facing only — never appears in output a
user reads, where it is described as the publications that are cached.

**Widening**:
Extending a Cone to cover a publication the Cache does not hold, pulling only the new content
into the clone already there. Never a re-clone.
_Avoid_: expanding, growing, downloading

**Snapshot**:
Which upstream commit a Cache came from and when it was taken. What makes an answer
attributable to a point in time rather than to "the docs".

**Staleness window**:
How old a Snapshot may be before use re-fetches it — seven days, against upstream's roughly
monthly cadence. Past it a Cache is _stale_: it still answers, and its age is reported so the
caller can stamp it on the answer. Stale is a property to disclose, never a reason to refuse.
_Avoid_: expiry, TTL, cache invalidation

**Heading index**:
A derived, regenerable record of every cached topic and its headings, used to locate content
without reading a Publication index. Contrast Publication index, which is upstream data to be
re-fetched; a Heading index is ours to regenerate.
_Avoid_: index, search index

**Routing table**:
The curated mapping from a platform concept to the Publication that is authoritative for it.
Supplies the judgment a Heading index cannot: several publications may mention a concept, and
only one is authoritative.

**Correctness contract**:
One of the behavioural rules the Skill must obey — the rules that make an admitted gap
preferable to a plausible invention. Each is a Golden question in the eval suite.

**Golden question**:
A question in the eval suite paired with the topics that should have been opened to answer it.
Passing means the right topics were opened on the right Family with a Canonical URL cited, not
that the prose was good.
