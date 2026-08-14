# The Adash language

Adash's command language is a defined subset of Ada 2022. This document says
what is in the subset, what each construct means here, and where the subset
ends. It is a reference: it answers *what does this do*, where `ROADMAP.md`
answers *what happened* and `CHANGELOG.md` answers *when*.

Everything here is checked. The conformance suite in `conformance/cases/` runs
each construct as a submission and compares what it printed, what it exited
with, and which diagnostics it produced — 618 cases, including every example in
`examples/`. Where this document states a rule, a case holds it; where it states
a limit, a case holds that too. A sentence here that nothing checks is a defect
in this document.

## What a submission is

A submission is a **program**. Typed at the prompt or read from a script, it is
lexed, analysed as a whole, lowered to instructions and run. A line is not a
command with arguments: it is Ada text.

    put_line ("hello");

Declarations, statements and internal commands mix freely in one submission,
and what a submission declares is carried to the next one in the session:

    X : Integer := 41;
    pwd;
    put_line (Integer'Image (X + 1));

Carried across submissions: variables with the values they ended with, types,
subtypes, subprograms, packages, generics, task types, protected objects with
their state, and exception names. Not carried: a task object or an identity of
one — a task does not outlive its master, and a submission is one.

A submission that stops early — `quit`, an unhandled exception — carries
nothing forward from that submission.

## Lexical elements

Ada 2022's lexical rules, with Ada's own reserved words. Identifiers fold for
comparison and keep their spelling for display. Comments run from `--` to the
end of the line. A construct may be written across as many lines as it takes;
the shell asks for more input until it is complete.

Numeric literals are Ada's: `42`, `1_000`, `1.5`, `16#FF#`. Character literals
are `'a'`; string literals are `"text"`, with `""` for an embedded quote.

**Interpolated strings** are Ada 2022's: `f"found {Count'Image} of them"`. The
braces take a `String`, so a number goes in through `'Image` — that is Ada's
rule rather than a limitation here, and `f"found {Count}"` is refused in terms
of the `&` the form rewrites to. A literal brace is escaped: `f"\{plain\}"`.

## Types

### The five predefined types

`Integer`, `Float`, `Boolean`, `Character`, `String`. There is no implicit
conversion between any of them: `1 + 1.0` is refused, and a value crosses only
through an explicit conversion or an attribute.

`Integer` is 64-bit. `String` is the one array type the language predefines; it
begins at one, so `S'First` is 1 and `S'Last` is `S'Length`. `S (2 .. 4)` reads
a slice and `S (2 .. 4) := "xyz"` writes one, as `S (2) := 'x'` writes one
position. What goes into a slice must be as long as the slice, which is Ada's
rule; a length that does not match is `Constraint_Error` where the assignment
stands. A part is taken of a part and of what a call yields —
`S (2 .. 5) (1 .. 2)`, `F (2 .. 4)`, `F (1) (2 .. 4)` — and positions inside a
part are that part's own, counted from one. A part of a variable is assigned to
however deep it is written; a part of what a call yielded is not, a value having
nowhere to put anything.

### Declared types

    type Verdict is (Worked, Failed, Killed);
    subtype Percent is Integer range 0 .. 100;
    type Line is record Number : Integer; Text : String; end record;
    type Counts is array (1 .. 4) of Integer;

**Enumerations** get Ada's ordering, the discrete attributes, `case` coverage
that names the type, and `for What in Verdict loop`. Two enumerations may name
one value — a literal is a parameterless function returning its own type, so it
overloads like one and the context settles which is meant.

**Subtypes** carry a range that is checked wherever a value arrives: an object's
initialisation, an assignment, an argument, a result, and on the way back out of
an `out` parameter. The bounds must be known before the program runs.

**Records and arrays** hold simple values only, get positional and named
aggregates with `others`, component selection, indexing with a bounds check,
whole-value assignment and component-by-component equality. An array's bounds
are known before the program runs and it holds at most 4096 elements.

**An array is sliced** — `A (2 .. 3) := B (1 .. 2)`, and `=` between two of
them. A slice's ends are known before the program runs, as the array's own are;
it is as long as what goes into it, checked where it is written; and it is a
place rather than a value, so it stands where a run of slots is copied or
compared and nowhere else. There is no null slice: a run of no slots is not a
value here.

