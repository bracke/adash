# Predefined entities

Twenty-eight names a program may use without declaring anything: six type
names, two constants, three procedures and seventeen functions. They are what a
script has before it writes a line of its own.

None of them may be redeclared at submission level — a subprogram of the same
name would fit every call the original does, and every call would then be
ambiguous. A body's own declarations are a different scope and may hide one,
which is Ada's rule and this one's:

    procedure Report is
       Status : Integer := 5;      --  hides the predefined Status here
    begin
       put_line (Status'Image);
    end Report;

The table below is the registry in `Adash.Predefined`, which is also what the
completion and the analyser read.

**A call may name its arguments**: `Index (Whole => Line, Piece => ",")`, and
`Put_Line (Item => Text)`. The names below are the ones to use, and a name that
is not a parameter — or one given twice — is reported as that.

## Types and constants

| Name | Is |
|---|---|
| `Integer` | 64-bit |
| `Float` | |
| `Boolean` | with `True` and `False` |
| `Character` | |
| `String` | the one predefined array; begins at one |
| `Task_Id` | what `T'Identity` yields |

## Writing

| Call | Answers | Notes |
|---|---|---|
| `Put (Item)` | — | writes a value without a newline |
| `Put_Line (Item)` | — | writes it with one |
| `New_Line` | — | writes a newline |

`Put` and `Put_Line` take a value of any *simple* type — `Integer`, `Float`,
`Boolean`, `Character`, `String`, an enumeration — and render it as `'Image`
does, except that a `String` is written as itself. A composite has no text form
and is refused: a record is its parts, and each of those has a text form where
the whole has none.

These write the **program's own bytes**. They do not go through the message
catalog, which is for the shell's own messages, and they are not structured
lines the way a command's output is.

## Reading

| Call | Answers | Notes |
|---|---|---|
| `Read_Line` | `String` | one line, without the newline that ended it |
| `Input_Ended` | `Boolean` | whether the last read found the end rather than a line |

Two questions rather than one, on purpose: an empty line is a line a file may
genuinely contain, and a program that could only see the text could not tell the
two apart. The shape every filter has is therefore

    loop
       Line : String := Read_Line;
       exit when Input_Ended;
       …
    end loop;

## Running and asking about programs

| Call | Answers | Notes |
|---|---|---|
| `Output_Of (Program, Argument_1, Argument_2, Argument_3)` | `String` | runs a program and answers with what it wrote to standard output |
| `Status` | `Integer` | what the last program or command reported |

`Output_Of` takes a program and **up to three arguments** — five in total is
refused, and the diagnostic says `1 .. 4`. The trailing newline is dropped,
which is the convention every shell follows and the reason `cd (Output_Of
("pwd"))` works; only from the end, so what is in the middle is what the program
wrote. Standard error is not collected: a program explaining why it failed
should be heard rather than swallowed into a value a script is about to compare.

Arguments arrive as they were written. There is no word-splitting and no
re-scanning of what a `String` holds, so one argument with a space in it is one
argument.

`Status` is 0 before anything has run, and afterwards is the one exit-status
model the shell itself exits with: what an external program chose, 126 for
something found and not executable, 127 for something not found, 128 + n for a
program a signal killed.

## The environment and the command line

| Call | Answers | Notes |
|---|---|---|
| `Env_Value (Name)` | `String` | a variable children would inherit |
| `Argument_Count` | `Integer` | how many arguments the script was given |
| `Argument (Position)` | `String` | one of them, from one |

A name that was never set reads as the empty string rather than failing, and so
does an argument position that was not given. A predicate that could fail would
need a second question beside every use, and the useful answer is the same
either way.

## Paths

| Call | Answers | Notes |
|---|---|---|
| `Exists (Path)` | `Boolean` | whether anything is there |
| `Is_Directory (Path)` | `Boolean` | whether it is a directory |
| `Is_Executable (Path)` | `Boolean` | whether it could be run |
| `Read_File (Path : String) return String` | what the file holds, or nothing when there is no such file |
| `Current_Directory` | `String` | where the session is, which `cd` moves |

A path nobody can reach — no such directory, nothing named at all — is not a
file, so the answer is `False` rather than a failure.

`Read_File` answers with nothing for a file that is not there, a file this shell
cannot read, a file that is not UTF-8, and a **directory** — all the same
answer, because a question has no consequences and a function that raised here
could not be written in the expression a script actually wants. `Exists` and
`Is_Directory` are how a script that cares tells them apart, and it asks before
it reads. Making the place a file goes is `make_directory`, which is a command.

## Text

| Call | Answers | Notes |
|---|---|---|
| `Trim (Whole)` | `String` | without leading or trailing spaces |
| `To_Upper (Whole)` | `String` | |
| `To_Lower (Whole)` | `String` | |
| `Index (Whole, Piece)` | `Integer` | where `Piece` starts, or **0** when it is not there |
| `Starts_With (Whole, Piece)` | `Boolean` | |
| `Ends_With (Whole, Piece)` | `Boolean` | |

`Index` answering zero rather than raising is what lets a script test before it
slices. A `String` begins at one, so zero is a position no string has.

## Time

| Call | Answers | Notes |
|---|---|---|
| `Clock` | `Float` | seconds on Ada's monotonic clock |

Monotonic rather than calendar, so a script that measures an interval measures
one whatever somebody does to the system time. `delay` and `delay until` take
the same kind of value; this language has no fixed-point type, so `Float` is
what a `Duration` is written as here.

## What is deliberately absent

No file reading or writing as functions — `write_file` and `append_file` are
commands, because writing a file changes the world and a question should not.
No string slicing beyond `S (First .. Last)` in the language itself, no regular
expressions, no formatting mini-language: interpolation and `&` are what a
script has, and `'Image` is how a value becomes text.

`internal-commands.md` describes the twenty-seven commands, and
`language-reference.md` the language they are called from.
