# Documentation

Reference documentation for Adash. The documents that describe decisions
already made live in the repository root; the ones below describe subsystems.

The rule that produced this index was that writing a reference for an
unimplemented subsystem produces a document that is wrong the moment the
subsystem is built, and that readers then disbelieve for the rest of the
project's life -- so each was to arrive with the phase that implemented the
thing it documents.

**All sixteen phases are complete.** The table below is therefore a list of
what is *owed* rather than what is scheduled, and the phase column says when
the subject existed rather than when the document will. What is written is
listed under "Available now"; everything else in the table is outstanding, and
the code it would describe is in the tree today.

Four remain. `ai-package-map.md` is not among them: `AI.md` names the
authoritative documents in order and `package-map.md` carries the map, so a
third copy for assistants would be the drift this project keeps finding.
 Three of them — the user, interactive and scripting guides — are
about what a person *does* with the shell rather than what it is, and the
interactive half of that cannot be checked by running a script: editing keys,
completion and the prompt need a terminal. They are owed, and they will be
written from a session rather than from the sources. `grammar-reference.md` is
owed too, and is the one document here that should be *derived* from the parser
rather than written beside it.

| Document | Describes | Subject existed since phase |
|---|---|---|
| `user-guide.md` | Using the shell | 14 |
| `interactive-guide.md` | Prompt, editing, completion, history, jobs | 14 |
| `scripting-guide.md` | Writing and running scripts | 13 |
| `grammar-reference.md` | The grammar, formally | 5 |

Documents marked *continuous* are generated or maintained as the code changes
rather than arriving in one phase. Generated documentation goes under
`generated/` and is never authoritative — the schema, the inventory and the
source it is derived from are.

## Available now

- [`language-reference.md`](language-reference.md) — what is in the Ada subset,
  what each construct means here, and where the subset ends.
- [`internal-commands.md`](internal-commands.md) — every internal command, what
  it takes, what it does and what it reports.
- [`predefined-functions.md`](predefined-functions.md) — the twenty-eight names
  a program has before it declares anything.
- [`execution-model.md`](execution-model.md) — what runs a program, what a
  pipeline is, where redirection happens, what a status means.
- [`job-control.md`](job-control.md) — jobs, what each command reports, and
  where a host cannot answer.
- [`configuration-reference.md`](configuration-reference.md) — the eight
  settings, their ranges, and the file they are written to.
- [`conformance-guide.md`](conformance-guide.md) — how a case is written and
  what makes one deterministic.
- [`persistence-formats.md`](persistence-formats.md) — the two files a session
  keeps, and how both are written.
- [`diagnostics-catalog.md`](diagnostics-catalog.md) — every message this build
  can produce, by identifier.
- [`RELEASE.md`](RELEASE.md) — the release gates, in order, and what each is
  for. This is the document the table called `release-guide.md`.
- [`package-map.md`](package-map.md) — every package that exists, its
  subsystem, and which crate it reaches outside Adash for.
- [`test-guide.md`](test-guide.md) — how to run and extend the suites.
- [`benchmark-guide.md`](benchmark-guide.md) — what `adash_bench` measures,
  what its numbers are and are not, and what to make of one that moves.
- [`hac-assessment.md`](hac-assessment.md) — what the HAC dependency gave the
  language subsystem while it lasted, why it ended, and what replaced it.
- [`command-calls.md`](command-calls.md) — history: the spike that found there
  were two gaps between commands and the language, not one, and that a single
  mechanism had to close both. The reasoning still holds; the p-code it
  describes is HAC's, not `Adash.Machine`'s.

Everything else in the table above is outstanding. `ROADMAP.md` and
`CHANGELOG.md` are what a reader has instead: between them they say what the
language and the shell do, in the order it arrived. That is not a substitute
for a reference -- a reference answers "what does this do", where those two
answer "what happened" -- and the gap is stated here rather than left for a
reader to discover.
