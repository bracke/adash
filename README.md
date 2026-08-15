# adash

A shell whose command language is Ada.

`adash` is not a POSIX shell with Ada-looking syntax bolted on, and it is not a
Bash clone. Its command language is a deliberately defined subset of Ada, and a
feature earns its place by fitting that language — not by existing in another
shell.

Interactive input and scripts take the same route: source acquisition, UTF-8
validation, lexing, parsing, semantic analysis, evaluation. There is no separate
interactive interpreter and no separate script interpreter, so a line typed at
the prompt and a line in a script mean the same thing.

## Status

**Pre-release, and working.** All sixteen planned phases are complete, and a
second body of language work has followed them. `adash` lexes, parses, analyses
and lowers its language to p-code that runs on its own virtual machine's virtual machine; it runs
scripts and interactive sessions through the same pipeline; and it starts, waits
for and stops external programs.

```ada
procedure Greet (Who : String) is
begin
   put_line (f"hello, {Who}!");
end Greet;

function Doubled (N : Integer) return Integer is
begin
   return N * 2;
end Doubled;

Greet ("world");

Total : Integer := 0;
for Step in 1 .. 4 loop
   Total := Total + Doubled (Step);
end loop;

put_line (f"total:{Total'Image}");

cd ("/tmp");
pwd;
```

```
hello, world!
total: 20
/tmp
```

That is one submission: declarations, a subprogram, a function, a loop, an
interpolated string literal, `'Image`, and two of the shell's own commands —
analysed together and run together.

What the language has: the five scalar and string types, with a String that can
be indexed, sliced and measured; declarations, named numbers
(`Max : constant := 100;`), assignment and the operators; explicit conversion
between the numeric types, `Integer (F)` and `Float (I)`, since nothing here
converts quietly; `if`, `case`, `while`, `for`, bare `loop` with
`exit`, and `return`; conditional expressions, `(if A then B else C)` and
`(case X is when 1 => A, when others => B)`; `for I in reverse L .. H`;
membership, `X in L .. H`, `X not in L .. H` and `X in Small` against a type
mark; `declare ... begin ... end;` blocks with exception handlers, `Wrong_Kind :
exception;` and `raise`; subprograms with `in`, `out` and
`in out` parameters, recursion,
nesting, overloading, named arguments, default parameters and separate
specifications; qualified expressions, `Small'(Red)` and `Row'(1, 2)`; Ada 2022 interpolated
string literals with the whole escape set; `'Image` and `'Value` in both directions; `'Pos`, `'Val`, `'Succ` and `'Pred`,
and a scalar type's own `'First` and `'Last`. Internal commands are callable from a
program like any other subprogram.

Six things reach outside the program. `Exists`, `Is_Directory` and
`Is_Executable` ask about a path, which is what a script does before it acts on
one. `Read_Line` reads a line of the shell's
own input, so a script at the end of a pipe can see what it was given, and
`Input_Ended` says when there is no more. `Env_Value` reads the environment:
`cd (Env_Value ("HOME"))`. `Output_Of` runs a program and answers with what it
wrote, so `Version : String := Output_Of ("git", "describe")` is writable.
`Status` is what the last command did, on the one exit-status scale the shell
itself exits with, so `run ("make"); if Status /= 0 then` is writable -- and so
is a subprogram that answers the question. `Argument_Count` and `Argument` are
what a script was invoked with, which is what makes `adash build.adash release`
a tool somebody can call. All four answer with ordinary values: a String
concatenates, an Integer does arithmetic.

`write_file (Report, "out.txt")` saves what a script worked out, and
`append_file` adds to the end of a file. They are commands rather than
functions on purpose: asking about a path has no consequences and belongs in a
condition, and writing has consequences and belongs where a reader sees it
happen.

`source ("greeting")` finds a script beside the one asking for it, or in your
own module directory; `source ("./setup.adash")` is a path and is used as
written.

