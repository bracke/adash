# Internal commands

An internal command is a **procedure**, called the way Ada calls one: a name,
parentheses if it takes anything, and a semicolon.

    pwd;
    cd ("/tmp");
    cd (Directory => "/tmp");
    quit (Total);

Not a bare word. There is one grammar here and commands live inside it, so a
command may stand wherever a procedure call may — inside an `if`, inside a loop,
between two declarations — and its arguments are values the machine evaluates
rather than the text they were written with.

A command that fails does not stop what follows it. Ada does not end a sequence
because a procedure reported a failure, and neither does `sh -c`. What it
reports is `Status`; a script that wants a sequence to stop writes the test.

There are twenty-seven, listed here with the arity and parameter names the
registry in `Adash.Commands` declares. `help;` lists them at the prompt and
`help ("cd");` describes one.

## The session

| Command | Takes | Does |
|---|---|---|
| `cd (Directory : String)` | 0 .. 1 | changes the directory; with no argument, goes to the home directory |

With no argument `cd` goes home; `cd ("-")` goes back to where the last `cd`
came from, and says so rather than guessing when the session has not moved yet.
A directory actually named `-` is reachable as `./-`, which is how the other
shells reach it too.

| `pwd` | 0 | reports the directory the shell is in |
| `quit (Status : Integer)` | 0 .. 1 | ends the session, with a status if one is given |
| `version` | 0 | reports which build this is |
| `help (Topic : String)` | 0 .. 1 | lists the commands, or describes one |
| `history (Count : Integer)` | 0 .. any | lists what has been typed this session |
| `forget (What)` | 0 .. 1 | forgets the last lines, or the line named, in the session and in the file |
| `source (Path : String)` | 1 | reads and runs a script in this session |

`quit` is spelled that way because `exit` is a keyword of the language.

`source` runs a file **in this session**, so what it declares is carried the way
any submission's declarations are: visible to the *next* submission. A bare name
is searched for — beside the script doing the loading first, then the user's own
module directory — so a set of scripts that ship together find each other
without knowing where they were installed.

**In a script, a literal name at the top of the file is read in rather than run
when reached.** A script is one submission, so a module's declarations have to
be part of it before it is analysed; reading the file in where the call stands
is what makes `source ("helpers"); Report ("x");` mean what it looks like. A
computed name — `source (Where)` — cannot be known before the program runs and
stays the command it was. `scripting-guide.md` says what follows from that.

`history` in a session with no log — a script — reports that it has nothing,
which is a different thing from a missing feature and is worded differently. It
lists what was recorded, so a line typed with a space in front of it is not
there: see `interactive-guide.md`.

`forget` is the other half of that. A space in front of a line keeps it out of
the history, and `forget` takes out a line already in: the last one by default,
the last *Count* with a number, and with a **string** the line that is exactly
that text — every copy of it, from the session and from the file both.

The string form reaches further than the count. A count can only take what the
session's log holds, which is the last `history.limit` entries and no more; a
line named by its text is taken out of the file whether or not this session
ever read it back, which is exactly the line a count cannot get to.

One command rather than two: the parameter takes whatever it is given, and a
number means how many while a string means which. **It
takes itself with it**, uncounted — a history whose last entry is the command
that emptied it has kept a record of the act. A count below one is refused
rather than read as "all of it", which is what `history (0)` does: a command
that destroys more than it was asked to must not be reachable by a typing
mistake.

It removes each line by its text, taking the **last** occurrence in the file
rather than a position. A shared history file holds what several shells wrote,
interleaved, so "the last three lines" of it may not be this session's three.

## The environment children inherit

| Command | Takes | Does |
|---|---|---|
| `set (Assignment : String)` | 1 | sets a variable, written `NAME=VALUE` |
| `unset (Name : String)` | 1 | removes one |
| `env` | 0 | lists them |

`Env_Value ("NAME")` reads one from the language side. A name that was never set
reads as the empty string rather than failing.

## Running programs

