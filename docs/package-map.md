# Package map

Every package that exists today, its owning subsystem, and what it depends on.
`repository.toml` is the authoritative inventory; this document explains it.
`adash_check` verifies that the two agree with the filesystem in both
directions.

## Shell crate (`adash`)

```
Adash                          (root, no state, no behaviour)
 |
 +- Adash.Version              -> Adash_Config
 |
 +- Adash.Messages             -> Ada.Strings.Unbounded
 |   |
 |   +- Adash.Messages.Rendering
 |                             -> messages (Runtime, Arguments, Result)
 |                             -> hostkit (Fs, Host)
 |                             -> Ada.Environment_Variables
 |
 +- Adash.Terminal             -> terminal_styles
                               -> hostkit (Host)
```

| Package | Subsystem | Depends on | Depended on by |
|---|---|---|---|
| `Adash` | root | — | everything |
| `Adash.Version` | root | `Adash_Config` | the main |
| `Adash.Messages` | messages | — | `Rendering`, the main, tooling |
| `Adash.Messages.Rendering` | messages | `messages`, `hostkit` | the main, tooling |
| `Adash.Terminal` | terminal | `terminal_styles`, `hostkit` | the main, tooling |

No cycles. Dependencies point downward: `Rendering` depends on its parent
`Messages`, never the reverse; nothing in the foundations depends on the main.

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
 +- Adash_Tests.Suite          -> the cases below
     +- Adash_Tests.Version_Cases      -> Adash.Version
     +- Adash_Tests.Message_Cases      -> Adash.Messages(.Rendering)
     +- Adash_Tests.Terminal_Cases     -> Adash.Terminal
     +- Adash_Tests.Repository_Cases   -> Adash_Tests.Repository
```

Mains are thin and hold no logic: `adash_tests_main` runs the suite,
`adash_check_main` renders what `Adash_Tests.Repository` found. The checks live
in a package precisely so that `Adash_Tests.Repository_Cases` can run the same
code — a checker reachable only from a main is a checker that is never itself
tested.

Nothing in this crate is reachable from the `adash` binary. AUnit and
`project_tools` are development dependencies and must never become dependencies
of the thing users install.

## Packages that do not exist yet

`ARCHITECTURE.md` lists the full intended hierarchy — `Adash.Source`,
`Adash.Diagnostics`, `Adash.Errors`, the `Adash.Language.*` family,
`Adash.Engine`, `Adash.Execution.*`, `Adash.Commands.*`, `Adash.Predefined.*`,
`Adash.Interactive.*`, `Adash.Scripting.*`, `Adash.Persistence.*`,
`Adash.Configuration` and `Adash.Platform`. None of them exists yet, and none is
stubbed. `ROADMAP.md` gives the order.