A part is taken of a part — `A (2 .. 5) (1 .. 2)` and `A (3 .. 5) (2)` — and
each level is bounded by the level outside it. Positions inside a part begin
where a value of the type begins: one for a String and for an array declared
from one, and the array's own first index otherwise.

### Aggregates

    (7, 8, 9)                     -- positional
    (A => 1, B => 2)              -- a record, by component
    (1 => 7, 2 => 8)              -- an array, by index
    (1 .. 2 => 7, others => 0)    -- a run, and the rest
    (Samples'Range => 0)          -- all of them

Every part gets exactly one value. A part left out, a part named twice, an index
the array does not have, and an `others` that answers for nothing are each
refused by name. An index is a value known before the program runs. An aggregate
is a value in a declaration or an assignment, not an argument at a call.

## Attributes

Seventeen, and `'Range` beside them. On a value or a type: `'Image`, `'Value`,
`'Pos`, `'Val`, `'Succ`, `'Pred`, `'Length`, `'First`, `'Last`, `'Size`. On a
task, an entry or a protected object: `'Priority`, `'Count`, `'Identity`,
`'Terminated`, `'Callable`, `'Storage_Size`, `'Execution_Time`. `'Range` is
counted apart because it stands where a range stands rather than where a value
does.

`'Image` and `'Value` are refused for a `String`: Ada 2022 defines a String's
image as the text in quotes with non-graphic characters bracketed, which is not
the text itself. The four position attributes are defined for the discrete types.
`'Range` is `'First .. 'Last` and stands wherever a range stands. `'Count` is
asked inside the body of the unit that declares the entry.

An attribute is a **value known before the program runs**, so it may stand where
a case choice, a subtype bound or an aggregate's index stands.

`'Size` and `'Storage_Size` answer in this machine's own unit — slots, and slots
and stack — rather than in bits. That is not Ada's meaning; the number is not
comparable with a compiler's.

## Statements

Assignment, `if`/`elsif`/`else`, `case`, `loop`, `while`, `for`, `exit`,
`exit when`, `return`, `null`, `declare` blocks, and the tasking statements
below.

A **`case`** must account for every value of its type; one that misses a value is
refused rather than run. Choices are values known before the program runs, or
ranges of them, or `others`, which comes last.

A **`for` loop** counts over a range or over a named type, and over any discrete
type either way: `for I in 1 .. 5`, `for C in 'a' .. 'z'`, `for What in Verdict`,
`for I in reverse Samples'Range`. The loop parameter is a constant of its type,
scoped to the loop.

A **block** — `declare … begin … end;` — is a scope and a master: what it
declares is gone after it, and it waits for what it started.

**Membership** is `X in L .. H` and `X not in L .. H` against a range, and
`X in Small` against a type or subtype mark — the bounds are then the type's
own, and a mark that names something other than a discrete type is refused
where it stands. The value is evaluated once either way.

## Subprograms

    function Framed (Text : String) return String is
    begin
       return "> " & Text;
    end Framed;

    procedure Swap (Left : in out Integer; Right : in out Integer) is …

Modes `in`, `out` and `in out`. Named arguments and defaults: `Report (Text =>
S, Loud => True)`, `procedure P (A : Integer := 1)`, where a default is a
literal, possibly signed, or `True`/`False`. Naming works for a call to
anything: a subprogram the program declared, a predefined entity, or an
internal command.

Subprograms nest, see what encloses them, and recurse. Nineteen levels deep is
the limit, and deeper is refused by name.

**Overloading** is resolved by the number and types of the arguments and, for a
function, by what the context expects of its result. Where both ends of a
comparison or a call are open, the one type they could share settles it. Two
readings that both fit is ambiguous, as it is in Ada.

Everything is passed by reference, where Ada passes elementary types by copy. No
*correct* Ada program can tell the difference.

## Packages and generics

    package Report is
       function Say (What : Verdict) return String;
    end Report;

    package body Report is … end Report;

`P.X` reaches a member; `use P` drops the prefix for the enclosing region.

    generic type Element is private;
    procedure Swap (Left : in out Element; Right : in out Element);
    procedure Swap_Numbers is new Swap (Integer);

A generic's body is a unit of its own and is analysed at each instantiation,
because what its names mean depends on what the instantiation binds.

## Exceptions

    Wrong_Kind : exception;

    begin
       raise Wrong_Kind;
    exception
       when Wrong_Kind => put_line ("caught");
       when others     => raise;
    end;

A program declares exceptions and raises them; `raise;` inside a handler raises
again what that handler caught. The five the machine raises may be raised by
name too: `Constraint_Error`, `Program_Error`, `Storage_Error`, `Tasking_Error`,
`Index_Error`. **The list a handler may name is exactly the list that can be
raised.** A program's own exception carries no message.

## Tasking

Tasks are **interleaved, not parallel**: the machine runs one strand at a time
and changes strand at defined points. Ada does not require parallelism, and
anything platform-specific belongs to `hostkit` rather than to a second provider
of threads here.

    task Worker is entry Go (What : Integer); end Worker;
    task body Worker is
    begin
       loop
          select
             accept Go (What : Integer) do … end Go;
          or
             terminate;
          end select;
       end loop;
    end Worker;

What is here: task types and objects, discriminants with defaults, protected
types and objects, entries with barriers, entry families, the rendezvous,
`requeue` with and without `with abort`, all four `select` forms — selective
accept, conditional and timed entry calls, and `then abort` — `or terminate`,
`abort` of one task or several, masters that wait for what they started
(subprogram bodies, task bodies, blocks and accept bodies), and the task
attributes above.

Configuration pragmas: `Priority`, `Detect_Blocking`, `Restrictions`,
`Task_Dispatching_Policy`, `Priority_Specific_Dispatching`, `Queuing_Policy`,
`Locking_Policy`, and `Profile (Ravenscar)` or `Profile (Jorvik)`. A policy or a
restriction this build cannot keep is **refused rather than accepted and
ignored**.

At most fifteen tasks at once. A select offers at most thirty-two alternatives.

## The shell inside the language

Internal commands are procedures: `pwd;`, `cd ("/tmp");`, `quit (Total);`.
`internal-commands.md` describes all twenty-seven. Their
arguments are values the machine evaluates, so a command may stand inside an
`if` or a loop and take what the program computed. A command that failed does
not stop what follows it — Ada does not end a sequence because a procedure
reported a failure, and neither does `sh -c`.

`Status` is what the last program or command reported: 0, what an external
program chose, 126 for something found and not executable, 127 for something not
found, 128 + n for a program a signal killed.

Predefined entities: `Put`, `Put_Line`, `New_Line`, `Read_Line`, `Input_Ended`,
`Output_Of`, `Status`, `Argument`, `Argument_Count`, `Env_Value`, `Exists`,
`Is_Directory`, `Is_Executable`, `Clock`, `Trim`, `To_Upper`, `To_Lower`,
`Index`, `Starts_With`, `Ends_With`, and the five type names with `True`,
`False` and `Task_Id`.

Nothing at submission level may be named after a predefined entity or an
internal command. A body's own declarations are a different scope and may hide
either, which is Ada's rule.

## Where the subset ends

Everything below parses in Ada and is refused here, by name, on purpose.

- **No access types.** A shell script has nothing to point at that outlives the
  statement that made it, and a language with pointers has an aliasing question
  in every assignment.
- **No derived types**, and no representation clauses or representation
  attributes.
- **A composite holds simple values only** — no record inside a record, no array
  of records — and a function does not return one. A composite has no text form.
- **No generic packages**, and no generic formal that is not a type.
- **No child packages**, no `private` part, no renaming of a package.
- **No `goto`, no labels, no `renames`, no loop names, no user-defined
  operators, no `for … of`.**
- **No message on a raise.** `raise X with "text"` is Ada's; nothing here can
  read one back.
- **Dynamic bounds.** An array's, a subtype's and a case choice's are known
  before the program runs.
- **Tasking's edges**: a protected entry takes no parameters, an entry parameter
  is a simple value, an accept repeats the profile its entry was declared with, a
  requeue names an entry of its own unit and its target takes nothing, at most
  one delay alternative in a select, and discriminants belong to a type rather
  than to a single task or object.

`ROADMAP.md` gives the reason for each, and the two lists under *What Adash
cannot do yet* carry the rest, including what is inside the subset and
imperfect.
