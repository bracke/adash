# HAC assessment

**Adash no longer depends on HAC.** `Adash.Machine` is the virtual machine now.
This document is kept because the reasoning that led into the dependency, and
out of it, is the same reasoning -- and because the finding at its centre is
still true of HAC and still worth knowing.

## Why it ended

The dependency was entered for the p-code interpreter and the runtime library,
having found that HAC's compiler could not be used at all (see below: there is
no syntax tree, and `Build_Main` compiles a whole unit, which a shell prompt is
not). So Adash wrote its own lexer, parser, tree, semantic pass and lowering,
and used HAC to execute.

Measured before the change:

| | lines |
|---|---|
| HAC's compiler, which Adash did not use | 11,447 |
| Adash's own front end, which replaced it | 9,421 |
| HAC's interpreter, which Adash did use | 3,995 |

Nine thousand lines written to avoid eleven thousand, in order to reach four
thousand. That alone is a poor trade but not a wrong one -- four thousand lines
of Ada-correct runtime is worth having.

What decided it was *how* Adash reached that runtime. Lowering went to
`HAC_Sys.PCode` and, unavoidably, to `HAC_Sys.Co_Defs`: Adash built identifier
tables, block tables and activation records of a fixed shape, and kept a display
vector in step -- it impersonated the output of a compiler rather than using a
published interface. Every defect that seam produced was of one kind: a display
vector not restored after a call to the command stub; bridge slots allocated
from whichever frame happened to be emitting; an argument cell typed for text
and given a number. None of them was a defect in HAC.

`Adash.Machine` is 1,325 lines against the 3,995 it replaces, because it is only
what the lowering emits: 46 opcodes, no generics, no tasking, no files. It uses
static links rather than a display, keeps variables and expression operands in
separate structures, and returns the shell's answer from the call rather than
through a reserved slot -- so each of those defect classes has no equivalent to
recur in.

What was kept deliberately: `Real` is `digits System.Max_Digits` and the whole
number is 64-bit, so `'Image` renders and `Integer'Last` reads as they always
did here; `'Image`, `'Value`, division by zero and index checks all go through
Ada's own operations, so the failures are Ada's failures.

What was lost: HAC's exception messages, which were better in one place --
`Element: Index, 9, is larger than Length (Source), 3` became `position 9 is
outside a String of 3`. Two conformance cases record the change.

## The finding that decided the original design

**HAC is a one-pass recursive-descent compiler. There is no syntax tree.**

`HAC_Sys.Parser.Block` takes `CD : in out Co_Defs.Compiler_Data` and returns
nothing. It parses and emits object code in the same pass, and the object code
is the only thing that survives. There is no intermediate representation to
retrieve, annotate or walk, and none can be added without rewriting the parser —
which would not be a fork of HAC but a different compiler wearing its name.

This is not a defect in HAC. It is what makes it small and quick, which is
exactly why it was chosen. But it decides several things for Adash.

## What HAC gives, and it is more than expected

**Structured diagnostics.** `Defs.Diagnostic_Kit` carries a kind
(error/warning/note/style), a file name, a `Symbol_Location` of line, column
start and column stop, and a `Repair_Kit` — a suggested insertion or token
replacement. Delivered through `Defs.Smart_Error_Pipe`, a callback, so Adash can
collect diagnostics rather than parse them off a stream. That maps onto
`Adash.Diagnostics` almost directly.

**Cross-reference data.** `HAC_Sys.Targets.Semantics` records declaration points
and a reference mapping from source position to identifier — built for the LEA
editor. Not a syntax tree, but real semantic information: what a name at a
position denotes, and where it was declared. Enough for go-to-definition and for
semantic highlighting *of identifiers*.

**Two-way embedding.** `HAC_Sys.Interfacing` converts between native and HAC
values and, through `Exported_Procedure`, lets the host expose its own
subprograms to a running HAC program. This is the mechanism by which an Adash
script would run a command: `Adash.Execution` is exported into the interpreter
rather than reimplemented in it.

**Compilation from any stream.** `Set_Main_Source_Stream` takes a stream and a
virtual file name, so a line typed at a prompt needs no temporary file.

