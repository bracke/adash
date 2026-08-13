# Architecture

This document is authoritative for subsystem boundaries, package ownership and
dependency direction. Where it and the code disagree, one of them is a defect;
`adash_check` exists to make some of those disagreements fail a build rather
than survive a review.

## The two rules everything else follows from

**One language pipeline.** Interactive input, script files, startup files,
command substitutions and prompt expressions all pass through the same lexer,
parser, semantic analyser and evaluator. There is no second implementation for
any of them. A shell that has two eventually has two dialects, and the
difference between them is discovered by users rather than by tests.

**One engine.** `Adash.Engine` is the single runtime coordinator. The
interactive frontend, script execution, startup processing and the test suite
all drive it; none of them reimplements what it does. A frontend that grows
execution behaviour of its own is a second engine.

## Layers

Dependencies point downward. A package may depend on the layers below it and on
its own subsystem's internals. It may never depend upward, and never on another
subsystem's `Internal` packages.

```
        Interactive          Scripting            (frontends)
                 \             /
                  \           /
                   +---------+
                   |  Engine |                    (coordination)
                   +---------+
                   /         \
          Execution           Language             (subsystems)
          Commands            Predefined
                   \         /
                    \       /
              Configuration    Platform  Terminal  Messages
                    |
              Persistence
                          |
              Diagnostics  Errors  Source  Version   (foundations)
                          |
      hostkit   messages   terminal_styles   jsonlib   tomllib
```

The foundations know nothing about the shell. `Adash.Source`,
`Adash.Diagnostics` and `Adash.Errors` are usable by every layer above and
depend on none of them.

## Subsystems and their owners

Every package has exactly one owning subsystem. `repository.toml` records the
mapping and `adash_check` verifies that it still describes the packages that
exist — a package added without an entry has no recorded owner, and ownership is
what this architecture is made of.

| Subsystem | Root package | Owns |
|---|---|---|
| Root | `Adash` | Project identity, version and build identity |
| Diagnostics | `Adash.Diagnostics` | Structured diagnostics, severities, stable identifiers, source spans |
| Source | `Adash.Source` | Source identities, buffers, positions, spans, line maps |
| Language | `Adash.Language` | Lexer, parser, syntax, semantics, values, types, evaluation, functions, modules |
| Predefined | `Adash.Predefined` | Predefined functions, procedures, constructors and their metadata |
| Engine | `Adash.Engine` | Orchestration of source processing, execution, cancellation, results |
| Execution | `Adash.Execution` | Commands, pipelines, redirection, streams, jobs, signals, exit status |
| Commands | `Adash.Commands` | Internal command registry, metadata, invocation |
| Interactive | `Adash.Interactive` | Prompt, editing, history, completion, highlighting, notifications, and the loop |
| Scripting | `Adash.Scripting` | Script loading, startup files, module resolution |
| Persistence | `Adash.Persistence` | Settings, history, sessions, aliases, caches |
| Configuration | `Adash.Configuration` | Schema, defaults, validation, migration |
| Platform | `Adash.Platform` | The adapter and policy layer over hostkit |
| Messages | `Adash.Messages` | Message identifiers, arguments, the presentation boundary |
| Terminal | `Adash.Terminal` | Style roles and colour policy over terminal_styles |

Implementation packages live under `Adash.<Subsystem>.Internal.*`. They are not
cross-subsystem APIs; a `with` of another subsystem's `Internal` is a defect
regardless of whether it compiles.

## What Adash does not own

Five capabilities belong to other crates, and Adash may not reimplement any of
them:

- **Platform behaviour** — `hostkit`. Anything that exists only because operating
  systems differ, and that therefore needs a body per host: process creation,
  pipes, descriptor wiring, process groups, signals, terminals, pseudo-terminals,
  polling, filesystem integration, file locking, atomic replacement. Adash has no
  per-host source directories, and the appearance of one means this rule has been
  broken. `Adash.Platform` is a portable adapter *over* hostkit, not a second
  implementation beneath it.
- **User-visible text** — message catalogs. No Ada source may contain a string a
  user reads. Subsystems exchange stable identifiers and structured arguments;
  text is produced at presentation boundaries and nowhere else.
- **Terminal styling** — `terminal_styles`. Adash never writes an escape
  sequence. It owns the vocabulary of roles; `terminal_styles` owns the bytes.
- **JSON** — `jsonlib`. **TOML** — `tomllib`.
- **The virtual machine** — `Adash.Machine`, this repository's own. A stack
  machine with frames, static links and one call out to the shell. It replaced
  `hac`; `docs/hac-assessment.md` records what that dependency gave, what it
  cost, and why it ended.

When one of those lacks something Adash needs, the capability is added there and
consumed through the approved adapter. It is never duplicated here.

## Errors

Operational failures are structured results, not exceptions. Parsing failure,
semantic failure, command lookup failure, process startup failure, redirection
failure, persistence failure, configuration failure, an unsupported platform
capability and cancellation are all expected outcomes of asking, and a caller
has to be able to handle them without an exception handler.

Exceptions are for violated contracts, impossible internal states and broken
invariants — that is, for defects. They are never swallowed silently.

