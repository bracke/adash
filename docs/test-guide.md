# Test guide

## Running

```
cd adash_tests
alr build
./bin/adash_tests        # AUnit suite
./bin/adash_conformance  # the cases in conformance/cases/, against the binary
./bin/adash_check        # repository invariants
./bin/adash_bench        # what things cost
```

Each exits non-zero on failure. A change is not finished until all four are
green and both crates build without a style warning.

`alr test` from the repository root runs **only** the AUnit suite -- that is
what the manifest's test action does -- so it is not the same as the four above.
The conformance suite runs the built `adash` binary against recorded cases, and
a manifest action that built the shell to test the shell would be a different
kind of thing; it is run by hand and by CI instead.

Run them from `adash_tests/`. The suite reads the repository catalog and the
repository root by relative path — `../resources/messages/catalog.txt` and `..`
— because an absolute path in a test is a test that passes only on the machine
it was written on.

## How the suites are organised

| | |
|---|---|
| `adash_tests/src/` | reusable tooling packages, and the thin mains that drive them |
| `adash_tests/tests/` | AUnit cases, one package per unit or coherent behaviour |
| `adash_tests/fixtures/` | test data, including deliberately broken trees |

A check worth running is worth being callable from a test. Logic goes in a
package under `src/`, and both a main and an AUnit case reach it. `adash_check`
and `Adash_Tests.Repository_Cases` run the same code rather than two copies that
drift apart.

## Adding a case

1. Create `adash_tests/tests/adash_tests-<name>_cases.ads/.adb`, deriving
   `Case_Type` from `AUnit.Test_Cases.Test_Case` and overriding `Name` and
   `Register_Tests`.
2. Register it in `Adash_Tests.Suite`, in dependency order — lowest layer first,
   so a failure list read top-down tells you which layer broke rather than only
   that something did.
3. Name each routine as a statement about the code: `"Color_Never emits no
   escapes"`, not `"test_3"`.
4. Assert with the offending value in the message. `Assert (X = Y, "mismatch")`
   sends the reader back to the debugger; naming the value saves the trip.

## Determinism

A test may not depend on execution order, filesystem enumeration order, the
locale unless the locale is what is under test, the wall clock without a
controlled clock, random values without a fixed seed, or developer-specific
paths.

The catalog tests pin `Requested_Locale => "en"` for exactly this reason.
Without it they read the developer's `LANG` and fail for whoever has it set to
something the catalog does not carry — which looks like flakiness and is not.

Use hostkit's fakes and test adapters where they exist. Do not bypass hostkit to
make a test simpler: a test that takes a different route through the platform
than the shell does is testing something else.

## Tests that would fail if the code did nothing

Every suite carries at least one. A test that passes vacuously is worse than no
test, because it is believed.

The examples in place today:

- `Adash.Terminal : Color_Always decorates every other role` — the complement of
  the three tests asserting that styling is *absent*. Without it, a `Styled` that
  returned its input unchanged in every case would pass all of them.
- `Adash_Tests.Repository : a root that is not a repository fails` — runs the
  checks against `fixtures/not-a-repository` and requires specific findings.
  Without it, a checker that reported success unconditionally would look correct.
- `Adash_Tests.Repository : the checks actually ran` — asserts a lower bound on
  the number of checks executed, so a checker that silently found no files to
  look at cannot report a clean repository.

## What the four tools cover

`adash_tests` covers behaviour, one case package per subsystem: the source
model and diagnostics, every stage of the language -- lexer, parser, semantics,
evaluation -- the machine, execution and commands, the engine, the interactive
session, persistence, configuration, predefined entities, messages and styling,
and the repository checks themselves.

Six of those cases drive the shell **through a terminal**: a whole
session, Tab completing a word, Up recalling a line, Up *not* recalling a line
that was typed with a space in front of it, backspace removing a character
rather than a byte, and a Ctrl-C stopping a loop. The shell is
started in a session of its own with that terminal as its controlling one --
`Hostkit.Spawn.Options.Controlling_Terminal` -- which is what makes a keystroke
into a signal; without it a child controls nothing and Ctrl-C reaches nobody.

**An assertion about a terminal asks about the text, not the bytes.** What
comes back is text and control mixed, and the two are interleaved: the prompt
writes its failure marker and then an escape sequence, so `!` and the space
after it are not next to each other. Looking for them together reported a
working interrupt as a broken one for half a day. Everything else about the interactive session
tests a piece -- the buffer, the decoder, the history, the completion registry
-- and a piece can be right while what a user meets is not. Each opens a
terminal, spawns the built binary on it, types, and reads bounded: a test that
reads until end of file from a shell waiting for input is a test that hangs,
and a hang in CI is a job that reports nothing. They run on all three hosts:
`Hostkit.Pty` answers Windows with the pseudo-console, and `Hostkit.Pty.Attach`
is what hands a child either a device as its three streams or a console through
a process-thread attribute, so the harness is one program rather than two.

