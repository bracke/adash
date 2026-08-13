# Examples

Executable, verified examples of Adash scripts.

Every example has a `.expected` file beside it holding exactly what the script
writes to standard output. `adash_conformance` runs each one and compares, so
an example that no longer produces what it claims **fails the build** rather
than being discovered by a reader. That is the whole reason they live here
rather than in prose: an unverified example is documentation that lies as soon
as the language moves.

The comparison is made with the message catalog pointed at a path that does not
exist, so output appears as message identifiers -- `!line.version{...}!` rather
than an English sentence. An example asserting on English would break on every
wording change and would stop checking anything the day somebody translated the
build.

That has one consequence worth knowing when adding an example: **its output
must be the same on every machine.** A script whose output contains a path, a
time or a process id cannot be verified this way, and a `.expected` file
recording one would fail on the next machine. Prefer scripts whose observable
result is an exit status or a fixed line.

## What is here

| Example | Shows |
|---|---|
| `exit-status.adash` | Ending a session with a status a caller can read |
| `statements.adash` | Declarations, a loop and arithmetic — a script that succeeds silently |
| `internal-command.adash` | Calling an internal command the way Ada calls a procedure |
| `strings.adash` | Strings as values: held, copied, assigned, joined and compared |
| `compute-and-exit.adash` | Computing a value and exiting with it |
| `reporting.adash` | Reporting, with a command's output in the middle of the program's |
| `subprograms.adash` | Declaring subprograms and calling them: arguments, results, recursion, frames |
| `attributes.adash` | `'Image` and `f"..."`: putting a computed value inside a sentence |
| `command-in-control-flow.adash` | A command inside a loop and a branch |
| `environment.adash` | Reading a value out of the session with `Env_Value` |
| `status.adash` | Acting on whether what was run worked, with `Status` |
| `arguments.adash` | Reading what the script was invoked with |
| `case.adash` | Choosing by value, and accounting for every value |
| `capture.adash` | Reading what a program wrote, with `Output_Of` |
| `blocks.adash` | A scope where you need one, and gone again at its end |
| `reading.adash` | Reading the shell's own input, a line at a time |
| `paths.adash` | Asking about a file before acting on it |
| `handlers.adash` | Answering for what went wrong |
| `writing.adash` | Saving what a script worked out, with `write_file` |
| `ranges.adash` | Counting backwards, and asking whether a value is in a range |
| `types.adash` | Types a program declares: enumerations and subtypes |
| `records.adash` | Records and arrays: grouping values, and holding many |
| `packages.adash` | Packages and generics: naming a group, and one body for many types |
| `tasking.adash` | Tasks and protected objects: two things at once, and sharing them |

## What is not here yet, and why

`strings.adash` still produces no output, because it predates `put_line` for
`String` and its point is what a String *is* rather than how it is reported.
`reporting.adash` and `environment.adash` write computed text, so nothing here
is unobservable for want of a way to say it.

`reading.adash` is run with nothing on its input, for the same reason: what a
script reads is what somebody piped into it, and that is not fixed either.

`writing.adash` starts by moving into a directory `mktemp` makes for it. A
script that wrote into whatever directory it was started from would leave files
behind wherever you ran it, and the filenames it prints have to be the same on
every machine that checks this file.

What no example can show is anything whose output differs by machine — a path,
a time, a process id — for the reason at the top of this file. `cd
(Env_Value ("HOME"))` is what `Env_Value` exists for and is described in
`environment.adash` rather than run by it.
