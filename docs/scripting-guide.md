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

`execution-model.md` describes running, redirection and pipelines;
`internal-commands.md` lists what each command takes.

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