| Command | Takes | Does |
|---|---|---|
| `run (Program : String; Argument : String…)` | 1 .. any | runs a program and waits |
| `run_matching (Program : String; Argument : String)` | 1 or more | runs a program with the arguments that hold `*`, `?` or `[` replaced by the paths they name, sorted; an argument with none is passed along untouched, and a pattern that names nothing refuses the command rather than passing the pattern on as a word |
| `run_instead (Program : String; Argument : String)` | 1 or more | becomes the program: runs it instead of this shell, keeping the process, its open files and its place in the terminal. Nothing runs after it, including `on_exit`. Windows has no such call and says so |

Expansion is the shell's, not the language's: nothing is expanded unless
`run_matching` was written, and `run` hands a program exactly the arguments it
was given. One host qualifies that last sentence — a Windows program built with
the usual C runtime expands the wildcards in its own argument list before `main`
runs, so `run ("prog", "*.log")` reaches `prog` as `*.log` everywhere and `prog`
may then expand it for itself there. `run_matching` is unaffected: what it hands
over has already been expanded, and nothing is left for a runtime to find.

| `run_into (File : String; Program : String…)` | 2 .. any | runs it with its output written to a file, replacing what was there |
| `run_append (File : String; Program : String…)` | 2 .. any | the same, added to the end |
| `run_new (File : String; Program : String…)` | 2 .. any | the same, to a file that must not already exist |
| `run_errors_into (File : String; Program : String; ...)` | 2 or more | runs it with what it complains about written to a file |
| `run_errors_append (File : String; Program : String; ...)` | 2 or more | adds what it complains about to the end of a file |
| `run_errors_new (File : String; Program : String; ...)` | 2 or more | as `run_errors_into`, refusing a file that is already there |
| `run_all_into (File : String; Program : String; ...)` | 2 or more | runs it with everything it writes in one file, in order |
| `run_all_append (File : String; Program : String; ...)` | 2 or more | adds everything it writes to the end of one file |
| `run_all_new (File : String; Program : String; ...)` | 2 or more | as `run_all_into`, refusing a file that is already there |
| `run_from (File : String; Program : String…)` | 2 .. any | runs it with its input read from a file |
| `run_from_text (Input : String; Program : String…)` | 2 .. any | runs it with its input read from text this script computed |
| `run_with (Assignment : String; Program : String…)` | 2 .. any | runs it with variables set for it alone, each written `NAME=VALUE`; the program is the first argument that is not one |
| `stop_process (Process : Integer)` | 1 | asks a process this session did not start to stop, by its id |
| `start_with (Assignment : String; Program : String…)` | 2 .. any | as `run_with`, without waiting |
| `time (Program : String; Argument : String…)` | 1 .. any | runs it and reports how long it took, in wall-clock seconds |
| `umask (Mask : String)` | 0 or 1 | shows what the host takes away from a new file's permissions, or sets it, in octal; Windows has none |
| `resource_limit (Resource : String; Value : String)` | 0 to 2 | with nothing, lists every limit this host has; with a resource, shows it and the ceiling it may be raised to; with both, sets it. Sizes are bytes, `processor_time` is seconds, the rest are counts, and `unlimited` is a value. Windows has none |
| `resource_ceiling (Resource : String; Value : String)` | 1 or 2 | shows or sets how far a limit may be raised. Anybody may lower a ceiling; only privilege raises it again |
| `complete_with (Program : String; Name : String)` | 2 | names a subprogram that says what may follow a program, one candidate per line, for Tab |
| `on_interrupt (Name : String)` | 1 | names a subprogram to run when the user interrupts; stays registered |
| `on_signal (Signal : String; Name : String)` | 2 | runs a subprogram when a signal arrives — `terminate`, `hangup`, `quit`, `continue` and the rest, by the host's own name in lower case. `kill` and `stop` cannot be caught anywhere and are refused; Windows has none of these and refuses too |
| `signal_process (Process : Integer; Signal : String)` | 2 | sends a signal to a process by id, naming it rather than numbering it |
| `pipe (Program : String; Argument : String…)` | 1 .. any | adds a stage to the pipeline being built |
| `pipe_run` | 0 | runs what `pipe` built, and waits |
| `pipe_start` | 0 | runs the pipeline in the background and names the job |
| `pipe_from (File : String)` | 1 | takes the pipeline's input from a file; does not run it |
| `pipe_from_text (Input : String)` | 1 | takes the pipeline's input from text this script computed; does not run it |
| `pipe_into (File : String)` | 1 | says its output goes to a file; does not run it |
| `pipe_append (File : String)` | 1 | says its output is added to the end of a file |
| `pipe_new (File : String)` | 1 | as `pipe_into`, refusing a file that is already there |
| `pipe_errors_into (File : String)` | 1 | says what the last stage complains about goes to a file |
| `pipe_errors_append (File : String)` | 1 | says it is added to the end of a file |
| `pipe_errors_new (File : String)` | 1 | as `pipe_errors_into`, refusing a file that is there |
| `pipe_all_into (File : String)` | 1 | says everything the last stage writes goes to one file |
| `pipe_all_append (File : String)` | 1 | says it is added to the end of one file |
| `pipe_all_new (File : String)` | 1 | as `pipe_all_into`, refusing a file that is there |

