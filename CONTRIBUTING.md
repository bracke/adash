# Contributing

## Requirements

[Alire](https://alire.ada.dev/) 2.1 or later and a GNAT toolchain. Nothing else
— there is no Make, no build script and no Python in this repository, and adding
one is not a shortcut but a second toolchain that has to be installed, learned
and kept working on every host the shell is built on. The one exception is the
manifest's own test action, a single `sh -c` line that Alire needs in order to
change directory before running the suite; every sibling crate writes the same
line, and nothing else in the repository is written in anything but Ada.

Adash is developed alongside its sibling crates, checked out beside it:

```
Ada/
  adash/
  hostkit/
  messages/
  terminal_styles/
  project_tools/
  ...
```

Alire honours path pins only in the root crate, so both `alire.toml` and
`adash_tests/alire.toml` name the whole graph. A resolve that succeeds without
them was reading a cache.

## Build and test

```
alr build                      # the shell
./bin/adash --help

cd adash_tests
alr build
./bin/adash_tests              # AUnit suite
./bin/adash_check              # repository invariants
```

`alr test` from the root runs the suite through the manifest's test action.

Both must be green before a change is proposed, and both are green on `main`. A
red suite on `main` is treated as an outage, not as a known issue.

## What a change has to include

A change is not finished when it compiles. From `ROADMAP.md`'s definition of
done, in practice:

- **Tests.** New behaviour gets tests. A fixed defect gets a permanent
  regression test, named for what it protects rather than for the ticket.
- **GNATdoc** on every public declaration, with `@param` and `@return`.
- **`repository.toml`** updated for any package added, renamed or removed.
  `adash_check` fails otherwise, in both directions.
- **Messages** for any new user-visible text, added the way `AI.md` describes.
- **Documentation** updated where the change is observable.
- **Conformance cases** for observable behaviour.

## Where code goes

| | |
|---|---|
| `src/library/` | the shell |
| `src/main/` | the executable entry point, kept thin |
| `resources/messages/` | every user-visible string |
| `adash_tests/src/` | reusable tooling packages and the mains that drive them |
| `adash_tests/tests/` | AUnit cases |
| `adash_tests/fixtures/` | test data, including deliberately broken trees |

A check worth running is worth being callable from a test, so its logic lives in
a package under `adash_tests/src/` and both a main and an AUnit case reach it.
`adash_check` and `Adash_Tests.Repository_Cases` run the same code rather than
two copies that drift.

## Review

A reviewer is entitled to reject a change that:

- puts a user-visible string in an Ada source file;
- reaches past hostkit to the operating system;
- writes a terminal escape sequence;
- adds a second parser, evaluator or engine;
- adds POSIX shell syntax rather than expressing the feature in Adash's language;
- uses an exception for an expected operational failure;
- adds a package with no `repository.toml` entry;
- claims completion without tests and documentation.

These are the invariants in `ARCHITECTURE.md`. They are not style preferences,
and "it is only temporary" is not an exemption — a temporary second
implementation is how a permanent one starts.

## Commit messages

Say what changed and why the change is correct. The diff already says what the
code does. When a change fixes a defect, name the defect and name the regression
test that now covers it.

## Releases

`0.1.0` was released on 2026-08-22; what it contains is under that heading in
`CHANGELOG.md`, and work since then goes under *Unreleased*. What a release takes is
in `docs/RELEASE.md` — the gates, in order, and what is deliberately not
claimed about reproducibility. The version lives in `alire.toml` and is mirrored
in `repository.toml`; `adash_check` verifies they agree, and no Ada source
contains a version literal.
