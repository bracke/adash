# Roadmap

Sixteen phases. Every phase leaves the repository buildable, its tests green and
`adash_check` passing. A phase is not "done" because its code compiles — see the
definition of done at the bottom.

## Where we are

**All sixteen phases are complete**, and a second body of work has followed them.
Two tables, because they answer different questions: the first is the plan and
whether it was carried out, the second is what the language grew afterwards. A
tick in either says a thing was built, tested and written about -- what is *not*
built is under *What Adash cannot do yet*, in words rather than by omission.

| # | Phase | Status |
|---|---|---|
| 1 | Repository bootstrap, manifests, GPRs, layout, root packages, test crate, tooling and documentation skeletons | **complete** |
| 2 | Source model, diagnostics, structured results, version, message identifiers, terminal style roles | **complete** |
| 3 | Language values, types, symbols, scopes, immutable core models | **complete** |
| 4 | Lexer and source mapping | **complete** |
| 5 | Adash parser and syntax representation (no HAC) | **complete** |
| 6 | Semantic analysis | **complete** |
| 7 | Evaluation: lowering to machine instructions, then interpretation | **complete** |
| 8 | Predefined values, functions, procedures, constructors, metadata registration | **complete** |
| 9 | Internal command framework and internal commands | **complete** |
| 10 | Platform adapter over hostkit | **complete** |
| 11 | External execution, streams, redirection, pipelines, cancellation, signals, jobs, exit status | **complete** |
| 12 | Engine orchestration | **complete** |
| 13 | Scripting and startup processing | **complete** |
| 14 | Interactive frontend: prompt, editing, completion, highlighting, history, notifications | **complete** |
| 15 | Persistence and configuration migration | **complete** |
| 16 | Conformance completion, stress testing, performance characterization, documentation, release engineering, reproducibility | **complete** |

### Since the sixteen phases

The plan above is finished. What followed is language and shell surface the
sixteen phases did not call for, tracked here because "all phases complete" says
nothing about it. Each row is described in full under *What the language gained*
below.

| Work | Status |
|---|---|
| Internal commands callable from a program, with arguments | **complete** |
| `put_line` for String, Character, Boolean and Float | **complete** |
| `abs`, unary minus, Float arithmetic | **complete** |
| Bare `loop` with `exit`, and `return` | **complete** |
| Cancellation: the machine polls, Ctrl-C requests it | **complete** |
| A program that raises reports it | **complete** |
| Declared subprograms: procedures, functions, recursion | **complete** |
| Parameter modes `in`, `out`, `in out` | **complete** |
| Nested subprograms | **complete** |
| Overloading by arguments, and by result type from context | **complete** |
| Separate subprogram specifications, and mutual recursion | **complete** |
| `'Image` | **complete** |
| Interpolated string literals and Ada 2022's escape set | **complete** |
| `for` evaluates its bounds once, and stops at the largest value | **complete** |
| `source` | **complete** |
| Running a program and waiting for it: `run` | **complete** |
| Redirection: `run_into`, `run_append`, `run_new`, `run_from` | **complete** |
| Pipelines: `pipe`, `pipe_run` | **complete** |
| Reading a value from outside the program: `Env_Value` | **complete** |
| Acting on whether a command worked: `Status` | **complete** |
| A script reading its own arguments: `Argument_Count`, `Argument` | **complete** |
| The `case` statement | **complete** |
| A construct written across several typed lines | **complete** |
| Reading a program's output as a value: `Output_Of` | **complete** |
| Taking a String apart: indexing, slicing, `'Length` | **complete** |
| The block statement: `declare ... begin ... end;` | **complete** |
| Names below the presentation boundary said in words | **complete** |
| Suspending and resuming a job: `suspend`, `resume` | **complete** |
| Showing and changing the shell's own settings: `settings` | **complete** |
| `source` finding a script by name | **complete** |
| Reading the shell's own input: `Read_Line`, `Input_Ended` | **complete** |
| Reading a value back from text: `Integer'Value` | **complete** |
| Asking about a path: `Exists`, `Is_Directory`, `Is_Executable` | **complete** |
| Saving what a script computed: `write_file`, `append_file` | **complete** |
| Counting backwards: `for I in reverse L .. H` | **complete** |
| Membership: `X in L .. H`, `X not in L .. H` | **complete** |
| Tasks: `task T;` and `task body T is ... end T` | **complete** |
| `delay`, in real time | **complete** |
| `select` on a protected entry, conditional and timed | **complete** |
| `abort` | **complete** |
| Protected objects, with entries and barriers | **complete** |
| Task entries and rendezvous: `accept E (…) do … end E;` | **complete** |
| Task types, and objects of them | **complete** |
| `select` with several accept alternatives, guarded | **complete** |
| `select ... then abort` | **complete** |
| Task discriminants: `task type W (Id : Integer)` | **complete** |
| A master waits per region, not per submission | **complete** |
| Block statements as masters | **complete** |
| Accept bodies as masters | **complete** |
| Task attributes: `T'Terminated`, `T'Callable` | **complete** |
| Entry attribute: `E'Count` | **complete** |
| `T'Identity`, `Task_Id`, and limited task and protected types | **complete** |
| `'Size` and `'Storage_Size`, in slots | **complete** |
| `pragma Priority`, `'Priority`, and a priority model | **complete** |
| Dynamic priorities: `X'Priority := N;` | **complete** |
| `Clock`, `delay until`, and `T'Execution_Time` | **complete** |
| `pragma Detect_Blocking` and blocking-operation checks | **complete** |
| `pragma Restrictions`: most of the Ravenscar profile | **complete** |
| `pragma Task_Dispatching_Policy` and `pragma Locking_Policy` | **complete** |
| `pragma Priority_Specific_Dispatching`, per range of priorities | **complete** |
| `pragma Queuing_Policy`, and an entry queue with an order | **complete** |
| A bounded call to a task entry: `select E; or delay D;` | **complete** |
| A conditional call to a task entry: `select E; else ...` | **complete** |
| `or terminate;`, and the master condition behind it | **complete** |
| `pragma Profile (Ravenscar)` and `pragma Profile (Jorvik)` | **complete** |
| Protected types, and objects of them | **complete** |
| Protected type discriminants | **complete** |
| Discriminant defaults, and unconstrained objects | **complete** |
| `requeue`, for a task entry and a protected one | **complete** |
| Entry families: `entry Request (Priority);` | **complete** |
| Protected entry families: `entry Pass (for I in T) when …` | **complete** |
| Packages: `package P is ... end P` and its body | **complete** |
| `use P;` | **complete** |
| Generic subprograms and instantiation | **complete** |
| Records: `type Line is record ... end record` | **complete** |
| Arrays: `type Counts is array (1 .. 4) of Integer` | **complete** |
| Aggregates, positional and named | **complete** |
| Enumerations: `type Colour is (Red, Green, Blue)` | **complete** |
| Subtypes with a range: `subtype Percent is Integer range 0 .. 100` | **complete** |
| `for X in T loop`, over any discrete type | **complete** |
| Named arguments and default parameters | **complete** |
| Position attributes: `'Pos`, `'Val`, `'Succ`, `'Pred` | **complete** |
| A scalar type's own bounds: `Integer'First`, `Integer'Last` | **complete** |
| Adash's own virtual machine; the HAC dependency ended | **complete** |
| Exception handlers on a block and on a body | **complete** |
| Job control: `start`, `jobs`, `wait`, `stop` | **complete** |
| Display width in cells, for wide and combining characters | **complete** |
| Long lines wrap instead of scrolling | **complete** |
| Per-session history, merged on exit and swept after a crash | **complete** |
| `history` | **complete** |
| `alias` | **retired, see below** |
| Declarations carried from one submission to the next | **complete** |


Phase 2 is complete: `Adash.Version`, `Adash.Messages`,
`Adash.Messages.Rendering`, `Adash.Terminal`, `Adash.Errors`, `Adash.Source` and
`Adash.Diagnostics`.

`Adash.Source` is what Phases 4 to 7 will rest on. Text is immutable once
loaded; offsets index the original bytes rather than a normalized copy; the line
map treats CR LF, a lone LF and a lone CR as one terminator each without
rewriting anything; columns count characters, not bytes; and malformed UTF-8 is
refused once, at acquisition, with the offset of the first bad byte — rather
than by whichever consumer first trips over it and reports a lexical error for
what is really an encoding problem. Overlong encodings, surrogate halves and
sequences past U+10FFFF are refused with the rest.

`Adash.Diagnostics` carries identity, severity, category, owner, span, typed
arguments and related locations — never a sentence. Ordering is canonical and
stable: source name, position, severity worst-first, message identifier, then
emission order, so two runs over one input produce the same list.

Phase 3 is complete: `Adash.Language` roots the subsystem, and `.Types`,
`.Values`, `.Symbols` and `.Scopes` are the immutable core models the rest of it
will be built on. Three decisions are locked by tests because they are the sort
of thing users write programs against and would be expensive to change later:

- The type set is Ada's and small — Boolean, Integer, Float, Character, String,
  plus `Type_None`. **No implicit conversion**, including the numeric widening
  Ada itself allows.
- Equality across types is `False`, not a refusal; ordering across types *is* a
  refusal. A user asking whether `1 = "1"` deserves an answer; there is no
  reason an Integer should sort before or after a String.
- Names fold case-insensitively, as Ada's do, and keep the user's spelling for
  diagnostics. A duplicate in one scope is refused with the position of the
  first declaration; a redeclaration in an inner scope is legal, hides the outer
  one, and restores it on leaving.

Phase 4 is complete: `Adash.Language.Tokens` and `Adash.Language.Lexer`. The
lexer is deterministic and locale-independent — `Ada.Characters.Handling`, never
the C library, so a name is not a letter in one country and not in another — and
it recovers rather than stopping, because the interactive frontend lexes text a
user is *still typing* and has to highlight the finished part of it.

Ada's lexical corners are each pinned by a test, since a plausible
implementation of any of them is quietly wrong rather than loudly:

- **The apostrophe** is a character-literal quote or an attribute marker
  depending on the previous token. `X'Image` and `'a'` and `'''` all lex
  correctly. The rule needs the previous token and nothing more, so it is
  context without being semantics.
- **`1..5` is a range**, not a malformed real. The dot only starts a fraction
  when a digit follows.
- **Longest match** on all ten compound delimiters: `:=` is never a colon and an
  equals sign.
- **Underscores** are legal between digits and between identifier characters,
  never leading, trailing or doubled.
- **Strings** keep their source form *and* their undoubled value, so a formatter
  can reproduce the text and an evaluator can read the meaning.

Comments are tokens the parser skips rather than whitespace the lexer discards:
a highlighter colours them and a formatter has to put them back. Whitespace is
not a token — it is the gap between adjacent spans.

Identifiers are ASCII, deliberately. Ada 2022 allows any script, but comparing
two identifiers then needs Unicode case folding, which is locale-sensitive in
the corners; a language where two names are equal on one machine and not another
is worse than one that says ASCII and means it. Non-ASCII is fine wherever it is
data — strings, character literals, comments.

Phase 5 is complete: `Adash.Language.Syntax` and `Adash.Language.Parser`, and
no HAC is involved — as the assessment decided, it enters at Phase 7.

**Nodes live in an arena and are addressed by index.** That is the decision the
rest of the tree follows from. A `Node_Id` is a stable key, so the semantic pass
annotates through a side table it owns and the tree never learns about — a tree
with an annotation field is one every later pass writes into, after which no
reader can tell which pass a value came from. Children are a contiguous slice,
so traversal is a loop over integers and two walks visit the same nodes in the
same order.

The parser is recursive descent over Ada's precedence levels, and the tests
assert the *shape* of the tree rather than that parsing succeeded — a parser
with precedence wrong does not fail, it computes a different answer:

- `1 + 2 * 3` groups as `1 + (2 * 3)`; `10 - 3 - 2` groups left, giving 5 rather
  than 9.
- Parentheses are kept rather than folded away: a formatter has to reproduce
  them.
- **Mixing `and` with `or` without parentheses is refused**, as Ada requires.
  The two have equal precedence there, so `a or b and c` has no reading a user
  could rely on; every language that answers it with a precedence rule has users
  who remember that rule wrongly.
- `and then` and `or else` are their own operators, not flags on `and` and `or`:
  they short-circuit, which is a difference in meaning.
- An `elsif` becomes a nested if, so every later pass has one shape to handle.
- Recovery reports once per construct and skips to something that reliably
  starts a statement, so one missing semicolon does not produce a cascade.

The parser is syntax only. Whether `X (1)` is a function call or an array index
is a semantic question — Ada spells both the same way — and a parser that
guessed would be doing name resolution.

Phase 6 is complete: `Adash.Language.Semantics`. It walks the tree, builds
scopes with the Phase 3 chain, resolves names to symbols, gives every expression
a type, and checks the language's static rules.

**It never mutates the tree.** Every conclusion goes into a side table keyed by
`Node_Id` — which is what the arena in `Adash.Language.Syntax` was for. A pass
that wrote into the tree would leave no way to tell which pass a value came
from, and no way to run analysis twice on one tree, which an interactive session
does every time a line is edited.

The rules it enforces, each pinned by a test on real programs:

- **No implicit conversion.** `X : Float := 1;` is refused, and so is mixed-type
  arithmetic. Ada itself would widen; Adash does not, because a quiet widening
  has a rounding rule nobody wrote down.
- **No truthiness.** A condition must be Boolean. `if X then` with an Integer X
  is refused rather than given a meaning the language does not state.
- **Constants cannot be assigned to**, and a `for` loop parameter is a constant,
  as Ada says — and it is gone after its loop.
- **A type name is not a value.** `X := Integer;` parses and is illegal, which is
  what `Symbol_Type` exists to tell apart.
- **One unknown type does not cascade.** An expression whose type could not be
  determined gets `Type_None`, which suppresses further complaints about it — a
  pass that blamed each operator would bury the one thing to fix.
- **A tree that did not parse is not analysed at all**, because the diagnostics
  would be about the recovery rather than the program.

Parameter association — matching arguments to formals and checking their types —
waits for Phase 8, which introduces the first callable things with profiles.
Until something has one, there is nothing to check against.

Phase 7 is complete: `Adash.Language.Evaluation`, the only package that reaches
into HAC. An Adash program is lexed, parsed, analysed, lowered to p-code and run
on HAC's virtual machine.

Lowered *at that point* — this section records what each phase left behind, not
what the language does now; see "What the language gained" below for that:
Integer, Boolean and Character; declarations and assignment;
arithmetic, comparison and logical operators; `if`/`elsif`/`else`; `while` and
`for` loops; and the short-circuit operators, which are emitted as jumps rather
than as operands so the right side genuinely does not run.

Not lowered, and reported as `Not_Lowerable` rather than refused — the program
is legal and Adash is incomplete, which is a different thing to tell a user:
Float and String, `abs`, bare `loop` with `exit`, `return`, procedure calls and
attributes. Each names the construct in its diagnostic.

Two limitations recorded where they were, rather than left to be discovered:

- A `for` loop re-evaluates its upper bound each turn. Ada evaluates the range
  once, so this is only correct while the bound is a literal or a variable the
  body does not change. Fixing it needs a slot allocator that can name
  temporaries.
- A bare `loop` needs its `exit` statements to jump past the loop's end, and the
  emitter has nowhere to record where that will be. It needs a stack of open
  loops with their pending jumps — which `while` does not need, because its test
  is at the top.

Phase 8 is complete: `Adash.Predefined`. It owns the entities that exist before
a program declares anything — the type names, the Boolean literals, and
`Put_Line`, `Put` and `New_Line` — and owns their *metadata* as much as the
names: signature, side effects, documentation key, completion description key,
availability. Each is a field rather than a convention, so an entity added
without them does not compile.

Registration order does not matter, and a test asserts it rather than the
comment claiming it.

It closes two loops left open earlier:

- **Calls are checked against real signatures.** Phase 6 deferred parameter
  association for want of anything with a profile; `Put_Line (N, N)` and
  `New_Line (1)` are now refused with the count they expected.
- **A program can write its output.** `N : Integer := 6 * 7; Put_Line (N);`
  prints `42`. That replaces division by zero as the way to observe a run,
  which is what the evaluation tests had to use.

Semantics no longer seeds its own predefined names; that list is gone rather
than duplicated, so there is one answer to what is predefined.

Writing is Integer-only so far. Boolean, Character and String each have their
own count of format parameters that HAC's runtime reads from the stack, and
String is pushed as an address and a length; a `Put_Line` of those reports
`Not_Lowerable` rather than pushing the wrong number of values, which would
misalign the stack rather than fail.

Phase 9 is complete: `Adash.Commands`, `Adash.Commands.Builtins` and
`Adash.Execution.Internal_Commands`.

**Commands produce data, not text.** Each output line is a message identifier
and typed arguments, exactly as a diagnostic is, and the frontend renders it.
That is what lets `pwd` be asserted on by identity rather than by comparing
strings, be written to a log as data, and be translated — and it is why
`Adash.Commands` has no dependency on the catalog.

Implemented: `cd`, `pwd`, `exit`, `set`, `unset`, `env`, `jobs`, `help`,
`version`. Registered and reported as **not in this build**: `history`, `alias`
and `source`, each needing a subsystem that does not exist yet. That distinction
matters to a user — a missing feature is not a typo — and only the shell knows
which it is.

Three decisions worth stating:

- **An internal command wins over an external program of the same name.** A `cd`
  on PATH does not shadow the shell's own; a shell where it could would be one
  where installing a program changes what a script means.
- **The working directory is not in the shell state.** `cd` changes the
  process's own and `pwd` asks the process, so there is one answer rather than a
  copy that drifts — and a child inherits the real one without being told.
- **`exit` records a request rather than ending the process.** A command that
  halted would take the decision away from whoever is driving the session: a
  script, a test, or the interactive frontend.

`set` changes what children inherit, not the shell's own environment. A test
asserts the shell's is untouched.