**A pluggable emit target — but only just started.** `HAC_Sys.Targets` is an
abstract machine interface whose own header predicts "likely hundreds of such
methods in the end". Measured at 0.42.0 it has fifteen, of which six emit code:
binary arithmetic, halt, two discrete-literal pushes, and a HAT builtin call.
Three more mark cross-references and the rest are informational.

Counting call sites in the compiler: **141 emissions go directly to p-code and 29
through the interface**. There is no load, store, jump, branch, call, return,
comparison, string or composite-access method. `Targets` cannot be a lowering
target for a real language today, and completing it is the "hundreds of methods"
its author describes rather than a fork-sized change.

**The p-code instruction set, which is the real lowering target.**
`HAC_Sys.PCode.Opcode` has 123 instructions, and
`HAC_Sys.Compiler.PCode_Emit` offers `Emit`, `Emit_1`, `Emit_2`, `Emit_3` plus
specialized emitters for comparisons, unary minus, float literals and bound
checks. This is the interface HAC's own parser uses, and it is complete because
the compiler depends on it being so.

## What HAC does not give

| Adash needs | HAC | Consequence |
|---|---|---|
| An annotatable syntax tree | none, and not addable by fork | Phase 5's `Language.Syntax` cannot be what §5 describes |
| A standalone semantic pass | fused into parsing | Phase 6 cannot run separately from Phase 5 |
| Incremental evaluation for a REPL | `Build_Main` compiles a whole unit | see below |
| Diagnostics as code plus arguments | code exists internally, kit carries formatted English | fork change 2 in `FORK.md` |
| A library to link against | `hac.gpr` builds executables | fork change 1 |

### The REPL problem, specifically

`Build_Main` compiles a complete main unit. A shell prompt is not a main unit:
`X : Integer := 1;` typed on one line and `Put_Line (Image (X));` on the next are
two compilations, and the second does not know what the first declared.

HAC has one mechanism that survives a compilation — `Build_Data.global_VM_variables`,
a string-to-string map reachable from HAT and from `Interfacing`. It is enough
to carry shell state, but it is not Ada scoping: values are text, and there are
no types, no declarations and no visibility rules in it.

So an interactive Adash session on HAC as it stands means one of:

- **Re-compile the accumulated session** on each line, replaying earlier
  declarations. Correct, and quadratic — a session of any length gets slow, and
  side effects would replay unless every command were also re-executed, which
  they must not be.
- **Wrap each line as its own unit** and carry declarations forward in
  `global_VM_variables` as text. Fast, and not Ada: `X` would be a string
  between lines and `Integer` only inside one.
- **Extend HAC with a persistent compilation context** — a `Build_Data` that
  retains its symbol table between units, so a line compiles against what
  earlier lines declared. This is the honest fix and it is a substantial change
  to a compiler that was not written for it.

None of these is free, and the choice is Adash's rather than HAC's.

## What this means for the phase plan

**Phase 4 (lexer) should be Adash's own.** `Scanner.In_Symbol` advances a
`Compiler_Data`, so reusing it means constructing compiler state to tokenize a
string — and Adash needs tokens for highlighting and completion, on input that
does not parse, which is precisely when a compiler's scanner is least usable.
The rule against duplicating a dependency's capability is about *capabilities*,
and standalone lexing is not one HAC offers. An independent lexer over
`Adash.Source` is the smaller and more honest option, and it is what Phases 14's
highlighting and completion need anyway.

**Phase 5 cannot deliver `Adash.Language.Syntax` as §5 describes it.** There is
no tree to build one from. The realistic options:

1. **Adapt the phase.** `Language.Parser` becomes a HAC integration that yields
   diagnostics, cross-references and compiled code, and `Language.Syntax` is
   dropped. Cheapest, and gives up formatting and structural refactoring for
   good.
2. **Adash parses, HAC executes.** Adash builds its own tree over its own lexer
   and lowers it into HAC's emit target. Keeps §5 intact and makes `Targets`'
   partial state a blocker.
3. **Adash owns the whole front end.** HAC contributes its virtual machine and
   runtime only. Most work, most control, and hardest to square with §2.1's rule
   against a competing parser — though that rule is about not duplicating what
   HAC provides, and a reusable parse tree is not something it provides.

**Phases 6 and 7 follow from that choice** and should not be planned until it is
made.

## Decision

**Option 2 was chosen: Adash parses into its own tree and lowers into HAC.**

