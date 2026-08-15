# Using Adash

Adash is a shell whose command language is a defined subset of Ada 2022. What
you type is a **program**, not a command line with words in it.

    adash                      -- start a session
    adash script.adash         -- run a script
    adash script.adash a b     -- with arguments
    adash --version
    adash --help

## The first thing to know

Everything is a call, with parentheses and a semicolon:

    pwd;
    cd ("/tmp");
    run ("ls", "-l");
    put_line ("hello");

Not `cd /tmp`. There is one grammar here and the commands live inside it, which
is what buys the rest: a command can stand in an `if`, take a value the program
computed, and be followed by a declaration that is still in scope afterwards.

    Total : Integer := 0;

    for Index in 1 .. 4 loop
       Total := Total + Index;
    end loop;

    quit (Total);              -- exits 10

`help;` lists the commands; `help ("cd");` describes one.

## What a session remembers

A submission — one line, or one construct written across several — is analysed
as a whole and run. What it declares is there on the next line:

    adash > X : Integer := 41;
    adash > put_line (Integer'Image (X + 1));
     42

Variables keep the value they ended with. Types, subprograms, packages, task
types, protected objects with their state and exception names are all carried
too. A task *object* is not: a task does not outlive the submission that
declared it.

A line that fails part way through — an unhandled exception, or `quit` — keeps
nothing of its own: what it declared is gone, and what it changed in variables
you already had is gone with it. Those go on holding what they held before that
line ran.

## Running programs

    run ("make", "all");
    put_line ("make said " & Integer'Image (Status));

    Where : String := Output_Of ("git", "rev-parse", "HEAD");

Arguments arrive exactly as written — no word-splitting, no globbing — so one
argument with a space in it is one argument. `Status` follows the usual model: 0
for success, 127 for a program that was not found, 128 + n for one a signal
killed.

Redirection and pipelines are commands rather than punctuation:

    run_into ("out.txt", "ls", "-l");
    pipe ("ls"); pipe ("wc", "-l"); pipe_run;

## When something is wrong

The shell reports what it found and carries on with the next submission. A
failing command does not stop what follows it — write the test if you want it to:

    cd ("/nowhere");
    if Status /= 0 then
       quit (Status);
    end if;

An error names what it is about. `X is not declared here`, `expected end here`,
`Index is a value of 2 types here`. Every message has an identifier behind it,
which is how the same session can be read in another language and how the tests
assert on diagnostics rather than on wording.

In a **file** it says where, in the form every compiler uses, and shows the
line with a caret under what it is about:

    report.adash:12:7: Total is not declared here
    put_line (Total'Image);
              ^~~~~

A diagnostic that is about more than one place says all of them — the earlier
declaration behind "already declared", the first of a pair given twice, every
declaration an ambiguous name could have meant:

    report.adash:6:1: Total is already declared in this scope
    Total : Integer := 2;
    ^~~~~
    report.adash:4:1: declared here

A file a script read in names *itself*, so a mistake in a module is reported
where it was written rather than where it was used — and a name declared in a
module and again in the script that read it in shows one line from each file. A line typed at the prompt
gets no position: it is on the screen above, and a position in front of it
would point at itself. Neither does something with no place in the text — a
file that could not be read at all, or a program that raised, which is a run
rather than a place.

## Settings and files

    settings;                          -- list them
    settings ("color", "never");       -- change one
    save_settings;                     -- keep it

Nine settings; `configuration-reference.md` lists them. They live in
`~/.config/adash/config.toml`, and the history in
`~/.local/share/adash/history.jsonl`.

## Where to go next

- `interactive-guide.md` — the prompt, editing, completion, history, Ctrl-C.
- `scripting-guide.md` — writing scripts, arguments, input, splitting them up.
- `language-reference.md` — the language itself, and where the subset ends.
- `internal-commands.md` and `predefined-functions.md` — everything callable.

## What Adash is not

It is not a POSIX shell and does not try to be: there is no word-splitting, no
globbing, no `$VAR` expansion, no backticks, no `&&`. What replaces them is a
language — `Env_Value ("HOME")`, `if`, `Output_Of`, and a status you can test.

A line that would be a one-liner in `sh` is often a line here too, and sometimes
it is three. What you get for that is a shell where a script is a program: it is
checked before it runs, it says what it means, and the same rules hold at the
prompt and in a file.
