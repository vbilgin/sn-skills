# Family is pinned in the repository, and its withdrawal is fatal

The Family a question is answered from is resolved, highest wins, from: an explicit argument on
the invocation, a `.docs` file at or above the working directory, the user configuration at
`$XDG_CONFIG_HOME/docs/config`, and finally the newest Family with a warning that nothing was
configured. The project file is the documented default. When the resolved Family's branch is no
longer published upstream, the command stops and reports the Release as **out of support**,
exiting non-zero.

The property being protected is that **nobody has to remember which Family they are on, and
nobody is ever silently moved off it**. Most ServiceNow customers do not run the newest release,
so answering a Zurich question from Australia documentation is the single most likely way this
Skill produces confident, wrong, unfalsifiable output.

## Considered options

- **Ask, or require the Family on every invocation.** Correct and unusable: an agent invoking
  the Skill dozens of times per session either asks dozens of times or guesses, and a guess here
  is the failure this exists to prevent.
- **Machine-level configuration only.** Wrong unit. Family is a property of the codebase, not of
  the machine — a consultant with four client repositories on one laptop has four Families, and
  a machine-level pin would be wrong for three of them at any moment.
- **Project file, with a machine-level default under it (chosen).** An update-set repository for
  a Zurich client is Zurich permanently. Committing that fact means teammates and agents inherit
  it without being told, and changing directory between client repositories changes the
  documentation set with no other action.

On a withdrawn Family:

- **Fall back to the newest Family.** Rejected outright. It converts an answerable question
  ("your release's documentation is gone") into a plausible answer from the wrong Release —
  the exact shape of failure the Correctness contracts exist to forbid.
- **Warn and continue.** A warning on stderr that a Family is out of support, followed by an
  answer, is a warning that will be summarized away by whatever reads it.
- **Stop and report (chosen).** Out of support is actionable information about the instance,
  not an error to swallow.

## Consequences

Resolution is offline and needs no Cache, so `bin/docs family` answers "which Family am I about to
get" without touching the network or changing any state. Every command reports the Family it
resolved and where that came from, and `status` carries both as fields.

The newest Family is compiled in and will drift when a release reaches general availability;
that drift is the price of not making resolution depend on the network, and it is only ever
consulted on the warned-about fallback path.

A Family upstream does not publish is described by how it was chosen. A pinned Family, or the
compiled-in fallback, is reported as out of support: it was chosen because an instance runs that
Release. A Family named on the command line and published nowhere is reported as not published,
because telling someone to check whether their instance is supported when they misspelled a
branch name would be its own confidently-wrong answer. A Cache that already exists settles the
question — the Family was published once, so its absence is a withdrawal.

An unreachable upstream is never reported as out of support. Offline is a degraded mode in which
a Cache still answers with its age disclosed; withdrawal is a fact about the Release.