With one refinement the measurements above force: the lowering target is
`HAC_Sys.PCode` through `HAC_Sys.Compiler.PCode_Emit`, **not** `HAC_Sys.Targets`.
Targets covers six emission operations and is bypassed by 83% of the compiler's
own emissions; p-code is complete and is what the compiler actually uses.

### What Adash owns

The lexer, the parser, `Language.Syntax`, and semantic analysis. HAC contributes
its virtual machine, its p-code instruction set and its runtime library (HAT).

### Why this is not a competing parser

§2.1 forbids implementing "a competing Ada parser, compiler, bytecode engine, or
interpreter **for functionality HAC already provides**". HAC's parser does not
provide a parse tree — it produces object code, consumed as it is emitted, and
nothing survives that another phase could read. Adash's parser therefore
produces something HAC does not have and cannot be asked for, which is the
condition §2.1 attaches. Adash still does not write a bytecode engine or an
interpreter: those remain HAC's, and lowering to p-code is precisely how it
stays that way.

This is recorded because it reads as a violation otherwise, and a future reader
comparing the code against §2.1 deserves the reasoning rather than a surprise.

### What it costs

Adash will depend on `HAC_Sys.Co_Defs`, `HAC_Sys.PCode` and
`HAC_Sys.Compiler.PCode_Emit`. The first is an *internal* package: `Interpret`
takes a `Builder.Build_Data` holding a `Compiler_Data`, and that record carries
the object code alongside the arrays, blocks, float-constant, string-constant
and task tables the interpreter reads at run time. Adash's lowering has to
populate all of it.

Upstream promises nothing about `Co_Defs`' shape. The fork has to treat it as an
interface and absorb the churn — which is the price of this option and is why it
is written down here rather than discovered during a merge.

### What it buys, beyond the syntax tree

The REPL problem gets *easier*, not harder. With Adash owning the front end, the
symbol table between prompt lines is Adash's own: a line is parsed and analysed
against the session's accumulated scope, and only the new statements are lowered
and run. HAC never has to hold a compilation context across units, which was the
substantial change option 1 would have needed.

### Consequences for the phase plan

HAC now enters at **Phase 7**, not Phase 5. Phases 4, 5 and 6 involve no HAC at
all:

| Phase | Was | Now |
|---|---|---|
| 4 | Lexer | unchanged — Adash's own |
| 5 | HAC parser integration and syntax representation | **Adash's parser and syntax tree; no HAC** |
| 6 | Semantic analysis | unchanged — over Adash's tree |
| 7 | Evaluation | **lowering to p-code, then `PCode.Interpreter.Interpret`** |

The two fork changes in `../hac/FORK.md` still apply, and a third is added: the
library project must export `HAC_Sys.Co_Defs`, `HAC_Sys.PCode` and
`HAC_Sys.Compiler.PCode_Emit`, not only the `Builder` façade.


## Phase 7 spike: what direct p-code emission actually costs

Measured, not estimated. A throwaway program linked against the vendored fork,
populating a `Compiler_Data` by hand and asking the VM to run it.

**Linking works.** `hac_lib.gpr` builds, Adash links `HAC_Sys`, and the whole
suite stays green with HAC in the graph. Fork change 1 is done.

**Emission works.** `Compiler.PCode_Emit.Emit_1` and `Emit` write into the
compiler data as expected — and HAC's peephole optimizer runs on the way in:
two `k_Push_Discrete_Literal` emissions became one
`k_Push_Two_Discrete_Literals`, which is visible as `LC = 2` after three calls.

**Two things do not, and both are the coupling to internals this document
warned about:**

1. `Compiler.Init_for_new_Build` calls `Scanner.In_Symbol` as its last act, so
   initialising a compiler data requires a source stream already attached and
   containing at least one token. HAC's initialisation is entangled with
   scanning; there is no "prepare an empty compiler data" entry point. Attaching
   a stub source works around it.

2. The interpreter then fails inside the first instruction:

       raised CONSTRAINT_ERROR : hac_sys-pcode-interpreter.adb:687 index check

   `Push (2)` overflows because the main task's control block has no frame. The
   VM builds one from `Blocks_Table` and `main_proc_id_index` — the block's
   parameter size, variable size, identifier range and display level — all of
   which HAC's `Parser.Block` computes as it parses and Adash never wrote.

### Resolved: the frame setup is four fields, not a reimplementation