`jobs` reports an empty list, honestly: `Adash.Execution.Jobs` exists and works,
but nothing owns a session that holds one until the Engine does.

Phase 12 is complete: `Adash.Engine`. It is the join — the first package that
can be used the way a shell is used: submit source, get a result. A session
carries the environment, the exit request and the cancellation token between
submissions.

**How a submission is classified.** Source is lexed and parsed once, and the
*tree* decides what it was: a sequence whose statements are all calls to
internal commands goes to `Adash.Commands`; anything else is analysed and run.
One lexer, one parser, one tree — `pwd;` is an ordinary Ada procedure call and
is parsed as one. What differs is only who executes it, which is exactly the
difference between a command that must change this process and a program that
must not.

Two findings from building it, both from tests rather than review:

- **`exit` cannot be a command.** It is Ada's loop-exit keyword, so the parser
  makes `exit;` an exit statement before anything could decide it was a
  command. The command is spelled `quit`. A shell whose language is Ada does not
  get to take that word back, and a parser guessing which was meant would be the
  second dialect this project exists to avoid.
- **Command output accumulates within a submission.** `Execute` used to clear
  it, so `pwd; version;` left only the version. Clearing belongs to the caller,
  once per submission, which is the unit a user thinks in.

A limitation stated rather than hidden: a submission may not *mix* commands with
statements. `pwd; N : Integer := 1;` is refused with its own diagnostic, because
a command runs in this process while statements are lowered together into one
activation record, and splitting a submission would give the statements two.
Unifying them means teaching the language to declare commands, which is a
language design question rather than an engine one.

The engine renders nothing. It returns identities, statuses and diagnostics, and
the frontend turns them into text — which is what lets a script run silently, a
test assert on outcomes, and the interactive shell decide where output goes,
from one engine rather than three.

Phase 13 is complete: `Adash.Scripting`, `.Modules` and `.Startup` — and the
`adash` binary now runs a script:

```
$ adash demo.adash
42
15
1
```

A script goes through the same engine an interactive line will. There is no
script interpreter and there will not be one.

**Startup policy, stated because it only matters on a bad day.** System, then
user, then session — later files win where they disagree, which is the order
users expect. A missing file is silent; most machines have no system file and
most users have none. An unreadable or failing one is reported and **startup
continues**, because refusing to start over a broken startup file leaves a user
without the tool they would fix it with. The session file is interactive-only:
running it for a script would make that script mean different things depending
on who ran it.

**Module resolution is predictable and unsearchable.** A name with a separator
is a path, used as written — `./setup` runs the one here. A bare name is found
beside the loading script first, so scripts that ship together find each other
without knowing where they were installed, then in the user's module directory.
There is no search path from the environment: a resolution a spawned process can
change is one where a script silently loads the wrong file.

**A script is one submission**, so it inherits the engine's rule that a
submission is commands or statements and not both. That means a file of commands
or a file of program. Stated here because a user will meet it.

Two things remain out of reach and are recorded rather than worked around. The
`source` command needs the scripting subsystem, which sits *above* commands in
the layering, so the dispatch has to come from above — the same inversion that
makes a mixed submission hard. And because nothing can yet load anything, the
cycle *refusal* cannot be reached from a test; what is tested is the chain
discipline it depends on.

Phase 10 is complete: `Adash.Platform` answers capability questions and turns
host refusals into `Adash.Errors` codes. It adds no platform code — there is
still no `src/platform` in this repository, and `adash_check` fails the build if
a source names `GNAT.OS_Lib`, `Interfaces.C` or `System.OS_Interface`.

Phase 11 is complete. `Adash.Execution` owns the one exit-status model;
`.Streams` makes descriptor ownership part of the type, which is what keeps a
pipeline from hanging; `.Environment` builds a child's environment as a value;
`.Commands` is the invocation model; `.External` resolves and starts;
`.Redirection` plans and validates before it opens anything; `.Pipelines` wires
the stages, with starting separated from waiting so a background job is
expressible; `.Cancellation` is sticky task-safe state; `.Signals` is the
shell's own policy; and `.Jobs` tracks identity, lifecycle and what has not yet
been reported.

Two things the phase does *not* include, which belong elsewhere and are not
oversights:

- **`Adash.Execution.Internal_Commands`** needs the registry in `Adash.Commands`,
  which is Phase 9. Dispatch has nothing to dispatch to until then.
- **Reporting a finished job to the user.** `Jobs` records that a change is
  unreported and offers it once; deciding when and where to print is
  `Adash.Interactive.Notifications`, Phase 14. Printing from `Jobs` would
  corrupt a half-typed line.

Nothing yet calls any of this: the language pipeline that would build an
`Invocation` from what a user typed is Phases 4 to 7, and `Adash.Engine` is
Phase 12. The subsystem is exercised by its tests, which construct invocations
directly.

Phase 14 is complete: `Adash.Interactive` and its seven children, and the loop
wired into `adash_main`. Running `adash` with no arguments is now a shell you
can sit in front of.

Each child is a model that can be tested without a terminal, which is the whole
reason they are separate: a frontend whose logic only runs under a real terminal
is one whose logic is never tested, and the interactive path is where a shell
spends its life. Sixteen tests cover the models; the reader itself is not
covered, because a test that faked a terminal would be testing the fake.

- `.Prompt` builds a prompt from parts rather than from a format string. A
  format string would be a second small language — its own escapes, its own
  errors, its own documentation — inside a shell whose whole point is that it
  has one language. The failure marker is text, never colour alone.
- `.Editing` is a line buffer, a key decoder and a reader. Positions are byte
  offsets and movement is by character, so the cursor never lands inside a
  UTF-8 character; the decoder reports "not enough bytes yet" rather than
  guessing at a split escape sequence; and no byte below a space is ever
  inserted as text.
- `.History` keeps failed lines, because a user recalling the last line usually
  wants the one they got wrong. Consecutive duplicates collapse; a
  non-consecutive repeat is kept. A line marked sensitive is recorded nowhere at
  all, not even as a placeholder.
- `.Completion` is deterministic and ordered by source, never by score, and
  never evaluates the line. With more than one candidate it inserts as much as
  is certain and lists the rest.
- `.Highlighting` runs off tokens rather than a tree, so a line being typed —
  unfinished by definition — is still coloured.
- `.Notifications` holds news until a quiescent point: after a submission and
  before the next prompt. Printing as it arrives would write over the line the
  user is typing, and that line is the one thing on screen that is theirs.
- `.Session` is the loop and the presentation boundary. Diagnostics and command
  output arrive as identifiers and become sentences here, once.

Two things this phase found, both of which were bugs that would have been hard
to see later:

- A `Buffer` whose private components were named `Text`, `Length` and `Cursor`
  shadowed its own accessors. Component selection beats a primitive operation of
  the same name, so `Line.Text` silently returned the whole fixed-size component
  — padding and all — rather than the trimmed string. The components are now
  `Content`, `Used` and `Point`.
- Bytes read but not yet decoded were held in a variable local to `Read_Line`,
  so everything after the newline it returned on was discarded. Type-ahead and
  the second line of a paste vanished silently. The buffer is now process-wide,
  as standard input is.

`Hostkit.Terminal_Control` gained cursor control — erase, column, movement,
hide and show — expressed as actions rather than bytes, so no caller ever holds
an escape sequence. Cursor movement is terminal control, not styling, so it
belongs to hostkit rather than to `terminal_styles`. Entering raw mode was also
changed from `TCSAFLUSH` to `TCSADRAIN`: flushing looks tidy and is data loss,
because a shell entering raw mode for each line would throw away everything the
user typed while the previous command was still running.

Known limits, recorded rather than left to be discovered:

- Display width is one cell per character. A line of East Asian text redraws
  wrongly, because getting it right needs character-property tables this crate
  does not have. *(Fixed since: see `Adash.Display_Width` below.)*
- Long lines scroll horizontally rather than wrapping. A wrapped line cannot be
  redrawn without knowing how many rows it took, and the terminal will not say.
- History is in memory only within a session. It is loaded at start-up and
  appended to as lines are entered — see Phase 15.
- The completion list shows names without their descriptions, because a
  description is a message identifier and rendering one needs a catalog the
  editor has no business holding.


Phase 15 is complete: `Adash.Persistence` and `Adash.Configuration`, with their
children, and every setting wired to something that reads it.

`Adash.Persistence` owns the mechanism and nothing about the content. Every
write is atomic — staged beside the destination, then replaced in one step — and
every write is held under an exclusive lock, because two sessions ending at the
same moment is the normal case rather than the rare one, and without a lock the
second silently discards the first. Files are created private. Nothing raises:
absence, permission, a full disk and a lock held by somebody else are seven
distinct outcomes, because a caller that cannot tell "there is no file yet" from
"I am not allowed to read it" will write the wrong message for one of them.

`Adash.Persistence.History` stores **one JSON string per line**, not one raw
line per entry. Adash accepts multi-line input, so an entry may contain a
newline, and a newline-separated format cannot hold one; the usual fixes each
invent a small undocumented format. A JSON string holds any byte sequence
exactly, keeps the file appendable and greppable, and jsonlib already owns it. A
line that will not parse is counted and skipped rather than fatal — a truncated
last line is the normal thing to find in a file appended to at the end of every
session.

`Adash.Configuration` is a **closed schema**: seven settings, each with a key, a
type, bounds and a default, and no way to hold a value for a key that is not in
it. That is what makes an unknown key something the user is told about at
start-up rather than something they discover much later. Every setting is read
by something; a setting nobody reads is a promise nothing keeps.

`Adash.Configuration.Files` reads and writes TOML through tomllib. **A bad file
never stops the shell** — every problem is a diagnostic naming its key and the
setting keeps its default, because a shell that refused to start over one line
of configuration leaves the user with no shell to fix it with. A value out of
range is refused rather than clamped: a history limit silently reduced is a
surprise the user gets much later, when entries they expected are missing and
nothing ever said why. An unknown key is a **warning**, so a user with two
versions of Adash on two machines can share one file. Only what differs from the
defaults is written.

`Adash.Configuration.Migration` carries the schema number and the rename table.
The table is empty, because there has been one schema — but the mechanism is
here, because the first rename is precisely when nobody wants to be designing
it. A test asserts that the table size and the schema number move together, so
a rename added without a bump fails rather than silently losing everybody's
setting.

What changed elsewhere: `Adash.Engine.Session` now carries the settings, so a
subsystem that needs one is handed the session it is working on rather than
reaching for a global, and two sessions in one test cannot leak into each other.
The prompt honours its two toggles, the reader honours the editing setting,
startup honours the session-file setting, and `Adash.Terminal`'s colour policy
comes from the file. A script gets the user's settings too — a script running
under the defaults while an interactive session ran under the configuration
would be two shells.

**A correction to the record.** Earlier phases were reported as building with
zero warnings. That was measured by grepping the build for `error` and
`warning`, and GNAT prints style diagnostics with a `(style)` prefix instead, so
twenty of them went unreported across three files — one-line `if/else` bodies in
the lexer, some doubled blank lines, one layout slip. They are fixed, and the
build is now clean under a check that looks for all three.


Phase 16 is complete: a conformance suite that runs the built binary, verified
examples, a benchmark harness with recorded numbers, and a written release
procedure.

**Conformance** (`conformance/`, `adash_conformance`, and a case in `alr test`)
executes `bin/adash` from the outside and compares its exit status, its standard
output and its standard error. It never calls into the library — a suite that
did would be testing something no user can reach. Diagnostics are compared as
**identifiers, not sentences**: the runner points the message catalog at a path
that does not exist, so every message renders as `!error.name_undeclared{name=zzz}!`.
A suite asserting on English would break on every wording change and would stop
testing anything the day somebody localized the build.

Cases are TOML, read through tomllib, so adding one when you find a bug is
cheaper than arguing about the behaviour. An absent key and an empty one are
different assertions — `diagnostics = []` says nothing came out, leaving it out
says nothing at all — which is what lets a case pin down that diagnostics never
leak into standard output. Fifteen cases pass.

**Examples** are conformance cases whose input is a file somebody is meant to
read. Each has a `.expected` file beside it, and an example that no longer
produces what it claims fails the build rather than being found by a reader.

**Benchmarks** (`adash_bench`, `benchmarks/README.md`) report the median *and*
the fastest of N runs, because a median alone hides the shape. The first run
found something worth recording: **lowering and running a submission costs about
1.7 ms, roughly forty times the rest of the pipeline combined**, because
`Adash.Language.Evaluation` calls HAC's `Init_for_new_Build` for every
submission. Nobody typing will notice; a script of many submissions will. It is
recorded rather than fixed, because this phase is about characterizing
performance and optimizing before behaviour is pinned produces a fast
implementation of the wrong thing.

**Release engineering** is `docs/RELEASE.md`: the checks, in order, what each is
for, and what is *not* claimed. Byte-identical binaries are not — `-g` embeds
absolute paths, so two checkouts in different directories produce different
binaries that behave identically. The conformance suite is what demonstrates
reproducibility, by comparing what a user gets rather than bytes nobody cares
about.

## What the language gained

Everything below was written after the sixteen phases and describes what Adash
*does*. It sat under a heading that said "cannot do yet" for a long time: each
entry began life as a limitation and was rewritten in place when the limitation
went, and none of them was ever moved. The genuine limits follow in a section of
their own, where a reader deciding whether to use this can find them in one
place.

**`put_line` writes every type the language has.** A Boolean writes as Ada
writes one, in upper case, and an Integer, a Character and a Boolean are
unpadded: the width is zero, so a value takes exactly the room it needs rather
than Ada's default of padding a Boolean to the width of the longer literal.

A **Float** is the exception, and deliberately: it is written with HAC's own
defaults, so `put_line (1.5)` gives ` 1.50000000000000000E+00` — what the same
program compiled by HAC gives. A prettier form was available and was not taken:
it would have made a Float print differently here than in the language Adash
claims to be a subset of, while quietly dropping precision from anything that
needed it. Padding a Boolean is noise; shortening a number is a change to what
it says.

**`'Image` turns a value into text.** That is what string formatting was
waiting for: a computed number could not be joined to text at all before it,
and had to go on a line of its own. `put_line ("count is" & X'Image & " today")`
works now.

The images are Ada's own, leading space and all. A shorter float form or a
dropped space would be a different language wearing Ada's syntax, and a program
written here would print something else under GNAT.

`'Image` of a `String` is refused, and that is not an omission. Ada 2022 defines
it -- as the text *in quotes*, with non-graphic characters bracketed, which is
not the text itself. Returning the text would be the plausible wrong answer, and
HAC refuses it too. Every other attribute is refused as an attribute rather than
as an undeclared name, which is what it used to be reported as.

**Interpolated string literals work too.** `f"hello {Name}!"`, Ada 2022's own
syntax, rewritten to concatenation because that is exactly what it means:
`f"a{X}b"` becomes `("a" & X) & "b"`. Carrying it as a node of its own would
have made every later rule learn about a construct that has no separate
meaning.

The rewrite is also where the type rule comes from. Ada 2022 expects a `String`
in the braces, and `&` requires one here, so `f"n is {Count}"` is refused for
the same reason and with the same message as `"n is " & Count`. A number goes in
through `'Image`; the two features are a pair, and neither is much use alone.

The lexer emits the literal pieces and the expressions as separate tokens rather
than handing the parser one blob to take apart. That is what keeps the spans
right -- a diagnostic about something inside the braces points at what the user
typed -- and it makes nesting fall out: `f"a{f"b{X}"}c"` works, because the
expressions are lexed by the same loop as everything else.

**Ada 2022's whole escape set is implemented**: `\{ \} \\ \" \n \t \r \a
\b \f \v \0`, and nothing else.

The set and the character each produces were **not taken from memory**. Every
candidate was compiled with GNAT 13.3 under `pragma Extensions_Allowed (All)`
and its result read back; the twelve above are what it accepts, and `\e` and
`\x41` -- escapes in other languages -- are what it rejects. Adash emits the
same twelve bytes GNAT does, checked one against the other.

Asking the compiler settled something that had been guessed wrong. A doubled
`""` inside an interpolated literal is **illegal Ada** -- GNAT says "double
quotations not allowed in interpolated string", because `\"` is what puts a
quote in one. This build had been accepting it as a single quote, on the
assumption that Ada's ordinary string rule carried over. That is the exact
failure the subset exists to prevent, and it was here until the compiler was
asked.

**A program can declare subprograms and call them.** `procedure P (A : Integer)
is ... begin ... end P;` and the same with `return T` for a function, with
parameters of any of the five types, local declarations, recursion, and calls
between one body and another. A body may call an internal command, so a shell
command can be given a name and a parameter list.

The hard part was frames rather than calls. Each call gets an activation record
of its own, which is what makes recursion compute rather than corrupt; a
subprogram's locals are allocated in that record and not at the submission's
level, where they would land on whatever it declared at the same offset; and
and returning from a call made *inside* another body restores the caller's own
frame, without which its parameters read as whatever the popped one held. Every one of those has a conformance case, because each fails by giving a
wrong answer rather than by stopping.

**Parameters have all three modes.** `in` is a value the body reads; `out` and
`in out` are the caller's own variable, passed by address and written through.
The machine already had the mechanism -- the command stub answers through a
by-reference parameter -- and what it needed was for a read and a write of such
a parameter to use different instructions from a variable's. The pair looks
inverted and is not: for a variable the address is its slot, and for a
by-reference parameter the slot *contains* the address, so pushing its value is
what yields one. HAC's own compiler makes the same choice at the same place.

Two rules fall out of this and are enforced. An `in` parameter cannot be
assigned to -- Ada says so, and before modes existed this language could not,
because every parameter counted as assignable. And an `out` argument must be a
variable rather than any expression: there would be nowhere for the write to
go, the argument being a value on the stack that the return pops.

One divergence from Ada is worth naming. Ada passes elementary types by copy,
so reading an `out` parameter before writing it is a bounded error and aliasing
two of them is unspecified; here everything goes by reference, so both have
defined behaviour. No *correct* Ada program can tell the difference -- the
divergence is confined to programs Ada already calls erroneous -- but a program
written here that relies on it would not mean the same thing under GNAT.

