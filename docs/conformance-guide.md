# Writing conformance cases

A conformance case is a **submission and what it must produce**. The suite runs
the built `bin/adash` — not the library — so what it checks is the shell as a
user meets it.

    cd adash_tests && ./bin/adash_conformance

`adash_tests` runs the same cases as one AUnit routine, so CI catches a failure
even though it invokes only the suite; `adash_conformance` exists because when
something fails, a per-case report is what you want rather than one assertion
message.

## A case

    [[case]]
    id = "loops.a-null-range-runs-no-times"
    requirement = """
    Why this must be so, in prose. What a reader needs in order to judge whether
    the expectation is right, rather than what the script does.
    """
    script = "for I in 3 .. 1 loop put_line (\"never\"); end loop;\nquit (0);"
    exit_status = 0
    output = ["…"]
    diagnostics = []

Every key the runner accepts: `id`, `requirement`, `script`, `arguments`,
`exit_status`, `output`, `diagnostics`, `platforms`, `input`. **A key it does
not know is rejected**, because `output_contains` instead of `output` reads as a
case that asserts something and is one that asserts nothing — a mistyped
assertion is worse than a missing one, since it looks like coverage.

`output` and `diagnostics` are optional: omitting one asserts nothing about it.
Asserting `diagnostics = []` is how a case says *and nothing was reported*.

## What makes a case deterministic

**`\n` in a script starts a new submission.** A case is a session, not a file:
`X : Integer := 1;\nput_line (X'Image);` is two submissions, and what the first
declares the second inherits. Most cases end with `\nquit (0);` so the exit
status is the one being asserted rather than whatever the last statement left.

**Diagnostics are compared by identifier.** The runner sets
`ADASH_MESSAGE_CATALOG` to a path that does not exist, so every message renders
as `!key{argument=value}!`. A case therefore says *which* diagnostic was
produced, not how it happened to be worded, and rewording the catalog never
breaks the suite.

**The environment is replaced, not inherited**, so a case gives the same answer
on a developer's machine as in CI. On Linux and macOS a case sees
`PATH=/usr/bin:/bin` and nothing else it did not set. Windows needs more than
that to start a process at all — `SystemRoot`, `windir`, a `PATH` reaching
`System32`, `TEMP`, `TMP`, `APPDATA` and `USERPROFILE` — so the runner builds
that set there. Replaced either way: nothing of the developer's own travels
into a case.

**Each case gets a store of its own**, emptied before it runs: `{store}` in a
script *or in an expectation* expands to a directory the case may write in, and
`{root}` to the repository root. `HOME` and the XDG variables point at the
store, so a case that writes history or settings writes them there and not into
the developer's own.

**A case that needs a program names a companion, not a utility.** `{emit}` and
`{upcase}` expand to the two programs this crate ships, with whatever suffix the
host puts on an executable:

| Want | Say |
| --- | --- |
| a program that says something | `{emit}` with the words as arguments |
| a program that fails | `{emit} --exit=3` |
| a program that complains where nobody collects it | `{emit} --error=text` |
| a program that is still running | `{emit} --sleep=30` |
| a program that shows what a file holds | `{emit} --file=path` |
| a program that transforms its input | `{upcase}` |

`{os}` and `{arch}` expand to how the build identifies itself, for the cases
that check what `--version` reports. `{shell}` expands to the binary under
test, with whatever suffix the host puts on one — a case that named
`{root}/bin/adash` was asking about a file that does not exist on Windows.

**`platforms` restricts a case** to the hosts it can hold on — `["linux",
"macos"]`, say. Twenty-four cases use it, nine of them Windows-only, and each
pair covers one capability from both sides: signals, resource limits, `exec`,
the creation mask, job control, and a C runtime that expands a wildcard before
the program sees it. One case asserts what POSIX does and its twin asserts what
Windows does instead, so no host is left without an answer. That is a
capability the host does not have, which is what the key is for.

**Every gate is worth re-reading now and then.** On 2026-08-20 one of them was
not a capability at all: a limit that is not a number was refused only on
Linux and macOS, because `resource_limit` asked the host whether it had the
limit before it looked at what the caller wrote, and Windows therefore answered
something else. The gate was hiding a defect rather than describing a host. It
came off with the fix, and the way to find the next one is to read each gate's
requirement and ask whether it names something the host lacks.

It is not for a case that merely needs a *program*: name `{emit}` or `{upcase}`
and it runs everywhere. **A gated case is a case one host of the three never
runs**, so gating to make a run green is the one use that is never right — and
a gap gated this way belongs in the requirement, so what the other host does
instead is visibly unasserted rather than quietly untested.

## Writing an expectation you cannot spell

Some output carries an absolute path that differs per machine — `save_settings`
reports where it wrote. Two ways out, both used:

- Name the file through `{store}` and assert its *content* instead.
- Put the assertion in the script and let the exit status carry it: a script
  that finds the wrong thing quits with a distinctive status, and asserting
  `exit_status = 0` is then the assertion passing.

The second is worth stating in the `requirement`, because a reader who sees only
`exit_status = 0` should not have to work out that it means something.

## What a requirement is for

The prose says **why the expectation is right**, not what the script does — the
script already says that. A case whose requirement restates its own code
teaches a later reader nothing when it fails, and the question at that moment is
always "was this expectation ever correct?".

## The examples are cases too

Every file in `examples/` runs as a case against its recorded `.expected`
output. Re-pin one with

    ADASH_MESSAGE_CATALOG=/nonexistent/x ./bin/adash examples/x.adash 2>/dev/null > examples/x.expected

and run it several times before trusting it: a few examples are timing-sensitive
by nature, and an expectation pinned from one run of a racy example is a test
that fails for the next person.
