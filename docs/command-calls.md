# Making commands callable from the language

This records a spike, and what it proved. It is the design for closing the
largest gap in `ROADMAP.md`: that a submission is either internal commands or
program statements, never both, so `quit (Total);` after a loop cannot be
written.

Written down for the same reason `hac-assessment.md` was: the expensive part of
this work was finding out whether the mechanism exists and what it needs, and
that knowledge is worth more on paper than in somebody's memory.

## There are two gaps, not one

Discovered while scoping, and worth stating plainly because fixing the first
alone does not deliver what anybody wants:

1. **A submission cannot mix commands and statements.** `Adash.Engine.Submit`
   counts how many top-level statements name internal commands; all or none is
   accepted, and anything between is refused with `Error_Mixed_Submission`.

2. **A command's arguments are source text, not values.**
   `Engine.Called_Arguments` returns `Syntax.Text` of each argument node, so
   `quit (Total)` passes the four characters `Total`. Even with the first gap
   closed, that call could never work.

Closing the second requires commands to be *callable entities* whose arguments
the virtual machine evaluates. Closing the first *correctly* requires the same
thing: the current refusal exists because "a command runs in this process while
statements are lowered together into one activation record, and splitting would
give the statements two of those". Splitting a submission into segments would
mean a declaration in one segment is invisible in the next —
`X : Integer := 1; pwd; Y : Integer := X;` would report `X` undeclared. There is
no correct middle design. One mechanism closes both.

## What the spike proved

**HAC callbacks fire from Adash's hand-emitted p-code.** `HAC_Sys.Interfacing`
exports `Exported_Procedure`, an access-to-procedure taking a
`HAC_Element_Array`, registered by name against the build data. HAC's own
compiler reaches it through the `with Import => True` aspect; nothing required
Adash to go through HAC's parser to do the same.

A spike emitted the call sequence by hand, ran it on the virtual machine, and
the callback fired with an evaluated `Integer` argument of 42 and no exception.

## The recipe

Per command that a submission calls, with N single-cell parameters.

**Code, emitted after `k_Halt_Interpreter`** — the callable's body lives past the
end of the main program, exactly where HAC puts a subprogram body:

    Entry_Point := BD.CD.LC;
    Emit_1 (k_Exchange_with_External, <command id_table index>);
    Emit_1 (k_Return_Call, Normal_Procedure_Call);

**The command's identifier-table entry:**

| Field | Value |
|---|---|
| `name` | The registered name, upper case — `Interfacing.Register` upper-cases, and the interpreter looks it up by `id_table` name |
| `entity` | `prozedure` |
| `lev` | 1 |
| `adr_or_sz` | `Entry_Point` |
| `block_or_pkg_ref` | Its block index |
| `decl_kind` | `spec_resolved` |

**One identifier-table entry per parameter:**

| Field | Value |
|---|---|
| `entity` | `variable_object` |
| `lev` | 2 |
| `adr_or_sz` | `fixed_area_size + (position - 1)` |
| `normal` | `True` — False means "passed by reference", and the interpreter would dereference the cell |
| `decl_kind` | `param_in` |
| `xtyp` | `Construct_Root (Ints)`, or `Construct_Root (VStrings)` for a string |

**The command's block-table entry:**

    (Id                 => <name>,
     Last_Id_Idx        => <last parameter id>,
     First_Param_Id_Idx => <first parameter id>,
     Last_Param_Id_Idx  => <last parameter id>,
     PSize              => fixed_area_size + N,
     VSize              => fixed_area_size + N,
     SrcFrom | SrcTo    => 1)

**At each call site, in the main code:**

    Emit_1 (k_Mark_Stack, <command id_table index>);
    <emit each argument expression, left to right>
    Emit_2 (k_Call, Normal_Procedure_Call, PSize - 1);

`k_Call`'s second operand is **`PSize - 1`, not the number of arguments.** This
is the one thing the spike got wrong first, and it fails as an index check deep
inside `Do_Call` rather than as anything that names the cause. The interpreter
computes the activation record base as `T - Y` and then reads the callee's
identifier index from `base + 4`; only `PSize - 1` puts those in the right
place. HAC's own compiler emits exactly
`Blocks_Table (id_table (ident).block_or_pkg_ref).PSize - 1`.