**Subprograms nest.** A body declared inside another reads and writes the frame
of the body it was declared in, two or nineteen levels out, and each call sees
the frame of the call it came from rather than the first or the last.

That works because the machine already did it. HAC's `Do_Call` filled a display
slot one level below the callee and recorded a static link; what this lowering
had to stop doing was assuming every frame was at level two. A routine carries
the level it was declared at, and a name reaching outward says how many levels
out it is. When the machine became this repository's own the display went and
the static links stayed, so the lowering did not change: `Outward` still emits a
distance, and `Adash.Machine` walks that many links.

One thing had to change shape for it. A call used to be matched to a routine by
the callee's *name*, which nesting makes ambiguous: two bodies may each declare
a `Step`, and the spelling no longer says which. Routines are keyed by the
declaration their name was written at, and a call is matched through the symbol
the scope chain resolved to -- so the two passes agree about which entity was
called, rather than agreeing by coincidence.

Nesting runs out at nineteen levels and deeper is refused by name. That was the
display's limit when there was a display; it is now the front end's, where the
analyser and the lowering each recurse once per level. `Adash.Language`
carries the constant, because both enforce it and a constant written twice is a
constant that will differ once.

**One name can denote several subprograms.** Which one a call means is decided
by how many arguments it has and what their types are. `Show (7)` and
`Show ("x")` reach different bodies, and a name written without arguments means
whichever takes none.

The lowering needed no change at all for this, which is worth saying because it
was not free. Calls have been matched to *the declaration the scope chain
resolved to* rather than to the callee's name since nesting arrived -- that
change was made because nesting makes a name ambiguous, and overloading makes it
ambiguous again in a different way. Once the semantic pass picks a candidate,
everything downstream already followed the pick.

Resolution is by the number of arguments, their types, and **what the context
requires of the result**. The last is what settles a pair differing only in what
they return: a declared type, an assignment's target, the result type of the
function being returned from, a parameter every candidate agrees about, or a
condition's Boolean. Parentheses pass the requirement through, and so does an
operator whose result is its operands' type -- `S : String := F & "!"` wants a
String of the whole and therefore of `F`.

A comparison does not pass the context's requirement down -- its result is
Boolean and its operands are not -- but its operands have *each other's* type,
and that is enough. When exactly one of them is a call several subprograms could
answer, the other is analysed first and settles it, which is how Ada reads
`if F = 1`. Two open operands say nothing about each other and stay ambiguous,
which is also Ada's answer.

Where nothing requires anything -- `put_line (F)`, since `put_line` takes any
type -- the call is ambiguous, which is Ada's answer too. It is also what this
used to get silently wrong: before the context participated, such a call took
whichever candidate happened to be declared last.

Two subprograms with the same parameter types *and* the same result are still
refused. No call could ever tell them apart.

The shell's own names stay the shell's. Ada would let a program overload
`Put_Line`; here it is refused, because `put_line` accepts *any* type, so a
user's version would fit every call the original does and every one of them
would be ambiguous. A declaration whose every use is an error is worse than no
declaration.

**A subprogram may be specified before it is written.** `procedure Odd (N :
Integer);` -- the profile, then a semicolon where `is` would go -- names a
subprogram whose body comes later. What that buys is mutual recursion: without
it, whichever of two subprograms is written first calls something undeclared.

A body completes a specification rather than redeclaring it, which meant the
body keeps the *specification's* symbol. Every call written before the body
resolved to that symbol, and the lowering keys routines by the declaration a
symbol names -- so a call emitted before the body had an address still finds it.
That worked without change, for the third time: the same key absorbed nesting,
then overloading, now this.

A specification with no body is refused. The name is perfectly visible and calls
to it resolve; what is missing is anything to jump to, and running the program
up to the point it is called would be worse than not running it. The complaint
arrives where the body should have been -- as the enclosing declarative region
closes -- rather than at the end of the submission.

Matching is by profile, so a body with different parameters is a second
subprogram and leaves the specification still waiting. That is Ada's rule and
also the only one that can be checked without guessing which of two near-misses
was meant.

**`for` follows Ada's range rule.** Both bounds are evaluated once, before the
loop, and the upper one is kept in a slot no declaration names. It used to be
re-evaluated on every turn, which was only correct while the bounds were
literals or variables the body left alone -- and a body that raised its own
bound looped for ever.

Fixing it turned up a second defect in the same six instructions. The loop
incremented the parameter and *then* tested it, so a loop whose bound was the
largest value the type holds raised `Constraint_Error` computing a value it was
never going to use. Testing before incrementing is both the fix and the reason
the null range now works by construction rather than by a separate check: the
first test comes before the body, so `for I in 3 .. 1` runs it no times.

**A program that raises now says so.** It did not before: a division by zero
produced no output, no diagnostic and a successful exit, which is
indistinguishable from a program that ran and printed nothing. The exit status
still survives a failed statement -- that is the documented model and is
unchanged -- but the diagnostic is emitted, naming the exception and whatever
detail the machine has. Subprograms are what made this urgent: runaway
recursion and a function that never returns are both new ways to die, and both
were silent.

**Nothing requests cancellation yet.** The machine now asks: it consults the
session's cancellation token between instructions, and a program stopped that
way reports `Exit_Cancelled` rather than a failure, so a script can tell an
interruption from a fault. `loop null; end loop;` can be stopped, and there is
a test that stops one — written so that a machine which asked only *before*
running would fail rather than hang.

Ctrl-C reaches it. `Hostkit.Signals` gained `Disposition_Record`, which
installs a handler that does one thing — set a flag — because a handler runs
between any two instructions and anything else it touched would have to be safe
to touch halfway through. The shell records `SIGINT` instead of discarding it,
the machine's cancellation check consults the arrival, and the interactive loop
acknowledges once the submission has ended so the next line does not start
already-interrupted.

One thing this turned up. `Adash.Execution.Signals.Install` had existed since
Phase 11 and **nothing ever called it**, so until now the shell ran with the
host's defaults: Ctrl-C killed it outright and a truncated pipeline would have
taken it down with `SIGPIPE`. Its own tests had passed throughout, because they
tested the package rather than whether anything used it.

**Windows is covered too, by a different mechanism.** It has no POSIX signals,
so the C runtime's `signal` was not the answer — it would look right and fire
unreliably. `SetConsoleCtrlHandler` is, and hostkit now installs it. The routine
runs on a thread Windows creates rather than between two instructions of the
interrupted one, which makes it less constrained in what it may call and more
constrained in what it may assume; setting one atomic flag is correct under
both, which is the whole reason the contract is a flag. Returning `TRUE` is also
what stops Windows ending the process, so recording and surviving are one act
there. Ctrl-Break is deliberately left to terminate, keeping one way out of a
program that has stopped listening on a host with no `kill`.

That needed a second capability query. `Is_Supported` asks whether the host
*has* a signal — numberable, sendable, dispositionable — and on Windows the
answer is still no, across the board. `Can_Record` asks only whether an arrival
can be reported, which is the narrower thing a shell needs for Ctrl-C. Folding
the two together would have told callers they could also send `SIGINT` on
Windows, which they cannot. A hostkit test pins the promise from both sides:
every signal a host claims it can record must accept a recorder, and every
signal it does not claim must refuse one.

Every one of the language's five types now lowers: Integer, Boolean, Character,
String and Float.

**Strings lower**: literals, variables, copying, assignment, concatenation and
all six comparisons, with UTF-8 carried through unchanged. One thing is
deliberately refused rather than half-supported:

- **`X : String;` is refused.** Ada does not allow it either — `String` is
  unconstrained — so accepting it would make Adash take a declaration that real
  Ada rejects.

**A program can read something from outside itself.** `Env_Value ("HOME")`
returns a String, so `cd (Env_Value ("HOME"))` is writable and what it returns
concatenates and compares like any other.

Until this, it could not. Every predefined entity was a type, a Boolean literal
or a way to write output -- **not one of them yielded a value** -- so a program
computed from literals and nothing else. That is a strange thing for a shell,
and it was not on the list of things this shell cannot do, because the list
records what somebody thought to write down.

The answer comes back through a parameter the machine passes by reference, which
is the only direction that works: the record a call is given is popped when it
returns, so a value written into it would be gone before anything could read it.
The stub already carried one such parameter, for saying the program should stop;
it carries two now. The same path is what command substitution would use.

**A program can tell whether what it ran worked.** `run ("false");
if Status /= 0 then` is writable, and so is a subprogram that answers the
question: `function Ran (What : String) return Boolean is begin run (What);
return Status = 0; end Ran;`.

It could not before, and that is a strange thing for a shell. A command is a
procedure -- `run ("false");` produces no value -- so a program could start
something and had no way to learn what became of it. Nearly everything a shell
script does is conditioned on exactly that. It was not on the list of things
this shell cannot do either; the list keeps recording what somebody thought to
write down.

The number is the one exit-status model, which the shell already had and which
nothing in the language could reach: 127 for a program that was not found, 126
for one found and not executable, 128 + n for one a signal killed. `run` had in
fact been answering 1 for all three -- `Adash.Execution.From_Start_Failure`
existed, was tested, and was called by nothing in the product. Being able to
read the number is what made that visible.

`Status` is `$?` under an Ada name, and it is a function rather than a variable
because it is not assignable. Ada writes a call to a parameterless function as a
bare name, so the lowering answers a name as readily as a call -- the same road
`Env_Value` opened, with a second cell on the stub for an answer that is a
number rather than text.

**A script can read what it was invoked with.** `Argument_Count` says how many
and `Argument (N)` says which, so `adash build.adash release --quiet` is a tool
somebody can call rather than a file that runs the same way whatever you say to
it.

Before this the shell ran the script and *discarded everything after its path*,
without a word. That is worse than refusing it: a wrong invocation looked like a
right one. Anything after the path belongs to the script, options included --
a script's own `-v` is not this shell's business, which is why the option loop
stops at the first name it sees.

Reading past either end answers with the empty string rather than failing, as
`Env_Value` does for a name nothing set. A script asking for an argument it was
not given is asking whether it was given one, and `Argument_Count` is there for
a script that would rather ask directly.

Finding this also found that **no conformance case had ever run a script from a
file**. Every one of them fed its source through standard input, so the shell's
other mode -- the one every user of a script takes -- was covered by a single
case that asserted a missing file. Cases can name a file in the repository now.

**`case` chooses by value.** All four forms Ada writes -- a value, several
values, a range, `others` -- over Boolean, Integer and Character. One
alternative runs and no other: there is no falling through and no `break` to
forget.

Ada requires every value of the type to be accounted for, and so does this. A
case that silently did nothing for a value nobody thought about is the mistake
the rule exists to prevent, so the analyser adds up what the choices cover and
refuses a case that leaves a gap or covers a value twice. `others` is not
required where the alternatives already finish the job -- two of them account
for a Boolean -- because completeness is what the rule asks for rather than the
word.

**A choice is decided when the program is analysed**, which is what lets those
rules mean anything. This build reads literals, `-1`, `True` and `False`, ranges
of those, and `others`; a variable as a choice is refused by name rather than
accepted and compared at run time. Whether a name is a literal is settled by
what it resolves to, not by how it is spelled: a parameter called `True` inside
a body is a variable, and the analyser asks the symbol.

The lowering evaluates the value **once**, into a slot of the frame, and tests
the alternatives against that. A case over something the shell has to be asked
for -- `case Argument_Count is` -- asks once, which a re-evaluating lowering
would not.

**A construct can be written across several lines.** `if C then`, then the
statements, then `end if;` -- typed as anybody would type them. Until this, each
line was a submission of its own, so the two halves of one construct were two
programs and neither was what the user wrote. It applies to every construct and
to expressions, because it is the grammar that decides rather than a list of
openers somebody maintains.

The judgement is `Adash.Language.Parser.Wants_More`: parse, and report whether
it *ran out of input* rather than met something it did not expect. That
distinction is the whole thing. Waiting for more after a mistake would leave a
user at a prompt that never comes back, which is worse than the mistake; and
counting `end`s against openers would be a second grammar, quietly different
from the one that parses.

It also needed the parser to be honest about what is missing. `end` was
*accepted if present* for `if`, `while`, `for`, `loop` and, when it was written,
`case` -- so `if C then` at the end of the input parsed as an if with an empty
body, ran, and did nothing, and `loop` on its own became a loop that never
stops. An unfinished construct now says which word it wanted, which is what
makes it answerable.

`Adash.Interactive.Prompt.Continuation` had existed since the prompt did, with a
catalog entry, and was selected by nothing. It is what the second line is asked
for with, verified by driving the shell under a pseudo-terminal.

**A program's output can be read as a value.** `Output_Of ("git", "rev-parse",
"HEAD")` runs it and answers with what it wrote, without the newline it ended
with -- which is what makes `cd (Output_Of ("pwd"))` work.

A shell whose language could run programs could not read what any of them said.
Everything a program wrote went to the terminal, and nothing could be computed
from it; the value it produced was its exit status and nothing else. That is
command substitution, and it is the last of the three ways out of a program that
`Env_Value` opened the door for.

`Adash.Execution.Pipelines.Capture` is where it happens, and it reads the pipe
**to end of file before waiting**. A program that writes more than a pipe holds
blocks until somebody drains it, and a shell that waited first would be that
somebody -- waiting for a program that is waiting for the shell. Where the host
can express it, the read is non-blocking and Ctrl-C is noticed between reads.

Standard error is deliberately not collected. It belongs to the user: a program
explaining why it failed should be heard, not swallowed into a value the script
is about to compare against something.

Two smaller things came with it. The stub's record carries five value slots
rather than four, because a call answered by the shell spends the first on the
name of what is being asked for -- so a command gets five arguments now and an
ask four. And the mapping from "would not start" to 126 or 127 lives in
`Adash.Execution` rather than in the `run` family's body, because two callers
work it out and two copies of a mapping is how they come to disagree.

**A String can be taken apart.** `S (2)` is the Character there, `S (7 .. 11)`
is the String between, and `'Length`, `'First` and `'Last` say how far it goes.
`S & C` joins a String and a Character, which is Ada's rule for an array and one
of its components -- and what a loop rebuilding text out of what it took apart
needs. Two Characters are refused, as Ada refuses them.

Until this a String could be held, copied, joined and compared and nothing else.
A shell that had just learned to read a program's output could not look at any
of it.

Indexing is written the way a call is, so which one it is depends on what the
name denotes -- a question only the semantic pass can answer, and it asks the
*symbol* rather than the text, because a parameter named after a function is a
parameter. The lowering is HAC's own `SF_Element`, `SF_Slice` and `SF_Length`,
so a position past the end raises where HAC raises rather than reading whatever
was next in the frame.

`'First` is one and `'Last` is the length, because every String here begins at
one -- there are no other index ranges to have, which is why neither needs a
builtin of its own.

**A block declares what it needs and gives the names back.** `declare X :
Integer := 1; begin ... end;`, with the `declare` optional as in Ada. That is
worth having in a shell in particular: an interactive session keeps every
top-level name it declares, so a value wanted for three lines and never again is
better kept where it cannot be reached afterwards.

`Node_Block` had existed since Phase 5. The semantic pass entered a scope for
it, the lowering emitted it, and **nothing produced one** -- so it could not be
written. Both halves of the handling were also wrong in a way nothing could
notice: each read one child where a block has two, so a block would have run its
declarations and none of its statements.

A block is in the same frame at the same level as the code around it, so neither
level nor frame says that its declarations are gone at `end`. The lowering
counts the blocks it is inside instead; without that, a name declared in a block
was handed back to the session and outlived the block by the rest of the session.

Ada draws the line at `begin`, and so does this. A declaration is parsed as a
statement here, so nothing in the grammar stops a statement being written before
`begin` -- and a subset that accepted what Ada rejects would be teaching the
wrong language.

**The shell no longer shows identifiers where it owes the user words.** `jobs`
printed `[1] JOB_RUNNING  sleep 30` for as long as `jobs` has existed, a
terminated job was `ended by TERMINATE`, and a host that could not do something
said `this system does not support JOB_CONTROL`. Every one of those is an
enumeration literal or a hard-coded identifier reaching a user: untranslatable,
and not a sentence.

The rule the repository states is that no user-visible text lives in Ada source.
These did not break it by holding *text* -- they broke it by holding a **name**
and letting the renderer treat it as text. hostkit even says so about its own:
`Signals.Name` is documented as "an identifier a consumer maps to a message, not
text for a user", and Adash was passing it straight through.

So a failure may now quote a message, as a command's output line already could:
it carries the identifier of the message that says the thing in words, and the
presentation boundary renders that one into this one. `Adash.Execution.Message`,
`Adash.Execution.Jobs.Message` and `Adash.Platform.Message` are the three maps,
each a case statement with no `others` -- a signal or a capability added below
fails to compile rather than arriving as its own name.

`adash_check` gained the rule that would have caught it: an `'Image` of anything
but a number, or a literal written entirely in capitals, in a line that builds a
message argument. Verified by putting the original defect back and watching the
check fail.

**A job can be suspended and resumed.** `suspend (1)` stops it and leaves it
resumable; `resume (1)` continues it in the background.

`Adash.Execution.Jobs.Resume_In_Background` was complete and tested and nothing
called it. Adding the command that calls it turned out not to be enough, because
**nothing underneath could see a suspended job either**:
`Adash.Execution.External.Wait` answered "not finished" for a program that had
stopped and for one that was still running, so `Stage_State.Stopped` was only
ever assigned False, `Pipelines.Is_Stopped` was always False, and `Job_Stopped`
was unreachable. Three layers of handling for suspended jobs, none of which
could ever be reached.

Wait now answers with four states rather than two. Suspending and resuming are
*events* -- the host reports each once -- so the pipeline remembers what it was
last told rather than asking again and believing the answer, which would have
made a suspended job look busy from the second poll onward.

