# Package map

Every package that exists, its owning subsystem, and what it depends on.
`repository.toml` is the authoritative inventory and `adash_check` verifies that
it agrees with the filesystem in both directions; this document explains the
shape that inventory has.

Fifty-four packages in the shell crate, in nineteen subsystems. What makes them
readable as a whole is that the dependencies point one way: a package depends on
what is below it and never on what is above, and no two subsystems depend on
each other.

## Shell crate (`adash`)

### Foundations — no Adash package below them

| Package | Depends on outside Adash |
|---|---|
| `Adash` | — (root: no state, no behaviour) |
| `Adash.Version` | `Adash_Config` |
| `Adash.Source` | — |
| `Adash.Diagnostics` | — |
| `Adash.Errors` | — |
| `Adash.Messages` | — |
| `Adash.Messages.Rendering` | `messages`, `hostkit` |
| `Adash.Terminal` | `terminal_styles`, `hostkit` |
| `Adash.Display_Width` | — |
| `Adash.Platform` | `hostkit` |
| `Adash.Filesystem` | `hostkit` |

### The language

`Adash.Language` and ten children: `Tokens`, `Lexer`, `Syntax`, `Parser`,
`Values`, `Types`, `Symbols`, `Scopes`, `Semantics`, `Evaluation`. None of them
reaches outside Adash at all -- the language subsystem knows nothing about the
operating system, and that is deliberate: what differs because the host differs
belongs to `hostkit`, reached through `Adash.Platform`.

`Adash.Machine` is the virtual machine the evaluation lowers to. It is its own
subsystem rather than a child of the language, because what it executes is
instructions rather than syntax, and nothing above it may reach into it.

`Adash.Predefined` names what a program can call without declaring it.

### Running things

| Subsystem | Packages | Outside Adash |
|---|---|---|
| `Adash.Execution` | and `Cancellation`, `Commands`, `Environment`, `External`, `Internal_Commands`, `Jobs`, `Pipelines`, `Redirection`, `Signals`, `Streams` | `hostkit` |
| `Adash.Commands` | and `Builtins` | `hostkit` |
| `Adash.Engine` | — | `hostkit` |
| `Adash.Scripting` | and `Modules`, `Startup` | `hostkit` |

`Adash.Engine` is the one place a submission becomes a run: it holds what a
session carries from one submission to the next, and everything else in this
group is reached through it.

### The session a user sees

| Subsystem | Packages | Outside Adash |
|---|---|---|
| `Adash.Interactive` | and `Completion`, `Editing`, `Highlighting`, `History`, `Notifications`, `Prompt`, `Session` | `hostkit` |
| `Adash.Persistence` | and `History` | `hostkit`, `jsonlib` |
| `Adash.Configuration` | and `Files`, `Migration` | `tomllib` |

Each of the three consumer crates appears in exactly one place: `jsonlib` in
persistence, `tomllib` in configuration, `terminal_styles` in the terminal. A
second reader for either format anywhere else would be the defect the rule
exists to prevent.

No cycles. Dependencies point downward, and nothing in the foundations depends
on anything above it.

### Why `Adash.Messages.Rendering` is where it is

`Adash.Messages` owns the vocabulary — identifiers, keys, declared placeholder
names, structured arguments. It deliberately does not render, because a package
that both names messages and produces sentences becomes the place every
subsystem reaches for text.

`Rendering` is the presentation boundary and the only package permitted to
produce a human sentence. Everything below it reports an identifier and typed
arguments and stops. That is what makes a diagnostic assertable by identity in a
test, re-renderable for a log or a structured report, and translatable without
touching Ada.

It sits inside the Messages subsystem rather than in a family of its own because
the architecture assigns localization to the `messages` crate; what remains here
is holding a loaded catalog and performing the resolve-and-format step, which is
Messages' own work.

## Tooling crate (`adash_tests`)

```
Adash_Tests                    (root, no state, no behaviour)
 |
 +- Adash_Tests.Repository     -> Adash.Messages
 |                             -> project_tools (Files, Text, TOML)
 |
 +- Adash_Tests.Conformance    -> Adash.Engine, project_tools (TOML)
 |
 +- Adash_Tests.Suite          -> the case packages
```

Twenty-one case packages, one per subsystem they exercise: `Command`,
`Configuration`, `Conformance`, `Engine`, `Evaluation`, `Execution`,
`Filesystem`, `Interactive`, `Language`, `Lexer`, `Machine`, `Message`,
`Parser`, `Persistence`, `Predefined`, `Repository`, `Scripting`, `Semantics`,
`Source`, `Terminal`, `Version`.

Four binaries come out of this crate: `adash_tests` runs the AUnit suite,
`adash_conformance` runs the cases in `conformance/cases/`, `adash_check` runs
the repository checks, and `adash_bench` measures. Two more, `adash_test_emit`
and `adash_test_upcase`, exist to be *run by* tests that need a child process
with known behaviour.

Mains are thin and hold no logic: `adash_tests_main` runs the suite,
`adash_check_main` renders what `Adash_Tests.Repository` found. The checks live
in a package precisely so that `Adash_Tests.Repository_Cases` can run the same
code — a checker reachable only from a main is a checker that is never itself
tested.

Nothing in this crate is reachable from the `adash` binary. AUnit and
`project_tools` are development dependencies and must never become dependencies
of the thing users install.


## What the inventory is for

`repository.toml` lists every package and its owner; `adash_check` fails if a
source file exists that the inventory does not name, or the reverse. That is
what keeps this document honest about *what exists*. What it cannot check is the
prose here, so the prose says as little as it can get away with and points at
the inventory for the rest.