A program declares its own types: `type Verdict is (Worked, Failed, Killed);`,
`subtype Percent is Integer range 0 .. 100;`, `type Line is record Number :
Integer := 0; Text : String; end record;`, `type Counts is array (1 .. 4) of
Integer;` and `type Line is array (Integer range <>) of Integer;` for one whose
values carry their own length. An array type is also written where an object's
type mark stands — `A : array (1 .. 3) of Integer;` — which is Ada's anonymous
array type. An enumeration gets Ada's ordering, all eight discrete attributes,
`case` coverage that names the type, and `for What in Verdict loop`; a
subtype's range is checked wherever a value arrives, including on the way back
out of an `out` parameter; a record and an array both get aggregates positional
and named — by component and by index — with `others` for the rest, aggregates
as arguments at a call, a component that says what it holds where nothing else
does, component selection, indexing with a bounds check, slices, whole-value
assignment and component-by-component equality.

`package Report is ... end Report;` groups declarations under a name, with its
body as a separate unit and `use Report;` to drop the prefix; `generic type
Element is private; procedure Swap (...);` writes one body for several types,
and `procedure Swap_Numbers is new Swap (Integer);` makes one.

`task Worker; task body Worker is ... end Worker;` runs beside the script, and
the script waits for it; `protected Tally is ... end Tally;` is how two tasks
share what they touch, with entries that wait on a barrier. Interleaved rather
than parallel, and inside the machine rather than on threads — hostkit owns
anything platform-specific, and a second provider of threads is not on.

`pragma Detect_Blocking;` catches an operation that may wait run inside a
protected operation and `pragma Restrictions (No_Abort_Statements);` is a
program forbidding itself something;
`pragma Task_Dispatching_Policy (FIFO_Within_Priorities);` gives a strand its
turn until it waits for something rather than sharing the processor out,
`pragma Priority_Specific_Dispatching (FIFO_Within_Priorities, 20, 30);` says
that of a range of priorities instead of all of them,
`pragma Queuing_Policy (Priority_Queuing);` takes the highest-priority caller
off an entry queue first rather than the one that arrived first,
`pragma Locking_Policy (Ceiling_Locking);` is a program saying what this
machine already does, and `pragma Profile (Ravenscar);` — or `(Jorvik)`, which
gives four of its restrictions back — is the name for all of it at once; `delay 0.2;` waits in real time and `delay until Clock + 0.2;` waits for a time
rather than a length; `T'Execution_Time` is how long a task has had turns for; `or terminate;` lets a server task end when nobody is left who could call it;
`select E; … else … end select;` takes a protected entry only if its barrier is
open and a task's entry only if the task is waiting to take it, `or delay D;`
bounds the wait — on a task's entry too, where the call joins the queue with a
deadline and leaves it if nobody comes — and `abort T;` stops
a task. `pragma Priority (20);` says what a task runs at and what a protected object's
ceiling is; `T'Priority` reads it back and `T'Priority := 28;` changes it; `X'Size` is how many slots a value
takes and `T'Storage_Size` how much room a
task is given, both in this machine's own unit; `T'Identity` is which task,
kept in a `Task_Id`; `T'Terminated` and
`T'Callable` are what a task — or an identity of one — says about itself, and
`E'Count` is how many callers are queued at an entry; `requeue E;` moves the
caller being served to another entry's queue without letting it go; and
`entry Request (Priority);` is a *family* — one entry per value, so a task can
choose what to serve rather than only when, and `requeue Later (Which);` moves a
caller to one of them.