Two things this made reachable, and wrong. **Waiting for a suspended job never
returned**: the stop had already been reported, so the blocking wait had no
event left and waited for an ending a stopped program cannot reach. And a
command that reported the job's state immediately after asking for it was
reporting its own intention -- the host delivers a signal when it delivers it,
and a program may catch a terminal stop and keep running. The job table waits a
bounded while for the children to actually reach the state before answering, so
what the user is told is what happened.

**The shell can show and change its own settings.** `settings;` lists every one
with its value and what it is for; `settings ("color", "never")` changes one;
`save_settings;` writes them where the next session will read them.

`Adash.Configuration` had carried the whole registry since Phase 13 -- what each
setting is for, whether it holds a Boolean, a number or one of a fixed list of
words, what its bounds are, which of its values are allowed -- and
`Adash.Configuration.Files.Save` could write the file. **None of it was
reachable from the shell.** A user could see a setting only by opening the TOML
file and change one only by editing it. The messages describing each setting
said "shown when the settings are listed", and nothing listed them.

Every refusal comes from the registry rather than from a second copy of the
rules: a value outside a range is refused with the range, a word outside a
choice list with the list. The one thing that needed writing was a message of
its own -- the file reader says an unknown key `was ignored`, which is true of a
line in a file nobody is watching and wrong for something a user has just typed.

Saving is a separate command on purpose. A shell that wrote to a file in the
user's home every time a setting changed would be making a durable change on
their behalf; asking for it explicitly is the difference between trying
something and keeping it.

**`source` finds a script by name.** `source ("greeting")` looks beside the
script doing the loading, then in the user's own module directory, adding
`.adash` if the name does not carry it. `source ("./setup.adash")` is a path and
is used as written.

`Adash.Scripting.Modules` had decided all of that since Phase 14 -- the order,
the extension, the rule that a name with a separator in it is never searched
for, the deliberate absence of a search path from the environment -- and
**nothing asked it**. Its own unit tests passed throughout, because they tested
the resolution rather than whether anything used it. `source ("greeting")`
failed unless a file of exactly that name sat in the working directory, which
means a set of scripts that ship together could only find each other when the
user happened to be standing in the right place.

A name that resolves to nothing now says where the search went, because `no
script called setup` leaves a reader wondering whether the shell searched at
all. The three answers are messages the diagnostic quotes rather than words
built into it -- the same road `help` and `jobs` take.

**The shell can read its own input.** `Read_Line` answers with one line;
`Input_Ended` says whether the last read found the end rather than a line. A
separate question on purpose: an empty line is a line a file may genuinely
contain, and a program that could only see the text could not tell it from `no
more`.

Until this the shell could write its output and run other programs and could
not read a byte of what it was given. A script at the end of a pipe had no way
to see anything at all, which is half of what a shell is for.

The part that needed care is that there is **one** standard input. The
interactive editor kept its own buffer of bytes read ahead of a line boundary --
correctly, since a paste arrives all at once -- so a user who typed their answer
before the program asked for it would have that answer sitting in the editor
while the program read nothing. Buffering now belongs to
`Adash.Execution.Streams`, and the editor takes what is held when it starts a
read and gives back what it did not use. Verified by driving the shell under a
pseudo-terminal with the answer typed ahead.

One thing is inherent rather than fixed: a script that *is* standard input --
`adash < script.adash` -- reads the rest of itself. Every shell behaves that
way, and pretending otherwise would need a second stream nobody asked for.

**A value can be read back from text.** `Integer'Value ("42")`, and the same for
`Float`, `Boolean` and `Character` -- with `Integer'Image (N)` the other way,
which is how Ada has always written it.

This is what the reading a shell had just learned to do was missing. `Read_Line`
answers with a String, and a String can be compared and joined and taken apart
and not added up: a program could read a number and had no way to make it one.

Ada's own spelling, and HAC's own `SF_Value_Attribute_*` builtins, so what is
accepted is what Ada accepts and text that does not hold a value raises rather
than answering with something nobody wrote.

A type's attribute is a call -- the prefix is a type name and the argument is
what it applies to -- so it needed the analyser to recognise that shape before
it analysed the prefix as a value. Without that, `Integer'Size` reported
`Integer is not a type`, which is both wrong and baffling.

**A script can ask whether a file is there.** `Exists`, `Is_Directory` and
`Is_Executable`, in `Adash.Filesystem`.

That is the commonest conditional anybody writes in a shell, and the language
could not ask it at all. Every other way a program touched the filesystem went
through *running* something -- a redirection, a captured program -- and running
something does not answer a question.

Three of them rather than one, because they are three different things, and
acting on a directory as though it were a file is the mistake the second one
exists to prevent. `Is_Executable` is hostkit's answer rather than a guess from
the name: what makes a file runnable is the host's business.

**Questions are functions; writing is a command.** A shell that could change a
file from inside an expression would make an expression a thing with
consequences, and `if Exists (P) and then Write (P, "") then` is a line nobody
should be able to write by accident. So `Exists` and its two companions are
predefined functions, and `write_file` and `append_file` are commands --
statements, where a reader sees them happen.

A path nobody can reach is answered rather than raised: it is not a file, and a
predicate that could fail would need a second question beside every use.

**A program can declare its own types.** `type Colour is (Red, Green, Blue);`
and `subtype Percent is Integer range 0 .. 100;`.

Until this the five built-in types were the whole model. A script that meant
"this is a colour, and there are three of them" had to say "this is an Integer,
and I promise it is 0, 1 or 2" -- and nothing checked the promise. `case` could
not tell whether it had covered every value, a wrong constant read as a
plausible number, and the mapping lived in the reader's head.

The type model had to open first. `Type_Kind` was an enumeration of six
literals with a comment saying that adding a composite type should fail to
compile everywhere that has to consider it. It is now a private type carrying a
*shape* -- which of the six kinds of thing it is -- and, for a declared type, an
identity. The identity is the offset its declaration was written at: unique
within a submission by construction, and the same number in every pass because
the source it points into does not move. Two enumerations with the same
literals spelled the same way are two types, which is Ada's rule, and the
identity is the whole of what says so.

Its `=` compares shape and identity and deliberately *not* the constraint. A
subtype is its base type in Ada, and every question of the form "is this an
Integer?" in the front end -- there are dozens -- means that one. A `=` that
compared bounds would answer no to all of them, and a subtype would stop being
usable anywhere its base is.

An enumeration's literals are a symbol kind of their own. A literal is its
position and has no storage; a loop parameter over the same type is a
*constant* of it and does have storage, and pushing its position rather than
reading its slot made every turn of a loop the first one. That defect is why
`Symbol_Literal` exists rather than a flag.

**Literals overload.** Two enumerations may each name a `Red`, which is Ada's
rule and follows from what a literal is: a parameterless function returning its
own type. So the same two places that already handled functions differing only
in what they return handle these -- the scope admits the second declaration
because the two could be told apart, and the analyser picks by what the context
expects. A second literal of the *same* type is still a redeclaration, because
nothing could tell those apart, and neither may shadow a name the shell
provides.

The lookup needed one change to allow it. Collecting candidates stopped at the
first name that was not callable, on the reasoning that a variable hides every
subprogram of its name outright -- true, but a literal is not that kind of
name. Where nothing says which type is meant the use is refused as a value of
several types rather than settled by which was declared last.

Sideways resolution came free with that, and it is worth saying why. The
comparison operators already analysed the *other* operand first when exactly
one of them was a call several subprograms could answer -- that is how `if F =
1` reads -- and a literal is such a call. So `Red = Amber` settles itself the
moment literals are collected as candidates. Membership did not, and now does:
the value settles the bounds unless the value is the one in doubt.

Where the context expects a type none of the declarations has, the fault is the
type and not the choice, and the diagnostic says so rather than reporting an
ambiguity nobody can act on.

The literal names live in the program's own text table, one contiguous run per
type with the type's name on the end. So `'Image`, `'Value`, the range check
and `put_line` all find them with two numbers an instruction already has room
for, and none of them needs a table of its own.

A subtype's range is checked at the five places a value arrives: an object's
initial value, an assignment, an argument entering an `in` parameter, a
caller's variable after a call wrote back through it, and a function's result.
The fourth is the one worth saying out loud -- the callee wrote through an
address and knows nothing about the constraint at the other end, Ada checks on
the copy back, and without it a variable would quietly hold a value it says it
cannot.

`for X in T loop` came with them, because `Colour'First .. Colour'Last` says
the same thing three times as long. It counts in a slot of its own rather than
in the loop variable: a `Character` loop counts 0 .. 255 and the variable holds
a Character, and writing the position into it would hand the body a number
wearing a Character's name.

**A range counts over any discrete type too.** `for What in Failed .. Killed
loop` walks part of an enumeration, and `for C in 'a' .. 'z' loop` part of the
Characters; the range form used to insist on Integers, which was this build
inventing a rule. What the loop counts over is what its bounds are, and the two
bounds settle each other the way a comparison's operands do -- so a bound that
is a literal two types could answer is settled by the other end.

The counting was already right for the type-named form and the same split
serves both: a slot of its own where a position and a value differ, the
variable itself where they coincide. A range of Characters or Booleans converts
its bounds to positions on the way in, which is the instruction the other
direction already had.

