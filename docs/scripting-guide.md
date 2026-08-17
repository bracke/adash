# Writing scripts

A script is a file of submissions. The same lexer, analyser, machine and
commands that answer at the prompt run it, so a line that works in a session
works in a script and the reverse.

    adash report.adash                 -- run it
    adash report.adash one two         -- with arguments

## What a script sees

    Argument_Count                     -- how many it was given
    Argument (1)                       -- the first, from one

A position that was not given reads as the empty string rather than failing.

    Status                             -- what the last program or command did
    quit (Status);                     -- forward it and stop

The script's own exit status is what `quit` was given, or 0 when it runs off the
end. An unhandled exception ends it with a failure status and reports which
exception it was.

## Reading input

    loop
       Line : String := Read_Line;
       exit when Input_Ended;
       put_line (To_Upper (Line));
    end loop;

`Input_Ended` is a separate question from what `Read_Line` returned, because an
empty line is a line a file may genuinely contain. That loop is the shape every
filter has.

## Files, programs and pipelines

    run ("make", "all");
    if Status /= 0 then
       quit (Status);
    end if;

    Text : String := Output_Of ("git", "rev-parse", "HEAD");
    write_file (Text, "build.id");

### Where what a program wrote goes

Every program a script runs has three streams, and each of them is a command
rather than punctuation:

    run_into ("out.txt", "make", "all");          --  what it said
    run_errors_into ("errors.txt", "make", "all"); --  what it complained about
    run_all_into ("build.log", "make", "all");     --  both, in the order it wrote them

Each of those three has an `_append` form for adding to a file and a `_new` form
that refuses a file already there. `run_from` feeds a program from a file, and
`start` runs one without waiting.

The reading side matches: `Output_Of` answers with what a program said,
`Error_Of` with what it complained about, and `All_Of` with everything it wrote.

    if Index (All_Of ("make", "all"), "warning") > 0 then
       put_line ("it built, and it was not happy about it");
    end if;

**`run_all_into` is not two files.** The error stream follows the output stream
into the same open file, so the lines stay in the order the program wrote them;
two files, however carefully a script interleaves them afterwards, cannot be
made into one.

### Pipelines

A pipeline is built a stage at a time and then run by the command that says what
becomes of it:

    pipe ("git", "log", "--oneline");
    pipe ("head", "-20");
    pipe_into ("recent.txt");

That is more words than a `|`, and it says what a `|` cannot: `pipe_from` gives
the pipeline its input and runs nothing, `pipe_start` leaves it running as a job,
and the nine `pipe_*` forms place its output exactly as the `run_*` forms place a
single program's. `Output_Of_Pipe`, `Error_Of_Pipe` and `All_Of_Pipe` read it
back as a value instead.

Input is attached to the **first** stage and output to the **last** — every
other stage is joined to its neighbour, and redirecting one of those would cut
the pipeline in half. Each running form empties the pipeline, so a script that
wants two of them builds it twice.

`examples/pipelines.adash` runs all of this.

`execution-model.md` describes running, redirection and pipelines;
`internal-commands.md` lists what each command takes.

A mistake in a script is reported with its place — `report.adash:12:7:` — with
the line quoted and a caret under it, and a mistake in a file the script read in
names that file and its own line.

A failing command does **not** stop the script — the test above is how a script
says it should. That is Ada's rule for a procedure that reported a failure, and
`sh -c` behaves the same way.

## Splitting a script up

    source ("helpers");

`source` runs another file in this session. A bare name is searched for beside
the script doing the loading first, then in the user's own module directory, so
a set of scripts that ship together find each other without knowing where they
were installed — and without the working directory deciding, which is what makes
it work when somebody runs the script from elsewhere.

**In a script, a sourced file is read in where the call stands.**

    source ("helpers");
    Report ("done");                   --  Report is visible: helpers was read
                                       --  in before any of this was analysed

A script is one submission, analysed as a whole before any of it runs, so a
call that only *ran* the other file would come too late — the names it declares
would not be there to resolve. Reading it in makes one program of the two, in
the order they were written.

Only a **literal** name, and only at the top of the file. Both are the rule
this language uses wherever something has to be known before the program runs —
an array's bounds, a case's choices, a parameter's default — and
`source (Name)` is not one of them. A computed name stays what it always was: a
command that runs a file when it is reached, whose declarations reach the next
submission.

A module may read in a module. A file that would read itself back is left as a
call, and running it reports the cycle with the path that closed it.

At a prompt this does not arise: each line is a submission, so a file sourced
on one line has declared its names by the next. Declarations that several
scripts share can also go in the **startup file**, which runs before the script:

    ~/.config/adash/startup.adash      --  procedure Report (...) is ... end;
    report.adash                       --  Report is visible here

## What runs before a script does

The configuration file, then the startup file if there is one. `startup.session`
controls the per-session file. Each is an ordinary submission, so what it
declares is carried into the session the way any submission's declarations are —
which is how a user gives themselves subprograms that are always there.

## Style

The language is Ada, so a script reads as Ada: declarations before statements in
a block, `end if;` and `end loop;`, one statement per line, a semicolon after
each. A script is a *program*, and the thing that makes it worth writing in this
shell rather than another is that it can be read as one.

`language-reference.md` is the subset it is written in.