The redirection file comes **first**, because it is what distinguishes these
four from `run` — there is no `>` here, and no word-splitting anywhere: an
argument with a space in it is one argument.

A pipeline is assembled by statements and reports what its **last stage**
reported. `run_new` on a file that is there fails with a status and says which
path it would not open, leaving the file alone.

`Output_Of ("program", "argument")` is the language-side form that answers with
what a program wrote to standard output, with the trailing newline dropped.
Standard error is not collected: a program explaining why it failed should be
heard rather than swallowed into a value.

## Jobs

| Command | Takes | Does |
|---|---|---|
| `start (Program : String; Argument : String…)` | 1 .. any | starts a program in the background and records it as a job |
| `jobs` | 0 | lists what the shell is running |
| `wait (Job : Integer)` | 1 | waits for one and reports how it ended |
| `stop (Job : Integer)` | 1 | asks one to stop |
| `suspend (Job : Integer)` | 1 | suspends one, leaving it able to be resumed |
| `resume (Job : Integer)` | 1 | resumes a suspended one, in the background |
| `foreground (Job : Integer)` | 1 | resumes a stopped job in front and waits for it |

Jobs are numbered from one as they are started. On Windows there are no process
groups and no pseudo-terminals; what that host *can* do is report Ctrl-C, and
the commands that cannot be honoured decline rather than pretending.

## Files and settings

| Command | Takes | Does |
|---|---|---|
| `write_file (Text : String; File : String)` | 2 | writes text to a file, replacing what was there |
| `append_file (Text : String; File : String)` | 2 | adds text to the end |
| `make_directory (Directory : String)` | 1 | makes a directory, and any above it that is missing |
| `remove_file (File : String)` | 1 | takes a file away; one that is not there is not an error |
| `remove_directory (Directory : String)` | 1 | takes an **empty** directory away |
| `rename (From : String; To : String)` | 2 | renames or moves; refuses to replace what is there |
| `copy_file (From : String; To : String)` | 2 | copies; refuses to replace what is there |
| `on_exit (Subprogram : String)` | 1 | runs that subprogram before the session ends |
| `settings (Setting : String; Value : String)` | 0, or 2 | lists the settings, or changes one |
| `save_settings` | 0 | writes the current settings to the configuration file |

`write_file` and `append_file` take the **text first and the file second**,
which is the order `run_into` does not use — those two are named after what runs
and these after what is written. Appending to a file that is not there makes it,
because the first turn of a loop that collects lines is not an error. A write
that worked says nothing; `Status` says what became of it.

**`start` takes no file**, and neither does `pipe_start`, so "run this in the
background with its output in a log" is said by building a one-stage pipeline:

    pipe ("make", "all");
    pipe_all_into ("build.log");
    pipe_start;

    Mine : Integer := Last_Job;

That is the whole reason placing and running are separate commands, and it is
why `start` was left as it is rather than growing nine file forms of its own.

`pipe_start` is `start` for a pipeline: it does not wait, it reports the job
number, and — like any background job on a host where the shell watches its own
terminal — the pipeline is given nothing to read rather than the keyboard the
shell is holding, unless `pipe_from` already said where it reads from.

`pipe_from` records where the input comes from and runs nothing, which is the
one difference from `run_from`: a pipeline reading one file and writing another
would otherwise be two commands each insisting on running, and only one could.
Its file is attached to the **first** stage, as the others are attached to the
last.