Testing that turned up a defect beside it: **`'First` and `'Last` on a subtype
mark answered with the base type's bounds.** `Percent'First` was Integer'First
-- a number the subtype refuses, handed back as its own first value -- and a
loop written `for X in Small'First .. Small'Last` counted from the bottom of
Integer. The bounds are a subtype's own now, which is what every other place
that asks already assumed.

**Tasks and protected objects.** `task T; task body T is ... end T;` and
`protected P is ... end P;` with procedures, functions and entries.

This one is worth the note it comes with, because `ROADMAP.md` argued against
it. Adash already had a concurrency model -- *processes*, which is what
`start`, `pipe` and the job commands are -- and the argument was that two
models answering one question is a cost. The cost is real and it is now paid
deliberately. What buys it is that a submission is a *program*: a program that
wants to overlap two pieces of its own work had no way to say so, and reaching
for a second process to do it means a second copy of the interpreter and no
shared state at all.

**Interleaved rather than parallel.** The machine runs one strand at a time and
changes strand at defined points -- on a fixed instruction quantum, so a
program interleaves the same way on every machine and a conformance case can
say what it printed. Ada does not require parallelism: a single-processor
implementation is conforming, and what a program may rely on is that its tasks
make progress and that its synchronisation holds.

Interleaving is also the only answer this repository can give. Anything
platform-specific belongs to hostkit, and a machine reaching for threads of its
own would be a second provider of them -- the same rule that decided every
other platform question here.

A strand is a set of the machine's registers and a region of its slots and its
stack. The environment task -- the submission itself -- keeps the front of
both, which is what makes a submission with no tasks in it run exactly as it
did. A switch saves the running registers into the strand being left and loads
the one being entered, so the interpreter still reads as one machine rather
than as a machine with a subscript on every line.

**Mutual exclusion is the whole implementation, not an optimisation on top of
one.** The machine does not change strand while a protected operation is
running, so no other strand can be inside one. Two tasks incrementing a shared
counter two hundred times between them leave two hundred.

**An entry is a barrier and a body**: a way to wait until something holds. A
strand that finds the barrier closed is set aside until the object is next
left, and *re-evaluates* it when it wakes -- testing the old value again would
answer the question it went to sleep on rather than the one that woke it, which
is the defect this was written wrong as the first time. Every strand waiting
for something no strand will do is reported rather than hung on: a shell that
hung on a script would be a shell somebody has to kill.

Ada's rule about masters is what makes a task usable in a script. The
declarative region that declared a task does not finish until the task has, a
submission is that region, and so the script waits. Two consequences follow and
both are written down: a task cannot outlive its submission, so a task *body*
is not carried between them -- carrying it would start the task again on every
line typed after; and `quit` ends the session without waiting, because a
program told to stop never reaches the end of a region.

**`delay`, `select` and `abort` came with them.**

`delay 0.2;` waits in real time, from Ada's own monotonic clock -- monotonic
rather than calendar, so a script that waits half a second waits half a second
whatever somebody does to the system time. A delay that only yielded would make
it a lie, and waiting for something is the commonest reason to write one. The
other strands run while one waits, and when none can the machine sleeps until
the earliest deadline rather than spinning -- every sleeper's deadline counts,
including the waiting strand's own, which is a scan that was written wrong the
first time and made a task waiting a twentieth of a second wait a whole one
because something else was waiting that long.

`select E; ... else ... end select;` is Ada's conditional entry call, and the
implementation is where the design earns its keep: the lock is taken *before*
the barrier is asked, and the machine does not change strand while a lock is
held -- so the barrier cannot close between being asked and being acted on.
That window is the whole difficulty of writing a conditional entry call, and
here it does not exist.

`select E; ... or delay D; ... end select;` bounds how long the call waits, and
the call waits the way an ordinary one does. This used to be the exception: the
timed form polled -- lock, ask the barrier, let go, sleep the whole of D, ask
again -- so a barrier that opened during the wait was taken when the wait
ended. The outcome was Ada's and the latency was not.

It queues now. A caller of a protected entry queues by being inside the entry's
own body, parked at its barrier, so what a deadline has to reach is that
parking, and the shape that reaches it was already here: the same wake the
scheduler gives a caller waiting a bounded time at a rendezvous, and the same
unwind an abandoned trigger is given. Waiting at a barrier became one more
thing the clock can end.

Giving up is leaving the entry body without running it, so the object has
nobody waiting at that entry afterwards and what the call was going to be given
is not given. Passing the barrier is the entry body starting, which is what the
deadline was against, so it stops applying there. Both halves are conformance
cases, and the ordering that shows the difference is one too -- a barrier
opened partway through a two-second wait, taken then rather than at the end.

The conditional form still asks the barrier under the lock, because that is
exact: nothing changes strand while a lock is held, so the barrier cannot close
between being asked and being acted on.

`abort T;` stops a task where the strand would next have run, which is the next
switch point. This machine interleaves rather than pre-empts, so there is no
moment between two instructions at which to intervene -- and none is needed,
because a strand that is not running cannot be in the middle of anything. An
aborted task does not run its handlers, which is Ada's rule too, and the master
no longer waits for it.

**A task's entry is met, not called.** `Server.Put (5);` on one side and
`accept Put (Which : Integer) do ... end Put;` on the other are one event: the
caller is set aside until an acceptor reaches the accept, the acceptor is set
aside until a caller arrives, and neither passes until both have. Callers queue
and the acceptor takes the one that has waited longest, which is Ada's rule.

The arguments travel as a *place* rather than as values. The caller writes them
into a run of its own slots and hands over where the run starts; the accept
body's formals are references into it. That is the only arrangement that works
when the two sides are separate strands with frames of their own, and it is
what makes an `out` parameter come back: the body writes where the caller is
reading from.

The accept repeats the entry's profile, as Ada writes it, and is held to
repeating the same one. The caller writes its arguments by the entry's profile
and the body reads them by the accept's, so an accept that disagreed would have
one side writing a number where the other reads text -- which no run-time check
could recover from, because both sides think they are right.

Calling an entry of a task that has ended -- run to its end, or aborted --
raises Tasking_Error in the caller, which is Ada's answer and reaches the
caller's own handler. It is raised where
the call left off, so a handler around the call catches it exactly as one
around any other call would -- and the alternative, stopping quietly, would
leave a program abandoned in the middle of a statement with nothing said.

**A task is a value, and a task type is a type.** `task type W is ... end W;`
declares a type whose objects are each a task of their own -- their own strand,
their own local state, their own entry queues -- and `A : W;` starts one where
it stands, which is where Ada elaborates it. That is why a task is a type at
all: several tasks share one body, so what a rendezvous or an abort names has
to be the object rather than the work. A task object holds which strand runs
it, and an entry is declared once beside the type; `A.Go` is the object saying
whose and the type saying which.

`task T is ... end T;` is the same thing written for one: a type named after
it, and an object. Everything below the analyser sees one arrangement.

**`select` with several alternatives** is a task saying "whichever of these
happens first". Its alternatives are accepts, where the other `select` has an
entry call -- one is a task deciding what to serve and the other is a caller
deciding how long to wait, and the first word after `select` is what tells them
apart, as it does in Ada.

A guard, `when <condition> => accept ...`, says what the task is ready for.
Guards are asked once, when the select is reached, and their answers are kept:
an alternative that was closed then is closed for this execution however the
world changes while it waits. That is Ada's rule, and it is why a strand that
waits and comes back finds the same set of alternatives it chose from. `else`
is what to do when nothing can be taken now, which makes the whole select a
look rather than a wait; `or delay D;` bounds the wait.

**`select ... then abort`** abandons a piece of work when something else
happens first. The abortable part runs as a strand of its own and the trigger
-- an entry call or a delay -- waits in the strand that wrote the select. That
is the only shape this machine can give it, and a faithful one: a strand that
is not running cannot be in the middle of anything, so there is nothing to
unwind when it is abandoned, and Ada's own rule about where an abort takes
effect is the same rule.

The trigger may be a delay, a call to a task's entry, or a call to a protected
object's -- anything that happens on somebody else's terms, which is the point
of abandoning work when it does.

Either side may win. When the trigger fires, the work is abandoned where it
would next have run and the trigger's statements run. When the work finishes
first, the trigger is cancelled, and how depends on where it was waiting: a
delay ends there rather than running its full course; a call queued at a task's
entry leaves the queue with nothing raised; and a call parked at a protected
object's *barrier* is parked inside that entry's own body rather than in a
queue, so it returns from that body without running it -- the same unwind a
return does, done to a strand that is not the one running. The entry's body
never runs and its queue is empty again: a cancelled trigger is a call that did
not happen, not one that half did.
What the select does after the wait is ask which of the two happened, which is
one question rather than a race between two answers.

**A master is a region.** Ada has a subprogram wait for the tasks declared
inside it before it returns, a task body wait for its own before it ends, and a
block statement wait before it completes; so does this. What says which region a
task belongs to is the *frame* that was current when it started, which is the
region the machine can see -- and a frame is exactly what has to stay: a task
reads what encloses it through a static link into that frame, and a master that
returned first would leave it reading slots the next call had taken.

A block makes no frame, so a frame alone cannot tell two blocks in one body
apart. Each block is a numbered *region* of its frame, numbered rather than
counted because a depth would make the second turn of a loop look like the
first, and a region waits for its own dependents and for every region opened
inside it. Falling off the end is not the only way out of a block either: an
`exit` completes however many blocks stand between it and the loop, and a
`return` completes them all by leaving the frame.

An accept body is a region too, and its wait stands *before* the caller is let
go: what a rendezvous started is finished with before the rendezvous completes,
which is what a caller is entitled to assume of one. Ada makes an accept body a
master for what an allocator creates in it; here what makes the rule worth
having is that this language accepts a declaration wherever a statement may
stand, so a task can be written in one at all.

**`pragma Restrictions`** is a program saying what it will not do, so that a
reader -- and this pass -- can rely on it. Four of the six are *statements*
given up -- `No_Abort_Statements`, `No_Delay`, `No_Select_Statements`,
`No_Requeue_Statements` -- which is what makes them checkable where they are
written rather than hoped for.

`No_Relative_Delay` and `No_Dynamic_Priorities` are statements and assignments
given up in the same way, and Ravenscar's reasons are the ones this language
already states: a loop delaying *for* a length drifts, and a priority settled
where it is declared is one a reader can see the whole of.

`Simple_Barriers` asks that a barrier be a name and nothing else, so that
reading one is reading a variable -- and a barrier is asked at moments the
program did not choose, which is why being able to see it matters.

`No_Task_Hierarchy` and `No_Local_Protected_Objects` are about where a
declaration stands rather than what a statement is: no task declared inside a subprogram, a task body, a block or an accept
body, so that the whole shape of a program's concurrency is written where the
program begins. Checked where a task is declared, because that is where its
master is decided.

Four carry a number. `Max_Task_Entries` and `Max_Protected_Entries` are counted
where the entries are declared, which is the one place they are all together.
`Max_Tasks` and `Max_Entry_Queue_Length` are counted while the program *runs*,
because what a loop starts and what a program queues are not things a reader
can count: the analyser reads the number and the machine keeps the count. A
strand that has gone back to being nobody is not one of the tasks running, so a
loop that starts a task, waits for it and starts another stays within a bound
of one.

`No_Task_Termination` is the other run-time one, said where a task runs out
because that is the only place it can be.

What is deliberately absent from the profile is what this language has nothing
to check: the restrictions about allocators, heap, interrupts, timing events
and library dependencies name things it does not have. A restriction nobody
checks is worse than none, so those are refused as names it does not know
rather than accepted and ignored.

A configuration pragma, so what it says is read before the first statement is
looked at: written after what it forbids, it forbids it still. A name this
language does not know is refused rather than ignored, because a restriction
nobody checks is worse than none -- a program would be told it had given
something up and go on doing it.

**`pragma Task_Dispatching_Policy`** and **`pragma Locking_Policy`** are the
other two pragmas the Ravenscar profile names. Neither is a switch this
language could have left out: each says what the machine does where Ada leaves
a choice, and a program that has to be reasoned about needs those answers
written down.

`FIFO_Within_Priorities` is the one that changes something. A strand's turn is
otherwise a fixed number of instructions, shared out between strands of the
same priority; under this policy a strand keeps its turn until it waits for
something. That is what Ada's policy means on one processor, and why Ravenscar
names it -- an interleaving nobody slices is one a reader can follow. Its cost
is Ada's own: a task that computes for ever and waits for nothing keeps the
machine, and Ada's answer is that such a program is wrong. The interrupt is
still asked for between instructions, so the shell is not lost with it.

`Round_Robin_Within_Priorities` is the other policy accepted, and is what the
machine does when nobody says. `Ceiling_Locking` is accepted because it is what
the machine already does: a caller above an object's ceiling is refused, and no
strand is set aside inside a protected operation.

Every other policy name is refused, for the reason an unknown restriction is: a
policy is a claim about how a program runs, and one nobody implements is a
false one. A policy is *named*, so a string spelling one is not one, and each
of these pragmas takes exactly one argument.

**A bounded call to a task entry** -- `select E; ... or delay D; ... end
select;` where `E` is a task's entry -- was refused until now, and the refusal
was the honest kind: the timed call this language had was built on a protected
entry's *barrier*, which it takes the object's lock to look at. A task entry
has no barrier and nobody to ask.

What it has instead is a queue, so the call carries a deadline into it. The
caller joins as any caller does and is set aside; the scheduler treats a caller
waiting a bounded time exactly as it treats a sleeper, both for waking it and
for deciding that a program with nothing else to run is waiting rather than
stuck. When the deadline passes the caller runs again and answers for itself:
still queued means nobody came, so it leaves the queue and the select takes its
other branch.

Cancelling at the deadline is Ada's rule about a rendezvous that has not
*started*, so two things follow and both are checked. A rendezvous begun in
time runs to its end however long the body takes, arguments carried in and
results carried back. And a caller whose deadline has passed is no longer there
to be taken -- an acceptor that arrives late finds the queue empty rather than
meeting somebody who has already given up.

**A program declares its own exceptions and raises them.** `Wrong_Kind :
exception;`, `raise Wrong_Kind;`, a handler naming it, and `raise;` inside a
handler to pass on what it caught. The five the machine raises for itself may
be raised by name too.

It cost less than it looks because the mechanism was already name-based. A
handler compares the raised name as *text* -- that is how `when Constraint_Error
=>` has always worked -- so a user's exception is a name the analyser admits
and the same comparison finds. `Raise_Named` carries which text; there is no
detail, and that is the difference a reader sees: the machine's own exceptions
carry a message saying what went wrong, a program's says what its name says.

`raise;` re-raises what the enclosing handler caught, from the two slots the
handler already kept it in for the fall-through case -- the path that passes an
unmatched exception outward. Nested handlers put their outer pair back
afterwards, so a handler inside a handler raises again what *it* caught. Outside
a handler there is nothing to raise again, and that is refused by name rather
than lowered into something that would raise whatever happened to be in a slot.

An exception declaration is carried between submissions the way a type is:
there is no value to hand back, and a raise typed on the next line has to find
the same name a handler will.

**`or terminate;`** is how a server task ends, and it was the one shape of
Ada's tasking a script could not write: a task that serves callers in a loop
had no way to stop, so the idiom every Ada program uses for a server ended here
as a task waiting for something no task will do.

What makes it unlike every other alternative is that nothing the task itself
does decides it. Ada takes it when the master the task depends on has completed
and every task depending on that master is either terminated or waiting at one
of these. So the strand writes down that it is willing and where to go, and the
*scheduler* is what notices: when nothing can run and nothing is waiting for
the clock -- exactly when the question has an answer -- it asks whether what is
left is only willing tasks and masters waiting for them, and if so sends each
willing one to its own ending.

Sending it there rather than marking it done is what keeps this from being a
second way for a task to end. The alternative's branch is an `End_Task` like
the one at the foot of any task body, so what happens next -- the wait for its
own dependents, the callers given `Tasking_Error`, the `No_Task_Termination`
check -- is the same code in the same order.

Anything that is not over and not willing stops all of them: a task computing,
sleeping, queued at an entry or waiting on a barrier is somebody who could
still call. A sleeping task keeps every server alive until it wakes, calls and
finishes, which is checked. Two servers that could call each other end
together, and neither ends alone.

A guard closes this alternative like any other, and a task whose only way out
is closed waits for a caller who never comes -- reported rather than ended
quietly. `terminate;` anywhere but as an alternative is refused by name, as is
a second one, or one beside a delay alternative or an `else`: those say what to
do when nothing can be accepted *now*, and this says there is nothing left to
wait for at all.

**A conditional call to a task entry** -- `select E; ... else ... end
select;` -- asks whether a rendezvous could start at *this instant*, which is a
question about what the called task is waiting for right now. The machine did
not record that, and the refusal said so.

It records it now, and the place it comes from is the offer pass built for the
queuing policy. A selective accept already tells the machine which of its
alternatives are open; what changed is that the offers are written down on the
strand instead of only being compared. A plain accept says the same thing the
same way -- an accept on its own is a select with one alternative and no guard
-- so both kinds of waiting task can be asked what they would take, and the
answer is exactly what the guards left open.

The rest follows. A task set aside at an accept cannot have a caller queued at
an entry it is open for, because queueing one wakes it, so being open is the
whole condition: no queue to look behind. A call that can start is made and
queued as any call is, and the rendezvous runs to its end; one that cannot is
not made at all, and the task is left where it was with nothing queued at it.
An ended task still raises Tasking_Error, conditionally or not.

The bound is `Max_Offers`, thirty-two alternatives in one select, and a select
with more is refused where it runs rather than answered wrongly -- a bound like
the machine's others, because what a strand records has to be a fixed size.

**A caller wakes a select that is waiting.** `select ... or delay D;` waits
for a caller *or* the clock, and this machine used to sleep the whole of D and
look afterwards. The outcome was Ada's and the latency was not -- and worse, a
task asleep in its own wait looked like a task waiting for nobody, so a
conditional call to one was not made where Ada would have taken it. One
deviation showing up as two.

Both are closed by the same three small things. The select's own wait is
emitted as a delay a caller may cut short, which is a flag on the instruction
because only the lowering knows which kind of wait this is. What the select is
open for stays written down across the sleep, so a caller can see it. And a
call arriving at such a sleeper wakes it, exactly as a call arriving at a task
already waiting for a caller does.

The waking forgets what the task was open for, and that is deliberate: a second
caller asking whether a rendezvous could start at once is told no, because this
task is running now and one of the two is going to be taken. It is the same
reason the case of a task already waiting is safe -- being woken is what makes
the answer stop being yes.

The clock is still the other thing it waits for: nobody calls, and the delay
alternative is taken at the time it said. Both halves are conformance cases,
and so is the ordering that shows the waking -- a caller served before a tick
that a slept-through wait would have served after.

What remains is the deviation on the *calling* side, which is a different
mechanism: a timed call to a *protected* entry polls the barrier rather than
queueing, so it waits its whole duration before taking one that opened during
it. That one is stated where it lives.

**`pragma Queuing_Policy`** says how callers are taken off an entry queue:
`FIFO_Queuing`, the order they arrived in, or `Priority_Queuing`, the highest
priority first and the order they arrived in among equals -- which is what
makes it an ordering rather than a lottery. Both are implemented, so both are
accepted.

Writing it found that this machine did not really have queues. A caller of a
*task* entry did: it took a ticket and the acceptor took the smallest. A caller
of a *protected* entry did not -- everything waiting on an object is woken when
the object is left, each tests its own barrier, and whoever the scheduler
happened to run first went through. That is neither of Ada's policies, and
under the default it was wrong: `FIFO_Queuing` says the one that arrived first.

So a caller now takes its place where it joins the object's queue, once per
call rather than at each waking, and an open barrier is no longer a turn: a
strand goes through only if nobody queued at that same entry is ahead of it
under the policy in force. Waking them all and letting each test its own
barrier is kept, because that is what keeps a barrier's meaning in one place;
what is added is that the order of the queue is kept too. A strand that defers
goes back to waiting and is woken again the next time the object is left.

The rule reaches into a selective accept as well. When several open
alternatives have callers waiting, `Priority_Queuing` serves the one whose
queue holds the caller who comes first -- not the one written first. The two
answers have to agree or the policy would stop at the edge of a select, which
is exactly where a program with several kinds of caller needs it.

Getting there needed the alternatives offered before any is tried. A selective
accept already asks its guards once and keeps the answers, because a strand
that waits and comes back must not find a different set of alternatives open;
what is added is a pass over those answers that asks each open alternative who
is at the head of its queue and keeps the best. Then the try chain is what it
was, except that only the entry the choice settled on may take a caller. Ties
keep the alternative written first, because that is the order they are offered
in, and a closed guard offers nobody however good its caller.

Under `FIFO_Queuing` the choice stays the one written first. Ada leaves it
arbitrary there, and keeping the old answer costs nothing and keeps every
program that says nothing interleaving exactly as it did -- which matters more
than it sounds: the offer pass is a scan of the strands per alternative per
round, and paying for it where Ada asks for nothing moved a timing-sensitive
example off its expected output.

**`pragma Priority_Specific_Dispatching (P, First, Last)`** gives a policy to a
range of priorities rather than to the whole program. What it is for is a
program that wants the strands doing its important work left alone and the rest
shared out, and Ada lets it say exactly that.

Taking it seriously changed the machine rather than the analyser: whether a
turn ends at the quantum is now asked of the priority the running strand is at,
not of the program. A policy that could only be said about a whole program
would have made this pragma either a lie or a second mechanism beside the
first, and both are worse than an array of thirty-one booleans.

The bounds are priorities, static and in range, and a range that runs backwards
is refused because it names no priority at all -- a program that wrote one
meant something it did not get. Two pragmas giving one priority two policies
are refused as well, and that check is what `pragma Task_Dispatching_Policy`
and `pragma Profile` now go through too, because each of them answers for every
priority. Saying the same thing twice is not a conflict: a configuration pragma
repeated is Ada's own, and what is refused is two answers to one question.

**`pragma Profile (Ravenscar)`** is the name for all of it said at once: the
restrictions, the blocking check and both policies. It is one pragma rather
than a convenience over the others, because what a profile is worth is that a
program naming it and a program writing them out run the same way -- so the
profile is read where the restrictions are, through the same place that takes
one on, and the machine is told the same things.

What it takes on is Ravenscar as far as this language can be held to it:
`No_Abort_Statements`, `No_Dynamic_Priorities`, `No_Local_Protected_Objects`,
`No_Relative_Delay`, `No_Requeue_Statements`, `No_Select_Statements`,
`No_Task_Hierarchy`, `No_Task_Termination`, `Simple_Barriers`,
`Max_Entry_Queue_Length => 1`, `Max_Protected_Entries => 1` and
`Max_Task_Entries => 0` -- no rendezvous, because Ravenscar's tasks talk
through protected objects. Not `No_Delay`: Ravenscar gives up a delay *for* a
length and keeps one *until* a time. Not `Max_Tasks`: the profile settles how
many tasks there are by saying where they may be declared. The rest of Ada's
list names allocators, heap, interrupts, timing events and library
dependencies, which this language does not have, so there is nothing there to
give up.

**`pragma Profile (Jorvik)`** is Ada's other profile, and Ada defines it as
Ravenscar with four things given back: `Simple_Barriers` becomes
`Pure_Barriers`, and `No_Relative_Delay`, `Max_Protected_Entries => 1` and
`Max_Entry_Queue_Length => 1` are dropped. What it keeps is everything else --
no abort, no select, no requeue, no task entries, no task declared inside
anything, and a task that ends is still an error.

Each of the four was given up for a reason about *analysis* rather than about
safety: how long a barrier takes to answer, how much room the queues need, how
far a delay may drift. Jorvik is Ada saying that a program willing to pay for
the analysis may have them, and this language says the same by taking the two
profiles through the same place, with the difference written where it is a
difference and nowhere else.

`Pure_Barriers` is the restriction that had to be added for it, and it is the
interesting one. A pure barrier may be worked out, so long as working it out
cannot *do* anything and cannot *fail*: no call, and no division, remainder,
exponentiation or join. Names, components, attributes, literals, the logical
and relational operators, `+`, `-`, `*` and membership are what is left. The
reason is the reason `Simple_Barriers` exists at all -- a barrier is asked at
moments the program did not choose, so it has to be answerable at any of them,
and one that raises would fail where nothing asked it to.

Writing it turned up that a function called without parentheses is a name to
the parser and a call to everybody else, so the check cannot be done on the
shape of the barrier alone -- what the name denotes decides. `Simple_Barriers`
had the same hole and admitted such a barrier; it does not now, because the
stricter restriction cannot admit what the relaxed one refuses.

Every other profile name is refused, for the reason an unknown restriction is:
a program would be told it had given something up and go on doing it.

The cost is worth stating plainly: `No_Task_Termination` makes a task that ends
an error, and Ravenscar means that because its programs do not end. A
submission does. A Ravenscar submission therefore finishes by reporting the
task that ran out, and that is faithful rather than a defect -- the profile is
here because the language has the pragmas it names, not because a shell is
where such a program belongs.

**`pragma Detect_Blocking`** asks for what Ada calls a potentially blocking
operation inside a protected action to be caught. What the operations on that
list have in common is that each may set the strand aside, and a strand set
aside while it holds a lock is holding it against everybody: deadlock waiting
to be written.

The list is asked in one place, once per instruction, because what makes an
operation blocking is not something each of them has to say about itself -- and
a list in one place is a list that can be read. A delay, an entry call, an
accept, a select, starting a task, waiting for one, an abort. Not an entry's
own barrier, which is how a protected entry is *meant* to wait and gives the
lock up to do it; not a requeue, which is Ada's answer to wanting to wait
without holding anything.

A configuration pragma: it says something about the whole program rather than
about the point it stands at, so it is a property of the program rather than an
instruction in it. Ada makes it a pragma rather than a rule because the check
costs something on every instruction, and a program that does not want it
should not pay.

**`Clock`, `delay until` and `T'Execution_Time`.** The clock is the session's
own monotonic one, in seconds since the session began -- counted from there
rather than from the submission, so a program that reads it, is interrupted by
the next line being typed, and reads it again sees time having passed rather
than having gone back to nothing.

`delay until` waits for a time on that clock where `delay` waits for a length.
Ada has both because a loop that delays *for* a tenth of a second drifts by
however long its own body takes, and one that delays *until* the next tenth
does not. A time already past is no wait at all, which is the relative form's
rule said the other way round.

`T'Execution_Time` is how long a task has had *turns* for, which is not how
long it has existed: a task that spends its life at a barrier or in a delay has
used almost none of it, and that is what makes it worth asking rather than
reading the clock twice. Ada puts it in a package and this language asks it of
the task, which is the spelling it uses for asking anything about a value.