`adash_conformance` covers the language and the shell *as a user meets them*:
each case is a submission and what it must print, exit with, and report. It
compares message **identifiers** rather than English, so a case says which
diagnostic was produced and not how it happened to be worded. The examples in
`examples/` are cases too, each against its recorded output.

`adash_check` covers structure, including one document: the grammar reference
is held to `Adash.Language.Syntax`'s own enumeration in both directions, so a
construct the parser gains without a production fails the checks. It also
covers: required files and directories, version
agreement between `alire.toml` and `repository.toml`, the package inventory in
both directions, catalog completeness for every message identifier, absence of
hand-written terminal escapes, and absence of direct operating-system
dependencies in shell source.

CI runs all four on **three hosts** -- ubuntu, macos-15-intel and
windows-latest -- because Adash depends on hostkit, whose reason to exist is
that operating systems differ. A change validated on one host has not been
validated. **A case that needs a program names a companion**, `{emit}` or
`{upcase}`, rather than a POSIX utility -- so capture, redirection and pipelines
are checked on all three hosts rather than two.

Four cases are gated to `["linux", "macos"]` and two to `["windows"]`, and
together they cover job control on every host. Windows has no process groups, so
a job is not a thing that can be signalled as one: `stop`, `suspend` and
`resume` each report that the system does not support job control and the job
runs to completion, and a job is still listed as running while it does. The
other four assert the half that needs signals to exist. A capability the host
lacks is what the key is for; a program it is missing is what the companions
removed.

**What is asserted *because* a host is Windows.** A gate keeps a case off a host
that cannot hold it; the harder question is what nobody is checking there at
all. So: a script whose every line ends CR LF runs, and a diagnostic about one
gives the right line and column and quotes the line without the carriage return
that ended it — the fixtures are pinned to CR LF in `.gitattributes`, which
holds the rest of the repository to LF, so all three hosts assert it. A
backslash in an ordinary string is a backslash, which is how a Windows path is
written, and needs doubling only in an interpolated string. The shell runs the
shell through `{shell}`, which carries whatever suffix the host puts on an
executable. And where hostkit reports no signals, a unit case asserts that the
shell does not believe it armed a disposition: installing succeeds, being
installed does not, nothing is ever pending, and sending refuses.

Four examples are skipped on Windows for a different reason again: an example is
documentation and reads `Output_Of ("echo", ...)`, which a reader understands and
that host does not have.

The interactive frontend is asserted there too now. hostkit grew a
pseudo-console body, so seven terminal cases run on Windows: a whole session,
Tab completing a word, Up recalling a line, Up *not* recalling a line typed with
a space in front of it, backspace removing something, and **Ctrl-C at the
prompt** abandoning the line being typed so that the next one runs.

Two things stay off that host. **Ctrl-C while a program is running.** Both ways
of typing one were tried there: the byte `0x03`, which is what a line discipline
takes, and the key event a console asks for when it writes `ESC [ ? 9001 h` on
attaching. The key event is the right encoding -- the prompt case uses it and
the editor sees the interrupt -- and a running loop still does not stop. What
arrives is *input to be read*, and nothing reads while a submission runs, so
there is no asynchronous event to record. A shell could poll its own input
between instructions instead; that is a decision rather than a fix, because
while a child is running the input belongs to the child. And
the **accented** half of the backspace case. A console host turns what arrives
into key events and re-encodes them, so writing two UTF-8 bytes at it is not
typing that character -- and neither, it turns out, is sending the key event
the console asks for when it writes `ESC [ ? 9001 h` on attaching: virtual key
and scan code nothing, the code point itself, down and then up. Both were tried
there and neither reached the shell; the line was never submitted. The shell
was asked about the first: after such a line it goes on answering, so what is
missing is the keystroke rather than the editor. That the editor steps by
characters and not by bytes is asserted on every host by the buffer and decoder
cases.

Windows found five defects the day CI first ran there, and three of them were
tests asserting POSIX rather than asserting the shell.

`adash_bench` covers cost: what each stage of the pipeline takes, reported as a
median and a fastest of many in-process runs. `benchmark-guide.md` says what its
numbers are and are not.

The overlap on the catalog is deliberate and the two checks are not the same.
`adash_check` verifies textually that each key is present. The suite verifies
that each message actually *renders*, given the placeholders the identifier
declares — which catches an entry that exists but is malformed, and a declared
placeholder the catalog entry never substitutes. Neither subsumes the other.
