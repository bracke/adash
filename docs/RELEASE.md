# Releasing Adash

Everything here is `alr` and the tools in `adash_tests`. There is no shell
script, no Makefile and no Python, and there will not be: repository tooling in
this project is Ada, so that it is compiled, type-checked and testable like the
rest of it. A release step that only exists in somebody's shell history is a
step that will be done differently next time.

## The checks, in order

Run from the repository root unless noted.

    alr build                                   # the shell itself
    cd adash_tests && alr build                 # the tools and the tests
    ./bin/adash_check                           # the repository obeys its own rules
    ./bin/adash_tests                           # unit, integration and conformance
    ./bin/adash_conformance                     # conformance and examples, in detail
    ./bin/adash_bench                           # performance, against benchmarks/ceilings.toml

`adash_tests` already runs the conformance suite and the examples, so it is the
one command CI needs. `adash_conformance` exists because when something fails,
a per-case report is what you want rather than one assertion message.

**Build the shell before running the conformance suite.** It runs `bin/adash`,
not the library — that is the point of it — so a stale binary means a stale
verdict.

## What each check is for

| Check | Fails when |
|---|---|
| `adash_check` | `docs/diagnostics-catalog.md` and the message catalog disagree about a message, a package has no owner in `repository.toml`, a required file is missing, `alire.toml` and `repository.toml` disagree about the version, a message is in the catalog and not in the code (or the reverse), a **terminal** escape byte appears in Ada source (the byte itself, or `ASCII.ESC`, `Latin_1.ESC`, `Character'Val (27)`) — styling belongs to terminal_styles and nowhere else, and a backslash escape in a string literal is a different thing this does not look for — or a forbidden unit is used |
| `adash_tests` | Any unit or integration test fails, or the conformance suite or examples do |
| `adash_conformance` | The built shell no longer behaves as `conformance/cases` says, or an example no longer produces its `.expected` output |
| `adash_bench` | A measured operation exceeds its ceiling in `benchmarks/ceilings.toml`, gets slower as it repeats (a median more than four times its own fastest run), or has no ceiling or drift rule recorded there. The bounds are an order of magnitude above what the operations take, so a failure is a change in what the operation does and not a slow machine. It still reports every figure — compare those against `benchmarks/README.md` and update that file when a number moves for a reason |

## Checking that a check works

Every check in the table was run through once, by making the thing it forbids
and looking for the failure. Two of them did not fail.

Every row above was run through again on 2026-08-20, by making the thing it
forbids and looking for the failure: a document row that disagrees with the
catalog, a package with no owner, a missing required file, a version that
disagrees, a message in the catalog that nothing names, a terminal escape byte,
a forbidden unit. All of them fail. Two things came out of that pass.

**A required file that was not required.** Moving `docs/diagnostics-catalog.md`
out of the way made `adash_check` run 1248 fewer checks and report PASS: the
check that compares it against the catalog returns early when it cannot read
either side, above a comment saying both are "required elsewhere" -- and that
one was not required anywhere. `docs/grammar-reference.md` and the CI workflow
were in the same position. All three are required now, and each was watched
failing.

**A row that described the wrong rule.** "An escape sequence appears in Ada
source" reads as a backslash escape in a string literal, and one of those
passes: what the check forbids is a *terminal* escape, which is a different
defect with a different reason. The row says which it means now.

`adash_check` read the version out of `alire.toml` and `repository.toml` with a
reader that wants the `= ` as part of the key it is given, was asked for
`"version"`, read nothing out of either file, compared the two nothings and
passed — for every version this repository has ever had, including runs where
the two files were made to disagree on purpose. The direction of the inventory
check that says *everything `repository.toml` names exists* read its paths the
same way and had never run either. Both are fixed, and reading nothing where a
value was expected is now a finding of its own rather than a silent agreement.

The lesson is the step, not the defect: **a check nobody has watched fail is a
check nobody has run.** Before trusting this table, break something it names
and see the failure — a wrong version, a spec entry pointing nowhere, a
sentence hard-coded in Ada source, a benchmark ceiling set to 1.

## Version numbers

The version appears in `alire.toml` and in `repository.toml`, and
`adash_check` fails when they disagree. Two files record it because they answer
different questions — what Alire resolves, and what the repository says of
itself — and a release that shipped them disagreeing is one nobody can identify
afterwards.

`Adash.Version` reads its number from the Alire-generated configuration, so
there is no third place to update.

## Reproducibility

Two builds of the same sources with the same toolchain and the same profile
produce the same behaviour, and the conformance suite is what demonstrates it:
it compares observable output, which is what a user gets, rather than bytes,
which differ for reasons nobody cares about (paths compiled into debug
information, build timestamps).

**Byte-identical binaries are not claimed.** The build embeds absolute paths
through `-g`, so two checkouts in different directories produce different
binaries that behave identically. Claiming more would be claiming something not
checked.

What *is* pinned: every dependency is a path pin in `alire.toml`, and Alire
honours pins only in the root crate, so each root repeats the whole graph. A
build that resolved something from the community index instead would be a
different build, and the lockfile records which happened.

## Before tagging

- `adash_check`, `adash_tests` and `adash_conformance` all pass on Linux, macOS
  and Windows. hostkit has a body per host and three of the four are not
  exercised by a developer machine.
- `CHANGELOG.md` describes the release in terms of what a user can observe.
- `ROADMAP.md` says what is complete and what is not, and the "known limits"
  notes are still true. A roadmap that has drifted is worse than none, because
  it is believed.
- `benchmarks/README.md` carries numbers from this build, not the last one.
- The sibling crates are at a commit somebody can name. Every dependency is a
  path pin, so a release of Adash is only reproducible together with the commits
  it was verified against — record them with the tag. Until those crates carry
  versions of their own, that list *is* the pin.

  **Take the list from Alire, not from this file.** `alr pin` in the repository
  root prints every pin the root crate resolves, and `alr pin` in `adash_tests`
  prints that crate's own — which adds `project_tools` and adash itself. This
  paragraph used to name six crates; there were fourteen, and following it would
  have recorded fewer than half the graph while calling the result reproducible.
  For each name, `git -C ../<name> rev-parse HEAD`, and check that none of them
  has uncommitted work: a pin resolves to a *directory*, so a dirty sibling is a
  release verified against something no commit contains.
- `adash_bench` passes on all three hosts, which CI runs on every push. A
  ceiling that had to be raised is recorded in `benchmarks/ceilings.toml` with
  the reason, because a bound that moves without one is not a bound.