**A priority model.** `pragma Priority (N);` inside a task declaration says
what one runs at; a strand of higher priority is preferred whenever the machine
chooses which runs next, and among equal ones nothing changes -- ties go to
whichever comes first in the scan, which is what the machine did before
priorities existed. A program that mentions none is unaffected by their being
there at all.

Chosen, not pre-empted. This machine changes strand at defined points, so a
priority decides who goes next rather than interrupting who is going; Ada's
model is pre-emptive, and what is faithful here is the preference.

The same pragma on a protected declaration is its **ceiling**: the highest a
task may be and still call it. Ada's reason is that a task inside a protected
operation runs at the ceiling, so a caller above it would be lowered by
calling; here nothing changes strand inside one, so the ceiling has nothing to
raise -- and what is left is the rule, which a program that breaks it is told
about rather than left thinking it was honoured.

`'Priority` reads either back and `X'Priority := N;` changes either. Ada
assigns to a protected object's `'Priority` and calls `Set_Priority` for a
task; this language has one spelling for asking something about a value, and
this is that spelling written the other way -- the one attribute a program may
assign to, because an attribute is a question and most questions have no answer
to put back.

Reading asks the *machine* rather than the declaration, since either may have
moved since: a ceiling lives with its object rather than in the instruction
that takes its lock, because a program may change it and every operation has to
be asking the same question.

Changing a task's priority takes effect from the next choice onwards. A running
strand is not interrupted by it, for the same reason a higher-priority task
does not pre-empt a lower one.

**One** pragma, and the analyser is where that is said: a mechanism that took
any name would be a second place to configure things, and what a program can
say about itself belongs in the language rather than beside it.

**`'Size`** is how many slots a value takes, and **`T'Storage_Size`** how much
room one task is given -- a region of the store and a region of the stack,
together.

Slots, rather than the bits Ada counts for the first and the host's storage
elements it counts for the second. A slot here holds a value of any type, so
either count would be a number nothing in this machine means: a plausible wrong
answer is worse than an honest different one, and this is the one place where
saying so costs a reader a sentence and saves them a wrong assumption.

An object of a protected type is not a value, so asking its type for a width
would answer about the wrong thing: what it takes is the run of slots its body
declares. The *analyser* answers that, because it is the pass that has been
through the body, and the lowering pushes the number rather than working it out
a second way. Only a task has a `'Storage_Size`: nothing else is given a region
of its own, so nothing else has one to report.

**`T'Identity`** is which task, as something a program can hold. Ada needs the
attribute because a task object is not a value there; here a task *is* a value
-- what it holds is which strand runs it -- so this is a spelling of the same
thing, and two identities compare exactly when they are one task.

It has a type of its own, `Task_Id`, because a task object cannot be *copied*.
Ada's task types are limited and so are these, and protected types with them:
what one is is the thing that runs or the state that is shared, and a second
name for it would be a second of it or a lie about which one. An identity that
could be compared and never kept would be most of the way to useless, so the
identity is the copyable half.

An identity answers the two questions a task answers. Ada spells them as
functions on a Task_Id and as attributes on a task; this language has one
spelling for asking something about a value and uses it for both. What it does
not have is Ada's `Null_Task_Id`, so an identity is declared with the task it
means: one with nothing in it names no task.

**`T'Terminated` and `T'Callable`** are Ada's two questions about one task, and
they are not each other's negation. A task that has run its body out and is
still waiting for what depends on it has *completed* without having
*terminated*: it has ended nothing and will meet nobody, so both answer False.
That is why there are two, and why a strand records that its body has been run
out as well as that it is over. Both are questions about a strand rather than
about a type, so both are asked of the task's own value -- which is what a task
object holds.

**A protected type** is a protected object worth having more than one of. Each
object has state and a lock of its own, and one is made by *copying* the type's
declaration and body with the type's name replaced by the object's -- which is
what a generic instantiation here already does, and it leaves everything below
the analyser seeing what it has always seen: one protected object per
declaration. What it costs is a copy of the code per object; what it buys is
that no pass below had to learn what a protected type is.

A discriminant may say what it defaults to, and a type whose discriminants all
default is one Ada calls unconstrained: an object of it may stand without a
constraint. A default is an expression rather than a literal, evaluated where
the object is elaborated -- its names are the type's and its value is the
object's, which is what Ada means by evaluating a default at elaboration. All of them or none of them, which is Ada's rule -- a constraint
constrains the whole of a type, and a partial one would leave a program saying
which ones it meant to leave out by counting. The defaults are analysed where
the *type* stands rather than at each object, because a default belongs to the
type and what a name in one means is settled by what is in scope where the type
was written.

Discriminants follow from the same idea. What a protected type takes at
elaboration arrives as *constants at the head of the object's own body*, which
is what a discriminant is here: something the type is written against and the
object fixes. The body reads one by name like any other of its own
declarations, so a barrier may be written against one and nothing below the
analyser has a new idea to learn.

Two copies share the span they came from, on purpose: a diagnostic about one
points at the source the reader has to look at. So a copy is told from its
original by *name* as well as by position -- a slot and a routine are keyed on
both, because two objects' state is two variables under one position and
keying on the position alone gave them one slot between them.

**An entry family** is a run of entries rather than one: `entry Request
(Priority);` declares one per value of Priority, and a caller says which by
writing `Request (High)`. What it is worth is that an acceptor can serve one
member and leave the rest queued -- a task that can decide *what* to serve and
not only when.

A member's number is the family's own plus which member it is, and which member
is a value the program computes, so the machine takes it off the stack rather
than reading it out of the instruction. A family therefore reserves as many
numbers as it has members, which is why its index must be discrete and short: a
run is counted, and `entry E (Integer)` would ask for as many entries as an
Integer has values.

A protected object has families too, and the shape follows from what a
protected entry already is. Its body is one routine with one barrier, so a
family of them is one routine taking which member it is running for -- `entry
Pass (for Which in Level) when ... is` -- and the barrier can ask. A caller
queues by being inside that routine, so each member's queue is told from the
others' by the number the body computes from its own argument.

What a member takes is nothing. Ada writes a family member with parameters as
two parenthesised lists, which is a second shape for a call where this language
has one.

Either end of a `requeue` may be a member: `requeue Later (Which);` is Ada's
spelling and this one's. A member's number is one the body works out, so where
the caller was taken from and where it goes are both computed and handed to the
machine rather than written into the instruction -- which is what let one rule
serve a plain entry and a family member without asking which it was.

**`requeue E;`** says "not this one, that one": the caller being served is put
on another entry's queue and the body it was being served by is left. The
caller does not resume and is not told -- from its own point of view it is
still waiting for the call it made, which is the whole of what makes a requeue
different from returning and being called again.

The two kinds of queue are joined differently and so are moved between
differently. A caller of a *task* entry is a strand parked in a queue, so
moving it is a matter of writing down which queue it is in. A caller of a
*protected* entry queues by being inside that entry's own body, parked at its
barrier -- so moving it is leaving that body and entering another, keeping the
place the call came from: a tail call, which is what a requeue of this kind is.

**`with abort`** decides whether the caller keeps its way out. Without it the
call becomes uncancellable: the deadline a timed call was made with stops
applying, and a trigger abandoned by its abortable part can no longer be pulled
out of the queue. With it, both still work. The reason Ada makes this the
requeueing body's decision is that the caller never asked to be where it now
is, so whether it may still leave is not its own business to answer.

This was accepted and ignored until the machine had a queue a call could be
cancelled out of. The old note here said the two spellings meant the same and
gave a reason that was true when it was written -- a timed entry call polled a
barrier rather than queuing. A bounded call to a *task* entry queues, so the
reason expired and the flag became a claim nothing kept. It is kept now: one
field on the caller, set where the requeue moves it, read where a deadline
would fire and where an abandoned trigger pulls a caller out.

A requeued call is also un-met again -- from the caller's point of view the
rendezvous it was in was not the one it made, which is the same sentence that
says what a requeue is, applied to the answer a bounded call gets back.

One corner is this machine's own reading rather than Ada's letter: when the
abortable part of a `then abort` finishes first and the trigger cannot be
pulled out, the select waits for the call to be served and then leaves without
running the triggering alternative's statements. The abortable part had already
completed, and running them would say the trigger won a race it lost.

**`E'Count`** is the length of an entry's queue, asked inside the body of the
unit that declares the entry -- Ada's rule, and not fussiness: a count is a
queue's length at an instant, and a caller reading it from outside would be told
something that had already changed by the time it acted. Inside, the unit is
held and the answer keeps.

A task's callers and a protected object's queue in different places -- one waits
for a rendezvous, the other on a barrier -- and `'Count` is the same question
about either. A strand is in a protected entry's queue from the moment it asks
until the moment it is through the barrier, which is longer than it is asleep on
one: leaving the object wakes everyone waiting so that each asks again, and a
count that only saw the sleepers would report an empty queue at exactly the
moment the queue is being served.

An exception that leaves an accept body is the caller's as well as the
acceptor's. Ada re-raises it at the point of the entry call and releases the
caller, and so does this: the caller asked for a piece of work and is owed the
answer, and being left queued for ever is not one. It is *carried* rather than
raised, because the caller is not running -- what is set aside cannot raise, so
the exception waits with it and is raised where it resumes, which is the point
of the call. An `out` argument keeps what it held: what a rendezvous did not
finish saying, it did not say.

An exception completes what it leaves, and a raise may leave several masters at
once -- blocks and the frames around them -- each of which never reached its own
way out. All of them are waited for before the handler runs. The unwind itself
cannot wait: it is reached from inside whatever raised, and waiting means giving
up the turn, so the wait stands where the unwind *lands* instead. That is the
same moment from the program's point of view and a place a strand can be set
aside from. A handler in the block that raised is the other side of the rule:
the exception never left, so the block has not completed and its dependents are
waited for at its end rather than before the handler.

The rule lives in the machine rather than in the lowering. Every way of leaving
a region goes through an instruction -- falling off the end, an explicit
`return`, a task ending -- and a rule written at each of those would be the same
rule three times over, with the third one forgotten. A run that never started a
task pays one comparison for it.

**Discriminants** are what a task type takes at elaboration, where a subprogram
takes parameters at a call. They arrive the way a parameter does and sit where
one sits, which is what makes them nothing new below the analyser, and they are
constants in the body: a discriminant is what the object was elaborated with,
and there is nothing to assign to after that.

What is deliberately not here: parameters on a *protected* entry, a composite
entry parameter, more than one delay alternative in a select, and discriminants
on a single task. A protected entry is a barrier and a body and has no second
side to carry parameters to: what carries them is the rendezvous, and a
protected object has no strand of its own.

**Packages, and then generics.** `package P is ... end P;` with its body, and
`generic type Element is private; procedure Swap (...);` with
`procedure Swap_Numbers is new Swap (Integer);`.

A submission is a unit here, and until packages existed the only way to group
declarations was to keep them in a file and `source` it -- which shares the
text and not the name. Everything a script declared landed in one namespace,
and two scripts that both wanted a `Limit` could not be used together.

A package is a naming convention the analyser keeps, and *nothing below it has
to know one exists*. What a package holds is declared beside it under a dotted
name, so `Config.Limit` is one symbol whose name has a dot in it and `P.X` is a
way of spelling one. Nothing carries a scope; the lowering sees ordinary
declarations and emits them in order. `use P;` is remembered rather than
copied: declaring a second symbol per member would make a later declaration of
the same name collide with something the user never wrote.

A specification and its body may be separate submissions, exactly as Ada makes
them separate units -- so a body arriving on the next line completes a
specification the session is still holding.

A generic is a template, and its body is *not* analysed where it stands: what
every name in it means depends on what an instantiation binds its formals to,
and there is nothing to conclude until one does. An instantiation copies it.

The copy is the piece worth stating. `Adash.Language.Syntax.Graft` deep-copies
a subtree, replacing names as it goes -- a substitution on names *in the tree*,
not on source text, and that difference is the whole of why this is not the
textual expansion this project refused when it removed `alias`. What is
replaced is what the parser already decided is a name; nothing is re-lexed and
nothing is re-parsed.

A copy rather than a second reading of the same nodes, because conclusions are
recorded per node: two instantiations of one generic would otherwise overwrite
each other's answers about every name in it. The copy keeps the generic's
spans, so a diagnostic about an instantiation points at the generic's own
source -- and takes a fresh span for its *name*, because what identifies a
subprogram to the lowering is where its name was written, and two
instantiations sharing one would be one routine.

What is deliberately not here: a generic package, and a generic formal that is
anything but a type. A formal value or a formal subprogram would each need a
rule of its own about what an instantiation may supply, and a type is what the
useful generics in a shell take.

**And then records and arrays.** `type Line is record Number : Integer; Text :
String; end record;` and `type Counts is array (1 .. 4) of Integer;`.

A composite is its parts laid end to end in the machine's slots. That is the
whole of how one works: a variable of a composite type is a *run* of slots, and
reaching into it is arithmetic on where the run starts -- a known distance for
a component, a computed one for an element, after a check that the subscript is
one the array has. Four instructions carry all of it: `Offset_Place`,
`Element_Place`, `Copy_Block` and `Same_Block`.

What a composite is made of is not in the type. A type travels inside every
symbol and every parameter profile, and those are copied constantly; a
component list riding along would make every scope lookup carry the whole shape
of every type in sight. The type carries an identity and a width, and
`Adash.Language.Semantics` holds what the identity opens -- asked by the
analyser for what a component is called and by the lowering for where it sits,
so the two cannot disagree about a value's shape.

Three things follow from a composite being a run rather than a value, and each
is refused by name rather than half-supported:

- **A composite holds simple values only.** A record inside a record, or an
  array of records, would need an offset made of two offsets, and every place
  that walks a value would have to recur.
- **A function does not return one.** A result is what a call leaves on the
  stack, and there is nowhere for a run of slots to be left. An `out` parameter
  is how a program hands one back, and that is a run whose place the caller
  supplied.
- **A composite has no text form.** `put_line` writes what a value *is*, and a
  record is its parts: each of those has a text form where the whole has none.

Equality is the one that would have been quietly wrong. Two composites compare
slot by slot, each by what its own cell kind means. Comparing the first cell of
each -- which is what an ordinary comparison of two places would have done --
called two different records equal whenever their first components matched.

A composite is passed by reference whatever its mode, because a parameter is
one slot and a composite is many.

A composite variable survives a submission like any other, but it is the one
that has to be *assembled*: it has no single value on the stack, so it is
written out as the aggregate that rebuilds it, part by part, each in the form
this language reads back. A String component needs quoting for that, which is
what `Quote_Text` is -- Ada's own image of a String is the text with its
non-graphic characters bracketed, and that does not read back.

What is still not here is access types. A shell script has nothing to point at
that outlives the statement that made it, and a language with pointers has an
aliasing question in every assignment.

**A call can name its arguments, and a parameter can have a default.**
`Report (Text => S, Loud => True)`, and `procedure P (A : Integer := 1)`.

A call with several arguments of the same type says nothing about what they
mean: `Line ("x", True, 3)` is three values and a guess. This is the feature
that makes such a call readable, and it is Ada's, so it belongs here.

Overload resolution reads the names. A named argument is not in the position it
is written in, so a resolver comparing types by position rejects the candidate
that fits and accepts the one that does not --
`P (B => "x", A => 1)` against a `P (Integer, String)` and a
`P (String, Integer)` is the case that shows it.

`Adash.Language.Semantics.Match_Arguments` says which argument goes to which
parameter, and both the analyser and the lowering ask it. Computed rather than
recorded: it depends only on the call and the callee, both of which the
lowering already has, and a copy kept beside the tree would be a second thing
to keep true.

A default is a literal, possibly signed, or `True`/`False`. That is a
restriction and a deliberate one: an arbitrary expression would have to be
evaluated at each call in the scope of the *declaration*, and a name resolved
at the call site is the one thing that cannot do that. It is kept as the
literal's own source text, so it reaches the machine by exactly the path a
literal written at the call site takes -- no second encoding to disagree with
the first. A parameter that is written to rather than given cannot have one,
which is Ada's rule and a sensible one.

**A value has a position in its type, and a type has bounds.** `'Pos`, `'Val`,
`'Succ` and `'Pred` for Integer, Character and Boolean; `'First` and `'Last`
for those and for Float.

`Character'Pos` and `Character'Val` are the only way to reach a character code,
and until they existed a script could not write a tab outside an interpolated
literal, could not compare against a byte value, and could not step from one
letter to the next. That was not on the list of things this shell cannot do,
for the usual reason.

`'Succ` and `'Pred` are a position, an addition, and a position back, which is
what Ada defines them as. Written that way they need no instruction of their
own and cannot disagree with `'Pos` and `'Val`, and the check that going past
the last value raises lives in the conversion back rather than in three places
that would each have to remember it. An Integer is its own position, so the
lowering emits nothing for either direction.

A type's bounds are constants this build knows, so `Integer'Last` is one
instruction with no evaluation. `String'First` is refused: a String's bounds
belong to a String that exists, and `S'First` on one is answered.

**A loop can count backwards, and a value can be asked whether it is in a
range.** `for I in reverse L .. H loop`, and `X in L .. H` with `not in` for
the other answer.

Both are Ada and both are what a shell script wants several times a day.
Walking a range backwards meant a `while` with a counter maintained by hand,
which is the loop `for` exists to remove; asking about a range meant writing
the two comparisons out, which is longer, easy to get backwards, and evaluates
the value twice. Membership keeps the value in a slot and compares that, so a
call inside it happens once, as Ada says.

Only the range form of membership. Ada also writes `X in Integer` -- a subtype
mark -- and this language has no subtypes to name, so accepting the spelling
would promise something the type model cannot answer.

Writing the example for those found a defect underneath them: **an `if` with
two or more `elsif` branches had never parsed.** An `elsif` hands the rest of
the chain to the next one, which consumes the one closing `end if;`, and then
consumed a second on the way back out -- so the statement asked for one
`end if;` per `elsif`. One worked and two did not, and the difference is that
the `if` at the head of the chain returns where the `elsif` did not. Nothing
had ever written three branches without an `else`, which is what a function
classifying an exit status looks like.