**Registration**, any time before the run:

    HAC_Sys.Interfacing.Register (BD, Callback'Access, "QUIT");

## What remains, in order

Each step leaves the repository buildable and tested.

1. ~~**String literals.**~~ **Done.** Adash interns the characters into the
   compiler's string-constant table and emits
   `k_Push_Two_Discrete_Literals (length, index)` followed by the standard
   function `SF_String_Literal_to_VString`. Storing a String needs `k_Store`
   with the `VStrings` type code, not `k_Store_Discrete`, which would copy the
   numeric field and leave the text behind; the comparisons are the `_VString`
   opcodes for the same reason.

   Two things came out of it. A declaration's type must be taken from its
   **symbol**, not from the declaration node — the node carries the initial
   expression's type, which is absent when there is no initializer. And `&` is
   refused: it is wrong whenever an operand is the empty string, and that is
   still unexplained. See `ROADMAP.md`.

2. ~~**Command entities with typed profiles.**~~ **Done.**
   `Adash.Commands.Metadata` gained a typed `Parameters` list beside its
   existing arity, and `Adash.Predefined` gained `Profile_Of`, which answers
   for the language's own subprograms *and* for commands. Semantics asks one
   question rather than two, so there is no second check to keep in step, and
   `Adash.Predefined.Install` now declares commands into the scope chain
   alongside the language's entities.

   The visible change: a command used where the analyser can see it is a known
   name. `quit` inside an `if` was "quit is not declared here" -- which tells
   the user they made a typo -- and is now "this build cannot yet run a call to
   quit", which is what has actually happened. `quit ("later")` and `cd (1)`
   are type errors, and `pwd (1)` an arity error.

   Arity had to become a range rather than a count: `quit` takes a status or
   nothing, and one number cannot say that.

   It also uncovered a **pre-existing bug**, unrelated to commands: a call
   written without parentheses is a `Node_Procedure_Call` wrapping a plain
   name, not a call node, so the parameter association never saw it. `set;` and
   `Put_Line;` were both accepted with no arguments. Fixed in the same change,
   since leaving it would have made half the new checks unreachable.

3. ~~**Callback lowering.**~~ **Done.** A command call in a lowered program
   now runs in this process at the moment the program reaches it — including
   inside a loop, three times for three iterations, which no design that ran
   commands before or after the program could express.

   Two things came out differently from the plan above. There is **one stub,
   not one per command**: which command is being called travels as an argument
   rather than as a separate registration, so adding a command to the shell
   needs no change in the lowering at all. And the stub takes **four fixed
   parameters** — name, argument kind, an integer slot and a text slot —
   because a machine cell carries either a number or text and never both, and
   the kind has to travel with the value rather than be guessed at.

   `Adash.Language.Evaluation` does *not* call `Adash.Commands`. The caller
   supplies a `Command_Sink`, so the language subsystem never gains an edge to
   the execution subsystem; `Adash.Engine`, which already owns both, will
   implement it in step 6. A run with no sink **refuses** a command call rather
   than skipping it: dropping the call would make the program mean something
   its author did not write.

4. ~~**The callback's context.**~~ **Done, with step 3.** `Current_Sink` is
   set immediately before the interpreter is entered and cleared immediately
   after, so it is live for exactly one run. It is forced by HAC's callback
   signature carrying no user data, not chosen, and the comment on it says so
   and names the condition under which it would break: a second thread running
   a second program at the same time. Adash does not do that.

   One trap worth recording: the *emitter* must test the sink it was passed,
   not `Current_Sink`, which is still null while the program is being lowered.

5. ~~**Commands take values, not text.**~~ **Done.**
   `Adash.Commands.Execute` takes an `Argument_Set` of
   `Adash.Language.Values.Value` — a bounded record, not a vector, because a
   command takes at most two arguments and a container would be machinery for
   nothing. `Command_Exit` reads an Integer directly; the `Integer'Value` on
   text somebody typed is gone, and with it the possibility of discovering
   `quit ("later")` at the moment the session is ending.

   The sink carries a value too, so nothing converts back and forth: the type
   the program wrote is the type the command receives.

   The engine's classification path does not analyse, so it types its arguments
   from the syntax — an integer literal becomes an Integer, a character literal
   a Character, anything else a String. That is enough because the path only
   ever supported literals, and step 6 removes it.

   One rough edge left: when a command *does* receive an argument of the wrong
   type — only reachable by building an argument set by hand, since the
   analyser refuses it otherwise — it is reported with
   `Error_Command_Wrong_Arguments`, whose message talks about the *number* of
   arguments. Step 6 makes the analyser catch this before the command runs, so
   the path becomes unreachable in practice; if it survives that, it wants its
   own message.

6. ~~**Remove the classification.**~~ **Done.** `Adash.Engine.Submit` no longer
   counts commands: every submission is a program, `Submission_Kind` has one
   fewer literal, and `Error_Mixed_Submission` and its catalog entry are gone.
   The engine implements `Command_Sink`, so the language never gains an edge to
   the execution subsystem.

   The bridge holds accesses to the session's state and output, taken with
   `'Unchecked_Access`. That is safe and the comment says why: the bridge is
   used only by `Ev.Run`, which returns before the block declaring it does, so
   everything it points at outlives it. Ada cannot see that, and the
   alternative -- a second process-wide variable holding the current session --
   would be a worse answer to a narrower problem.

   **One behaviour changed, and it is worth knowing about.** A failing command
   used to stop the rest of the line: `cd nowhere; pwd` reported nothing. It no
   longer does. That rule came from neither of the two things Adash is meant to
   agree with -- Ada does not end a sequence because a procedure reported a
   failure, and `sh -c 'cd /nonexistent; pwd'` prints the unchanged directory
   and exits zero. Commands are calls in a program now, so the program
   continues, which is what both would do. A caller that wants a sequence to
   stop writes the test; that is what `if` is for, and it is now possible to
   write.

## `quit` halts

Done, and worth recording because getting an answer *back* from a HAC callback
is not obvious.

Everything the stub is handed lives in an activation record that `k_Return_Call`
pops, so a value written into one is gone by the time the caller resumes. The
way back is an **`out` parameter passed by reference**: the caller pushes the
address of a cell in its own frame, `Do_Exchange_with_External` dereferences it
because the parameter's `normal` is False, and writes through it after the
callback returns because its `decl_kind` is `param_out`.

So the stub has a fifth parameter, the lowering allocates one frame slot the
first time a command is called, and after each call it emits:

    k_Push_Value (1, Halt_Slot)
    k_Jump_If_Zero_With_Pop (past)
    k_Halt_Interpreter
    past:

The sink says whether to stop, separately from whether the command failed.
Those are different questions: `quit (0)` succeeds and stops, and `cd` on a
missing directory fails and does not. The engine's bridge answers it from
`Exit_Requested` rather than by naming `quit`, so a second command that ended a
session would need no change here.

## What this will make possible

    Total : Integer := 0;

    for Index in 1 .. 4 loop
       Total := Total + Index;
    end loop;

    quit (Total);          --  exits 10

and commands inside control flow, which no shell-command-beside-a-language
design can express at all:

    for Index in 1 .. 3 loop
       pwd;
    end loop;

## What lowering `put_line` for String exposed

A program can report now, and that made a defect reachable that had been
unreachable rather than absent: **program output and command output arrive out
of order.** `pwd; put_line ("after");` prints `after` first, because a program
writes to standard output as the machine runs it while a command produces
structured lines the frontend renders once the submission has finished.

**Fixed**, by the first of the two candidates: the frontend renders command
output *as it is produced*. `Adash.Engine.Submit` takes an `Output_Sink` -- the
same pattern as the command sink, and for the same reason -- and writes each
line through it at the moment the command produced it, rather than leaving the
frontend to render the accumulated list afterwards.

The other candidate was to route a program's `put_line` through the command
sink and give raw text a message identity. It was rejected: `put` writes a
partial line and does not fit a list of lines at all, and it would have put a
program's own bytes through the message catalog, which is for the shell's
messages rather than for whatever a user's program computed. The distinction
between the two kinds of output is real; what was wrong was only *when* one of
them was rendered.

The lines are still accumulated, so `Output_Count` and `Output_Line` still
answer and the tests that use them did not change. The sink is about ordering,
not about storage.