A task's entry is met rather than called: `task Server is entry Put (Which :
Integer); end Server;` with `accept Put (Which : Integer) do … end Put;` in its
body, and `Server.Put (5);` on the other side. Neither side passes the meeting
until both have reached it, callers queue in the order they arrived, and an
`out` parameter is how a task hands something back.

`protected type Tally (Called : String := "a tally") is … end Tally;` is a
protected object worth having more than one of, each with state and a lock of
its own — and a discriminant that defaults is one an object need not give; and
`task type Worker (Id : Integer) is … end Worker;` is a task worth having more
than one of: each object is a task of its own, with its own state and its own
entry queues, and discriminants are what it takes at elaboration where a
subprogram takes parameters at a call. `select accept A; … or when Ready =>
accept B; … end select;` is a task saying whichever of these happens first, with
`else` for not waiting at all and `or delay D;` for waiting a bounded time; and
`select … then abort …  end select;` abandons work when something else happens
first.

Overloading is resolved by what a context expects and, where both ends of a
comparison or a call are open, by the one type they could share.

`docs/language-reference.md` is the reference for all of it: what is in the
subset, what each construct means, and where it ends.

What the subset leaves out, deliberately: access types, composites inside
composites, derived types, generic packages and generic formals that are not
types, child packages and `private` parts, a message attached to a raise,
`goto` and labels, `renames`, loop names, user-defined operators, `for ... of`,
and representation clauses. `ROADMAP.md` says why for each.

A construct may be written across as many lines as it takes: the shell asks for
more until the grammar says the program is whole, and a mistake is reported at
once rather than waited on.

A subprogram declared on one line is callable on the next, and a variable keeps
the value it ended with, so an interactive session builds up a vocabulary and a
state.

What the shell has: `cd`, `pwd`, `set`, `unset`, `env`, `quit`, `version`,
`help`, `history`, `forget`, `source`, `run`, `run_into`, `run_append`, `run_new`,
`run_from`, `pipe`, `pipe_run`, `write_file` and `append_file`, and job control
through `start`, `jobs`, `wait`,
`stop`, `suspend` and `resume`; `settings` and `save_settings` for its own
configuration — every one of them working, none registered-but-missing.
Line editing with completion — of commands, keywords, paths, and of programs on
the search path where one is named — and highlighting, history that survives the
session and leaves out a line typed with a space in front of it, TOML
configuration, cancellation with Ctrl-C, and a conformance suite that runs the
built binary from the outside.

**Nothing here claims a capability it does not have.** What is missing is written
down rather than implied: see *What Adash cannot do yet* in
[ROADMAP.md](ROADMAP.md), and the same list in
[CHANGELOG.md](CHANGELOG.md).

## Quick start

Requires [Alire](https://alire.ada.dev/) and a GNAT toolchain.

```
alr build                     # build the shell
./bin/adash                   # an interactive session
./bin/adash script.adash      # run a script
echo 'put_line ("hi");' | ./bin/adash

cd adash_tests
alr build
./bin/adash_tests             # the AUnit suite
./bin/adash_check             # the repository invariants
./bin/adash_conformance       # the conformance cases, against the built binary
```

## Design rules

Seven capabilities are owned by other crates, and Adash may not reimplement any
of them. This is not a preference — each rule names one place a capability
lives, so a second, subtly different copy cannot grow inside the shell.

| Capability | Provider |
|---|---|
| Anything that differs because the operating system differs | `hostkit` |
| Every string a user reads | message catalogs, via `messages` |
| Terminal styling | `terminal_styles` |
| JSON | `jsonlib` |
| TOML | `tomllib` |
| Repository tooling | `project_tools`, in Ada |

When one of those crates lacks something Adash needs, the answer is to extend
that crate — never to write a private version here. A private version is always
faster to write and always the more expensive of the two.

`adash_check` enforces the ones that can be checked mechanically: no Adash source
may name `GNAT.OS_Lib`, `Interfaces.C` or `System.OS_Interface`, and none may
write a terminal escape sequence of its own.

## Repository layout

```
src/library/       the shell
src/main/          the thin executable entry point
resources/messages every user-visible string
docs/              reference documentation
examples/          executable, verified examples
benchmarks/        Ada benchmark programs
conformance/       implementation-independent conformance cases
adash_tests/       AUnit suites and every repository tool
```

Runtime code and tooling are separate crates so that no tool is reachable from
the shell binary, and so AUnit and `project_tools` are never dependencies of the
thing users install.

## Documentation

- [ARCHITECTURE.md](ARCHITECTURE.md) — subsystems, ownership, dependency direction
- [ROADMAP.md](ROADMAP.md) — the phases, what followed them, and what is still missing
- [CHANGELOG.md](CHANGELOG.md) — what changed, and the known limitations
- [CONTRIBUTING.md](CONTRIBUTING.md) — build, test and review workflow
- [STYLE_GUIDE.md](STYLE_GUIDE.md) — Ada style and project conventions
- [SECURITY.md](SECURITY.md) — reporting, and a shell's own risk model
- [AI.md](AI.md) — deterministic instructions for coding assistants
- [docs/](docs/) — reference documentation index

## Licence

MIT. See [LICENSE](LICENSE).