**A script can save what it worked out.** `write_file (Text, Path)` replaces
what was there; `append_file (Text, Path)` adds to the end and makes the file
when it is not there, because the first turn of a loop that collects lines is
not an error.

Everything that wrote a file before these existed wrote what a *program* had
printed -- `run_into` and its relatives attach a program's output to a file --
so a value the language itself computed had nowhere to go. A shell that can
read a file, run a program and work something out, and then cannot save the
answer, has to end every script by piping through `cat`.

Text first and file second, matching assignment rather than `run_into`: nothing
follows the text, so there is no boundary to protect, and `write_file (Report,
"out.txt")` reads in the order it happens.

A write that worked says nothing. A command that announced each one would put
its own lines into the script's output, and then nothing could read what the
script itself printed. `Status` says it worked; a refusal says so on standard
error, and there are two refusals -- a path that cannot be written at all, and
a write that started and stopped -- because the first is the user's mistake and
the second is the machine's.

Ordinary permissions, not the private ones the shell's own stores get: this is
the user's file, written where they asked for it, and a shell that quietly made
it unreadable by anyone else would be deciding something that is not its to
decide.

Nothing removes a file. Unmaking things is what programs are for.

**Adash runs on its own virtual machine.** `Adash.Machine`: a stack machine
with frames, static links and one call out to the shell, in 1,325 lines against
the 3,995 of HAC's interpreter it replaces -- because it is only what the
lowering emits, and nothing else.

The dependency was worth entering and stopped being worth keeping. It was
entered for the runtime, HAC's compiler being unusable here: it has no syntax
tree, so there is nothing to annotate for highlighting, completion or a separate
semantic pass, and `Build_Main` compiles a whole unit, which a shell prompt is
not. So Adash wrote a front end. By the time that front end was 9,400 lines it
rivalled the 11,400-line compiler it existed to replace, in order to reach 4,000
lines of interpreter.

What actually decided it was the seam. The lowering did not use a published
interface: it built HAC's own identifier tables, block tables and activation
records, and kept a display vector in step -- it impersonated compiler output.
Every defect that seam produced was of one kind, and this repository fixed three
of them in as many months: a display vector not restored after a call to the
command stub; bridge slots taken from whichever frame happened to be emitting;
an argument cell typed for text and handed a number.

The machine removes each of those classes rather than each of those bugs. Static
links instead of a display, so nothing has to be kept in step. Variables and
expression operands in separate structures, so there is no frame arithmetic to
agree about. The shell's answer returned from the call rather than written into
a reserved slot, which deletes the whole stub -- no identifier table, no
activation record, no answer cell, no halt cell.

Ada's semantics were kept where they were load-bearing: `Real` is `digits
System.Max_Digits` and the whole number is 64-bit, so `'Image` renders and
`Integer'Last` reads exactly as before. Two exception details are now this
repository's words rather than HAC's, and two conformance cases record it.

**A block or a body can answer for what went wrong.** `begin ... exception when
Constraint_Error => ... when others => ... end;`, on a block and on a subprogram
body, with the four exceptions anything here raises: Ada's three, plus the one
Ada.Strings defines for an index outside a string.

This was the first thing built after the machine, and it is why the machine was
built. Under HAC it would have meant reverse-engineering somebody else's
exception machinery through a seam that was already the source of three defects.
Owning the machine, it is a handler stack, an unwind in the one place that
already reported failures, and three opcodes.

Unwinding is the part that matters. A handler records how deep the frames and
the operand stack were when it was set; raising puts them back before jumping,
which is what lets a handler in an outer block catch what a call two frames down
raised. A machine that only remembered where to jump would run the handler on
somebody else's frame.

An exception nobody answers for is raised again rather than swallowed: a handler
that looked at one and matched nothing passes it outwards, and one that matches
nothing at all leaves the program failing as it did before. `Broken` -- a defect
in the machine rather than in the program -- is never caught, because a handler
catching that would hide the one thing worth reporting.

**A pipeline joins programs.** `pipe ("cat", "f"); pipe ("sort"); pipe_run;`
runs them together with each reading what the one before it wrote.

Two commands rather than one, because a pipeline is a *list of command lines*
and this language has no lists. A single call would have to carry the boundary
between stages inside its own arguments -- a separator string, parsed -- which
is the second command language the specification rules out, just spelled with
quotation marks. Building a stage at a time mirrors what the subsystem
underneath actually does: add stages, then start.

`Adash.Execution.Pipelines` had supported several stages since Phase 11 and the
whole shell contained exactly one `Add_Stage` call, so every pipeline ever run
had one stage. That is the third subsystem found complete, tested and
unreachable -- after job control and redirection -- and none of the three was on
the list of things this shell cannot do. The list records what somebody thought
to write down; it does not notice a capability with no way in.

The stages are forgotten once they run, and forgotten too when the pipeline
cannot start: leaving them would put them at the front of whatever is built
next, which is the last thing somebody fixing a mistyped program name wants.
Running with nothing added is refused rather than treated as a pipeline of no
stages, which would succeed and look like it had run something.

**A program's output can go to a file and its input can come from one.**
`run_into ("out.txt", "ls", "-l")` and `run_from ("in.txt", "wc", "-l")`.

`Adash.Execution.Redirection` and the stream endpoints on an invocation have
existed since Phase 11, tested, and **nothing referenced them** -- the same
shape as job control before `start`. Looking for the next entry on the
limitations list found this instead, which is the second time that has happened
and is worth saying plainly: a subsystem nobody can reach is indistinguishable
from one that does not work, and the list does not notice.

Four commands, because opening a file for writing is four different acts:
`run_into` replaces, `run_append` adds to the end, `run_new` refuses a file that
already exists, and `run_from` reads. The file is named first because the
arguments after it belong to the program and there is nowhere else to put the
boundary. This language has no `>` and will not grow one: a second notation for
running things is a second command language, which the specification rules out.

**The first version of this opened the file itself**, and that was wrong. Asking
which packages nothing outside themselves referenced -- the check that found the
three unreachable subsystems -- found `Adash.Execution.Redirection` still
referenced only by its own test, because the command had grown a private copy of
what that package does. The copy was quietly poorer: it could only truncate, so
there was no appending and no refusing to clobber; and it opened the file when
the redirection was named rather than when the program was about to run, so a
command refused for some later reason had already created its output.

Those are not incidental. Appending is a property of the open file rather than a
seek the shell performs, or two programs appending to one log overwrite each
other. Refusing an existing file has to be the open itself rather than a check
before it, or two shells creating one file both find it absent. The subsystem
knew all three; the copy knew none of them.

Making it work turned up a defect in the pipeline. `Start` overwrote **every**
stage's input with the shell's own, so an input the caller attached was
discarded -- silently, because a program reading an empty stream succeeds:
`wc -l` on a two-line file reported nothing at all. It now takes the shell's
input only where the stage has not been given one.

**`run` starts a program and waits for it**, which is the thing a shell is for.
Until now that took two commands and a job number -- `start`, then `wait` -- with
two job lines printed around the output. It was not in this list of limitations
either, which is worth saying: the gap was invisible because job control was
recorded as complete and nobody had asked what running a program actually looked
like.

A foreground program is forgotten once its status has been taken. `Jobs.Forget`
is what does it: `Reap` deliberately keeps a finished job until its change has
been announced, so that a background job is never removed before the shell has
said it ended, and marking every job reported to get rid of one would have
swallowed that notification.

**Ctrl-C stops it**, and making that true fixed something wider. The token a
waiter polls now answers for a recorded interrupt as well as for an explicit
request, instead of each waiter consulting the signal separately. One of them
was not: a foreground program waited out its full duration because the pipeline
polled the token while only the virtual machine consulted the signal. The engine
had the rule; the token has it now, and the engine's copy is gone.

**Job control is reachable from the language.** `start ("sleep", "30")` runs a
program in the background and records it; `jobs` lists what is running; `wait`
gives a job's status and `stop` ends it.

`start` is what made the rest reachable at all. `Adash.Execution.Jobs` had been
complete and tested since Phase 11 and `jobs` reported an empty list honestly --
because nothing in this language could run an external program, so there was
never anything to list. A subsystem nothing can reach is indistinguishable from
one that does not work.

The program and its arguments are separate values rather than a command line.
Splitting a string here would invent a quoting rule this language does not have,
and a filename with a space in it would become two arguments.

That forced a widening underneath. A command call carried exactly **one**
argument from a program: the stub the machine calls through was built with one
value slot, and anything more was refused. `start ("sleep", "30")` is a program
and its argument and neither half is optional, so the stub now carries four --
one triple of kind, number and text per argument, all of them pushed on every
call because the machine takes the whole activation record at once.

A job ended by a signal says so rather than reporting an exit status it never
chose. `Exit_Status.Code` is only meaningful for a program that chose one, and
reading it anyway described a terminated job as "status 0".

**`source` runs a file in the session that called it.** That is what makes it
worth having: a child process could not change the environment of the shell
that started it, and a sourced file can, because it is the same session.

The layering that made this look impossible is real and was solved rather than
bent. `source` is a command; commands are called *by* the engine; running a
script means submitting to the engine. So `Adash.Commands` declares the
capability it needs as an interface and whoever owns the session supplies it --
the same shape the language already uses to call commands from inside the
virtual machine, for the same reason.

What actually stood in the way was reentrancy, in three places, none of which
was obvious from the outside:

- `Adash.Engine.Session` reused one buffer, token stream and tree between
  submissions, deliberately, as the only cost an interactive loop cannot
  amortise elsewhere. A submission made *during* another would have overwritten
  the outer one's tree while it was still being lowered. A submission now brings
  its own set when it finds the session busy.
- `Adash.Language.Evaluation` reached its command sink through a body-level
  variable, set on the way in and cleared on the way out. A nested run cleared
  it, and the outer program lost the ability to call anything. Saved and put
  back now.
- The stub file HAC needs a source stream for had a fixed name, so a nested run
  reopened a file the outer run still held open. It carries the process id and a
  serial now -- which also fixes two shells running at once, which had the same
  collision and nobody had hit yet.

A file that sources itself is refused with the path that closed the cycle, not
left to loop.

**A long line wraps.** It used to scroll sideways, because "a wrapped line
cannot be redrawn without knowing how many rows it took, and the terminal will
not say". The terminal still will not say -- but the answer is computable, and
became computable when width started being counted in cells. With one cell per
character the row count was wrong for any line containing an ideograph, and a
wrong row count leaves debris on screen after every edit.

The breaks are written rather than left to the terminal, and each row stops a
cell short of the edge. Writing into the last column makes some terminals wrap
and others not; breaking early means the question never arises.

**The cursor is placed by walking, not by dividing**, and that is the whole of
what was hard. Two attempts at arithmetic were wrong in two different ways. A
position falling exactly on a row boundary is the end of that row and not the
start of the next, because the break is written *before* a character that would
overflow -- a row filled exactly has none after it. And rows are not all the same
width: one ending in a wide character stops a cell short, so a cell count
divided by the row width is out by one on every line of ideographs. The layout
and the cursor are now derived by the same walk, so they cannot disagree.

Both mistakes were found by driving the shell under a pseudo-terminal and
replaying its output through a terminal emulator written for the purpose --
counting escape sequences said only that something was happening. `Place` is
public so that the part that was wrong twice is testable without a terminal.

A line taller than the screen still scrolls sideways. Wrapping it would scroll
the terminal, and a redraw cannot find its way back to a row that has gone.

**Display width is counted in cells.** `Adash.Display_Width` answers how much
room text takes: a wide or fullwidth code point is two cells, a combining mark
or zero-width character is none, everything else is one. The editor scrolls,
slices and places its cursor in cells, so a line of East Asian text redraws
where it is rather than half a screen left of it.

Driven under a pseudo-terminal, stepping the cursor back over one ideograph now
emits a two-cell move where it used to emit one -- which is the whole defect,
seen from outside.

The table is written out in the source rather than derived from a Unicode data
file, because this repository has no such file and generating one would put a
build step between the source and the binary. It covers the ranges Annex 11
calls Wide or Fullwidth and the combining ranges a shell is likely to meet; a
code point in none of them is one cell, which is what the editor assumed for
*everything* before. Nothing it does not cover became worse, but that default is
an assumption rather than knowledge and the package says so.

A wide character that would straddle the right edge is left out of the redraw
entirely. Half of one is not something a terminal can draw, and letting it wrap
is what the horizontal scrolling exists to avoid.

**A session can keep its history in a file of its own.** `history.per-session`
gives each shell `history-<pid>.jsonl` in the data store, written as lines are
typed, and merged into the shared file in one block when the session ends.

The point is what the shared file reads like afterwards. Two shells appending to
it a line at a time interleave correctly -- the lock has always seen to that --
but the result is their commands shuffled together, which is not what either
user did and not something either can read back. Merging at the end puts each
session's run in one piece.

Verified by running two overlapping sessions: the shared file holds `env;
version;` then `pwd; version;`, each block intact, with no session files left
behind.

It is off by default. One shell writing one file is what a user expects, and
the merge only earns its keep when two are running at once.

**A session that dies before merging is swept up by the next one to start.** Its
file is found, its lines are folded into the shared history, and what it left is
removed.

The earlier note here said this needed a directory listing hostkit does not
offer. That was true about hostkit and the wrong conclusion:
`Ada.Directories.Start_Search` is standard Ada, portable, not on the forbidden
list, and already used throughout this library. The platform rule is about
`GNAT.OS_Lib`, `Interfaces.C` and `System.OS*` -- reaching for the host behind
hostkit's back -- not about the standard library.

**Whether a session is still running is asked, never inferred.** Each holds an
exclusive lock on `history-<pid>.jsonl.owner` from start to finish; a sweep tries
that lock without waiting, and only a lock it actually gets means nobody is
there. Reasoning from the process id in the name would have been the obvious
shortcut and is wrong: ids are reused, and a sweep that believed the number
would eventually take a running shell's history.

Only a lock it *holds* counts. A store that will not carry locks, a directory
that could not be made, another session on a reused id -- each leaves this
session unable to claim a file of its own, and it uses the shared one instead. A
session file nobody claims is one the next sweep takes away while it is still
being written, which is exactly the failure this arrangement exists to prevent.

Verified both ways: a session killed with `SIGKILL` has its `pwd; version;`
folded in by the next shell, and a session still running keeps its file while
another shell sweeps around it.

**Configuration is still per-user.** Only history gained a per-session notion.

**A subprogram declared on one line is callable on the next.** The session keeps
the source of what it declared and puts it in front of whatever is submitted
after, so a definition and the line that uses it are one program -- which they
have to be, because a name is resolved by the semantic pass and a pass that
never saw the definition cannot resolve a call to it.

Redefining a name replaces what was carried; a declaration of a different
profile is an overload and both stay. That is the language's own rule applied
across submissions rather than within one, and it needs the submission parsed
*twice*: what a session carries can only be put in front of a line once it is
known what that line replaces. Prepending first and sorting it out afterwards
reports a duplicate, which is what a user redefining something interactively
least wants to see.

**Objects persist too, with the value they ended with.** `X : Integer := 5;`
then `X := 9;` then `put_line (X);` prints 9 -- not the 5 it was declared with,
which is what re-running the initialiser would have given.

Getting a value out of the machine is the whole of the problem. The frame it
lives in is gone once the run returns, so the program reports its own
variables rather than being asked afterwards: the lowering emits, after the
statements and before the halt, one hand-back per top-level variable carrying
its name, how it was declared, and its value as text. The session writes each
back as a declaration the next submission reads. That decision was made when
the machine was somebody else's and its stack was not on offer; it is kept
because a program that reports what it holds is one whose answer does not
depend on where the machine happened to leave it.

As text for every type, and that was not the first design. The record the
machine hands over has one numeric slot and one text slot: a Float does not fit
the numeric one at all, and an Integer, a Boolean and a Character all fit it in
a way that loses which of the three it was -- a Boolean came back as
`B : Integer := 0`. `'Image` renders each as something this language reads back,
a String is already text and is quoted on the way in.

`constant` travels with the type, or a constant would come back assignable.

**A program stopped before it ends hands nothing back**, so its variables are
not carried. `quit`, `return` and an unhandled exception all leave the
hand-back unreached, and what a half-run program left in a variable is not a
value anyone chose.

The hand-back has an operation of its own on the sink rather than arriving as a
call to a reserved command name. A test probe counting command calls found the
difference: it was being handed something that is not a command.

Finding this working turned up a defect in the parser that had been there since
Phase 5: **a statement's extent reached one token past itself**, because it
ended at `Here` -- the token that comes *next* -- rather than at the last one
consumed. Harmless while a span was only ever pointed at; not harmless the
moment the source under it was read back, which is what carrying a declaration
does. Fixed for the declaration node; the other forty-one sites still overshoot
and are worth a sweep.

**`alias` was retired rather than built.** It had been registered since Phase 9
and reported as not in this build; the honest answer turned out to be that it
does not belong here at all.

Its own documentation said it was for defining "a short name for something
longer". This language already has one, and a better one:

```ada
procedure LL is
begin
   start ("ls", "-l");
end LL;

LL;
```

That is checked, composable, and works today. An alias would have been the same
idea with none of those properties, and building it would have cost one of three
things the shell is not willing to spend:

- **Textual expansion** -- `alias ("ll", "start (""ls"");")` substituted before
  the line is parsed -- is a second command language, which the specification
  rules out. The same characters would mean different things depending on
  session state.
- **A dynamic name** would make the semantic pass consult the running session.
  Every other name is resolved from what the analyser owns, and a program whose
  meaning depended on when it ran would undo the property the conformance suite
  rests on.
- **A binding invoked by another command** -- `alias ("ll", "ls", "-l")` and
  then something to run it -- avoids both, and is a second way to name things
  that buys nothing the language does not already give.

