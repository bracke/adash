# Instructions for coding assistants

This file is deterministic on purpose. It names packages, invariants and
procedures rather than giving advice. If something here is ambiguous, that is a
defect in this file — fix it here rather than deciding case by case.

## Authoritative specifications

In this order. A later one never overrides an earlier one:

1. `ARCHITECTURE.md` — subsystem boundaries, ownership, dependency direction.
2. `repository.toml` — the package inventory: what exists and who owns it.
3. `ROADMAP.md` — what is implemented and what is not.
4. `STYLE_GUIDE.md` — how the Ada is written.
5. This file — how to carry out the common changes.

Do not infer the architecture from the code. The code is checked against these
documents, not the other way round.

## The rules that are not negotiable

Each names one place a capability lives. A second, subtly different copy inside
Adash is the failure mode all of them exist to prevent.

- **hostkit only** for anything that differs because the operating system
  differs: process creation, waiting, status, executable lookup, pipes, stream
  duplication, redirection primitives, signals, process groups, terminal
  handling, pseudo-terminals, polling, filesystem integration, working
  directory, environment access for child processes, path discovery, user and
  home directories, platform paths, file locking, atomic replacement, platform
  error translation.
  Never `GNAT.OS_Lib`, `Interfaces.C`, `System.OS_Interface`, POSIX bindings,
  Win32 bindings or syscalls. Adash has no `src/platform/` directory and must
  never acquire one.
- **jsonlib only** for JSON. **tomllib only** for TOML. Never a parser or
  serializer inside Adash.
- **messages only** for user-visible text. No Ada source may contain a string a
  user reads — including help, usage, prompts, warnings, errors, status,
  confirmations, completion descriptions, and the output of release and test
  tools.
- **terminal_styles only** for styling, reached through `Adash.Terminal`. Never
  an escape sequence in Adash source.
- **project_tools only**, in Ada, for repository tooling. No shell scripts, no
  Make, no Python, no Node.
- **Adash owns its language.** The lexer, the parser, the syntax tree, the
  analyser, the lowering and the virtual machine are all Adash's, and that is
  the one place the "never a second copy" rule does not send you to another
  crate: no dependency provides them. `Adash.Machine` is the machine — do not
  add a second interpreter beside it, and do not lower to anything else.

`adash_check` enforces the mechanically checkable subset. Run it.

### When a dependency lacks something

1. Identify the missing capability precisely.
2. Confirm it belongs to that dependency — for hostkit the test is "does this
   differ *because the host differs*?"
3. Implement or specify it there.
4. Consume it through the approved adapter.
5. Do **not** add a duplicate implementation inside Adash, not even temporarily.

No gaps are open. `jsonlib`, `tomllib` and `hostkit` are sibling crates that
carry everything Adash asks of them; `ROADMAP.md` records what each gave. When
a new gap opens, the dependent work does not start until it is closed *there* —
it is not unblocked by writing the capability here.

`hostkit` provides the platform side in full: `Hostkit.Descriptors`,
`Hostkit.Signals`, `Hostkit.Spawn`, `Hostkit.Terminal_Control`, `Hostkit.Pty`
and `Hostkit.Locks`. Three things to know when using them.

- Use `Hostkit.Spawn`, never `Hostkit.Process.Launch`. Launch reaps finished
  children indiscriminately and will steal a status `Hostkit.Spawn.Wait` was
  waiting for.
- Ignore `Signal_Background_Write` (SIGTTOU) around
  `Hostkit.Terminal_Control.Set_Foreground_Group`, or the shell stops itself
  when it reclaims the terminal after a job. The disposition is process-wide
  and hostkit deliberately does not set it for you.
- Check `Is_Supported` before building on signals, process groups or
  pseudo-terminals. All three are refused on Windows, and a refusal is an
  answer to act on — never store it as "not needed here".

## Public versus internal

- Public: everything listed in `repository.toml` without an `Internal` segment.
- Internal: `Adash.<Subsystem>.Internal.*`. These are private to their
  subsystem. A `with` of another subsystem's `Internal` package is a defect even
  though it compiles.
- Dependencies point downward through the layers in `ARCHITECTURE.md`. Never
  upward. Never cyclic.

## Implementation order

Follow `ROADMAP.md`. Do not create placeholder APIs for a later phase unless a
completed lower layer needs them to compile. Do not implement a phase out of
order because it is easier.

Every commit leaves the repository buildable, `./bin/adash_tests` green and
`./bin/adash_check` passing.

## How to add a message

1. Add a literal to `Adash.Messages.Message_Id`.
2. Give it a key in `Adash.Messages.Key`. The case statement has no `others`, so
   this step cannot be skipped.
3. Declare its placeholders in `Adash.Messages.Placeholders`, even when the
   answer is `No_Placeholders`. Also no `others`.
