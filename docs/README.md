# Documentation

Reference documentation for Adash. The documents that describe decisions
already made live in the repository root; the ones below describe subsystems.

The rule that produced this index was that writing a reference for an
unimplemented subsystem produces a document that is wrong the moment the
subsystem is built, and that readers then disbelieve for the rest of the
project's life -- so each was to arrive with the phase that implemented the
thing it documents.

**All sixteen phases are complete, and so is this index.** Everything it once
listed as owed is written. Two entries turned out not to be owed at all:
`release-guide.md` is `RELEASE.md` under another name, and `ai-package-map.md`
would be a third copy of what `AI.md` and `package-map.md` already carry -- the
kind of duplication this project keeps finding as drift.

What kept the last three waiting was that the user, interactive and scripting
guides are about what a person *does* with the shell, and the interactive half
cannot be checked by running a script. They were written from a session
instead: a pseudo-terminal, the real binary, and every claim typed at it.

## Available now

- [`user-guide.md`](user-guide.md) — starting here: what a submission is, how
  a command is called, and what a session remembers.
- [`interactive-guide.md`](interactive-guide.md) — the prompt, editing,
  completion, history, and the interrupt.
- [`scripting-guide.md`](scripting-guide.md) — writing scripts, their arguments
  and input, and splitting them up.
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
- [`grammar-reference.md`](grammar-reference.md) — what the parser accepts, as
  productions, each naming the node it builds. `adash_check` holds it to the
  syntax enumeration in both directions.
- [`RELEASE.md`](RELEASE.md) — the release gates, in order, and what each is
  for. This is the document the table called `release-guide.md`.
- [`package-map.md`](package-map.md) — every package that exists, its
  subsystem, and which crate it reaches outside Adash for.
- [`test-guide.md`](test-guide.md) — how to run and extend the suites.
- [`benchmark-guide.md`](benchmark-guide.md) — what `adash_bench` measures,
  what its numbers are and are not, and what to make of one that moves.

Everything else in the table above is outstanding. `ROADMAP.md` and
`CHANGELOG.md` are what a reader has instead: between them they say what the
language and the shell do, in the order it arrived. That is not a substitute
for a reference -- a reference answers "what does this do", where those two
answer "what happened" -- and the gap is stated here rather than left for a
reader to discover.