Lower-layer errors are translated once, at a subsystem boundary, preserving the
original structured information where it is useful.

## Diagnostics are presentation-independent

A diagnostic carries a stable identifier, a severity, a category, a source span,
structured arguments, optional related spans and its owning subsystem. It does
not carry a sentence.

Text appears at the presentation boundary, in three steps: resolve the
identifier through the catalog, format the structured arguments, apply style
roles if styling is enabled. With styling off, the output must remain
semantically complete — a message that distinguishes an error from a warning
only by colour is a defect.

This is what lets the same diagnostic be rendered for a terminal, a log and a
structured report, and asserted on by identity in a conformance case, without
any of them parsing another's output.

## Concurrency

Native Ada tasking and protected objects. No external thread runtimes.

Every piece of shared mutable state has one documented synchronization owner.
Asynchronous work uses bounded queues and explicit cancellation. Worker tasks do
not mutate interactive presentation state directly; they publish structured
events to the frontend, which owns the screen.

## Decisions recorded here

Where this prompt's requirements were open to more than one reading, the
interpretation that preserved an architectural boundary was chosen, and the
decision is recorded rather than left implicit.

- **`Adash.Messages.Rendering`** is a child of the Messages subsystem rather than
  a new top-level package. The architecture gives `Adash.Messages` the
  identifiers and leaves localization to the `messages` crate; something still
  has to hold the loaded catalog and perform the resolve-and-format step at the
  edge. Making it a child keeps that inside the owning subsystem instead of
  inventing a family for it. It also carries a key-addressed `Text` overload so
  the tooling crate can render its own messages through the same boundary
  without adding tooling identifiers to the shipped `Message_Id`.

- **Environment variables are read with `Ada.Environment_Variables`**, not
  through hostkit. Hostkit's charter is "does this differ *because the host
  differs*?"; reading an environment variable does not. The host's *locale* and
  the executable's own directory do, and both are asked of hostkit.

- **Message placeholder names are declared in Ada**
  (`Adash.Messages.Placeholders`) as well as used in the catalog. The catalog
  cannot enforce that a caller passes `path` where the message says `path`, and
  the compiler cannot see it; declaring the names lets the suite render every
  message with its own placeholders and catch the drift at build time rather
  than at run time in an error path.

- **`Adash.Language.Symbols` and `Adash.Language.Scopes`** are packages the
  package list does not name. Phase 3 calls for symbols and scopes as core
  models, and Phase 6 gives `Adash.Language.Semantics` the *algorithms* that
  build and query them. Splitting the container from the analysis keeps both the
  semantic pass and the evaluator reading one structure; folding them into
  `Semantics` would make the evaluator depend on the pass that produced its
  input rather than on the input itself.

- **The Adash type set is Ada's, and small**: Boolean, Integer, Float,
  Character, String, plus `Type_None` for what a procedure yields. There is no
  untyped scalar and no implicit conversion, including the numeric ones Ada
  itself allows — a language that quietly widens an Integer has a rounding rule
  nobody wrote down. Composite types are absent rather than stubbed: `Type_Kind`
  has no placeholder literals, so adding one is a source change that fails to
  compile at every point which must consider it. Nothing shell-specific is a
  language type; exit statuses and paths belong to `Adash.Execution`, which is a
  sibling subsystem, and a type descriptor that knew about them would invert the
  dependency.

- **A value's `Image` is not a catalog message.** It is the language's own
  lexical form: a script that prints a Boolean and tests for `True` must not
  break because the shell was started in another locale. Prose about a value
  still goes through `messages`; the value's own text does not.

- **Adash owns the language, end to end.** The lexer, parser,
  `Language.Syntax`, semantic analysis, the lowering, and the machine it lowers
  to are all this repository's.

  It was not always so. HAC ran the p-code until the front end had grown to
  9,400 lines -- rivalling the 11,400-line compiler it existed to replace -- in
  order to reach a 4,000-line interpreter. Worse, it reached that interpreter by
  building HAC's own compiler tables: identifier entries, block entries,
  activation records of a fixed shape, a display vector to keep in step. That
  seam produced defects rather than preventing them -- a display vector not
  restored after a call, frame slots taken from whichever frame happened to be
  emitting, argument cells given the wrong type.

  The machine's instruction set is what the lowering emits and nothing else.
  Ada's semantics are kept where they were load-bearing: `Real` is `digits
  System.Max_Digits` and the whole number is 64-bit, so `'Image` and
  `Integer'Last` mean what they always meant here.

## Invariants

These hold at every commit, not only at a release:

- One Alire binary crate, one child `adash_tests` crate. Runtime code is Ada 2022.
- Package dependencies are acyclic and point downward.
- Every package has one subsystem owner, recorded in `repository.toml`.
- Internal packages are not cross-subsystem APIs.
- Interactive and scripting modes share one language implementation and one engine.
- Operational errors are structured; diagnostics are presentation-independent.
- No hard-coded user-facing strings; no direct terminal escape sequences.
- No direct operating-system layer inside Adash; no non-Ada repository tooling.
- Every public API is documented and tested; every observable feature has
  conformance coverage; every confirmed defect gains a permanent regression test.
- Generated artifacts are reproducible and never authoritative.