4. Add the key to `resources/messages/catalog.txt` for the default locale.
5. Run the suite. `Every_Identifier_Renders` renders every message with its own
   declared placeholders and fails if the entry is missing, malformed, or does
   not substitute what it declares.

Keys are stable across releases. Renaming one is a breaking change even when the
English text is untouched. Avoid apostrophes in message text — ICU treats them
as escapes, and a doubled apostrophe is invisible to review and renders wrongly
exactly once, in the released build.

## How to add a package

1. Decide the owning subsystem. If none fits, the architecture needs revising
   first — say so rather than inventing a family.
2. Create spec and body under `src/library/`, named `adash-<subsystem>-<name>`.
3. Give every public declaration GNATdoc, including `@param` and `@return`.
4. Add an entry to `repository.toml` with name, subsystem, visibility, spec,
   body, status and summary. `adash_check` fails if you do not.
5. Add an AUnit case under `adash_tests/tests/` and register it in
   `Adash_Tests.Suite`.

## How to add an internal command

Register it with `Adash.Commands`, give it structured metadata and a
documentation key, put every string it emits in the catalog, add conformance
cases for its observable behaviour, and document it in
`docs/internal-commands.md`. A command is callable from a program like any
other entity, so its arguments are evaluated by the machine and its count is
checked against its own registry entry.

## How to add a predefined function

Register it in `Adash.Predefined` with complete metadata — stable identifier,
name, signature, parameters, result type, side effects, exceptions,
availability, documentation key, completion description key. Registration order
must not affect behaviour. Where the machine can answer it from values it
already holds, emit an instruction rather than a call out to the shell.

## How to add a language construct

It touches these, in this order: the lexer (`Language.Lexer`) if it needs a
token, the syntax model (`Language.Syntax`) for the node kind, the parser
(`Language.Parser`), semantic analysis (`Language.Semantics`), and the lowering
(`Language.Evaluation`) — plus conformance cases, the grammar reference, and
whichever of `ROADMAP.md` and `docs/language-reference.md` describes the
boundary it moves. It never touches only one of them.

`adash_check` holds `docs/grammar-reference.md` to `Language.Syntax`'s
enumeration in *both* directions, so a node kind the parser can build without a
production named for it fails the checks.

## How to add a persistence field or change configuration

Bump the schema version, add a migration, add defaults, add validation, decide
the unknown-key policy, keep the write atomic, and add a conformance case for
the migration. TOML goes through tomllib and JSON through jsonlib; neither
format is ever parsed or written by hand here.

## How to add a conformance case

Give it a stable case identifier, requirement references, input, environment,
expected output, expected diagnostics, expected exit status, applicable
platforms and required capabilities. A conformance case is
implementation-independent: it describes observable behaviour, never internals.

## Common mistakes

- Writing a string a user will read into an Ada source file.
- Reaching for `GNAT.OS_Lib` because hostkit does not have the call yet. Extend
  hostkit.
- Adding a second parser, evaluator or engine "just for the interactive case".
- Adding POSIX shell syntax because another shell has it. Adash's command
  language is Ada; a feature is expressed through that language or not at all.
- Putting a check in a main instead of in a package, which makes it unreachable
  from a test.
- Using an exception for an expected operational failure.
- Adding a package without a `repository.toml` entry.
- Marking something complete without tests, GNATdoc and documentation.

## Prohibited shortcuts

- Stubbing a public API to make a later phase's code compile.
- Silently narrowing scope and reporting completion.
- Disabling a check, a warning or a test to get a green run.
- Introducing a plugin architecture, a second command language, a compatibility
  layer or a platform abstraction that is not required here.
- Committing generated artifacts as though they were authoritative.

## Testing expectations

Tests must not depend on execution order, filesystem enumeration order, the
locale unless it is under test, the wall clock without a controlled clock,
random values without a fixed seed, or developer-specific paths.

Use hostkit's fakes and test adapters where they exist. Do not bypass hostkit in
a test to make it simpler — a test that takes a different route through the
platform than the shell does is testing something else.

Every confirmed defect gains a permanent regression test.

## Terminal control belongs to hostkit, not to terminal_styles

`terminal_styles` owns styling: what a role looks like. It does not own cursor
movement or erasing, and it should not — those are terminal control, which is
platform behaviour, and platform behaviour is hostkit's by rule. A line editor
that reached for ANSI sequences directly, or that grew a "just a couple of
escapes" helper beside the styling calls, would be the first crack in the rule
that no Adash source contains an escape sequence.

`Hostkit.Terminal_Control.Control` takes an action — erase, move, hide, show —
and never a byte string, so a caller cannot hold a sequence even by accident.
Windows needs the console told to interpret them first; that is inside the
Windows body, where it belongs, and `Supports_Cursor_Control` answers honestly
when the console refuses.