The paragraph that used to be here estimated that direct p-code emission meant
reimplementing HAC's frame layout, and called it materially larger and more
fragile than the phase plan assumed. **That estimate was wrong**, and the spike
that produced it was simply incomplete. What the VM actually needs, from
`Interpreter.Tasking.Init_main_task`, is:

    CD.main_proc_id_index                       -> an identifier table entry
    id_table (that).adr_or_sz                   -> the PC of the first instruction
    id_table (that).block_or_pkg_ref            -> a Blocks_Table entry
    Blocks_Table (that).VSize                   -> the frame size

`Co_Defs.fixed_area_size` is 5 — the activation record's fixed area — so a main
procedure with no locals has `VSize = 5`, and each variable adds its size. That
is the whole of it for a statement sequence, which is what a shell runs.

Working recipe, verified end to end:

    Compiler.Init_for_new_Build (BD.CD.all);   --  needs a stream attached first
    ...populate id_table (1), Blocks_Table (1), main_proc_id_index...
    Compiler.PCode_Emit.Emit_1 (BD.CD.all, PCode.k_Push_Discrete_Literal, 1);
    Compiler.PCode_Emit.Emit_1 (BD.CD.all, PCode.k_Push_Discrete_Literal, 0);
    Compiler.PCode_Emit.Emit  (BD.CD.all, PCode.k_DIV_Integer);
    Compiler.PCode_Emit.Emit  (BD.CD.all, PCode.k_Halt_Interpreter);
    PCode.Interpreter.Interpret_on_Current_IO (BD, 0, "spike", PM);

The division by zero is the control: the program above reports an unhandled
exception, and the same program without it reports none. The VM is running the
emitted instructions rather than starting and halting.

Frame layout grew when Adash gained subprograms with parameters, as predicted:
`PSize`, the parameter identifier range and the display all matter now. What
that cost in practice was one table per subprogram and one per parameter, plus
`k_Update_Display_Vector` after a call made inside another body — the field
values are documented by HAC's own emission, and reading `Do_Call` was what
established them. The identifier layout became computed rather than fixed at
the same time: the command stub used to sit at a constant index, and a
subprogram table of unknown size cannot start after a constant without leaving
entries the count covers and nothing fills.

The `Co_Defs` coupling is still real and still the fork's maintenance cost.
It is a handful of documented-by-example fields rather than an algorithm.

### The alternative that was considered and rejected

Adash could have lowered to **HAC source text** instead of to p-code: keep its own
lexer, parser, tree, semantics and diagnostics exactly as they are, and have
`Language.Evaluation` render the analysed tree as a HAC-compatible unit for
`Builder.Build_Main` to compile and run.

- **Costs**: a round trip through text, and HAC re-parses what Adash already
  parsed. Adash's spans no longer line up with HAC's diagnostics — though Adash
  has already reported everything HAC would, because Phase 6 checks the same
  rules.
- **Buys**: no dependency on `Co_Defs`, no frame layout to reimplement, and a
  fork that stays close to upstream. HAC's own semantic pass becomes a second
  check on Adash's lowering, which is a genuine safety net for a first release.

Nothing already built would have been wasted either way: Phases 4 to 6 are
Adash's own and do not change. The choice was only about what
`Language.Evaluation` emits.

**Decided: p-code**, now that the frame setup is known to be small. The text
path would have re-parsed what Adash already parsed and thrown away the spans
Phases 4 to 6 exist to preserve.


## Phase 7 outcome

The lowering is written and works. One correction to the recipe above, found by
the tests rather than by reading:

**`k_Store` does not take an address.** Its operand is a *type code*
(`Typen'Val (IR.Y)`), and the destination address comes off the stack, below the
value. The sequence for an assignment is:

    k_Push_Address (level, address)
    ...code for the value...
    k_Store_Discrete

`k_Store_Discrete` is the right instruction for Integer, Boolean and Character:
it copies the discrete field and skips the variant check that `k_Store` performs.
Passing an address as `k_Store`'s operand -- the obvious reading of "store to
this address" -- makes the machine interpret it as a type code, and the run fails
with "Invalid data (maybe due to an uninitialized variable)", which points at
nothing resembling the cause.

`k_Push_Value (level, address)` for reading *is* what it looks like. The
asymmetry is the trap.