What aliases are usually reaching for in other shells is not naming but
**persistence**: a definition typed on one line and used on the next. This shell
has that, and it is what makes an alias unnecessary rather than merely
redundant -- a subprogram typed at the prompt is there on the next line, and so
are types, packages, generics, task types, and protected objects with the state
they ended with. What is not carried is a task object or an identity of one,
for the reason given below: a task does not outlive its master, and a
submission is one.


## What Adash cannot do yet

Two lists. The first says where the subset ends -- what is Ada and is
deliberately not in this language, so that a reader knows the boundary rather
than discovering it. The second says what is inside the subset and imperfect.

### Where the subset ends

Adash's command language is *a defined subset of Ada*, and a subset is defined
by what it leaves out as much as by what it takes. Everything here parses in
Ada and is refused here, by name, on purpose. None of it is pending work.

- **No access types.** A shell script has nothing to point at that outlives the
  statement that made it, and a language with pointers has an aliasing question
  in every assignment.
- **A record or an array holds simple values only** -- no record inside a
  record, no array of records. Reaching into one would need an offset made of
  two offsets, and every place that walks a value would have to recur.
- **A function does not return a record or an array**, and neither is written
  by `put_line`. Both follow from a composite being a run of slots rather than
  a value; the section above says why for each.
- **An array's bounds must be known before the program runs**, and it holds at
  most 4096 elements: it is a run of slots in a frame whose size is decided
  when the program is built.
- **No derived types.** `type Count is new Integer;` is not written. A subtype
  is the narrowing a script wants; a *new* type would need its own operators
  and its own literals to be worth anything.
- **A subtype's bounds must be known before the program runs**, because the
  check is two numbers in an instruction. `range 1 .. N` is refused rather than
  half-supported.
- **A range narrows a discrete type only.** Ada allows one on a Float;
  admitting it here without the check would be a constraint that does nothing.
- **No generic packages**, and no generic formal that is not a type. A formal
  value or a formal subprogram would each need a rule of its own about what an
  instantiation may supply.
- **No child packages**, no `private` part, no renaming of a package. A package
  here is a name for a group of declarations and nothing more.
- **A requeue names an entry of its own unit.** Ada lets it name any entry at
  all; what the caller is moved to has to be a queue this unit can put it on,
  and another object's is reached through a name the body may not even have.
- **A requeue's target takes nothing.** Ada allows a target that takes what the
  caller already gave; what the caller gave sits in a run of its own slots,
  laid out by the entry it called, and a target with a profile of its own would
  be reading it by somebody else's layout. A body that needs the argument takes
  it before moving the caller on.
- **Discriminants belong to a type, not to a single task or protected object.**
  A single one is elaborated where it is declared and there is nowhere to write
  what it would take; Ada's answer is a default on every one of them, which is
  a second way of giving one something when it already has operations.
- **At most one delay alternative in a select.** Ada takes the shortest of the
  open ones, which is a run-time comparison that decides which branch runs;
  one is what a script wants and two are refused where they are written.
- **Neither a task nor an identity of one is carried between submissions.**
  What either holds names a strand, and a task does not outlive its master --
  so what would be carried is the name of something that has ended. There is
  nothing to carry it *as*, either: a value is handed back as the text a
  program could have written, and a task has no such text.
- **A task object is not carried between submissions.** What it holds names a
  strand, the submission that declared it is its master, and Ada says a task
  does not outlive its master -- so what would be carried is the name of
  something that has ended. A task *type* is carried, body and all, because a
  type is a template and starts nothing.
- **A protected entry takes no parameters.** What carries an entry's parameters
  is the rendezvous, and a protected object has no strand of its own to be the
  second side of one. Refused where it is written rather than ignored, because
  a parameter that was accepted and never given a value would be read as
  whatever its slot held.
- **An accept must repeat the profile its entry was declared with.** Ada has it
  written again; this holds it to writing the same one, because the two sides
  agree on where the arguments are by agreeing on what they are.
- **An entry parameter is a simple value.** The arguments of a rendezvous live
  in a run of the caller's slots, one slot each, and a composite is itself a
  run: it would need a run inside a run, and every place that walks an argument
  would have to know how far the next one is rather than that it is one along.
- **`delay` takes a Float**, where Ada takes a Duration. This language has no
  fixed-point type, and Float is the closest thing it has.
- **Tasks are interleaved rather than parallel**, and by default on a fixed
  instruction quantum -- `pragma Task_Dispatching_Policy` says otherwise. A
  program that relies on the order two tasks print in is relying on the policy
  rather than on the language.
- **At most fifteen tasks at once**, each with a fixed region of the machine's
  slots and stack.
- **No `raise ... with "a message";`.** Ada attaches a string to the
  occurrence and a handler reads it back with `Exception_Message`; this
  language has no way to read one back, so the string would be written and
  never seen. A program's own exception says what its name says. A script reports a
  failure by exiting with a status, which is what a shell script is read by.
- **No `goto` and no statement labels.** A submission is short by nature, and a
  jump into the middle of one is a thing to read twice.
- **No `renames`.** A short name for something longer is what a subprogram is,
  and this language has those.
- **No loop names**, so `exit Outer;` is not written. `exit when` inside the
  loop it belongs to is.
- **No user-defined operators**, no `for ... of`, no attributes beyond the
  seventeen listed below, and no representation clauses.
- **An aggregate is positional, or named for a record.** `(7, 8, 9)` builds an
  array and `(A => 1, B => 2)` a record; `(1 => 7, 2 => 8)` and `(others => 0)`
  are not written, and an aggregate is a value in a declaration or an
  assignment rather than an argument at a call. One component is `(A => 1)` and
  not `(1)`, which is Ada's rule as well: a parenthesised expression is what
  the second one is.
- **Membership is against a range**, `X in L .. H`, and not against a subtype
  mark -- there are no subtypes to name.
- **A parameter's default is a literal**, possibly signed, or `True`/`False`.
  An arbitrary expression would have to be evaluated at each call in the scope
  of the declaration, and a name resolved at the call site cannot do that.

### What is inside the subset and imperfect

- **Overload resolution is outside-in, not simultaneous.** What a context
  expects reaches into it -- an object's type, a parameter's, a case's, a
  return's -- and settles a call or a literal that several declarations could
  answer. Between the two operands of a comparison or a membership it works
  sideways as well: when exactly one of them is open, the other is analysed
  first and its type settles it. What it does not do is try *every* combination
  when both ends are open: `Red = Red` with `Red` in two types is refused,
  which is what Ada does with it too, but so is anything else needing two
  choices made together. Ada resolves a call and everything around it at once;
  this resolves from the outside in and from the closed end sideways.
- **Nothing at submission level can be named after a predefined entity or an
  internal command.** For a subprogram the reason is resolution: those accept
  any type, so a user's version would fit every call the original does and every
  one would be ambiguous. For anything else it is that the name is already in
  that scope. A body's own declarations are a different scope and may hide
  either, which is Ada's rule and this one's.
- **A command call carries at most five arguments** from a program, and a call
  answered by the shell four -- it spends the first slot on the name of what is
  being asked for. The activation record the machine builds has a fixed shape,
  decided when the stub is built rather than when a call is written.
- **Subprograms nest nineteen deep**, and deeper is refused by name. Not a
  machine limit -- the machine walks static links and does not count them --
  but a front-end one: the analyser and the lowering each recurse once per
  level, and a stated limit is a better answer than the compiler's own stack
  running out somewhere nobody can read. `Adash.Language.Max_Nesting`.
- **Everything is passed by reference**, where Ada passes elementary types by
  copy. Reading an `out` parameter before writing it, and aliasing two write-back
  arguments, are defined here and erroneous or unspecified in Ada. No *correct*
  Ada program can tell the difference.
- **There are seventeen attributes.** On a value or a type: `'Image`,
  `'Value`, `'Pos`, `'Val`, `'Succ`, `'Pred`, `'Length`, `'First`, `'Last` and
  `'Size`. On a task, an entry or a protected object: `'Priority`, `'Count`,
  `'Identity`, `'Terminated`, `'Callable`, `'Storage_Size` and
  `'Execution_Time`.

  `'Image` and `'Value` are refused for a `String`: Ada 2022 defines a String's
  image as the text in quotes with non-graphic characters bracketed, which is
  not the text itself, and reading one back is not defined at all. `'Length` is
  an array's, and answers for a `String` and for a declared array alike, as
  `'First` and `'Last` do on one. The four position attributes are defined
  only for the discrete types, which is Ada's rule.
  `'Count` is refused outside the body of the unit that declares the entry, and
  `'Priority` may be assigned to as well as read.

  `'Size` and `'Storage_Size` answer in this machine's own unit -- slots, and
  slots and stack -- rather than in bits or bytes. That is not Ada's meaning
  and the number is not comparable with a compiler's, but it is the only
  honest one available: this build has no layout to report, so what it reports
  is what it does have. There is still no `'Range` and no representation
  attribute.
- **Display width covers the ranges named in `Adash.Display_Width`**; a code
  point in none of them is one cell, which is an assumption rather than
  knowledge.
- **Configuration is per-user.** Only history has a per-session notion.
- **A program that stops early carries nothing forward.** `quit`, `return` and
  an unhandled exception all leave the hand-back unreached, so the variables of
  that submission are not kept.
- **A session with no log -- a script -- says `history` has nothing to report**,
  which is a different thing from a missing feature and is worded differently.
  Every command the shell registers now works.
- **A line taller than the screen scrolls horizontally rather than wrapping.**
  Wrapping it would scroll the terminal, and a redraw cannot find its way back
  to a row that has scrolled off.
- **Windows has no pseudo-terminals and no process groups.** `Hostkit.Pty` and
  `Supports_Foreground_Group` are False there; the one thing that host *can* do
  is report Ctrl-C, which `Can_Record` answers for.
- **Byte-identical binaries are not claimed**; see `docs/RELEASE.md`.

These two lists are probed rather than remembered. Each claim in them was
written as a program and run, and five had drifted from what the build does --
aggregates, discriminant defaults, `'Length` on an array, and two sentences in
`README.md` that predated records and generics. A claim about behaviour is a
test that nothing runs, which is why they drift; the honest answer is to run
them, and the sweep is worth repeating whenever a section here is touched.

A note on one of those, because it was the largest single defect found after
the machine landed and it was found by looking rather than by a test failing.
**Four subsystems were writing English.** The rule is that every user-visible
string lives in the catalog, and it was true of the obvious ones from the day
`Adash.Messages` existed. It was quietly untrue of a class beside them: the
machine's exception details, the parser's `expected an expression`, the
lowering's thirty-four refusals, and the settings' `true or false`. None of
those packages is a presentation boundary. Each was found by grepping the
sources for a string literal holding two ordinary words, which took a minute,
and `adash_check` now does it on every run.


## Dependency work outstanding

These block specific phases and are tracked here because no amount of work
inside Adash resolves them: each is a capability another crate owns, and the
answer is always to extend that crate rather than to grow a second copy here.

**`jsonlib` and `tomllib` now exist**, as sibling crates at
`../jsonlib` and `../tomllib`. Both are complete, tested and warning-free:
jsonlib 26 tests, tomllib 21 tests, neither depending on anything beyond the
compiler. Phase 15 is no longer blocked.

- **jsonlib** reads RFC 8259 and nothing else — no comments, no trailing
  commas, no `NaN`, no leading zeros — because a parser that accepts more than
  the standard produces documents other tools reject. Numbers keep the text
  they were written with and members keep their order, so a document read and
  written again is byte for byte the same document. Writing cannot fail: the
  walk is iterative, so depth is not a failure mode. `Jsonlib.Pointers`
  implements RFC 6901 for reaching into a document by path.
- **tomllib** implements TOML 1.0.0 including the redefinition rules in full —
  duplicate keys, repeated headers, closed inline tables, dotted keys that
  close their table, `[[header]]` arrays that a static array cannot become.
  The four date-time types stay distinct and are never converted, because
  turning a local date-time into an instant needs a zone the file did not give.
  Unlike jsonlib it does *not* promise a byte-for-byte round trip, and says so:
  TOML has several ways to write the same document and a document does not
  record which was used.

Both are pinned in `alire.toml` as of Phase 15: `Adash.Configuration.Files`
reads and writes TOML through tomllib, and `Adash.Persistence.History` encodes
each entry as a JSON string through jsonlib.

**`hostkit` now has the shell primitives.** Six packages were added to it, each
with a body for linux, macos, windows and unsupported:

- `Hostkit.Descriptors` — pipes, duplication, explicit inheritance, non-blocking
  mode, reads and writes that distinguish end-of-file from would-block from a
  broken pipe, file opening for redirection including a genuine append, and
  assignment onto a child's standard streams.
- `Hostkit.Signals` — a portable signal set, sending to a process or to a whole
  process group, and dispositions, so a shell can ignore SIGPIPE rather than die
  on its first truncated pipeline.
- `Hostkit.Spawn` — spawning with caller-supplied descriptors, a constructed
  environment, a working directory, process-group placement and terminal
  handover; waiting, blocking or polling, with exits, signals, stops and
  continuations told apart.
- `Hostkit.Terminal_Control` — the foreground process group, terminal modes
  including raw, and window size.
- `Hostkit.Pty` — pseudo-terminals, for running a child under a terminal it
  believes is real.
- `Hostkit.Locks` — advisory file locks, for persistence.

Phases 11, 14 and 15 are unblocked as far as the platform is concerned.

Two capabilities are refused rather than provided, on Windows only, and a
consumer degrades on them explicitly:

- **No signals or process groups.** `Hostkit.Signals.Is_Supported` and
  `Hostkit.Terminal_Control.Supports_Foreground_Group` are False there. Job
  control has to degrade, which §7.6 already requires. The one exception is
  narrow and has its own query: `Hostkit.Signals.Can_Record` is True for
  `Signal_Interrupt`, because a console can report Ctrl-C even where no signal
  exists to send. Nothing else about that signal works there.
- **No pseudo-terminals.** `Hostkit.Pty.Is_Supported` is False. The host's
  answer is the pseudo-console, a differently shaped API; implementing it
  belongs in hostkit when a consumer needs it.

**`hac` is vendored at `../hac`, version 0.42.0, with two local changes.** It
builds, runs, and is now linked into Adash: `hac_lib.gpr` exports `HAC_Sys` as a
library, and the crate's manifest points at it. Fork change 1 is done.

**Phase 7's mechanism is proved.** A spike emits p-code into a `Compiler_Data`
Adash populated itself and HAC's virtual machine runs it — verified with a
division by zero as the control, which reports an unhandled exception where the
same program without it reports none.

The frame setup turned out to be four fields and one `Blocks_Table` entry, not
the reimplementation of `Parser.Block` an earlier note in this file estimated;
that estimate was wrong and `docs/hac-assessment.md` records the correction and
the working recipe. Two entanglements remain worth knowing:
`Compiler.Init_for_new_Build` calls the scanner, so a source stream must be
attached before it, and `Co_Defs` is internal and upstream promises nothing
about its shape.

What remains is the lowering itself: walking the analysed tree and emitting the
instructions for each node kind, plus evaluation contexts, frames, calls and
exceptions. See `docs/hac-assessment.md` for the assessment and `../hac/FORK.md`
for provenance and required changes.

**The integration is decided: Adash parses into its own tree and lowers into
HAC.** Adash owns the lexer, the parser, `Language.Syntax` and semantic
analysis; HAC contributes its virtual machine, its 123-instruction p-code set
and its runtime library.

The lowering target is `HAC_Sys.PCode` through `HAC_Sys.Compiler.PCode_Emit`,
not `HAC_Sys.Targets`. Targets is an abstract-machine interface its own author
describes as needing "likely hundreds of methods in the end"; at 0.42.0 it has
six that emit code, and 141 of the compiler's own emissions bypass it against 29
that use it. P-code is complete because the compiler depends on it being so.

**This is not a competing parser under §2.1.** That rule forbids reimplementing
functionality *HAC already provides*, and HAC's parser does not provide a parse
tree — it emits object code as it goes and keeps nothing. Adash's parser
produces something HAC has not got and cannot be asked for. Adash still writes
no bytecode engine and no interpreter; lowering to p-code is how it avoids
doing so.

**Consequence: HAC enters at Phase 7, not Phase 5.** Phases 4, 5 and 6 involve
no HAC at all, which makes them independent of the fork and of upstream churn.

Costs, recorded rather than discovered later:

- Adash will depend on `HAC_Sys.Co_Defs`, an internal package. `Interpret` takes
  a `Build_Data` holding a `Compiler_Data`, and that record carries the object
  code alongside the arrays, blocks, float-constant, string-constant and task
  tables the interpreter reads at run time. Adash's lowering must populate all
  of it, and upstream promises nothing about its shape.
- Three fork changes are needed: a library project file, a diagnostic code in
  `Defs.Diagnostic_Kit`, and that library exporting `Co_Defs`, `PCode` and
  `Compiler.PCode_Emit` rather than only the `Builder` façade.

What it buys beyond the tree: the REPL gets *easier*. The symbol table between
prompt lines becomes Adash's own, so a line is analysed against the session's
accumulated scope and only its new statements are lowered and run. HAC never has
to hold a compilation context across units — which was the substantial change
the alternative would have required.

## Definition of done

A **package** is complete when its spec and body are implemented, ownership and
error behaviour are documented, public GNATdoc is complete, unit tests pass,
integration tests pass where applicable, requirements are traceable, subsystem
AI documentation is updated, `repository.toml` is updated, and no temporary
implementation remains.

A **feature** is complete when its behaviour is specified, implemented and
tested; regression coverage exists for any defect fixed along the way;
conformance cases exist for observable behaviour; documentation and examples are
updated; messages are added and validated; configuration and persistence
migrations are added where needed; and repository validation passes.

A **subsystem** is complete when its package inventory is complete, its
dependency graph is valid, its public API is stable, and its tests,
documentation, AI documentation, metadata, traceability, benchmarks (where
performance-sensitive) and conformance suite (where behaviour is observable) are
complete.
