# Conformance cases

Implementation-independent cases for externally observable behaviour. Run them:

    cd adash_tests && alr build && ./bin/adash_conformance

They also run as part of `alr test`, last in the suite: a failure there after
everything else passed says the parts are right and the whole is not.

The runner executes **the built binary**, `bin/adash`, and compares its exit
status, its standard output and its standard error. It never calls into the
library — a suite that did would be testing something no user can reach.

## Comparing identifiers, not sentences

The runner points the message catalog at a path that does not exist, so every
message renders in its fallback form:

    !error.name_undeclared{name=zzz}!

That is the stable identifier and its arguments. A suite asserting on English
would break on every wording change, would be untranslatable, and would quietly
stop testing anything the day somebody localized the build.

The one line this arrangement produces itself — the shell correctly saying its
catalog is unavailable — is dropped by the runner rather than written into
every case, where it would be noise that stops being read.

## Each case gets a store of its own

The environment a case's shell runs in is replaced rather than inherited, so it
answers the same on a developer's machine as in CI. That was not enough on its
own: a home directory is a real thing whether or not `HOME` is set, so hostkit
asks the passwd database when it is missing -- and every case was writing its
script into the history file of whoever ran the suite.

`HOME`, `XDG_DATA_HOME` and `XDG_CONFIG_HOME` now point at a directory under the
host's temporary one, a different one per case, emptied before the case runs.
Three properties follow: the suite leaves a developer's own shell history alone;
case N cannot see what cases 1 to N-1 left behind; and a second run of the suite
gives the same answers as the first. The last one is not hypothetical -- a case
asserting on `history` passed once and failed every run after, because the
directory outlived the run that made it.

## The format

Cases are data, read with tomllib, so adding one when you find a bug is cheaper
than arguing about the behaviour.

    suite = "exit-status"

    [[case]]
    id = "exit.explicit"
    requirement = "quit ends the session with the status it was given"
    script = "quit (7);"
    exit_status = 7
    output = []
    diagnostics = []

| Field | Meaning |
|---|---|
| `id` | Stable identity. Referred to in commit messages and issues; never renamed. |
| `requirement` | What the case pins down, and why it matters. |
| `script` | Fed on standard input. |
| `arguments` | Passed on the command line. |
| `exit_status` | Required. |
| `output` | Exact lines expected on standard output, in order. |
| `diagnostics` | Exact lines expected on standard error, in order. |
| `platforms` | Hosts the case applies to; every host when absent. |

**An absent key and an empty one are different assertions.** Leaving
`diagnostics` out says nothing about standard error; `diagnostics = []` says
nothing came out of it. That distinction is what lets a case pin down that
diagnostics never leak into standard output.

A case that does not apply to this host is **skipped**, and counted separately
from a pass: a suite reporting skips as passes would look complete on a machine
where half of it never ran. A case that is itself wrong — no `id`, no
`exit_status`, unreadable file — is **malformed**, which fails the run, because
a suite nobody can trust is worse than none.

## What is covered

| File | Pins down |
|---|---|
| `command-line.toml` | `--version`, `--help`, unknown options, a missing script |
| `exit-status.toml` | The exit-status model, including that an earlier failure does not set it |
| `diagnostics.toml` | Diagnostic identities, and that they stay off standard output |
| `program-output.toml` | That a program can report what it computed |
| `loops.toml` | Bare loops, `exit` in each loop kind, and `return` |
| `commands-in-programs.toml` | Internal commands called from a program |
| `subprograms.toml` | Declared subprograms: arguments, results, recursion, and frames |

Cases are added with the phase that makes each behaviour observable, not in one
pass at the end. The suite grows with the observable surface: there was nothing
to assert about program output until `put_line` was lowered for `String`, and
nothing to assert about frames until a program could declare a subprogram to
have one. See `ROADMAP.md`.
