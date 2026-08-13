# Test guide

## Running

```
cd adash_tests
alr build
./bin/adash_tests      # AUnit suite
./bin/adash_check      # repository invariants
```

Both exit non-zero on failure. `alr test` from the repository root runs the
suite through the manifest's test action.

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

## What the two tools cover

`adash_tests` covers behaviour: version derivation, message identifier
uniqueness and well-formedness, catalog rendering including argument
substitution, the degradation path when the catalog is absent, styling policy
across every role and destination, and the repository checks themselves.

`adash_check` covers structure: required files and directories, version
agreement between `alire.toml` and `repository.toml`, the package inventory in
both directions, catalog completeness for every message identifier, absence of
hand-written terminal escapes, and absence of direct operating-system
dependencies in shell source.

The overlap on the catalog is deliberate and the two checks are not the same.
`adash_check` verifies textually that each key is present. The suite verifies
that each message actually *renders*, given the placeholders the identifier
declares — which catches an entry that exists but is malformed, and a declared
placeholder the catalog entry never substitutes. Neither subsumes the other.
