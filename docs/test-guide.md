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
validated. Thirty-two conformance cases carry a `platforms` key because they
name a POSIX utility or path; those are checked on two hosts of the three, and
closing that gap means Windows equivalents rather than dropping the key.

`adash_bench` covers cost: what each stage of the pipeline takes, reported as a
median and a fastest of many in-process runs. `benchmark-guide.md` says what its
numbers are and are not.

The overlap on the catalog is deliberate and the two checks are not the same.
`adash_check` verifies textually that each key is present. The suite verifies
that each message actually *renders*, given the placeholders the identifier
declares — which catches an entry that exists but is malformed, and a declared
placeholder the catalog entry never substitutes. Neither subsumes the other.
