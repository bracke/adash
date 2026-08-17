# The execution model

How a submission becomes work: what runs a program, what a pipeline is, where
redirection happens, and what a status means.


## When there is nowhere to write

A reader that takes what it wants and leaves — `adash script | head -1` — closes
the pipe under the shell. The next write fails: on POSIX the shell has refused
the signal that would otherwise kill it, so the write raises, and on Windows
there is no such signal and it raises too.

What a *program* the shell runs writes is that program's business, and a shell
whose own write fails has run out of ways to say so. So a write inside a
submission is reported to the program as a stream failure, and a write the shell
makes for itself ends the session with status **74** — the convention for an
input/output error — with nothing printed, because the place a complaint would
go is the place that just failed.

Neither prints a stack trace. That is worth saying because it used to: fifteen
lines of addresses on the standard error, which is a stream something else may
be reading.

## One submission, one program

A submission is lexed, analysed as a whole, lowered to instructions and run by
`Adash.Machine`. Internal commands are calls in that program, not a second
mechanism beside it — `Adash.Engine` is the one place a submission becomes a
run, and the machine asks the shell for what only the shell can answer.

A command's arguments are values the machine evaluates. That is why `quit
(Total);` after a loop works, why a command may stand inside an `if`, and why a
declaration written before a command is still in scope after it.

## Running a program

`run ("program", "argument", …)` starts a program, waits for it, and reports
through `Status`. `Output_Of` runs one and answers with what it wrote to
standard output.

**Arguments arrive as they were written.** There is no word-splitting, no
globbing and no re-scanning of what a `String` holds, so `run ("echo", "one
two")` passes one argument with a space in it. What a program is given is what
the program's own quoting rules would have had to be written for elsewhere.

**Standard error is not collected.** It belongs to the user: a program
explaining why it failed should be heard rather than swallowed into a value a
script is about to compare against something.

## Redirection

Four commands rather than an operator, because there is no `>` in a language
whose calls are Ada calls:

| Command | Does |
|---|---|
| `run_into (File, Program, …)` | output to a file, replacing what was there |
| `run_append (File, Program, …)` | output added to the end |
| `run_new (File, Program, …)` | output to a file that must not already exist |
| `run_from (File, Program, …)` | input read from a file |

The file comes first, which is what distinguishes these from `run`. `run_new` on
a file that is there fails with a status, says which path it would not open, and
leaves the file alone.

## Pipelines

    pipe ("echo", "hello");
    pipe ("tr", "a-z", "A-Z");
    pipe_run;

`pipe` adds a stage, `pipe_run` runs what was built and waits. A pipeline is
assembled by statements rather than written as punctuation, so a stage may be
added inside an `if`. What the last stage writes is what the session sees, and
**the status is the last stage's**. `pipe_run` with nothing built reports an
empty pipeline.

## Exit status

One model, which the shell itself exits with:

| Status | Means |
|---|---|
| 0 | success |
| what the program chose | it ran and decided |
| 126 | found and not executable |
| 127 | not found |
| 128 + n | killed by signal n |

`Status` is 0 before anything has run. A script forwarding a status does not
have to translate it: `quit (Status);` is the whole of it.

**A failing command does not stop what follows.** Ada does not end a sequence
because a procedure reported a failure, and `sh -c 'cd /nonexistent; pwd'`
prints the unchanged directory and exits zero. A caller that wants a sequence to
stop writes the test — that is what `if` is for.

## What the shell owns and what hostkit owns

Everything that differs because the operating system differs — spawning, pipes,
descriptors, signals, process groups, terminals — belongs to `hostkit` and is
reached through `Adash.Platform`. `Adash.Execution` and its family hold the
*policy*: what a pipeline is, which status means what, when a job is recorded.
`adash_check` enforces the boundary: no Adash source may name `GNAT.OS_Lib`,
`Interfaces.C` or `System.OS_Interface`.

That is why "cannot tell" is never rounded up to "fine": where a host cannot
answer a question, the answer is a deliberate refusal rather than an optimistic
default, and `job-control.md` says what that means on Windows.
