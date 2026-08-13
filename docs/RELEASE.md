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
    ./bin/adash_bench                           # performance, against benchmarks/README.md

`adash_tests` already runs the conformance suite and the examples, so it is the
one command CI needs. `adash_conformance` exists because when something fails,
a per-case report is what you want rather than one assertion message.

**Build the shell before running the conformance suite.** It runs `bin/adash`,
not the library — that is the point of it — so a stale binary means a stale
verdict.

## What each check is for

| Check | Fails when |
|---|---|
| `adash_check` | A package has no owner in `repository.toml`, a required file is missing, `alire.toml` and `repository.toml` disagree about the version, a message is in the catalog and not in the code (or the reverse), an escape sequence appears in Ada source, or a forbidden unit is used |
| `adash_tests` | Any unit or integration test fails, or the conformance suite or examples do |
| `adash_conformance` | The built shell no longer behaves as `conformance/cases` says, or an example no longer produces its `.expected` output |
| `adash_bench` | Nothing — it reports. Compare against `benchmarks/README.md` and update that file when a number moves for a reason |

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