**Saying and running are two things, so they are two commands.** `pipe_from` and
the nine placement forms say; `pipe_run` and `pipe_start` run. That is what lets
one pipeline read a file, write a log and be left running — which could not be
said while placing and running were one command, and which is the commonest
reason to put anything in the background.

The nine placement forms are the nine `run_*` forms, for a pipeline: the same
names, the same order of arguments, and the same three ways of meeting a file.
They attach to the **last** stage, which is the one whose output is the
pipeline's — the others are attached to the stage after them, and attaching to
one of those would cut the pipeline in half. Running is what empties a pipeline,
so a script that wants two of them builds it twice.

The `run_all_*` three are what a build log wants: the error stream follows the
output stream into the **same open file** rather than opening a second one, so
what a program said and what it complained about stay in the order it wrote
them. Two opens of one path would be two file positions writing over each
other, which is not a log of anything.

**Removing a directory takes an empty one, deliberately.** A recursive removal
is one typo away from the most destructive thing a shell can be asked to do, and
a script that means it can say so in three lines that name what they destroy:
list it, remove what is in it, remove it. `rename` and `copy_file` refuse to
replace something already there — a move that silently overwrote would be the
destructive case wearing the safe one's name.

**`on_exit` is `trap`, under a name that says what it does.** It takes the name
of a subprogram this session declared and runs it when the session ends however
it ends: off the end, through `quit`, or because an interrupt stopped what was
running. Most recently registered runs first, so cleanups undo in the order the
things they clean up were made, and the name is resolved when it runs — so a
script may register cleanup at the top and declare it below.

**Writing puts down exactly the bytes it is given.** The three readers drop the
carriage return in front of a line feed, because a String in this language is
text and a line in text ends with a line feed — but nothing on the way out puts
one back. A file a script writes on Windows therefore has line feeds alone,
which every tool made this century reads and a few old ones show as one long
line. That is deliberate: a shell that added carriage returns on one host would
make `write_file (Read_File (P), Q)` change the file it copied, and a script
that wants them can write them, since `Character'Val (13)` is a character like
any other.

`make_directory` makes every missing directory in the path rather than only the
last: a script that has worked out `logs/2026/august` means all of it. A
directory that is already there is not a failure — what was asked for is that it
be there — and something that is not a directory in the way is refused and says
so. It is a command rather than a function for the same reason writing is one:
it has consequences, and a reader should see it happen.

`settings` takes nothing or two arguments — a query form taking one is not
written. The setting names are `color`, `history.enabled`, `history.limit`,
`read.limit`, `trace.commands`, `prompt.directory`, `prompt.failure` and
`editing.enabled`.

Every command checks its own count and says what it wanted: `write_file` with
three arguments is told it takes 2, `run_into` with one is told it takes *2 or
more*, `pipe_run` with nothing built reports an empty pipeline, and `help` on a
name nothing declares reports that command as unavailable.

**A call written in a program carries at most four arguments**, whatever the
table above says a command takes: the activation record the machine builds for
a command call has a fixed shape, decided when the stub is built rather than
when a call is written, so `run ("p", "a", "b", "c", "d", "e")` is refused
where it stands rather than losing the fifth. Building the argument list first
-- a String a program assembles, or `pipe` a stage at a time -- is how a longer
command line is written.

## What a command reports

Every command reports through `Status`, on the one exit-status model the shell
itself exits with: 0 for success, what an external program chose, 126 for
something found and not executable, 127 for something not found, 128 + n for a
program a signal killed. The shell has two numbers of its own on the way out —
2 for a usage error and 74 for having nowhere left to write — and neither ever
reaches `Status`, since one happens before a session and the other ends it.

Commands write **structured lines**, not text: what you see at the prompt is a
message identifier rendered through the catalog. That is why a conformance case
can assert `!line.job_started{id=1,what=true}!` and why the same session can be
read in another language. A program's own `put_line` is different — that is the
program's bytes, and they are not routed through the catalog.

## What the registry knows

`Adash.Commands` holds one metadata record per command: its name, its minimum
and maximum arguments, the type and name of each parameter, whether it reports
only, changes state or ends the session, and the message identifiers for its
description and its help. Nothing in that package holds prose — the text lives
in the catalog, which is what makes `help` translatable and this table
generated rather than remembered.
