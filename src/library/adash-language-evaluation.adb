with Ada.Containers.Vectors;

with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;

with Adash.Errors;
with Adash.Machine;
with Adash.Language.Symbols;
with Adash.Language.Types;
with Adash.Predefined;
with Adash.Messages;

package body Adash.Language.Evaluation is

   ---------------------------------------------------------------------
   --  The bridge from the virtual machine back into this process.
   --
   --  `Adash.Machine.Host` is an interface the machine calls out through, and
   --  what it carries is the call: the name, the arguments, and somewhere to
   --  put the answer. It carries no user data, so the sink a run was given
   --  cannot travel through it and has to be reachable some other way.
   --
   --  This variable is that way, and it is forced rather than chosen. It is
   --  set immediately before the interpreter is entered and cleared
   --  immediately after, so it is live only for the duration of one Run, and
   --  Run is not re-entrant -- a program cannot start another program. A
   --  second thread running a second program at the same time would break it,
   --  and Adash does not do that; if it ever does, this is where it breaks.
   ---------------------------------------------------------------------
   package Values renames Adash.Language.Values;

   Current_Sink : Sink_Access := null;

   --  Asked by the machine, between instructions, whether to stop. Live for
   --  exactly one run, like Current_Sink and forced by the same thing: the
   --  hook the machine calls takes no user data.
   Current_Cancel : Cancellation_Access := null;

   --  What a host call is told to distinguish a variable's value from a
   --  command. Never seen outside this package: the host below turns it into
   --  Keep_Value before any sink is reached, and no user can write it because
   --  the parser has no way to put a percent sign in a name.
   Keep_Marker : constant String := "%keep";

   --  And what it is told to ask the shell something.
   Ask_Marker : constant String := "%ask";

   --  Where the machine's Call_Host lands.
   --
   --  One host for all three ways out: a command, a question the shell
   --  answers, and a value on its way out of a finished program. Which of the
   --  three travels as the name, because the machine has one way to call out
   --  and three would be three things to keep in step.
   type Bridge is limited new Adash.Machine.Host with null record;

   overriding procedure Call
     (Item      : in out Bridge;
      Name      : String;
      Arguments : Adash.Machine.Cell_Array;
      Count     : Natural;
      Result    : out Adash.Machine.Answer);

   overriding function Stop_Requested (Item : in out Bridge) return Boolean;

   --  What a machine cell means to the shell.
   function As_Value (Item : Adash.Machine.Cell) return Values.Value;

   --  And the other way, for what the shell answers.
   function As_Cell (Item : Values.Value) return Adash.Machine.Cell;

   ----------------
   -- As_Value --
   ----------------

   function As_Value (Item : Adash.Machine.Cell) return Values.Value is
   begin
      case Item.Kind is
         when Adash.Machine.Cell_Whole =>
            --  The machine carries the widest whole number and the shell
            --  carries Ada's Integer. Narrowing here keeps the one conversion
            --  in one place, and a value too large for the shell arrives as
            --  the text it images to rather than as a wrong number.
            return (if Item.Whole in
                      Adash.Machine.Whole_Number (Integer'First)
                        .. Adash.Machine.Whole_Number (Integer'Last)
                    then Values.To_Value (Integer (Item.Whole))
                    else Values.To_Value
                           (Adash.Machine.Whole_Number'Image (Item.Whole)));

         when Adash.Machine.Cell_Truth =>
            return Values.To_Value (Item.Truth);

         when Adash.Machine.Cell_Letter =>
            return Values.To_Value (Item.Letter);

         when Adash.Machine.Cell_Real =>
            --  The machine carries the widest real this host has and the shell
            --  carries Ada's Float. Narrowing here keeps the one conversion in
            --  one place.
            return Values.To_Value (Float (Item.Number));

         when Adash.Machine.Cell_Text =>
            return Values.To_Value
              (Ada.Strings.Unbounded.To_String (Item.Text));

         when others =>
            return Values.None;
      end case;
   end As_Value;

   ---------------
   -- As_Cell --
   ---------------

   function As_Cell (Item : Values.Value) return Adash.Machine.Cell is
      Whole  : Integer := 0;
      Truth  : Boolean := False;
      Letter : Character := ' ';
      Number : Float := 0.0;
   begin
      --  The value's own type is what decides which cell it becomes. The
      --  analyser and the shell agree about what each name yields, so a cell
      --  of the wrong kind here would be the two disagreeing rather than
      --  anything a program wrote.
      if Values.Get (Item, Whole) then
         return (Kind => Adash.Machine.Cell_Whole,
                 Whole => Adash.Machine.Whole_Number (Whole));
      elsif Values.Get (Item, Truth) then
         return (Kind => Adash.Machine.Cell_Truth, Truth => Truth);
      elsif Values.Get (Item, Letter) then
         return (Kind => Adash.Machine.Cell_Letter, Letter => Letter);
      elsif Values.Get (Item, Number) then
         return (Kind => Adash.Machine.Cell_Real,
                 Number => Adash.Machine.Real (Number));
      end if;

      return (Kind => Adash.Machine.Cell_Text,
              Text => Ada.Strings.Unbounded.To_Unbounded_String
                        (Values.Image (Item)));
   end As_Cell;

   ------------
   -- Call --
   ------------

   overriding procedure Call
     (Item      : in out Bridge;
      Name      : String;
      Arguments : Adash.Machine.Cell_Array;
      Count     : Natural;
      Result    : out Adash.Machine.Answer)
   is
      pragma Unreferenced (Item);

      Given : Argument_Values := [others => Values.None];
      Kept  : constant Natural := Natural'Min (Count, Max_Command_Arguments);

      Failed : Boolean;
      Halt   : Boolean := False;
   begin
      Result := (Value => (Kind => Adash.Machine.Cell_None), Halt => False);

      if Current_Sink = null then
         --  Nothing to call. A defect here rather than in the program, and
         --  raising inside a callback would name nothing useful.
         return;
      end if;

      for Position in 1 .. Kept loop
         Given (Position) := As_Value (Arguments (Position));
      end loop;

      if Name = Ask_Marker then
         --  Something the shell knows, asked for by name. What comes back is
         --  the value of the expression, which the machine pushes.
         declare
            Asked  : Argument_Values := [others => Values.None];
            Told   : Values.Value := Values.None;
         begin
            for Position in 2 .. Kept loop
               Asked (Position - 1) := Given (Position);
            end loop;

            Ask (Current_Sink.all, Values.Image (Given (1)),
                 Asked, Natural'Max (Kept - 1, 0), Told);

            Result.Value := As_Cell (Told);
         end;

      elsif Name = Keep_Marker then
         if Kept = 3 then
            Keep_Value
              (Current_Sink.all,
               Values.Image (Given (1)),
               Values.Image (Given (2)),
               Values.Image (Given (3)));

         elsif Kept = 2 then
            --  Which variable, and the text that puts it back. What is
            --  carried this way is a variable whose value cannot be written
            --  as one expression: it has none yet, or only some of its parts
            --  do.
            Keep_As_Written
              (Current_Sink.all,
               Values.Image (Given (1)),
               Values.Image (Given (2)));
         end if;

      else
         Invoke (Current_Sink.all, Name, Given, Kept, Failed, Halt);
         Result.Halt := Halt;
      end if;
   end Call;

   ----------------------
   -- Stop_Requested --
   ----------------------

   overriding function Stop_Requested (Item : in out Bridge) return Boolean is
      pragma Unreferenced (Item);
   begin
      return Current_Cancel /= null and then Is_Cancelled (Current_Cancel.all);
   end Stop_Requested;

   package S renames Adash.Language.Syntax;
   package Sem renames Adash.Language.Semantics;
   package D renames Adash.Diagnostics;
   package Ty renames Adash.Language.Types;
   package VM renames Adash.Machine;

   use type S.Node_Kind;
   use type S.Operation;
   use type Ty.Type_Kind;
   use type Ty.Type_Shape;
   use type Symbols.Symbol_Kind;
   use type Adash.Predefined.Entity_Id;

   Instruction_Count : Natural := 0;

   -----------------------------
   -- Last_Instruction_Count --
   -----------------------------

   function Last_Instruction_Count return Natural is
   begin
      return Instruction_Count;
   end Last_Instruction_Count;

   --  Where a declared variable lives in the activation record.
   --
   --  Keyed by the *declaration's* position, and by the name under it. A name
   --  alone would be wrong the moment one scope hides another: a `for`
   --  parameter called I inside a block that already has an I must not share
   --  its slot, and the two declarations are what differ.
   --
   --  A position alone became wrong when a declaration could be *copied*. Two
   --  objects of one protected type are two copies of one body, and a copy
   --  keeps the span it came from on purpose -- so a diagnostic about one
   --  points at the source the reader has to look at. Their state is two
   --  variables with two names under one position, and keying on the position
   --  alone gave them one slot between them.
   --
   --  The name is compared only when the position matches, which is what makes
   --  it cost nothing to have: a lookup walks positions and reads a name at
   --  most where it was going to stop anyway.
   type Slot is record
      Declared_At : Adash.Source.Byte_Offset := 1;
      Named       : Ada.Strings.Unbounded.Unbounded_String;
      Address     : Natural := 0;

      --  Which frame it lives in. A submission's own variables are level 1;
      --  a subprogram's parameters and locals are level 2, in the activation
      --  record the call built. The level travels with the slot because the
      --  instruction that reads a variable names both, and a body that
      --  addressed a local at level 1 would read whatever the submission
      --  happened to declare at that offset.
      Level       : Positive := 1;

      --  True when the slot holds the *address* of the caller's variable
      --  rather than a value of its own. That is what an `out` or `in out`
      --  parameter is, and every read and write of one needs a different
      --  instruction, so the fact travels with the slot.
      By_Reference : Boolean := False;
   end record;

   --  Addresses of instructions waiting to be told where to jump.
   package Patch_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Natural);

   package Slot_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Slot);

   ---------
   -- Run --
   ---------

   procedure Run
     (Tree     : S.Tree;
      Analysis : Sem.Analysis;
      Origin   : Adash.Source.Origin;
      Result   : out Outcome;
      Report   : in out D.List;
      On_Command : Sink_Access := null;
      Cancel     : Cancellation_Access := null)
   is
      --  What is being built: instructions, the literals they name, and one
      --  entry per routine.
      Code  : VM.Program;
      Slots : Slot_Vectors.Vector;

      --  Every `exit` in an open loop, waiting for the address just past that
      --  loop's end -- which is not known until the loop has been emitted.
      --
      --  One flat list with a mark per open loop, rather than a list per loop:
      --  loops nest, and closing one has to patch its own exits and no others.
      --  The mark is how long the list was when the loop opened, so its exits
      --  are everything after it.
      Exit_Sites : Patch_Vectors.Vector;
      Loop_Marks : Patch_Vectors.Vector;

      --  Which entry the accept body being emitted is serving -- its number,
      --  and, when it is a family, the entry itself and which member the
      --  accept named, so that a requeue can say where it took the caller
      --  from. Where the requeues inside it jump out to.
      --
      --  A requeue leaves the accept body it stands in, past the instruction
      --  that lets a caller go: the caller it moved is not one to let go.
      Serving_Entry  : Natural := 0;
      Serving_Symbol : Symbols.Symbol;
      Serving_Member : S.Node_Id := S.No_Node;
      Requeue_Sites  : Patch_Vectors.Vector;

      --  Where each open block keeps the region around it, innermost last, and
      --  how many were open when each loop began.
      --
      --  A block is a master, so leaving one waits for what it started -- and
      --  an `exit` leaves however many of them stand between it and the loop.
      --  Falling off the end of a block is not the only way out of it, and a
      --  block whose wait only stood at its end would be a master that some
      --  ways out did not answer to.
      Region_Slots : Patch_Vectors.Vector;
      Loop_Regions : Patch_Vectors.Vector;

      --  The next free slot of the frame being emitted. Zero, because a frame
      --  is variables and nothing else: there is no fixed area to step over,
      --  which was the whole of what a frame used to have to agree about.
      Next_Address : Natural := 0;

      --  A variable whose value is handed back when the program ends, so the
      --  session can start the next submission from it.
      type Survivor is record
         Named   : S.Node_Id := S.No_Node;
         Of_Type : Ty.Type_Kind := Ty.Type_None;
      end record;

      package Survivor_Vectors is new Ada.Containers.Vectors
        (Index_Type => Positive, Element_Type => Survivor);

      Survivors : Survivor_Vectors.Vector;

      --  What the lowering emits through. Three shapes, because an instruction
      --  takes nought, one or two operands.
      procedure Emit (Code_Point : VM.Opcode);
      procedure Emit_1 (Code_Point : VM.Opcode; Operand : VM.Whole_Number);
      procedure Emit_2
        (Code_Point : VM.Opcode;
         Level      : Natural;
         Operand    : VM.Whole_Number);

      --  Where the next instruction will land, for a jump patched later.
      function Here return Natural;

      procedure Emit (Code_Point : VM.Opcode) is
      begin
         Code.Add (Code_Point);
      end Emit;

      procedure Emit_1 (Code_Point : VM.Opcode; Operand : VM.Whole_Number) is
      begin
         Code.Add (Code_Point, 0, Operand);
      end Emit_1;

      procedure Emit_2
        (Code_Point : VM.Opcode;
         Level      : Natural;
         Operand    : VM.Whole_Number) is
      begin
         Code.Add (Code_Point, Level, Operand);
      end Emit_2;

      function Here return Natural is
      begin
         return Code.Next;
      end Here;

      --  A loop has opened: its exits are everything appended from now on.
      procedure Open_Loop;

      --  It has closed: patch its own exits to just past its end.
      procedure Close_Loop;

      procedure Open_Loop is
      begin
         Loop_Marks.Append (Natural (Exit_Sites.Length));
         Loop_Regions.Append (Natural (Region_Slots.Length));
      end Open_Loop;

      procedure Close_Loop is
         Mark : constant Natural := Loop_Marks.Last_Element;
      begin
         for Index in reverse Mark + 1 .. Natural (Exit_Sites.Length) loop
            Code.Patch (Exit_Sites.Element (Index), Here);
            Exit_Sites.Delete_Last;
         end loop;

         Loop_Marks.Delete_Last;
         Loop_Regions.Delete_Last;
      end Close_Loop;

      --  How many blocks enclose the statement being emitted.
      --
      --  A block's declarations are gone at its `end`, so they are not handed
      --  back to the session. Level and frame do not say so -- a block is in
      --  the same frame at the same level as the code around it -- which is
      --  why this is counted rather than derived.
      Block_Depth : Natural := 0;

      --  A subprogram this submission declares.
      --
      --  Collected before anything is emitted, because a call has to name its
      --  callee's identifier-table index and a program may call a subprogram
      --  declared further down. Ada allows that only after a specification;
      --  this subset has no specifications, so the pre-pass is what makes the
      --  whole submission one declarative region.
      type Routine is record
         Node : S.Node_Id := S.No_Node;

         --  Where its name was written, and what that name is. By declaration
         --  because with nesting a name is not unique: two bodies may each
         --  declare a `Step`, and matching on the spelling would call whichever
         --  was collected first. By name as well because a declaration can be
         --  *copied*: two objects of one protected type are two copies of one
         --  body, and a copy keeps the span it came from on purpose -- so the
         --  position alone gave both objects one set of operations, and every
         --  call reached the first object's.
         Declared_At : Adash.Source.Byte_Offset := 1;
         Named       : Ada.Strings.Unbounded.Unbounded_String;

         --  Whether it is a task body, which is started on a strand of its
         --  own rather than called, and ends rather than returns.
         Is_Task : Boolean := False;

         --  Whether a declaration names it.
         --
         --  An abortable part is a routine that nothing names, and Declared_At
         --  cannot tell it from a declaration written at the same offset --
         --  which the predefined names, declared nowhere, all are. A call
         --  looks only at what a declaration named.
         Is_Declared : Boolean := True;

         --  Which protected object it belongs to, or zero. A protected
         --  operation takes the lock on entry and gives it back on every way
         --  out, which is what makes it mutually exclusive.
         Guarded_By : Natural := 0;

         --  What that object's ceiling is: the highest priority a task may
         --  have and still call it. Ada's rule, checked where the lock is
         --  taken.
         Ceiling : Natural := VM.Highest_Priority;

         --  The level it is declared *at*: one for a subprogram of the
         --  submission, two for one declared inside that, and so on. Its own
         --  frame is one deeper, which is the machine's rule and not this
         --  lowering's choice.
         Level : Positive := 1;

         --  Where it and its parameters sit in the identifier table, and which
         --  block describes its frame.
         Ident : Positive := 1;
         Block : Positive := 1;

         Params : Natural := 0;
         Modes  : Symbols.Parameter_Modes := [others => Symbols.Mode_In];

         --  Where its first instruction ended up, and how big its frame turned
         --  out to be. Neither is known until the body has been emitted.
         Entry_At : Natural := 0;
         Frame    : Natural := 0;

         --  What it returns. Type_None for a procedure, which is also what
         --  makes it one.
         Returns : Ty.Type_Kind := Ty.Type_None;
      end record;

      package Routine_Vectors is new Ada.Containers.Vectors
        (Index_Type => Positive, Element_Type => Routine);

      Routines : Routine_Vectors.Vector;

      --  Which routine's body is being emitted, or zero for the submission
      --  itself. What `return` needs in order to know whether it is leaving a
      --  frame or ending the program.
      Current_Routine : Natural := 0;

      --  Which frame is being emitted into. One while emitting the submission
      --  itself, two inside a subprogram body. Not a depth counter: it is the
      --  operand the machine indexes its display with, so it is the level.
      Current_Level : Positive := 1;

      --  Whether the program calls a command at all. The stub and its tables
      --  are built only when something needs them, so a program that is pure
      --  Ada carries no trace of the shell.

      --  How the identifier and block tables are laid out: MAIN first, then
      --  one entry per declared subprogram followed by its parameters, then
      --  the command stub if the program needs one.
      --
      --  Computed rather than fixed, because the stub used to sit at a
      --  constant index and a subprogram table of unknown size cannot start
      --  after a constant without leaving a hole. A hole would be entries the
      --  count covers and nothing fills, which a traceback would read.
      --  How deep the machine's display goes. A frame beyond this has no slot
      --  to be addressed through, so a body nested that far is refused rather
      --  than emitted with a level the machine cannot index.

      --  Where the stub and its parameters end up. Assigned once the
      --  subprograms are known and before anything is emitted.

      --  Where the stub's first instruction ended up. Not known until the main
      --  program has been emitted, because the stub follows it.

      Lowerable : Boolean := True;

      --  Whether this submission started a task. What decides whether it has
      --  to wait for anything before it ends: Ada's rule is that a master does
      --  not finish while a dependent is still running, and a submission that
      --  started none has nothing to wait for.
      Started_A_Task : Boolean := False;

      --  Every entry this submission mentions, by where its declaration was
      --  written, and the number both ends of a rendezvous use for it.
      --
      --  A *family* is a run of them rather than one: it takes as many numbers
      --  as it has members, so that a member's own number is the family's plus
      --  which member it is. Handed out rather than counted from the position
      --  in this table, because a family leaves gaps in the numbering that
      --  nothing else fills.
      type Known_Entry is record
         Declared_At : Adash.Source.Byte_Offset := 1;
         Number      : Natural := 0;
         Members     : Positive := 1;
      end record;

      package Entry_Vectors is new Ada.Containers.Vectors
        (Index_Type => Positive, Element_Type => Known_Entry);

      Entries    : Entry_Vectors.Vector;
      Next_Entry : Natural := 0;

      use type Symbols.Parameter_Mode;

      --  Where a variable lives: which frame, and where in it.
      type Place is record
         Level        : Positive := 1;
         Address      : Natural := 0;
         By_Reference : Boolean := False;
      end record;

      procedure Refuse
        (Node      : S.Node_Id;
         Construct : Adash.Messages.Message_Id;
         Given     : Adash.Messages.Argument_List :=
           Adash.Messages.No_Arguments);
      function New_Temporary return Natural;
      procedure Reserve_Temporary;
      function Outward (Of_Level : Positive) return Natural;
      procedure Emit_Address (Where : Place);
      procedure Emit_Value (Where : Place);
      procedure Collect_Routines;
      procedure Collect_Types;
      procedure Emit_Bodies;
      function Find_Routine (Sym : Symbols.Symbol) return Natural;
      --  @param Callee What the call resolved to. Passed rather than found
      --         from Node, because a call written without parentheses is a
      --         name rather than a call node and has no prefix to ask.
      procedure Emit_Routine_Call
        (Node      : S.Node_Id;
         Which     : Positive;
         Arguments : S.Node_Id;
         Callee    : Symbols.Symbol);

      procedure Emit_Text (Item : String);
      procedure Emit_Store (Of_Type : Ty.Type_Kind);
      procedure Emit_Bounds_Check (Of_Type : Ty.Type_Kind);

      --  Push the place a name, a component or an element denotes.
      --
      --  The three shapes an assignment target can have, and the three a
      --  composite can be reached through. `R.Field` is the place R starts at
      --  moved along by a known offset; `A (I)` is the place A starts at moved
      --  along by a computed one, after a check that the subscript is one of
      --  A's. Written once because a target and a value are the same walk --
      --  what differs is only whether the place is stored into or read from.
      --
      --  @param Node The name, selection or index.
      --  @param Ok False when it is none of those, with a refusal reported.
      procedure Emit_Place (Node : S.Node_Id; Ok : out Boolean);

      --  Fill a composite from an aggregate, part by part.
      --
      --  The parts go into the slots directly rather than being built into a
      --  value first: a composite has no representation on the stack, and
      --  giving it one would mean a cell that could hold a run of cells.
      --
      --  @param Target The place the value starts at, already on the stack and
      --         left there.
      --  @param Of_Type What is being built.
      --  @param Values The aggregate's sequence of values.
      --  @param At_Address Where to build it, when it is not being built into
      --         something with a place of its own. An aggregate written as an
      --         argument has nowhere to live: it is built in a run of the
      --         caller's own slots and the call is handed where that run
      --         starts, which is how every composite travels here.
      procedure Emit_Aggregate
        (Target     : S.Node_Id;
         Of_Type    : Ty.Type_Kind;
         Values     : S.Node_Id;
         At_Address : Integer := -1);

      --  Whether this expression is an array element rather than a call.
      --
      --  Both are written `X (Y)`. Semantics settled which by the type it gave
      --  the prefix, and asking the shape again here would be a second answer
      --  to a question already answered.
      function Is_Element (Node : S.Node_Id) return Boolean;

      --  Whether this is a part of a String rather than a call: `S (2)` or
      --  `S (2 .. 4)`, written where a target may stand.
      --
      --  The same question Is_Element asks and answered the same way, from
      --  the type semantics gave the prefix. What it is for is the assignment,
      --  which cannot ask for a place inside a String because there is none:
      --  the whole text is one cell.
      function Is_Text_Part (Node : S.Node_Id) return Boolean;

      --  Whether this denotes an array that has a place: a variable, or a
      --  slice or element of one. A function does not return a composite here,
      --  so a call over an array can only be a part of one.
      function Is_Array_Place (Node : S.Node_Id) return Boolean;

      --  Whether this is a run of an array's own elements: `A (2 .. 4)`.
      --
      --  Decided the way Is_Element decides its question, from the type
      --  semantics gave the prefix. A slice is a place and never a value here,
      --  which is what a composite is everywhere in this build.
      function Is_Array_Slice (Node : S.Node_Id) return Boolean;

      --  Leave every block that stands between here and the loop being left.
      --
      --  A block is a master, and an `exit` completes however many of them it
      --  jumps out of. Innermost first, which is the order they end in.
      procedure Emit_Leaving_Blocks;

      --  Bind an accept's formals to the caller's arguments and run its body.
      --
      --  The place of the caller's argument block is on the stack, left there
      --  by the Try_Accept that took the caller. Written once because one
      --  accept and a select over several do the same thing once a caller has
      --  been taken -- what differs is only how they waited.
      --
      --  @param Node The accept.
      --  @param Which Which entry it is, as both ends count them.
      procedure Emit_Accept_Body (Node : S.Node_Id; Which : Positive);

      --  Abandon a piece of work when something else happens first.
      --
      --  Ada's asynchronous transfer of control. The abortable part runs as a
      --  strand of its own and the trigger waits in this one -- which is the
      --  only shape this machine can give it, and a faithful one: a strand
      --  that is not running cannot be in the middle of anything, so there is
      --  nothing to unwind when it is abandoned.
      --
      --  @param Node The select.
      procedure Emit_Then_Abort (Node : S.Node_Id);

      --  Serve whichever entry a caller is waiting at.
      --
      --  Ada's selective accept. The guards are asked once, when the select is
      --  reached -- an alternative whose guard was closed then is closed for
      --  this execution of the select however the world changes while it
      --  waits, which is Ada's rule and the reason they are read into slots
      --  before anything is tried.
      --
      --  @param Node The select.
      procedure Emit_Selective_Accept (Node : S.Node_Id);

      --  Start a task and keep it in the object that names it.
      --
      --  A task is a value: what it holds names the strand running it, and
      --  that is what a rendezvous and an abort have to find. Several objects
      --  of one task type run one routine, so naming the work would name all
      --  of them at once.
      --
      --  @param Sym The task object.
      --  @param Which The routine it runs.
      --  @param Actuals What it is elaborated with, or No_Node.
      procedure Emit_Start_Task
        (Sym : Symbols.Symbol; Which : Positive; Actuals : S.Node_Id);

      --  Whether the program asked for blocking operations to be caught.
      --
      --  A configuration pragma, which Ada writes before a unit and this
      --  language writes among what a submission holds: what makes it one is
      --  that it says something about the whole program rather than about the
      --  point it stands at.
      function Asked_For (Named : String; Argument : String := "")
                        return Boolean;

      --  Give the machine what each `pragma Priority_Specific_Dispatching`
      --  said, which is a policy for a range of priorities rather than for
      --  the whole program.
      procedure Take_Dispatching_Ranges;

      --  Which protected object a name denotes, or zero.
      --
      --  Numbered when the routines were collected, which is where the objects
      --  were met: an operation carries the number, so any operation of the
      --  object answers for it.
      function Object_Number (Named : S.Node_Id) return Natural;

      --  What a task or protected type of this name says it runs at.
      --
      --  Written as a pragma among what the declaration holds, and looked for
      --  there: a priority is a property of the declaration, and the one place
      --  it can be written is inside it.
      --
      --  @param Name The task or protected type.
      --  @return Its priority, or the default when it named none.
      function Priority_Of (Name : String) return Natural;

      --  The discriminant part a task of this name was declared with.
      --
      --  The same question the analyser asks, asked of the same tree: written
      --  on the declaration only, so a body and an object both look it up.
      function Discriminants_Of (Name : String) return S.Node_Id;

      --  Which routine was collected for a construct written here.
      --
      --  An abortable part has no symbol -- nothing names it -- so what tells
      --  its routine from every other is the part itself.
      function Find_Routine_At (Part : S.Node_Id) return Natural;

      --  Which routine a task of this name runs.
      --
      --  A task's *name* denotes the object; what an abort or a rendezvous has
      --  to name is the work, and a strand records which routine it is
      --  running.
      function Find_Task (Named : String) return Natural;

      --  Whether a name is a member of something rather than a name of its
      --  own, which is to say whether it has a dot in it.
      function Is_Member (Name : String) return Boolean
      is (for some Letter of Name => Letter = '.');

      --  Whether this declaration or body is a protected *type* rather than a
      --  protected object.
      --
      --  A type is a template: what an object of one has is state and a lock
      --  of its own, so nothing is emitted where the type stands and
      --  everything is emitted where an object is declared.
      function Is_Guarded_Template (Node : S.Node_Id) return Boolean;

      --  Which protected object an entry belongs to, or zero when it is a
      --  task's.
      --
      --  What `'Count` counts differs between the two: a task's caller waits
      --  for a rendezvous and a protected object's waits on a barrier.
      function Guarding_Object (Sym : Symbols.Symbol) return Natural;

      --  Emit which member of a family a name says, when it says one.
      --
      --  What the machine adds to the family's own number is how far into it
      --  the member is: the position of the value for a type whose values are
      --  counted from zero, and the value less the first for one with bounds.
      --
      --  @param Sym The entry.
      --  @param Which_One The member, or No_Node.
      --  @return True when an offset was left on the stack.
      function Emit_Family_Member
        (Sym : Symbols.Symbol; Which_One : S.Node_Id) return Boolean;

      --  Which entry of its task a symbol denotes, counting from one.
      --
      --  Numbered by where its declaration was written, which is what both
      --  ends of a rendezvous can agree on without either holding a table.
      function Entry_Number (Sym : Symbols.Symbol) return Natural;

      --  Say that a slot holds a place rather than a value.
      procedure Mark_By_Reference (Sym : Symbols.Symbol);

      --  Check the value on top of the stack against a subtype's bounds.
      --
      --  Emitted wherever a value is stored into something declared with a
      --  range: an object's initial value, an assignment, an argument on its
      --  way into an `in` parameter, a caller's variable after a call wrote
      --  back through it, and a function's result. Those are the five places a
      --  value arrives somewhere, and a check missing from one of them is a
      --  value nobody wrote sitting in a variable that says it cannot hold
      --  one.
      --
      --  Nothing is emitted for a type with no range, which is every built-in
      --  type -- so the ordinary case costs no instruction.

      --  Push what a parameter left out of a call defaults to.
      --
      --  The default is the literal's own source text, kept in the symbol, so
      --  this emits exactly the instruction a literal written at the call site
      --  would have produced. Reading it back rather than storing a value is
      --  what keeps the two from ever disagreeing.
      procedure Emit_Default
        (Node   : S.Node_Id;
         Callee : Symbols.Symbol;
         Index  : Positive);

      function Place_Of (Sym : Symbols.Symbol) return Place;
      procedure Emit_Expression (Node : S.Node_Id);
      procedure Emit_Statement (Node : S.Node_Id);
      procedure Emit_Sequence (Node : S.Node_Id);
      procedure Emit_Builtin_Call
        (Node, Prefix, Arguments : S.Node_Id);
      procedure Emit_Command_Call
        (Node : S.Node_Id; Name : String; Arguments : S.Node_Id);
      procedure Emit_Survivors;
      procedure Emit_Handlers (Handlers : S.Node_Id);

      --  Where the exception a handler caught is kept, while that handler's
      --  statements are being lowered. Zero outside one, which is what the
      --  analyser has already refused a bare `raise` for.
      Caught_Named  : Natural := 0;
      Caught_Detail : Natural := 0;

      --  Whether the machine answers this one itself, and with what.
      --
      --  A predefined function is answered by the shell unless it is something
      --  the machine already holds everything for. Searching and shaping text
      --  is that: the value is on the stack, and asking the shell would be a
      --  round trip to be told what is already here.
      function Computed_Here
        (Which : Adash.Predefined.Entity_Id;
         Op    : out VM.Opcode) return Boolean;

      function Computed_Here
        (Which : Adash.Predefined.Entity_Id;
         Op    : out VM.Opcode) return Boolean is
      begin
         Op := VM.Halt;

         case Which is
            when Adash.Predefined.Entity_Index       => Op := VM.Text_Index;
            when Adash.Predefined.Entity_Trim        => Op := VM.Text_Trim;
            when Adash.Predefined.Entity_To_Upper    => Op := VM.Text_Upper;
            when Adash.Predefined.Entity_To_Lower    => Op := VM.Text_Lower;
            when Adash.Predefined.Entity_Starts_With => Op := VM.Text_Starts;
            when Adash.Predefined.Entity_Ends_With   => Op := VM.Text_Ends;

            --  The clock is the machine's: asking the shell for it would be a
            --  round trip to be told what is already here.
            when Adash.Predefined.Entity_Clock       => Op := VM.Read_Clock;

            when others                              => return False;
         end case;

         return True;
      end Computed_Here;
      --  The argument written for one parameter position.
      --
      --  A call may name its arguments, and a named one is not in the position
      --  it is written in. The analyser settles which parameter each names --
      --  that is what lets it type-check the call -- and the lowering has to
      --  reach the same answer, because what it pushes travels by position.
      --
      --  Positional arguments answer for themselves. A named one is found by
      --  asking the callee's own parameter names, which is what the registries
      --  in `Adash.Predefined` and `Adash.Commands` carry them for.
      --
      --  What a callee calls each of its parameters, by position. Long enough
      --  for either registry: a predefined entity takes at most four and a
      --  command at most as many as its own list holds.
      type Parameter_Names is
        array (Positive range <>) of Ada.Strings.Unbounded.Unbounded_String;

      --  @param Arguments The list as written.
      --  @param Position Which parameter is wanted, from one.
      --  @param Names What the callee calls each parameter, by position.
      --  @return The argument for that parameter, or No_Node.
      function Argument_For
        (Arguments : S.Node_Id;
         Position  : Positive;
         Names     : Parameter_Names) return S.Node_Id;

      procedure Emit_Argument (Node : S.Node_Id; Item : S.Node_Id);
      procedure Emit_Ask
        (Node      : S.Node_Id;
         Named     : String;
         Arguments : S.Node_Id;
         Yields    : Ty.Type_Kind);

      ------------------
      -- Find_Routine --
      ------------------

      function Find_Routine (Sym : Symbols.Symbol) return Natural is
      begin
         if Symbols.Is_Nothing (Sym) then
            return 0;
         end if;

         for Index in 1 .. Natural (Routines.Length) loop
            if Routines.Element (Index).Is_Declared
              and then Routines.Element (Index).Declared_At
                       = Symbols.Extent (Sym).First
              and then Ada.Strings.Unbounded.To_String
                         (Routines.Element (Index).Named)
                       = Symbols.Name (Sym)
            then
               return Index;
            end if;
         end loop;

         return 0;
      end Find_Routine;

      --------------------
      -- New_Temporary --
      --------------------

      --  A slot in the current frame that no declaration names.
      --
      --  For a value the program computed and the lowering has to keep, where
      --  the source gave it nowhere to live. It is never looked up, so it goes
      --  nowhere near the table that maps declarations to slots; taking the
      --  next address is the whole of it, and the frame size follows because
      --  that is what the frame size is measured from.
      function New_Temporary return Natural is
      begin
         Next_Address := Next_Address + 1;
         return Next_Address - 1;
      end New_Temporary;

      -------------------------
      -- Reserve_Temporary --
      -------------------------

      --  Take a slot without naming it, which is how a run of them is asked
      --  for: only the first of a run is addressed, and the rest have to exist
      --  rather than be reachable.
      procedure Reserve_Temporary is
         Taken : constant Natural := New_Temporary;
         pragma Unreferenced (Taken);
      begin
         null;
      end Reserve_Temporary;

      ---------------
      -- Outward --
      ---------------

      --  How many static links out the frame holding a slot is.
      --
      --  The machine addresses a variable by distance rather than by level: a
      --  routine called from two depths has one body, and a body naming
      --  absolute levels would be right for one caller only. A display vector
      --  is the other way of answering this, and it has to be kept in step on
      --  every call and return -- which is a thing to forget.
      function Outward (Of_Level : Positive) return Natural is
      begin
         return Natural'Max (Current_Level - Of_Level, 0);
      end Outward;

      -------------------
      -- Emit_Address --
      -------------------

      --  Put the address a store will write to on the stack.
      --
      --  For a variable that is the slot's own address. For a parameter passed
      --  by reference the slot *contains* the address, so pushing its value is
      --  what yields the address -- which is why the two opcodes look swapped
      --  and are not.
      procedure Emit_Address (Where : Place) is
      begin
         Emit_2 ((if Where.By_Reference then VM.Load else VM.Address),
                 Outward (Where.Level), VM.Whole_Number (Where.Address));
      end Emit_Address;

      -----------------
      -- Emit_Value --
      -----------------

      procedure Emit_Value (Where : Place) is
      begin
         Emit_2 ((if Where.By_Reference then VM.Load_Indirect else VM.Load),
                 Outward (Where.Level), VM.Whole_Number (Where.Address));
      end Emit_Value;

      ----------------------
      -- Emit_Aggregate --
      ----------------------

      procedure Emit_Aggregate
        (Target     : S.Node_Id;
         Of_Type    : Ty.Type_Kind;
         Values     : S.Node_Id;
         At_Address : Integer := -1)
      is
         Given : constant Natural := S.Child_Count (Tree, Values);

         --  Where each part's value comes from, by position. An aggregate may
         --  name its parts and reorder them, exactly as a call may name its
         --  arguments, so position in the text is not position in the value.
         Filled : array (1 .. Sem.Part_Count (Analysis, Of_Type))
                    of S.Node_Id := [others => S.No_Node];

         --  What `others` gives to every part nothing else named. Filled in
         --  after the rest, because that is what it answers for.
         Rest : S.Node_Id := S.No_Node;
      begin
         for Index in 1 .. Given loop
            declare
               One : constant S.Node_Id := S.Child (Tree, Values, Index);
            begin
               if S.Kind (Tree, One) = S.Node_Named_Argument
                 and then S.Kind (Tree, S.First (Tree, One)) = S.Node_Others
               then
                  Rest := S.Second (Tree, One);

               elsif S.Kind (Tree, One) = S.Node_Named_Argument
                 and then S.Kind (Tree, S.First (Tree, One)) = S.Node_Range
               then
                  --  A run of slots, `1 .. 3 => 0`, and what `X'Range` stands
                  --  for. One value goes into every slot between the ends.
                  declare
                     Choice : constant S.Node_Id := S.First (Tree, One);
                     Low, High : Long_Long_Integer;
                  begin
                     if Sem.Static_Choice
                          (Analysis, Tree, S.First (Tree, Choice), Low)
                       and then Sem.Static_Choice
                                  (Analysis, Tree, S.Second (Tree, Choice),
                                   High)
                     then
                        for Each in Low .. High loop
                           declare
                              Slot : constant Long_Long_Integer :=
                                Each - Sem.First_Index (Analysis, Of_Type) + 1;
                           begin
                              if Slot in 1 .. Long_Long_Integer (Filled'Last)
                              then
                                 Filled (Natural (Slot)) :=
                                   S.Second (Tree, One);
                              end if;
                           end;
                        end loop;
                     end if;
                  end;

               elsif S.Kind (Tree, One) = S.Node_Named_Argument
                 and then Ty.Shape (Of_Type) = Ty.Shape_Array
               then
                  --  An array names a part by its index. Semantics settled
                  --  that the index is a value known before the program runs
                  --  and that it is one of this array's; what is left is
                  --  turning it into which slot.
                  declare
                     Where : Long_Long_Integer;
                  begin
                     if Sem.Static_Choice
                          (Analysis, Tree, S.First (Tree, One), Where)
                     then
                        declare
                           Slot : constant Long_Long_Integer :=
                             Where - Sem.First_Index (Analysis, Of_Type) + 1;
                        begin
                           if Slot in 1 .. Long_Long_Integer (Filled'Last) then
                              Filled (Natural (Slot)) := S.Second (Tree, One);
                           end if;
                        end;
                     end if;
                  end;

               elsif S.Kind (Tree, One) = S.Node_Named_Argument then
                  declare
                     Slot : constant Natural :=
                       Sem.Part_At
                         (Analysis, Of_Type,
                          S.Text (Tree, S.First (Tree, One)));
                  begin
                     if Slot in Filled'Range then
                        Filled (Slot) := S.Second (Tree, One);
                     end if;
                  end;

               elsif Index in Filled'Range then
                  Filled (Index) := One;
               end if;
            end;
         end loop;

         if S.Is_Present (Rest) then
            for Index in Filled'Range loop
               if not S.Is_Present (Filled (Index)) then
                  Filled (Index) := Rest;
               end if;
            end loop;
         end if;

         for Index in Filled'Range loop
            exit when not Lowerable;

            if not S.Is_Present (Filled (Index)) then
               --  Semantics establishes that every part has a value, so
               --  reaching here means the two passes disagree.
               Refuse (Target, Adash.Messages.Msg_Lower_This_Expression);
               return;
            end if;

            declare
               Holds : constant Ty.Type_Kind :=
                 Sem.Part_Type (Analysis, Of_Type, Index);
               Ok : Boolean;
            begin
               if At_Address >= 0 then
                  Emit_2 (VM.Address, 0, VM.Whole_Number (At_Address));
                  Ok := True;
               else
                  Emit_Place (Target, Ok);
               end if;

               exit when not Ok;

               Emit_1
                 (VM.Offset_Place,
                  VM.Whole_Number
                    (Sem.Part_Offset (Analysis, Of_Type, Index)));

               Emit_Expression (Filled (Index));
               Emit_Bounds_Check (Holds);
               Emit_Store (Holds);
            end;
         end loop;
      end Emit_Aggregate;

      -----------------
      -- Emit_Copy --
      -----------------

      procedure Emit_Copy
        (Target  : S.Node_Id;
         Value   : S.Node_Id;
         Of_Type : Ty.Type_Kind)
      is
         Onto, From : Boolean;
      begin
         Emit_Place (Target, Onto);

         if not Onto then
            return;
         end if;

         Emit_Place (Value, From);

         if not From then
            return;
         end if;

         Emit_1 (VM.Copy_Block, VM.Whole_Number (Ty.Width (Of_Type)));
      end Emit_Copy;

      -------------------------
      -- Emit_Rendezvous --
      -------------------------

      procedure Emit_Rendezvous
        (Node, Prefix, Arguments : S.Node_Id;
         Wait_For : S.Node_Id := S.No_Node;
         Only_If_Ready : Boolean := False)
      is
         --  A call that says how long it will wait, or that it will not wait
         --  at all, leaves behind whether it was met for the select around it
         --  to branch on.
         Timed   : constant Boolean := S.Is_Present (Wait_For);
         Bounded : constant Boolean := Timed or else Only_If_Ready;
         Answer  : constant Natural :=
           (if Bounded then New_Temporary else 0);

         Called : constant Symbols.Symbol := Sem.Symbol_Of (Analysis, Prefix);
         Count  : constant Natural := Symbols.Parameter_Count (Called);
         Which  : constant Natural := Entry_Number (Called);

         --  Whose entry it is. The analyser left the object's own symbol on
         --  the prefix, because what a rendezvous has to find is the task
         --  rather than the entry: several objects of one task type share
         --  every entry, and a caller of one is not a caller of another.
         Whose  : constant Symbols.Symbol :=
           Sem.Symbol_Of (Analysis, S.First (Tree, Prefix));

         --  A run of slots in the *caller's* frame. The accept body's formals
         --  are references into it, which is what makes an `out` parameter
         --  come back: the body writes where the caller is reading from.
         Block : constant Natural := New_Temporary;

         Slots_Given : Sem.Argument_Map := [others => S.No_Node];
         At_Node : S.Node_Id := S.No_Node;
         Spot    : Natural := 0;
      begin
         --  The rest of the run. Taken one at a time because that is the only
         --  way to ask for a slot, and contiguous because that is what taking
         --  them in a row gives.
         for Index in 2 .. Count loop
            Reserve_Temporary;
         end loop;

         --  A family's parentheses hold which member rather than what it
         --  takes, and a member takes nothing -- so there is no profile to
         --  match a call against.
         if Symbols.Of_Type (Called) = Ty.Type_None
           and then S.Is_Present (Arguments)
           and then Sem."/=" (Sem.Match_Arguments
                                (Tree, Arguments, Called, Slots_Given,
                                 At_Node, Spot),
                              Sem.Matched)
         then
            Refuse (Node, Adash.Messages.Msg_Lower_Call_Wrong_Count);
            return;
         end if;

         --  What is given, written into the block before the meeting. An `out`
         --  parameter starts as whatever the caller's variable holds, which is
         --  what Ada copies in for `in out` and what a body may not read for
         --  `out` -- and the analyser is what enforces the difference.
         for Index in 1 .. Count loop
            exit when not Lowerable;

            Emit_2 (VM.Address, 0, VM.Whole_Number (Block + Index - 1));

            if S.Is_Present (Slots_Given (Index)) then
               Emit_Expression (Slots_Given (Index));
            else
               Emit_Default (Node, Called, Index);
            end if;

            Emit_Store (Symbols.Parameter_Type (Called, Index));
         end loop;

         if Symbols.Is_Nothing (Whose) then
            Refuse (Node, Adash.Messages.Msg_Lower_Unresolved_Name);
            return;
         end if;

         --  How long it will wait, under everything else, because the
         --  instruction takes it last.
         if Timed then
            Emit_Expression (Wait_For);
         end if;

         --  Which member of a family, then whose it is, then where the
         --  arguments are: the order the machine takes them off in, reversed.
         declare
            Member : constant Boolean :=
              Emit_Family_Member
                (Called,
                 (if S.Is_Present (Arguments)
                    and then S.Child_Count (Tree, Arguments) = 1
                  then S.Child (Tree, Arguments, 1) else S.No_Node));
         begin
            Emit_Value (Place_Of (Whose));
            Emit_2 (VM.Block_At, 0, VM.Whole_Number (Block));
            Emit_2 (VM.Call_Entry, Which,
                    VM.Whole_Number ((if Member then 1 else 0)
                                     + (if Timed then 2 else 0)
                                     + (if Only_If_Ready then 4 else 0)));
         end;

         --  Whether it was met, kept until the arguments have been carried
         --  back: a call that ran out has nothing to carry, but the copying
         --  is the same code and copying a caller's own values back into its
         --  own variables changes nothing.
         if Bounded then
            Emit_2 (VM.Address, 0, VM.Whole_Number (Answer));
            Emit (VM.Call_Answer);
            Emit (VM.Store);
         end if;

         --  And what came back. The block holds what the accept body left, and
         --  a write-back parameter's actual is where it belongs.
         for Index in 1 .. Count loop
            exit when not Lowerable;

            if Symbols."/=" (Symbols.Parameter_Passing (Called, Index),
                             Symbols.Mode_In)
              and then S.Is_Present (Slots_Given (Index))
            then
               declare
                  Ok : Boolean;
               begin
                  Emit_Place (Slots_Given (Index), Ok);
                  exit when not Ok;

                  Emit_2 (VM.Load, 0, VM.Whole_Number (Block + Index - 1));
                  Emit_Bounds_Check
                    (Sem.Type_Of (Analysis, Slots_Given (Index)));
                  Emit_Store (Symbols.Parameter_Type (Called, Index));
               end;
            end if;
         end loop;

         if Bounded then
            Emit_2 (VM.Load, 0, VM.Whole_Number (Answer));
         end if;
      end Emit_Rendezvous;

      -------------------------------
      -- Is_Guarded_Template --
      -------------------------------

      function Is_Guarded_Template (Node : S.Node_Id) return Boolean is
      begin
         if S.Kind (Tree, Node) = S.Node_Protected_Declaration then
            return S.Text (Tree, Node) = "type";
         end if;

         --  A body says nothing about itself; what it completes does.
         return S.Kind (Tree, Node) = S.Node_Protected_Body
           and then Ty.Is_Protected
                      (Symbols.Of_Type
                         (Sem.Symbol_Of (Analysis, S.First (Tree, Node))));
      end Is_Guarded_Template;

      ----------------------------
      -- Guarding_Object --
      ----------------------------

      function Guarding_Object (Sym : Symbols.Symbol) return Natural is
      begin
         for Index in 1 .. Natural (Routines.Length) loop
            if S.Kind (Tree, Routines.Element (Index).Node) = S.Node_Entry
              and then Routines.Element (Index).Declared_At
                       = Symbols.Extent (Sym).First
              and then Ada.Strings.Unbounded.To_String
                         (Routines.Element (Index).Named)
                       = Symbols.Name (Sym)
            then
               return Routines.Element (Index).Guarded_By;
            end if;
         end loop;

         return 0;
      end Guarding_Object;

      ---------------------
      -- Entry_Number --
      ---------------------

      function Entry_Number (Sym : Symbols.Symbol) return Natural is
         --  How many numbers it takes: one, or one per member of a family.
         Members : constant Positive :=
           (if Symbols.Is_Nothing (Sym)
              or else Symbols.Of_Type (Sym) = Ty.Type_None
            then 1
            else Positive (Ty.Admitted_Count (Symbols.Of_Type (Sym))));
      begin
         if Symbols.Is_Nothing (Sym) then
            return 0;
         end if;

         for Index in 1 .. Natural (Entries.Length) loop
            if Entries.Element (Index).Declared_At
               = Symbols.Extent (Sym).First
            then
               return Entries.Element (Index).Number;
            end if;
         end loop;

         Next_Entry := Next_Entry + 1;
         Entries.Append
           (Known_Entry'(Declared_At => Symbols.Extent (Sym).First,
                         Number      => Next_Entry,
                         Members     => Members));

         --  The rest of a family's run, reserved so that the next entry
         --  declared does not land inside it.
         Next_Entry := Next_Entry + Members - 1;

         return Entries.Last_Element.Number;
      end Entry_Number;

      ------------------------------
      -- Emit_Family_Member --
      ------------------------------

      function Emit_Family_Member
        (Sym : Symbols.Symbol; Which_One : S.Node_Id) return Boolean
      is
         Indexed_By : constant Ty.Type_Kind := Symbols.Of_Type (Sym);
      begin
         if Indexed_By = Ty.Type_None or else not S.Is_Present (Which_One) then
            return False;
         end if;

         Emit_Expression (Which_One);

         --  A constrained subtype counts from its own first value, and every
         --  other discrete type counts from zero -- which is what its values
         --  already are on the stack.
         if Ty.Has_Bounds (Indexed_By) then
            Emit_1 (VM.Push_Whole,
                    VM.Whole_Number (Ty.Low_Bound (Indexed_By)));
            Emit (VM.Subtract_Whole);
         end if;

         return True;
      end Emit_Family_Member;

      --------------------------
      -- Mark_By_Reference --
      --------------------------

      procedure Mark_By_Reference (Sym : Symbols.Symbol) is
         Declared : constant Adash.Source.Byte_Offset :=
           Symbols.Extent (Sym).First;
         Called   : constant String := Symbols.Name (Sym);
      begin
         for Index in 1 .. Natural (Slots.Length) loop
            if Slots.Element (Index).Declared_At = Declared
              and then Ada.Strings.Unbounded.To_String
                         (Slots.Element (Index).Named) = Called
            then
               declare
                  Held : Slot := Slots.Element (Index);
               begin
                  Held.By_Reference := True;
                  Slots.Replace_Element (Index, Held);
               end;

               return;
            end if;
         end loop;
      end Mark_By_Reference;

      -------------------------------
      -- Emit_Leaving_Blocks --
      -------------------------------

      procedure Emit_Leaving_Blocks is
         Outermost : constant Natural :=
           (if Loop_Regions.Is_Empty then 0 else Loop_Regions.Last_Element);
      begin
         for Index in reverse Outermost + 1
                              .. Natural (Region_Slots.Length)
         loop
            Emit_2 (VM.Load, 0,
                    VM.Whole_Number (Region_Slots.Element (Index)));
            Emit (VM.Leave_Region);
         end loop;
      end Emit_Leaving_Blocks;

      ---------------------------
      -- Emit_Accept_Body --
      ---------------------------

      procedure Emit_Accept_Body (Node : S.Node_Id; Which : Positive) is
         Formals : constant S.Node_Id := S.Second (Tree, Node);
         Held    : constant S.Node_Id := S.Third (Tree, Node);

         --  Which member of a family this serves, computed again here because
         --  letting the caller go names the same member the accept took it
         --  from -- and what named it is an expression, which may say
         --  something different by the time the body has run.
         Served : constant Symbols.Symbol :=
           Sem.Symbol_Of (Analysis, S.First (Tree, Node));
         Member : constant S.Node_Id :=
           (if S.Child_Count (Tree, Node) >= 4
            then S.Child (Tree, Node, 4) else S.No_Node);

         --  Saved and put back, so that a requeue written inside this accept
         --  leaves *this* one -- an accept inside an accept is not something
         --  Ada writes, and a state that assumed so would be a rule kept by
         --  luck.
         Outer_Entry  : constant Natural := Serving_Entry;
         Outer_Symbol : constant Symbols.Symbol := Serving_Symbol;
         Outer_Member : constant S.Node_Id := Serving_Member;
         Outer_Leaves : constant Natural := Natural (Requeue_Sites.Length);

         --  Where the caller's arguments start, kept for the length of the
         --  rendezvous. The formals are references into that run, which is
         --  what makes an `out` parameter come back: the body writes where the
         --  caller is reading from.
         Block : constant Natural := New_Temporary;
      begin
         Emit_2 (VM.Address, 0, VM.Whole_Number (Block));
         Emit (VM.Swap);
         Emit (VM.Store);

         for Index in 1 .. S.Child_Count (Tree, Formals) loop
            declare
               One : constant S.Node_Id := S.Child (Tree, Formals, Index);
               Sym : constant Symbols.Symbol :=
                 Sem.Symbol_Of (Analysis, S.First (Tree, One));
               Where : Place;
            begin
               if Symbols.Is_Nothing (Sym) then
                  Refuse (Node, Adash.Messages.Msg_Lower_Unresolved_Name);
                  return;
               end if;

               --  One slot per formal, holding a place into the caller's
               --  block. By-reference is what the machine already does with a
               --  slot holding a place, so the body reads and writes them with
               --  no rule of its own.
               Where := Place_Of (Sym);
               Mark_By_Reference (Sym);

               Emit_2 (VM.Address, Outward (Where.Level),
                       VM.Whole_Number (Where.Address));
               Emit_2 (VM.Load, 0, VM.Whole_Number (Block));
               Emit_1 (VM.Offset_Place, VM.Whole_Number (Index - 1));
               Emit (VM.Store);
            end;
         end loop;

         Serving_Entry  := Which;
         Serving_Symbol := Served;
         Serving_Member := Member;

         if S.Is_Present (Held) then
            --  A region of its own. An accept body is a master in Ada, and
            --  what makes it worth being one here is that this language
            --  accepts a declaration wherever a statement may stand: a task
            --  declared inside a rendezvous is finished with before the caller
            --  is let go, which is what the caller is entitled to assume.
            declare
               Outer : constant Natural := New_Temporary;
            begin
               Region_Slots.Append (Outer);

               Emit_2 (VM.Address, 0, VM.Whole_Number (Outer));
               Emit (VM.Enter_Region);
               Emit (VM.Store);

               Emit_Sequence (Held);

               --  Before the caller is let go rather than after.
               Emit_2 (VM.Load, 0, VM.Whole_Number (Outer));
               Emit (VM.Leave_Region);

               Region_Slots.Delete_Last;
            end;
         end if;

         if Emit_Family_Member (Served, Member) then
            Emit_2 (VM.End_Accept, Which, 1);
         else
            Emit_2 (VM.End_Accept, Which, 0);
         end if;

         --  Where a requeue lands: past the End_Accept, because the caller it
         --  moved is not the caller this would let go.
         for Index in reverse Outer_Leaves + 1
                              .. Natural (Requeue_Sites.Length)
         loop
            Code.Patch (Requeue_Sites.Element (Index), Here);
            Requeue_Sites.Delete_Last;
         end loop;

         Serving_Entry  := Outer_Entry;
         Serving_Symbol := Outer_Symbol;
         Serving_Member := Outer_Member;
      end Emit_Accept_Body;

      -------------------------
      -- Emit_Then_Abort --
      -------------------------

      procedure Emit_Then_Abort (Node : S.Node_Id) is
         Trigger : constant S.Node_Id := S.First (Tree, Node);
         Taken   : constant S.Node_Id := S.Second (Tree, Node);

         Which : constant Natural :=
           Find_Routine_At (S.Third (Tree, Node));

         --  The strand running the abortable part, kept for as long as the
         --  select lasts: it is what the trigger watches, what is abandoned
         --  when the trigger fires, and what says the trigger was cancelled.
         Running : constant Natural := New_Temporary;

         Cancelled : Natural;
      begin
         if Which = 0 then
            Refuse (Node, Adash.Messages.Msg_Lower_This_Statement);
            return;
         end if;

         Emit_2 (VM.Address, 0, VM.Whole_Number (Running));
         Emit_2 (VM.Start_Task,
                 Routines.Element (Which).Level,
                 VM.Whole_Number (Routines.Element (Which).Ident));
         Emit (VM.Store);
         Started_A_Task := True;

         --  Watched, so that the wait ends when the work does. Without it a
         --  delay would run its full course after the reason to wait had
         --  finished, which is the outcome Ada gives and not the timing.
         Emit_2 (VM.Load, 0, VM.Whole_Number (Running));
         Emit (VM.Watch_Task);

         Emit_Statement (Trigger);

         Emit (VM.Watch_Nothing);

         --  Which of the two happened. A trigger that ended because the work
         --  finished is a cancelled trigger, and its statements do not run.
         Emit_2 (VM.Load, 0, VM.Whole_Number (Running));
         Emit (VM.Task_Ended);
         Cancelled := Here;
         Emit_1 (VM.Jump_If_False, 0);

         declare
            Done : constant Natural := Here;
         begin
            Emit_1 (VM.Jump, 0);
            Code.Patch (Cancelled, Here);

            --  The trigger fired first. What it was waiting for has happened,
            --  so the work is abandoned where it would next have run.
            Emit_2 (VM.Load, 0, VM.Whole_Number (Running));
            Emit (VM.Abort_Task);
            Emit_Sequence (Taken);

            Code.Patch (Done, Here);
         end;
      end Emit_Then_Abort;

      -------------------------------
      -- Emit_Selective_Accept --
      -------------------------------

      procedure Emit_Selective_Accept (Node : S.Node_Id) is
         Choices   : constant S.Node_Id := S.First (Tree, Node);
         Otherwise : constant S.Node_Id := S.Second (Tree, Node);
         Count     : constant Natural := S.Child_Count (Tree, Choices);

         --  Where each guard's answer is kept. Asked once, before anything is
         --  tried, because a strand that waits and comes back must not find a
         --  different set of alternatives open than the one it chose from.
         --
         --  Whether there is one is a field rather than a reserved address:
         --  the first slot of a frame is address zero, and a task body's frame
         --  starts there because it has no parameters.
         type Guard_Slot is record
            Asked : Boolean := False;
            Where : Natural := 0;
         end record;

         Open : array (1 .. Natural'Max (Count, 1)) of Guard_Slot;

         --  Which alternative bounds the wait, if one does.
         Waits : Natural := 0;

         --  Which alternative says the task may end instead of waiting, if
         --  one does, and where the code that ends it stands.
         Ends     : Natural := 0;
         Ends_At  : Natural := 0;

         --  Every jump out to the end, patched when the end is known.
         Leaving : Patch_Vectors.Vector;

         --  Emit one accept alternative: its guard, its try, and its body.
         --  Falls through when the alternative is closed or nobody is there.
         procedure Emit_One (Index : Positive);

         --  Offer every open alternative to the choice, so that the one
         --  served is the one holding the caller who comes first rather than
         --  whichever is written first.
         --
         --  Emitted before each run of the try chain -- there are two, one
         --  before a bounded wait and one after -- because callers arrive
         --  between them and the choice is about who is there now.
         procedure Emit_Offers;

         procedure Emit_Offers is
         begin
            Emit_1 (VM.Choose, 1);

            --  The one alternative nothing here can take: whether it is taken
            --  is the scheduler's to decide, so what is emitted is the
            --  willingness and where to go.
            if Ends /= 0 then
               if Open (Ends).Asked then
                  Emit_2 (VM.Load, 0, VM.Whole_Number (Open (Ends).Where));
               else
                  Emit_1 (VM.Push_Truth, 1);
               end if;

               Emit_2 (VM.Offer_End, 0, VM.Whole_Number (Ends_At));
            end if;

            for Index in 1 .. Count loop
               exit when not Lowerable;

               if Index /= Waits and then Index /= Ends then
                  declare
                     One   : constant S.Node_Id :=
                       S.Child (Tree, Choices, Index);
                     Taken : constant S.Node_Id := S.Second (Tree, One);
                     Which : constant Natural :=
                       Entry_Number
                         (Sem.Symbol_Of (Analysis, S.First (Tree, Taken)));
                     Family : Boolean;
                  begin
                     if Which /= 0 then
                        --  The member first, then whether the alternative is
                        --  open: the instruction reads the open answer off
                        --  the top and the member from under it.
                        Family :=
                          Emit_Family_Member
                            (Sem.Symbol_Of (Analysis, S.First (Tree, Taken)),
                             (if S.Child_Count (Tree, Taken) >= 4
                              then S.Child (Tree, Taken, 4) else S.No_Node));

                        if Open (Index).Asked then
                           Emit_2 (VM.Load, 0,
                                   VM.Whole_Number (Open (Index).Where));
                        else
                           Emit_1 (VM.Push_Truth, 1);
                        end if;

                        Emit_2 (VM.Offer_Entry, Which,
                                (if Family then 1 else 0));
                     end if;
                  end;
               end if;
            end loop;
         end Emit_Offers;

         procedure Emit_One (Index : Positive) is
            One   : constant S.Node_Id := S.Child (Tree, Choices, Index);
            Taken : constant S.Node_Id := S.Second (Tree, One);
            Rest  : constant S.Node_Id := S.Third (Tree, One);

            Which : constant Natural :=
              Entry_Number (Sem.Symbol_Of (Analysis, S.First (Tree, Taken)));

            Closed  : Natural := 0;
            Nobody  : Natural;
         begin
            if Which = 0 then
               Refuse (Node, Adash.Messages.Msg_Lower_This_Statement);
               return;
            end if;

            if Open (Index).Asked then
               Emit_2 (VM.Load, 0, VM.Whole_Number (Open (Index).Where));
               Closed := Here;
               Emit_1 (VM.Jump_If_False, 0);
            end if;

            if Emit_Family_Member
                 (Sem.Symbol_Of (Analysis, S.First (Tree, Taken)),
                  (if S.Child_Count (Tree, Taken) >= 4
                   then S.Child (Tree, Taken, 4) else S.No_Node))
            then
               Emit_2 (VM.Try_Accept, Which, 1);
            else
               Emit_2 (VM.Try_Accept, Which, 0);
            end if;

            Nobody := Here;
            Emit_1 (VM.Jump_If_False, 0);

            Emit_Accept_Body (Taken, Which);
            Emit_Sequence (Rest);

            Leaving.Append (Here);
            Emit_1 (VM.Jump, 0);

            Code.Patch (Nobody, Here);

            if Closed /= 0 then
               Code.Patch (Closed, Here);
            end if;
         end Emit_One;
      begin
         --  The guards, once. An alternative with none is always open and
         --  needs no slot.
         for Index in 1 .. Count loop
            declare
               One   : constant S.Node_Id := S.Child (Tree, Choices, Index);
               Guard : constant S.Node_Id := S.First (Tree, One);
            begin
               if S.Kind (Tree, S.Second (Tree, One)) = S.Node_Delay then
                  Waits := Index;
               end if;

               if S.Kind (Tree, S.Second (Tree, One)) = S.Node_Terminate then
                  Ends := Index;
               end if;

               if S.Is_Present (Guard) then
                  Open (Index) := (Asked => True, Where => New_Temporary);
                  Emit_2 (VM.Address, 0,
                          VM.Whole_Number (Open (Index).Where));
                  Emit_Expression (Guard);
                  Emit (VM.Store);
               end if;
            end;
         end loop;

         --  Where a task that may end goes when the scheduler says it may.
         --  Jumped over rather than fallen into: nothing reaches it except by
         --  being sent there.
         if Ends /= 0 then
            declare
               Past : constant Natural := Here;
            begin
               Emit_1 (VM.Jump, 0);
               Ends_At := Here;
               Emit_1 (VM.Choose, 0);
               Emit (VM.End_Task);
               Code.Patch (Past, Here);
            end;
         end if;

         declare
            Again : constant Natural := Here;
         begin
            Emit_Offers;

            for Index in 1 .. Count loop
               exit when not Lowerable;

               if Index /= Waits and then Index /= Ends then
                  Emit_One (Index);
               end if;
            end loop;

            --  Nothing could be taken. What happens then is what the select
            --  said: run the other statements, wait a bounded time and look
            --  again, or wait for a caller.
            if S.Is_Present (Otherwise) then
               Emit_1 (VM.Choose, 0);
               Emit_Sequence (Otherwise);

            elsif Waits /= 0 then
               declare
                  One   : constant S.Node_Id :=
                    S.Child (Tree, Choices, Waits);
                  Taken : constant S.Node_Id := S.Second (Tree, One);
                  Rest  : constant S.Node_Id := S.Third (Tree, One);
                  Shut  : Natural := 0;
               begin
                  if Open (Waits).Asked then
                     --  A closed delay alternative bounds nothing, so the
                     --  select waits as though it were not written.
                     Emit_2 (VM.Load, 0,
                             VM.Whole_Number (Open (Waits).Where));
                     Shut := Here;
                     Emit_1 (VM.Jump_If_False, 0);
                  end if;

                  --  What is open stays written down across the wait, and
                  --  the wait says a caller may cut it short: a select that
                  --  says `or delay D` is waiting for a caller as much as for
                  --  the clock, and it was only the sleeping that made it
                  --  look otherwise.
                  Emit_Expression (S.First (Tree, Taken));
                  Emit_1 (VM.Delay_For, 1);

                  Emit_Offers;

                  for Index in 1 .. Count loop
                     exit when not Lowerable;

                     if Index /= Waits and then Index /= Ends then
                        Emit_One (Index);
                     end if;
                  end loop;

                  Emit_1 (VM.Choose, 0);
                  Emit_Sequence (Rest);

                  if Shut /= 0 then
                     Leaving.Append (Here);
                     Emit_1 (VM.Jump, 0);
                     Code.Patch (Shut, Here);
                     Emit_1 (VM.Await_Caller, VM.Whole_Number (Again));
                  end if;
               end;

            else
               Emit_1 (VM.Await_Caller, VM.Whole_Number (Again));
            end if;
         end;

         for Jump of Leaving loop
            Code.Patch (Jump, Here);
         end loop;
      end Emit_Selective_Accept;

      ------------------------
      -- Emit_Start_Task --
      ------------------------

      procedure Emit_Start_Task
        (Sym : Symbols.Symbol; Which : Positive; Actuals : S.Node_Id)
      is
         --  What it runs at, said before it starts. A task that says nothing
         --  runs at the default, which is what the machine goes back to after
         --  every start.
         Runs_At : constant Natural :=
           Priority_Of (Ty.Name (Symbols.Of_Type (Sym)));
         --  What the type takes, which is what says how many values the
         --  machine will look for -- an object that gave none is one whose
         --  discriminants all default, and the defaults are the type's.
         Formals : constant S.Node_Id :=
           Discriminants_Of (Ty.Name (Symbols.Of_Type (Sym)));
      begin
         Emit_Address (Place_Of (Sym));

         if Runs_At /= VM.Default_Priority then
            Emit_1 (VM.Priority_Is, VM.Whole_Number (Runs_At));
         end if;

         --  What it is elaborated with, in the order it was written. The
         --  machine takes them off the stack into the new frame's first slots,
         --  which is where the body's own lowering expects a parameter.
         for Index in 1 .. S.Child_Count (Tree, Formals) loop
            if S.Child_Count (Tree, Actuals) >= Index then
               Emit_Expression (S.Child (Tree, Actuals, Index));
            else
               Emit_Expression
                 (S.Child (Tree, S.Child (Tree, Formals, Index), 3));
            end if;
         end loop;

         Emit_2 (VM.Start_Task,
                 Routines.Element (Which).Level,
                 VM.Whole_Number (Routines.Element (Which).Ident));
         Emit (VM.Store);

         Started_A_Task := True;
      end Emit_Start_Task;

      ---------------------
      -- Asked_For --
      ---------------------

      function Asked_For (Named : String; Argument : String := "")
                         return Boolean
      is
         Root : constant S.Node_Id := S.Root (Tree);

         --  Whether this pragma's one argument is the one asked about. An
         --  empty question is about the pragma alone.
         function Says (Node : S.Node_Id) return Boolean is
            Given : constant S.Node_Id := S.Second (Tree, Node);
         begin
            return Argument = ""
              or else (S.Child_Count (Tree, Given) = 1
                       and then Symbols.Fold
                                  (S.Text (Tree, S.Child (Tree, Given, 1)))
                                = Symbols.Fold (Argument));
         end Says;

      begin
         for Index in 1 .. S.Child_Count (Tree, Root) loop
            declare
               Node : constant S.Node_Id := S.Child (Tree, Root, Index);
            begin
               if S.Kind (Tree, Node) = S.Node_Pragma
                 and then Symbols.Fold (S.Text (Tree, S.First (Tree, Node)))
                          = Symbols.Fold (Named)
                 and then Says (Node)
               then
                  return True;
               end if;
            end;
         end loop;

         return False;
      end Asked_For;

      -------------------------------------
      -- Take_Dispatching_Ranges --
      -------------------------------------

      procedure Take_Dispatching_Ranges is
         Root : constant S.Node_Id := S.Root (Tree);
      begin
         for Index in 1 .. S.Child_Count (Tree, Root) loop
            declare
               Node : constant S.Node_Id := S.Child (Tree, Root, Index);
            begin
               if S.Kind (Tree, Node) = S.Node_Pragma
                 and then Symbols.Fold (S.Text (Tree, S.First (Tree, Node)))
                          = "priority_specific_dispatching"
               then
                  declare
                     Given : constant S.Node_Id := S.Second (Tree, Node);
                     First : Long_Long_Integer;
                     Last  : Long_Long_Integer;
                  begin
                     --  Only the one that changes something is passed on:
                     --  sharing turns out is what the machine does anyway, so
                     --  a range given round robin is a range left alone.
                     if S.Child_Count (Tree, Given) = 3
                       and then Symbols.Fold
                                  (S.Text (Tree, S.Child (Tree, Given, 1)))
                                = "fifo_within_priorities"
                       and then Sem.Static_Choice
                                  (Analysis, Tree, S.Child (Tree, Given, 2),
                                   First)
                       and then Sem.Static_Choice
                                  (Analysis, Tree, S.Child (Tree, Given, 3),
                                   Last)
                       and then First >= 0
                       and then Last >= First
                     then
                        Code.Run_To_Completion
                          (Natural (First), Natural (Last));
                     end if;
                  end;
               end if;
            end;
         end loop;
      end Take_Dispatching_Ranges;

      ---------------------------
      -- Object_Number --
      ---------------------------

      function Object_Number (Named : S.Node_Id) return Natural is
         Wanted : constant String :=
           (if S.Kind (Tree, Named) = S.Node_Name
            then Symbols.Fold (S.Text (Tree, Named)) else "");
      begin
         for Index in 1 .. Natural (Routines.Length) loop
            declare
               One : constant Routine := Routines.Element (Index);
            begin
               if One.Guarded_By /= 0
                 and then S.Kind (Tree, One.Node) in S.Node_Entry
                                                   | S.Node_Subprogram_Declaration
               then
                  --  Which object an operation belongs to is what its own
                  --  name is under: `Gate.Pass` belongs to Gate.
                  declare
                     Full : constant String :=
                       Symbols.Name
                         (Sem.Symbol_Of (Analysis, S.First (Tree, One.Node)));
                  begin
                     for Position in Full'Range loop
                        if Full (Position) = '.'
                          and then Symbols.Fold
                                     (Full (Full'First .. Position - 1))
                                   = Wanted
                        then
                           return One.Guarded_By;
                        end if;
                     end loop;
                  end;
               end if;
            end;
         end loop;

         return 0;
      end Object_Number;

      ---------------------------
      -- Priority_Of --
      ---------------------------

      function Priority_Of (Name : String) return Natural is
         Root : constant S.Node_Id := S.Root (Tree);
      begin
         for Index in 1 .. S.Child_Count (Tree, Root) loop
            declare
               Node : constant S.Node_Id := S.Child (Tree, Root, Index);
            begin
               if S.Kind (Tree, Node) in S.Node_Task_Declaration
                                       | S.Node_Protected_Declaration
                 and then Symbols.Fold (S.Text (Tree, S.First (Tree, Node)))
                          = Symbols.Fold (Name)
               then
                  declare
                     Held : constant S.Node_Id := S.Second (Tree, Node);
                  begin
                     for Position in 1 .. S.Child_Count (Tree, Held) loop
                        declare
                           One : constant S.Node_Id :=
                             S.Child (Tree, Held, Position);
                        begin
                           if S.Kind (Tree, One) = S.Node_Pragma then
                              declare
                                 Given : constant S.Node_Id :=
                                   S.Second (Tree, One);
                                 Value : Long_Long_Integer;
                              begin
                                 if S.Child_Count (Tree, Given) = 1
                                   and then Sem.Static_Choice
                                              (Analysis, Tree,
                                               S.Child (Tree, Given, 1),
                                               Value)
                                 then
                                    return Natural (Value);
                                 end if;
                              end;
                           end if;
                        end;
                     end loop;
                  end;
               end if;
            end;
         end loop;

         return VM.Default_Priority;
      end Priority_Of;

      ---------------------------
      -- Discriminants_Of --
      ---------------------------

      function Discriminants_Of (Name : String) return S.Node_Id is
         Root : constant S.Node_Id := S.Root (Tree);
      begin
         for Index in 1 .. S.Child_Count (Tree, Root) loop
            declare
               Node : constant S.Node_Id := S.Child (Tree, Root, Index);
            begin
               if S.Kind (Tree, Node) = S.Node_Task_Declaration
                 and then S.Child_Count (Tree, Node) >= 4
                 and then Symbols.Fold (S.Text (Tree, S.First (Tree, Node)))
                          = Symbols.Fold (Name)
               then
                  return S.Child (Tree, Node, 4);
               end if;
            end;
         end loop;

         return S.No_Node;
      end Discriminants_Of;

      ---------------------------
      -- Find_Routine_At --
      ---------------------------

      function Find_Routine_At (Part : S.Node_Id) return Natural is
      begin
         for Index in 1 .. Natural (Routines.Length) loop
            if not Routines.Element (Index).Is_Declared
              and then S."=" (Routines.Element (Index).Node, Part)
            then
               return Index;
            end if;
         end loop;

         return 0;
      end Find_Routine_At;

      -----------------
      -- Find_Task --
      -----------------

      function Find_Task (Named : String) return Natural is
      begin
         for Index in 1 .. Natural (Routines.Length) loop
            if Routines.Element (Index).Is_Task
              and then Routines.Element (Index).Is_Declared
              and then Symbols.Fold
                         (S.Text (Tree,
                                  S.First (Tree,
                                           Routines.Element (Index).Node)))
                       = Symbols.Fold (Named)
            then
               return Routines.Element (Index).Ident;
            end if;
         end loop;

         return 0;
      end Find_Task;

      ------------------
      -- Is_Element --
      ------------------

      function Is_Element (Node : S.Node_Id) return Boolean is
      begin
         if S.Kind (Tree, Node) /= S.Node_Call then
            return False;
         end if;

         return Is_Array_Place (S.First (Tree, Node));
      end Is_Element;

      -------------------
      -- Is_Array_Slice --
      -------------------

      function Is_Array_Place (Node : S.Node_Id) return Boolean is
      begin
         if Ty.Shape (Sem.Type_Of (Analysis, Node)) /= Ty.Shape_Array then
            return False;
         end if;

         if S.Kind (Tree, Node) = S.Node_Name then
            return not Symbols.Is_Callable (Sem.Symbol_Of (Analysis, Node));
         end if;

         return S.Kind (Tree, Node) = S.Node_Call
           and then Is_Array_Place (S.First (Tree, Node));
      end Is_Array_Place;

      function Is_Array_Slice (Node : S.Node_Id) return Boolean is
      begin
         if S.Kind (Tree, Node) /= S.Node_Call then
            return False;
         end if;

         declare
            Prefix    : constant S.Node_Id := S.First (Tree, Node);
            Arguments : constant S.Node_Id := S.Second (Tree, Node);
         begin
            return Is_Array_Place (Prefix)
              and then S.Child_Count (Tree, Arguments) = 1
              and then S.Kind (Tree, S.First (Tree, Arguments))
                       = S.Node_Range;
         end;
      end Is_Array_Slice;

      ------------------
      -- Is_Text_Part --
      ------------------

      function Is_Text_Part (Node : S.Node_Id) return Boolean is
      begin
         if S.Kind (Tree, Node) /= S.Node_Call then
            return False;
         end if;

         declare
            Prefix : constant S.Node_Id := S.First (Tree, Node);
         begin
            --  A part of a part, as deep as it is written. Each level is a
            --  part of the level outside it, and the whole chain is a part of
            --  the variable it bottoms out at -- which is the one thing here
            --  that has a place to store to.
            if Is_Text_Part (Prefix) then
               return True;
            end if;

            return S.Kind (Tree, Prefix) = S.Node_Name
              and then Ty.Shape (Sem.Type_Of (Analysis, Prefix))
                       = Ty.Shape_String
              and then not Symbols.Is_Callable
                             (Sem.Symbol_Of (Analysis, Prefix));
         end;
      end Is_Text_Part;

      ------------------
      -- Emit_Place --
      ------------------

      procedure Emit_Place (Node : S.Node_Id; Ok : out Boolean) is
      begin
         Ok := True;

         case S.Kind (Tree, Node) is
            when S.Node_Name =>
               declare
                  Sym : constant Symbols.Symbol :=
                    Sem.Symbol_Of (Analysis, Node);
                  Of_Type : constant Ty.Type_Kind :=
                    Sem.Type_Of (Analysis, Node);
               begin
                  if Symbols.Is_Nothing (Sym) then
                     Refuse (Node, Adash.Messages.Msg_Lower_Unresolved_Name);
                     Ok := False;
                     return;
                  end if;

                  Emit_Address (Place_Of (Sym));

                  --  A run whose length is known says how long it is, so that
                  --  a callee given it can ask. Not for an open type: what a
                  --  parameter of one holds was told by its caller, and saying
                  --  anything here would overwrite that with a length this
                  --  build does not have.
                  if Ty.Shape (Of_Type) = Ty.Shape_Array
                    and then not Ty.Is_Open (Of_Type)
                  then
                     Emit_1
                       (VM.Run_Of,
                        VM.Whole_Number
                          (Sem.Part_Count (Analysis, Of_Type)));
                  end if;
               end;

            when S.Node_Selected =>
               declare
                  Prefix  : constant S.Node_Id := S.First (Tree, Node);
                  Of_Type : constant Ty.Type_Kind :=
                    Sem.Type_Of (Analysis, Prefix);
                  Which   : constant Natural :=
                    Sem.Part_At
                      (Analysis, Of_Type,
                       S.Text (Tree, S.Second (Tree, Node)));
               begin
                  --  `P.X` where P is a package is a name: what a package
                  --  holds was declared beside it, and the analyser resolved
                  --  the whole spelling to one symbol.
                  if Ty.Shape (Of_Type) /= Ty.Shape_Record then
                     declare
                        Sym : constant Symbols.Symbol :=
                          Sem.Symbol_Of (Analysis, Node);
                     begin
                        if Symbols.Is_Nothing (Sym) then
                           Refuse (Node,
                                   Adash.Messages.Msg_Lower_Unresolved_Name);
                           Ok := False;
                           return;
                        end if;

                        Emit_Address (Place_Of (Sym));
                        return;
                     end;
                  end if;

                  if Which = 0 then
                     Refuse (Node, Adash.Messages.Msg_Lower_This_Expression);
                     Ok := False;
                     return;
                  end if;

                  Emit_Place (Prefix, Ok);

                  if not Ok then
                     return;
                  end if;

                  Emit_1
                    (VM.Offset_Place,
                     VM.Whole_Number
                       (Sem.Part_Offset (Analysis, Of_Type, Which)));
               end;

            when S.Node_Call =>
               declare
                  Prefix  : constant S.Node_Id := S.First (Tree, Node);
                  Of_Type : constant Ty.Type_Kind :=
                    Sem.Type_Of (Analysis, Prefix);

                  Held : constant Ty.Type_Kind :=
                    Sem.Part_Type (Analysis, Of_Type, 1);

                  First : constant Long_Long_Integer :=
                    Sem.First_Index (Analysis, Of_Type);
                  --  How many elements the prefix holds, from its width
                  --  rather than from what its identity was declared with: a
                  --  slice shares the array's identity and is shorter, and
                  --  asking the declaration would check an index against the
                  --  whole array.
                  Last  : constant Long_Long_Integer :=
                    First
                    + Long_Long_Integer (Ty.Width (Of_Type))
                      / Long_Long_Integer (Ty.Width (Held)) - 1;
               begin
                  --  A slice is where the run starts, moved along to the first
                  --  element it covers. The distance is known here because the
                  --  analyser required the ends to be -- one implementation of
                  --  that question, asked twice.
                  if Is_Array_Slice (Node) then
                     declare
                        Low : Long_Long_Integer;
                     begin
                        if not Sem.Static_Choice
                                 (Analysis, Tree,
                                  S.First
                                    (Tree,
                                     S.First (Tree, S.Second (Tree, Node))),
                                  Low)
                        then
                           Refuse (Node,
                                   Adash.Messages.Msg_Lower_This_Expression);
                           Ok := False;
                           return;
                        end if;

                        Emit_Place (Prefix, Ok);

                        if not Ok then
                           return;
                        end if;

                        --  How far a run of the caller's length reaches is
                        --  not known here, so the far end is checked where the
                        --  program runs. The near end and the count are known,
                        --  as they are for every slice.
                        if Ty.Is_Open (Of_Type) then
                           declare
                              High : Long_Long_Integer;
                           begin
                              if not Sem.Static_Choice
                                       (Analysis, Tree,
                                        S.Second
                                          (Tree,
                                           S.First
                                             (Tree, S.Second (Tree, Node))),
                                        High)
                              then
                                 Refuse
                                   (Node,
                                    Adash.Messages.Msg_Lower_This_Expression);
                                 Ok := False;
                                 return;
                              end if;

                              Emit_2
                                (VM.Run_Covers,
                                 Code.Text_Literal (Ty.Name (Of_Type)),
                                 VM.Whole_Number (High));
                           end;
                        end if;

                        if Low /= First then
                           Emit_1
                             (VM.Offset_Place,
                              VM.Whole_Number
                                (Long_Long_Integer (Ty.Width (Held))
                                 * (Low - First)));
                        end if;

                        Emit_1
                          (VM.Run_Of,
                           VM.Whole_Number
                             (Sem.Part_Count
                                (Analysis, Sem.Type_Of (Analysis, Node))));
                     end;

                     return;
                  end if;

                  if not Is_Element (Node) then
                     Refuse (Node, Adash.Messages.Msg_Lower_This_Expression);
                     Ok := False;
                     return;
                  end if;

                  Emit_Place (Prefix, Ok);

                  if not Ok then
                     return;
                  end if;

                  Emit_Expression
                    (S.Child (Tree, S.Second (Tree, Node), 1));

                  --  An open type has no bounds to check against, so the
                  --  run itself is asked: the length travelled with the place
                  --  from whoever knew it.
                  if Ty.Is_Open (Of_Type) then
                     Emit_2
                       (VM.Element_Place_Counted,
                        Code.Text_Literal (Ty.Name (Of_Type)),
                        VM.Whole_Number (Ty.Width (Held)));
                     return;
                  end if;

                  --  The bounds and the type's name travel together, so an
                  --  index outside the array can say which array and what was
                  --  asked for. Operand is how wide one element is, which is
                  --  what turns a position into a distance.
                  Emit_2
                    (VM.Element_Place,
                     Code.Bound_Entry
                       (VM.Whole_Number (First), VM.Whole_Number (Last),
                        Code.Text_Literal (Ty.Name (Of_Type))),
                     VM.Whole_Number (Ty.Width (Held)));
               end;

            when others =>
               Refuse (Node, Adash.Messages.Msg_Lower_This_Expression);
               Ok := False;
         end case;
      end Emit_Place;

      -----------------------
      -- Collect_Routines --
      -----------------------

      --  Where an enumeration's literal names live in the program's text table.
      type Enumeration is record
         Id    : Natural := 0;
         Base  : Positive := 1;
         Count : Natural := 0;
      end record;

      package Enumeration_Vectors is new Ada.Containers.Vectors
        (Index_Type => Positive, Element_Type => Enumeration);

      Enumerations : Enumeration_Vectors.Vector;

      --  Where one enumeration's names start, and how many there are.
      --
      --  @param Of_Type The enumeration.
      --  @param Base Its first name's index, when this returns True.
      --  @param Count How many it has.
      --  @return True when the type is one this program declared.
      function Names_Of
        (Of_Type : Ty.Type_Kind;
         Base    : out Positive;
         Count   : out Natural) return Boolean;

      procedure Collect_Types is
         procedure Collect_From (Sequence : S.Node_Id);

         procedure Collect_From (Sequence : S.Node_Id) is
         begin
            for Index in 1 .. S.Child_Count (Tree, Sequence) loop
               declare
                  Item : constant S.Node_Id := S.Child (Tree, Sequence, Index);
               begin
                  case S.Kind (Tree, Item) is
                     when S.Node_Type_Declaration =>
                        declare
                           Literals : constant S.Node_Id :=
                             S.Second (Tree, Item);
                           Count : constant Natural :=
                             S.Child_Count (Tree, Literals);
                           First : Positive := 1;
                        begin
                           for Position in 1 .. Count loop
                              declare
                                 Where : constant Positive :=
                                   Code.Text_Literal
                                     (S.Text
                                        (Tree,
                                         S.Child (Tree, Literals, Position)));
                              begin
                                 if Position = 1 then
                                    First := Where;
                                 end if;
                              end;
                           end loop;

                           --  The type's own name on the end of the run. A
                           --  diagnostic about a position outside the type has
                           --  to name the type, and putting it here costs no
                           --  second table and no second lookup.
                           declare
                              Ignored : constant Positive :=
                                Code.Text_Literal
                                  (S.Text (Tree, S.First (Tree, Item)));
                              pragma Unreferenced (Ignored);
                           begin
                              null;
                           end;

                           Enumerations.Append
                             (Enumeration'
                                (Id    =>
                                   Ty.Identity
                                     (Sem.Type_Of
                                        (Analysis, S.First (Tree, Item))),
                                 Base  => First,
                                 Count => Count));
                        end;

                     when S.Node_Subprogram_Declaration =>
                        Collect_From (S.Child (Tree, Item, 4));
                        Collect_From (S.Child (Tree, Item, 5));

                     when S.Node_Package_Declaration
                        | S.Node_Package_Body
                        | S.Node_Protected_Declaration
                        | S.Node_Protected_Body =>
                        Collect_From (S.Second (Tree, Item));

                     when S.Node_Instantiation =>
                        --  The copy the analyser made. It carries a type
                        --  declaration only if the generic did, and this walk
                        --  is what interns an enumeration's literal names.
                        Collect_From (Sem.Expansion_Of (Analysis, Item));

                     when S.Node_Block =>
                        Collect_From (S.First (Tree, Item));
                        Collect_From (S.Second (Tree, Item));

                     when others =>
                        null;
                  end case;
               end;
            end loop;
         end Collect_From;
      begin
         Collect_From (S.Root (Tree));
      end Collect_Types;

      function Names_Of
        (Of_Type : Ty.Type_Kind;
         Base    : out Positive;
         Count   : out Natural) return Boolean
      is
         Wanted : constant Natural := Ty.Identity (Of_Type);
      begin
         Base  := 1;
         Count := 0;

         for Index in 1 .. Natural (Enumerations.Length) loop
            if Enumerations.Element (Index).Id = Wanted then
               Base  := Enumerations.Element (Index).Base;
               Count := Enumerations.Element (Index).Count;
               return True;
            end if;
         end loop;

         return False;
      end Names_Of;

      procedure Collect_Routines is
         --  Which protected object the walk is inside, or zero. Numbered in
         --  the order they are met, which is all a lock needs: what matters is
         --  that two operations of one object have the same number and two of
         --  different objects do not.
         Inside_Object : Natural := 0;

         --  What a task may be and still call the object being walked. Read
         --  where the object is met, because every operation collected inside
         --  it takes the same one.
         Inside_Ceiling : Natural := VM.Highest_Priority;
         Objects_Seen  : Natural := 0;

         procedure Collect_From (Sequence : S.Node_Id; Level : Positive);

         --  One body, wherever it stands: written in a sequence, held in a
         --  package, or copied out of a generic by an instantiation.
         procedure Collect_Body (Item : S.Node_Id; Level : Positive);

         --  Every routine a *statement* introduces, wherever it stands.
         --
         --  A separate walk because the bodies Collect_From looks for are
         --  declarations and stand in declarative parts, while a statement may
         --  stand anywhere one may -- inside a loop, inside an `if`, inside a
         --  handler. Two of them introduce a routine: `select ... then abort`,
         --  whose abortable part runs on a strand of its own, and a block,
         --  whose declarations may hold bodies.
         --
         --  What it has to agree with Collect_From about is the level, and
         --  the rule is the same one written once: a routine's level is the
         --  frame that encloses it, and the constructs that make a frame are
         --  a subprogram body, a task body, an entry body and an abortable
         --  part. Nothing else -- a package makes no frame, a protected body
         --  makes none, and neither does a block.
         procedure Collect_Statements (Node : S.Node_Id; Level : Positive);

         --  Depth first, parents before children, which is what lets a body be
         --  emitted before anything nested in it: the outer frame's slots are
         --  in place by the time an inner body asks where one of them lives.
         procedure Collect_From (Sequence : S.Node_Id; Level : Positive) is
         begin
            for Index in 1 .. S.Child_Count (Tree, Sequence) loop
               declare
                  Item : constant S.Node_Id := S.Child (Tree, Sequence, Index);
               begin
                  if S.Kind (Tree, Item) = S.Node_Object_Declaration
                    and then Ty.Is_Protected
                               (Sem.Type_Of (Analysis, Item))
                  then
                     --  An object of a protected type: the copy the analyser
                     --  made of the type's declaration and body. It is not
                     --  under the root -- it was grafted onto the tree rather
                     --  than parsed into it -- so nothing would reach it by
                     --  walking the sequence.
                     declare
                        Copy : constant S.Node_Id :=
                          Sem.Expansion_Of (Analysis, Item);
                     begin
                        if S.Is_Present (Copy) then
                           Collect_From (Copy, Level);
                        end if;
                     end;

                  elsif S.Kind (Tree, Item) = S.Node_Instantiation then
                     --  The copy the analyser made of the generic's body. It
                     --  is not under the root -- it was grafted onto the tree
                     --  rather than parsed into it -- so nothing would reach
                     --  it by walking the sequence.
                     declare
                        Copy : constant S.Node_Id :=
                          Sem.Expansion_Of (Analysis, Item);
                     begin
                        if S.Is_Present (Copy) then
                           Collect_Body (Copy, Level);
                        end if;
                     end;

                  elsif S.Kind (Tree, Item) = S.Node_Entry
                    and then S.Is_Present (S.Third (Tree, Item))
                  then
                     --  An entry body: a routine belonging to the object it
                     --  stands in, and the one kind of routine whose body
                     --  begins by waiting. It takes one argument when it is a
                     --  family's -- which member it is running for, which is
                     --  what lets one body serve them all and a barrier ask
                     --  which it is.
                     Routines.Append
                       (Routine'
                          (Node        => Item,
                           Declared_At =>
                             Symbols.Extent
                               (Sem.Symbol_Of
                                  (Analysis, S.First (Tree, Item))).First,
                           Named       =>
                             Ada.Strings.Unbounded.To_Unbounded_String
                               (Symbols.Name
                                  (Sem.Symbol_Of
                                     (Analysis, S.First (Tree, Item)))),
                           Level       => Level,
                           Ident       => Code.Declare_Routine,
                           Block       => 1,
                           Params      =>
                             (if S.Child_Count (Tree, Item) >= 6
                                and then S.Is_Present (S.Child (Tree, Item, 6))
                              then 1 else 0),
                           Modes       => [others => Symbols.Mode_In],
                           Entry_At    => 0,
                           Frame       =>
                             (if S.Child_Count (Tree, Item) >= 6
                                and then S.Is_Present (S.Child (Tree, Item, 6))
                              then 1 else 0),
                           Returns     => Ty.Type_None,
                           Is_Task     => False,
                           Is_Declared => True,
                           Guarded_By  => Inside_Object,
                           Ceiling     => Inside_Ceiling));

                     Collect_From (S.Third (Tree, Item), Level + 1);

                  elsif S.Kind (Tree, Item) = S.Node_Task_Body then
                     --  A task body is a routine like any other, and the one
                     --  thing that makes it a task is what starts it: an
                     --  instruction rather than a call, and a strand of its
                     --  own to run on.
                     --
                     --  Its discriminants are its parameters. They arrive the
                     --  same way and sit in the same slots, which is what
                     --  makes them nothing new: what a task takes at
                     --  elaboration is what a subprogram takes at a call.
                     declare
                        Given : constant S.Node_Id :=
                          Discriminants_Of
                            (S.Text (Tree, S.First (Tree, Item)));
                        Count : constant Natural :=
                          S.Child_Count (Tree, Given);
                     begin
                        Routines.Append
                          (Routine'
                             (Node        => Item,
                              Declared_At =>
                                Symbols.Extent
                                  (Sem.Symbol_Of
                                     (Analysis, S.First (Tree, Item))).First,
                              Named       =>
                                Ada.Strings.Unbounded.To_Unbounded_String
                                  (Symbols.Name
                                     (Sem.Symbol_Of
                                        (Analysis, S.First (Tree, Item)))),
                              Level       => Level,
                              Ident       => Code.Declare_Routine,
                              Block       => 1,
                              Params      => Count,
                              Modes       => [others => Symbols.Mode_In],
                              Entry_At    => 0,
                              Frame       => Count,
                              Returns     => Ty.Type_None,
                              Is_Task     => True,
                              Is_Declared => True,
                              Guarded_By  => 0,
                              Ceiling     => VM.Highest_Priority));
                     end;

                     Collect_From (S.Second (Tree, Item), Level + 1);

                  elsif S.Kind (Tree, Item) in S.Node_Protected_Declaration
                                             | S.Node_Protected_Body
                    and then Is_Guarded_Template (Item)
                  then
                     --  A protected type, whose operations belong to its
                     --  objects. Each object collects a copy of its own.
                     null;

                  elsif S.Kind (Tree, Item) in S.Node_Package_Declaration
                                             | S.Node_Package_Body
                                             | S.Node_Protected_Declaration
                                             | S.Node_Protected_Body
                  then
                     if S.Kind (Tree, Item) = S.Node_Protected_Body then
                        Objects_Seen  := Objects_Seen + 1;
                        Inside_Object := Objects_Seen;

                        --  What a task may be and still call it, read where
                        --  the object is met: every operation collected inside
                        --  takes the same one.
                        Inside_Ceiling :=
                          Priority_Of (S.Text (Tree, S.First (Tree, Item)));
                     end if;

                     --  A package holds declarations, and a body it holds is
                     --  a body like any other: at the same level, because a
                     --  package makes no frame. Without this a subprogram
                     --  declared in a package body was never emitted, and
                     --  every call to one refused itself.
                     Collect_From (S.Second (Tree, Item), Level);
                     Inside_Object := 0;

                  elsif S.Kind (Tree, Item) = S.Node_Subprogram_Declaration
                    and then S.Is_Present (S.Child (Tree, Item, 5))
                  then
                     --  A body. A specification has no statements and nothing
                     --  to emit; the name it introduced belongs to whichever
                     --  body completes it.
                     Collect_Body (Item, Level);
                  end if;
               end;
            end loop;
         end Collect_From;

         procedure Collect_Body (Item : S.Node_Id; Level : Positive) is
            Named   : constant S.Node_Id := S.Child (Tree, Item, 1);
            Whose   : constant Symbols.Symbol :=
              Sem.Symbol_Of (Analysis, Named);
            Formals : constant S.Node_Id := S.Child (Tree, Item, 2);
            Result  : constant S.Node_Id := S.Child (Tree, Item, 3);
            Count   : constant Natural := S.Child_Count (Tree, Formals);
            Modes   : Symbols.Parameter_Modes := [others => Symbols.Mode_In];
         begin
            if Symbols.Is_Nothing (Whose)
              or else Symbols.Kind (Whose) = Symbols.Symbol_Generic
            then
               --  A generic's own body, which is a template rather than
               --  something to run: its names mean nothing until an
               --  instantiation binds the formals, so nothing in it carries a
               --  conclusion. Collecting it produced a routine that every call
               --  matched by accident, because a body with no symbol has no
               --  position to be told apart by.
               return;
            end if;

               for Position in 1 .. Count loop
                  declare
                     Spelt : constant String :=
                       S.Text (Tree,
                               S.Child (Tree, Formals, Position));
                  begin
                     Modes (Position) :=
                       (if Spelt = "out" then Symbols.Mode_Out
                        elsif Spelt = "in out"
                        then Symbols.Mode_In_Out
                        else Symbols.Mode_In);
                  end;
               end loop;

               Routines.Append
                 (Routine'
                    (Node        => Item,
                     --  Taken from the symbol rather than from this
                     --  node, because a body completing an earlier
                     --  specification keeps that specification's
                     --  symbol -- and calls written before the body
                     --  resolved to it.
                     Declared_At =>
                       Symbols.Extent
                         (Sem.Symbol_Of (Analysis, Named)).First,
                     Named       =>
                       Ada.Strings.Unbounded.To_Unbounded_String
                         (Symbols.Name (Sem.Symbol_Of (Analysis, Named))),
                     Level       => Level,
                     --  The machine's own index for it, handed out
                     --  before anything is emitted so that a call
                     --  written above a body can name it.
                     Ident       => Code.Declare_Routine,
                     Block       => 1,
                     Params      => Count,
                     Modes       => Modes,
                     Entry_At    => 0,
                     Frame       => Count,
                     Returns     =>
                       (if S.Is_Present (Result)
                        then Sem.Type_Of (Analysis, Named)
                        else Ty.Type_None),

                     --  A protected operation, when it stands in one: the
                     --  lowering wraps its body in taking and giving back the
                     --  lock, which is what makes it mutually exclusive.
                     Is_Task     => False,
                     Is_Declared => True,
                     Guarded_By  => Inside_Object,
                     Ceiling     => Inside_Ceiling));

               --  The subprogram, then one entry per parameter.

               --  Anything it declares in turn. Both parts, because
               --  this parser accepts a declaration wherever a
               --  statement may stand and a body missed here would
               --  simply never be emitted.
               Collect_From (S.Child (Tree, Item, 4), Level + 1);
               Collect_From (S.Child (Tree, Item, 5), Level + 1);
         end Collect_Body;
         procedure Collect_Statements (Node : S.Node_Id; Level : Positive) is
            Deeper : Positive := Level;
         begin
            if not S.Is_Present (Node) then
               return;
            end if;

            if S.Kind (Tree, Node) = S.Node_Block then
               --  What a block declares, at the level around it: a block makes
               --  no frame, so what it holds lives in the frame it stands in.
               --  Its own statements are walked below like anything else's,
               --  which is what finds a block inside a block.
               --
               --  Both parts, because this language accepts a declaration
               --  wherever a statement may stand and a body written among the
               --  statements is a body all the same.
               Collect_From (S.First (Tree, Node), Level);
               Collect_From (S.Second (Tree, Node), Level);
            end if;

            if S.Kind (Tree, Node) = S.Node_Accept then
               --  An accept body, for the same reason and at the same level:
               --  it makes no frame either, and what it holds is the caller's
               --  arguments rather than a frame of its own.
               Collect_From (S.Third (Tree, Node), Level);
            end if;

            if S.Kind (Tree, Node) = S.Node_Then_Abort then
               --  The abortable part is a routine, started rather than
               --  called: it runs beside the trigger, which is the whole of
               --  what makes abandoning it possible on a machine that changes
               --  strand at defined points rather than pre-empting.
               --
               --  Keyed by where the select was written. It has no symbol --
               --  nothing names it -- and the select's own offset is a
               --  keyword's, so no declaration can share it.
               Routines.Append
                 (Routine'
                    (Node        => S.Third (Tree, Node),
                     Declared_At => S.Extent (Tree, Node).First,
                     Named       =>
                       Ada.Strings.Unbounded.Null_Unbounded_String,
                     Level       => Level,
                     Ident       => Code.Declare_Routine,
                     Block       => 1,
                     Params      => 0,
                     Modes       => [others => Symbols.Mode_In],
                     Entry_At    => 0,
                     Frame       => 0,
                     Returns     => Ty.Type_None,
                     Is_Task     => True,
                     Is_Declared => False,
                     Guarded_By  => 0,
                     Ceiling     => VM.Highest_Priority));

               Collect_Statements (S.First (Tree, Node), Level);
               Collect_Statements (S.Second (Tree, Node), Level);
               Collect_Statements (S.Third (Tree, Node), Level + 1);
               return;
            end if;

            if S.Kind (Tree, Node) in S.Node_Subprogram_Declaration
                                    | S.Node_Task_Body
                                    | S.Node_Entry
            then
               Deeper := Level + 1;
            end if;

            for Index in 1 .. S.Child_Count (Tree, Node) loop
               Collect_Statements (S.Child (Tree, Node, Index), Deeper);
            end loop;
         end Collect_Statements;
      begin
         Collect_From (S.Root (Tree), 1);
         Collect_Statements (S.Root (Tree), 1);
      end Collect_Routines;

      ------------------
      -- Emit_Bodies --
      ------------------

      procedure Emit_Bodies is
      begin
         for Index in 1 .. Natural (Routines.Length) loop
            exit when not Lowerable;

            declare
               Item    : Routine := Routines.Element (Index);

               --  A task body and an entry have no formals: a task takes
               --  nothing because nothing calls it, and an entry here is a
               --  barrier and a body.
               Formals : constant S.Node_Id :=
                 (if S.Kind (Tree, Item.Node) = S.Node_Task_Body
                  then Discriminants_Of
                         (S.Text (Tree, S.First (Tree, Item.Node)))
                  elsif S.Kind (Tree, Item.Node) in S.Node_Entry
                                                  | S.Node_Sequence
                  then S.No_Node else S.Child (Tree, Item.Node, 2));

               --  The submission's own allocator, put back afterwards. A
               --  subprogram's locals are in its own frame and start again
               --  from the fixed area; carrying on from where the submission
               --  had got to would leave the frame full of holes and size it
               --  by an accident of what was declared elsewhere.
               Outer_Address : constant Natural := Next_Address;
            begin
               Item.Entry_At   := Here;
               Current_Routine := Index;
               Current_Level   := Item.Level + 1;
               Next_Address    :=
                 Item.Params;

               --  Parameters occupy the frame immediately after the fixed
               --  area, in the order they were written. The machine put them
               --  there; this only has to agree about where.
               --
               --  An entry body of a family has one that was not written in a
               --  formal list: which member it is running for, named by the
               --  `for` that stands where a formal list would.
               for Position in 1 .. Item.Params loop
                  declare
                     Named : constant S.Node_Id :=
                       (if S.Kind (Tree, Item.Node) = S.Node_Entry
                        then S.Child (Tree, Item.Node, 6)
                        else S.First (Tree, S.Child (Tree, Formals, Position)));
                     Sym   : constant Symbols.Symbol :=
                       Sem.Symbol_Of (Analysis, Named);
                  begin
                     Slots.Append
                       (Slot'(Declared_At  => Symbols.Extent (Sym).First,
                              Named        =>
                                Ada.Strings.Unbounded.To_Unbounded_String
                                  (Symbols.Name (Sym)),
                              Address      => Position - 1,
                              Level        => Item.Level + 1,
                              By_Reference =>
                                Item.Modes (Position) /= Symbols.Mode_In
                                --  A composite always, whatever its mode: it
                                --  is a run of slots and a parameter is one
                                --  slot, so what travels is where the run
                                --  starts. Ada passes a record by reference
                                --  too, and the rule that an `in` parameter
                                --  may not be assigned to is the analyser's
                                --  rather than the machine's.
                                or else Ty.Is_Composite
                                          (Symbols.Of_Type (Sym))));
                  end;
               end loop;

               --  A body answers for what went wrong the same way a block
               --  does, and is wrapped the same way. Ada lets a body carry
               --  handlers and it is where most of them belong: a function
               --  that answers for its own failure is the shape a caller can
               --  use without knowing it might.
               declare
                  Handlers : constant S.Node_Id :=
                    (if S.Kind (Tree, Item.Node) in S.Node_Entry
                                                  | S.Node_Sequence
                     then S.No_Node
                     elsif S.Kind (Tree, Item.Node) = S.Node_Task_Body
                     then S.Third (Tree, Item.Node)
                     else S.Child (Tree, Item.Node, 6));
                  Guarded  : constant Boolean :=
                    S.Is_Present (Handlers)
                      and then S.Child_Count (Tree, Handlers) > 0;

                  Catching : Natural := 0;
                  Leaving  : Natural := 0;
               begin
                  if Guarded then
                     Catching := Here;
                     Emit_1 (VM.Push_Handler, 0);
                  end if;

                  --  A protected operation runs holding the lock. The machine
                  --  does not change strand while one is held, which is the
                  --  whole of what makes it mutually exclusive rather than an
                  --  optimisation on top of something else.
                  if Item.Guarded_By /= 0 then
                     --  With the ceiling it was declared with, so that a task
                     --  above it is told rather than let in.
                     Emit_2 (VM.Enter_Protected, Item.Ceiling,
                             VM.Whole_Number (Item.Guarded_By));
                  end if;

                  if S.Kind (Tree, Item.Node) = S.Node_Sequence then
                     --  An abortable part is statements and nothing else: no
                     --  name, no profile, no declarative part of its own.
                     Emit_Sequence (Item.Node);
                  elsif S.Kind (Tree, Item.Node) = S.Node_Task_Body then
                     --  A task body holds statements rather than a
                     --  declarative part and statements.
                     Emit_Sequence (S.Second (Tree, Item.Node));
                  elsif S.Kind (Tree, Item.Node) = S.Node_Entry then
                     --  Which entry this is, said before the barrier is asked:
                     --  a strand set aside by one is queued at the object, and
                     --  what tells two entries of one object apart is this.
                     --
                     --  For a family it is which *member*, which the body was
                     --  given as its one argument -- so the number is the
                     --  family's own plus how far into it that argument is.
                     declare
                        Of_Entry : constant Symbols.Symbol :=
                          Sem.Symbol_Of (Analysis, S.First (Tree, Item.Node));
                        Member : constant S.Node_Id :=
                          (if S.Child_Count (Tree, Item.Node) >= 6
                           then S.Child (Tree, Item.Node, 6) else S.No_Node);
                     begin
                        Emit_1 (VM.Push_Whole,
                                VM.Whole_Number (Entry_Number (Of_Entry)));

                        if Emit_Family_Member (Of_Entry, Member) then
                           Emit (VM.Add_Whole);
                        end if;

                        Emit_2 (VM.Waiting_At, 0,
                                VM.Whole_Number (Item.Guarded_By));
                     end;

                     --  Its barrier first, which the machine waits on: a
                     --  strand that finds it closed is set aside and the
                     --  barrier is tested again when the object is next left.
                     if S.Is_Present (S.Second (Tree, Item.Node)) then
                        declare
                           Asking : constant Natural := Here;
                        begin
                           Emit_Expression (S.Second (Tree, Item.Node));
                           Emit_2 (VM.Await_Barrier, Item.Guarded_By,
                                   VM.Whole_Number (Asking));
                        end;
                     end if;

                     Emit_Sequence (S.Third (Tree, Item.Node));
                  else
                     Emit_Sequence (S.Child (Tree, Item.Node, 4));
                     Emit_Sequence (S.Child (Tree, Item.Node, 5));
                  end if;

                  if Item.Guarded_By /= 0 then
                     Emit_1 (VM.Leave_Protected,
                             VM.Whole_Number (Item.Guarded_By));
                  end if;

                  if Guarded then
                     Emit (VM.Pop_Handler);
                     Leaving := Here;
                     Emit_1 (VM.Jump, 0);

                     Code.Patch (Catching, Here);

                     --  Where the unwind lands, and before the handler runs:
                     --  an exception on its way out completes what it leaves,
                     --  and completing a master waits for its dependents. The
                     --  unwind itself cannot wait -- it is reached from inside
                     --  whatever raised -- so the wait stands here, which is
                     --  the same moment from the program's point of view.
                     Emit (VM.Await_Abandoned);

                     Emit_Handlers (Handlers);
                     Code.Patch (Leaving, Here);
                  end if;
               end;

               --  Falling off the end. A procedure returns; a function that
               --  gets here never executed a return, and the machine raises
               --  rather than handing back whatever the frame happened to
               --  hold.
               if Item.Is_Task then
                  --  A task ends rather than returns: there is no caller to
                  --  return to, and the strand it ran on is finished with.
                  Emit (VM.End_Task);
               elsif Item.Returns = Ty.Type_None then
                  Emit (VM.Return_Plain);
               else
                  Emit (VM.Raise_No_Return);
               end if;

               Item.Frame := Next_Address;
               Routines.Replace_Element (Index, Item);

               --  Now that the body has been laid down, the machine is told
               --  where it starts, how big its frame is and how deep it is
               --  declared. All three are known only here: the frame size is
               --  what the emission of the body allocated.
               Code.Define_Routine
                 (Which      => Item.Ident,
                  Entry_At   => Item.Entry_At,
                  Frame      => Item.Frame,
                  Parameters => Item.Params,
                  Level      => Item.Level);

               Current_Routine := 0;
               Current_Level   := 1;
               Next_Address    := Outer_Address;
               pragma Assert (Item.Level + 1 <= Adash.Language.Max_Nesting);
            end;
         end loop;
      end Emit_Bodies;

      -----------------------
      -- Emit_Routine_Call --
      -----------------------

      procedure Emit_Routine_Call
        (Node      : S.Node_Id;
         Which     : Positive;
         Arguments : S.Node_Id;
         Callee    : Symbols.Symbol)
      is
         Called : constant Routine := Routines.Element (Which);

         --  Where each parameter's value comes from. Computed here rather than
         --  carried from semantics: it depends only on the call and the
         --  callee, both of which are to hand, and a copy kept beside the tree
         --  would be a second thing to keep true.
         Slots   : Sem.Argument_Map := [others => S.No_Node];
         At_Node : S.Node_Id := S.No_Node;
         Spot    : Natural := 0;

         Fitted : constant Sem.Match_Outcome :=
           (if S.Is_Present (Arguments)
            then Sem.Match_Arguments
                   (Tree, Arguments, Callee, Slots, At_Node, Spot)
            else Sem.Matched);
      begin
         --  A member of a protected entry family: what stands in the
         --  parentheses is which member rather than what the entry takes, and
         --  the body was given it as its one argument.
         if Symbols.Kind (Callee) = Symbols.Symbol_Entry
           and then Symbols.Of_Type (Callee) /= Ty.Type_None
         then
            declare
               Member : constant Boolean :=
                 Emit_Family_Member
                   (Callee,
                    (if S.Is_Present (Arguments)
                       and then S.Child_Count (Tree, Arguments) = 1
                     then S.Child (Tree, Arguments, 1) else S.No_Node));
            begin
               if not Member then
                  Refuse (Node, Adash.Messages.Msg_Lower_Call_Wrong_Count);
                  return;
               end if;
            end;

            Emit_2 (VM.Call, Called.Level, VM.Whole_Number (Called.Ident));
            return;
         end if;

         if not S.Is_Present (Arguments) then
            Slots := [others => S.No_Node];
         end if;

         if Sem."/=" (Fitted, Sem.Matched) then
            --  Semantics checks all of this and would have refused the
            --  program, so reaching here means the two passes disagree.
            Refuse (Node, Adash.Messages.Msg_Lower_Call_Wrong_Count);
            return;
         end if;

         for Index in 1 .. Called.Params loop
            exit when not Lowerable;

            if not S.Is_Present (Slots (Index)) then
               --  Left to its default. Emitted here rather than at the
               --  declaration, because a default is evaluated at each call --
               --  and it is a literal, so emitting it is exactly what the
               --  lowering would do had it been written at the call site.
               Emit_Default (Node, Callee, Index);

            elsif Ty.Is_Composite (Symbols.Parameter_Type (Callee, Index)) then
               --  Where the run starts, not what is in it. A composite
               --  parameter is one slot holding a place, whichever mode it
               --  was declared with.
               declare
                  Of_Type : constant Ty.Type_Kind :=
                    Symbols.Parameter_Type (Callee, Index);
                  Ok : Boolean;
               begin
                  if S.Kind (Tree, Slots (Index)) = S.Node_Aggregate then
                     --  An aggregate written as an argument has nowhere of
                     --  its own to be. It is built in a run of this frame's
                     --  slots and the call is handed where that run starts,
                     --  which is what every composite argument is.
                     declare
                        Base : constant Natural := New_Temporary;
                     begin
                        for Extra in 2 .. Ty.Width (Of_Type) loop
                           Reserve_Temporary;
                        end loop;

                        Emit_Aggregate
                          (Slots (Index), Of_Type,
                           S.First (Tree, Slots (Index)),
                           At_Address => Base);

                        Emit_2 (VM.Address, 0, VM.Whole_Number (Base));
                     end;

                  else
                     Emit_Place (Slots (Index), Ok);

                     if not Ok then
                        return;
                     end if;
                  end if;
               end;

            elsif Called.Modes (Index) = Symbols.Mode_In then
               Emit_Expression (Slots (Index));
               Emit_Bounds_Check (Symbols.Parameter_Type (Callee, Index));
            else
               --  The caller's own variable, by address. Semantics has already
               --  established that the actual is one; this refuses rather than
               --  pushing a value the callee would write through as though it
               --  were a pointer.
               declare
                  Actual : constant S.Node_Id := Slots (Index);
                  Sym    : constant Symbols.Symbol :=
                    Sem.Symbol_Of (Analysis, Actual);
               begin
                  if Symbols.Is_Nothing (Sym)
                    or else not Symbols.Is_Assignable (Sym)
                  then
                     Refuse (Node, Adash.Messages.Msg_Lower_Write_Back_Not_Variable);
                     return;
                  end if;

                  Emit_Address (Place_Of (Sym));
               end;
            end if;
         end loop;

         --  The arguments are on the stack, in order. The machine makes the
         --  frame, takes them into it, and finds the frame this one was
         --  declared in by walking static links -- so there is nothing here to
         --  say about record sizes, and nothing to put back afterwards.
         Emit_1 (VM.Call, VM.Whole_Number (Called.Ident));

         --  What was written back, checked against what the caller's variable
         --  says it can hold. The callee wrote through an address and knows
         --  nothing about the constraint on the other end; Ada checks on the
         --  copy back, and this is where that is.
         for Index in 1 .. Called.Params loop
            exit when not Lowerable;

            if Called.Modes (Index) /= Symbols.Mode_In
              and then S.Is_Present (Slots (Index))
            then
               declare
                  Sym : constant Symbols.Symbol :=
                    Sem.Symbol_Of (Analysis, Slots (Index));
               begin
                  if not Symbols.Is_Nothing (Sym)
                    and then Ty.Has_Bounds (Symbols.Of_Type (Sym))
                  then
                     Emit_Value (Place_Of (Sym));
                     Emit_Bounds_Check (Symbols.Of_Type (Sym));
                     Emit (VM.Discard);
                  end if;
               end;
            end if;
         end loop;
      end Emit_Routine_Call;

      --------------------------
      -- Emit_Bounds_Check --
      --------------------------

      procedure Emit_Bounds_Check (Of_Type : Ty.Type_Kind) is
         Base  : Positive := 1;
         Count : Natural := 0;

         Named : constant Boolean :=
           Ty.Shape (Of_Type) = Ty.Shape_Enumeration
             and then Names_Of (Of_Type, Base, Count);
      begin
         if not Ty.Has_Bounds (Of_Type) then
            return;
         end if;

         Emit_2
           (VM.Check_In_Range,
            Code.Bound_Entry
              (VM.Whole_Number (Ty.Low_Bound (Of_Type)),
               VM.Whole_Number (Ty.High_Bound (Of_Type)),
               (if Named then Base else 0)),
            VM.Whole_Number (Code.Text_Literal (Ty.Name (Of_Type))));
      end Emit_Bounds_Check;

      -------------------
      -- Emit_Default --
      -------------------

      procedure Emit_Default
        (Node   : S.Node_Id;
         Callee : Symbols.Symbol;
         Index  : Positive)
      is
         Text : constant String := Symbols.Default_Text (Callee, Index);
         Of_Type : constant Ty.Type_Kind :=
           Symbols.Parameter_Type (Callee, Index);
      begin
         case Ty.Shape (Of_Type) is
            when Ty.Shape_Integer =>
               Emit_1 (VM.Push_Whole, VM.Whole_Number'Value (Text));

            when Ty.Shape_Float =>
               Emit_1 (VM.Push_Real,
                       VM.Whole_Number
                         (Code.Real_Literal (VM.Real'Value (Text))));

            when Ty.Shape_Boolean =>
               Emit_1 (VM.Push_Truth, (if Text = "true" then 1 else 0));

            when Ty.Shape_Character =>
               Emit_1
                 (VM.Push_Letter,
                  Character'Pos
                    (if Text'Length > 0 then Text (Text'First)
                     else Character'Val (0)));

            when Ty.Shape_String =>
               Emit_Text (Text);

            when Ty.Shape_Enumeration =>
               --  Its position, which is what an enumeration value is on the
               --  stack and what a literal written at the call site would
               --  have pushed. Semantics carried the position rather than the
               --  name for exactly that reason.
               Emit_1 (VM.Push_Whole, VM.Whole_Number'Value (Text));

            when Ty.Shape_None | Ty.Shape_Record | Ty.Shape_Array
               | Ty.Shape_Task | Ty.Shape_Protected | Ty.Shape_Task_Id =>
               --  A composite default would be an aggregate, which is not a
               --  literal: what it holds is expressions, and two aggregates
               --  with the same text can mean different values at different
               --  points of a program. Semantics refuses one before this.
               Refuse (Node, Adash.Messages.Msg_Lower_Argument_Of_Type,
                       [1 => Adash.Messages.Named
                               ("type", Ty.Name (Of_Type))]);
         end case;

      exception
         when Constraint_Error =>
            --  A default semantics accepted and this cannot spell back. It
            --  would be a defect here rather than in the program, and a
            --  refusal names it instead of pushing something nobody wrote.
            Refuse (Node, Adash.Messages.Msg_Lower_Float_Literal);
      end Emit_Default;

      ------------
      -- Refuse --
      ------------

      procedure Refuse
        (Node      : S.Node_Id;
         Construct : Adash.Messages.Message_Id;
         Given     : Adash.Messages.Argument_List :=
           Adash.Messages.No_Arguments)
      is
      begin
         if not Lowerable then
            --  One report. After the first refusal the emitter is producing
            --  nothing anyway, and a second complaint about the same program
            --  would say the same thing about a different node.
            return;
         end if;

         Lowerable := False;

         Report.Emit
           (D.Make
              (Message   => Adash.Errors.Message (Adash.Errors.Error_Not_Lowerable),
               Level     => D.Severity_Error,
               Of_Kind   => D.Category_Runtime,
               Raised_By => D.Owner_Language,
               Origin    => Origin,
               Extent    => S.Extent (Tree, Node),

               --  Named rather than rendered. What could not be lowered is a
               --  phrase a user reads, and this package has no catalog: it
               --  says which message and what fills it, and the frontend turns
               --  the pair into a sentence.
               Quoted    => Construct,
               Fills     => "construct",
               Quoted_Arguments => Given));
      end Refuse;

      ----------------
      -- Place_Of --
      ----------------

      function Place_Of (Sym : Symbols.Symbol) return Place is
         Declared : constant Adash.Source.Byte_Offset :=
           Symbols.Extent (Sym).First;
         Called   : constant String := Symbols.Name (Sym);
      begin
         for Current of Slots loop
            if Current.Declared_At = Declared
              and then Ada.Strings.Unbounded.To_String (Current.Named)
                       = Called
            then
               return (Level        => Current.Level,
                       Address      => Current.Address,
                       By_Reference => Current.By_Reference);
            end if;
         end loop;

         --  Not yet allocated. Reaching here for a name means the declaration
         --  was not lowered first, which the walk order prevents; allocating
         --  now keeps the emitter total rather than raising inside a code
         --  generator.
         Slots.Append
           (Slot'(Declared_At  => Declared,
                  Named        =>
                    Ada.Strings.Unbounded.To_Unbounded_String (Called),
                  Address      => Next_Address,
                  Level        => Current_Level,
                  By_Reference => False));

         --  A composite takes as many slots as it has parts. That is the whole
         --  of how a record and an array work here: a value is a run, and
         --  reaching into it is arithmetic on where the run starts.
         Next_Address := Next_Address + Ty.Width (Symbols.Of_Type (Sym));

         return (Level        => Current_Level,
                 Address      =>
                   Next_Address - Ty.Width (Symbols.Of_Type (Sym)),
                 By_Reference => False);
      end Place_Of;

      --  Whether a type has a representation this lowering can emit.
      function Is_Emittable (Of_Type : Ty.Type_Kind) return Boolean
      is (Of_Type = Ty.Type_Integer
          or else Of_Type = Ty.Type_Boolean
          or else Of_Type = Ty.Type_Character
          or else Of_Type = Ty.Type_String
          or else Of_Type = Ty.Type_Float
          --  An enumeration is a whole number on the stack, like a Character:
          --  what it is is its position.
          or else Ty.Shape (Of_Type) = Ty.Shape_Enumeration
          --  A composite is a run of slots rather than a value on the stack,
          --  and everything that moves one moves the run.
          or else Ty.Is_Composite (Of_Type)
          --  A task is one cell, holding which strand runs it, and an
          --  identity is that cell kept somewhere else.
          or else Ty.Is_Task (Of_Type)
          or else Of_Type = Ty.Type_Task_Id);

      --  Whether a value of this type occupies a stack cell whose variant part
      --  matters. An Integer, a Boolean and a Character are the discrete field
      --  alone; a String and a Float each live in a field of their own, and
      --  storing one with the discrete store would copy the tag and leave the
      --  value behind.
      function Is_Whole_Cell (Of_Type : Ty.Type_Kind) return Boolean
      is (Of_Type = Ty.Type_String or else Of_Type = Ty.Type_Float);

      procedure Emit_Store (Of_Type : Ty.Type_Kind) is
         pragma Unreferenced (Of_Type);
      begin
         --  One store for every type. The machine carries the type with the
         --  value, so nothing here has to say which kind of cell is being
         --  written -- which is what the two stores were for.
         Emit (VM.Store);
      end Emit_Store;

      --  Put a string literal's text into the program's own table and emit the
      --  push that names it.
      --
      --  An instruction has no room for a string, so the text is interned and
      --  the instruction carries an index. The table belongs to the program
      --  being built and is emptied with it, which is what makes it safe to
      --  append here without clearing anything first.

      ----------------
      -- Emit_Text --
      ----------------

      --  The text is kept whole in the program rather than spliced into a
      --  table of every string it holds: a literal is one thing with one
      --  index, and there is no length to get wrong and no table to overflow.
      procedure Emit_Text (Item : String) is
      begin
         Emit_1 (VM.Push_Text, VM.Whole_Number (Code.Text_Literal (Item)));
      end Emit_Text;

      ---------------------
      -- Emit_Expression --
      ---------------------

      procedure Emit_Expression (Node : S.Node_Id) is
         Of_Type : constant Ty.Type_Kind := Sem.Type_Of (Analysis, Node);
      begin
         if not Lowerable then
            return;
         end if;

         case S.Kind (Tree, Node) is
            when S.Node_Integer_Literal =>
               Emit_1
                 (VM.Push_Whole, VM.Whole_Number'Value (S.Text (Tree, Node)));

            when S.Node_Character_Literal =>
               declare
                  Text : constant String := S.Text (Tree, Node);
               begin
                  --  A Character is a discrete value on the stack, like an
                  --  Integer; its position in the type is what the machine
                  --  holds.
                  Emit_1
                    (VM.Push_Letter,
                     Character'Pos
                       (if Text'Length > 0 then Text (Text'First)
                        else Character'Val (0)));
               end;

            when S.Node_Real_Literal =>
               --  Interned into the compiler's float table, which is what
               --  holds the value: the instruction carries an index into it
               --  rather than the number, because an instruction has no room
               --  for one.
               begin
                  Emit_1
                    (VM.Push_Real, VM.Whole_Number (Code.Real_Literal (VM.Real'Value (S.Text (Tree, Node)))));
               exception
                  when Constraint_Error =>
                     --  A literal the host's float cannot hold. Refused rather
                     --  than rounded to infinity, which would run and be wrong.
                     Refuse (Node, Adash.Messages.Msg_Lower_Float_Literal);
               end;

            when S.Node_String_Literal =>
               Emit_Text (S.Text (Tree, Node));

            when S.Node_Name | S.Node_Selected =>
               declare
                  Sym : constant Symbols.Symbol := Sem.Symbol_Of (Analysis, Node);
               begin
                  --  A selection is here as well as a name, and it is here
                  --  *only* when it is one: `P.X` where P is a package is a
                  --  name with a dot in it, and the analyser resolved the
                  --  whole spelling to one symbol. A reach into a record is
                  --  the other reading, and it is handled above.
                  if S.Kind (Tree, Node) = S.Node_Selected
                    and then Ty.Shape (Sem.Type_Of (Analysis,
                                                    S.First (Tree, Node)))
                             = Ty.Shape_Record
                  then
                     declare
                        Ok : Boolean;
                     begin
                        Emit_Place (Node, Ok);

                        if Ok then
                           Emit (VM.Fetch);
                        end if;
                     end;

                     return;
                  end if;

                  if Symbols.Is_Nothing (Sym) then
                     Refuse (Node, Adash.Messages.Msg_Lower_Unresolved_Name);
                     return;
                  end if;

                  --  True and False are the predefined Boolean constants; they
                  --  have no storage, so they are pushed as the literals they
                  --  are rather than loaded from a slot that was never
                  --  allocated.
                  if Symbols.Kind (Sym) = Symbols.Symbol_Constant
                    and then Ty.Shape (Symbols.Of_Type (Sym)) = Ty.Shape_Boolean
                    and then (Symbols.Key (Sym) = "true"
                              or else Symbols.Key (Sym) = "false")
                  then
                     Emit_1
                       (VM.Push_Truth,
                        (if Symbols.Key (Sym) = "true" then 1 else 0));
                     return;
                  end if;

                  --  An enumeration literal is its position, and has no
                  --  storage: the declaration named the values, it did not
                  --  make room for them.
                  if Symbols.Kind (Sym) = Symbols.Symbol_Literal then
                     Emit_1
                       (VM.Push_Whole,
                        VM.Whole_Number (Symbols.Position (Sym)));
                     return;
                  end if;

                  if not Is_Emittable (Of_Type) then
                     Refuse (Node, Adash.Messages.Msg_Lower_Variable_Of_Type,
                             [1 => Adash.Messages.Named ("type", Ty.Name (Of_Type))]);
                     return;
                  end if;

                  --  A parameterless function written without parentheses,
                  --  which Ada allows and which reaches here as a plain name.
                  --  Reading it as a variable would allocate a slot nothing
                  --  ever writes.
                  if Symbols.Kind (Sym) = Symbols.Symbol_Function then
                     declare
                        Which : constant Natural := Find_Routine (Sym);
                        Known : Adash.Predefined.Entity_Id :=
                          Adash.Predefined.Entity_Boolean;
                        Is_Known : Boolean := False;
                     begin
                        --  A predefined one is answered by the shell. Written
                        --  without parentheses it arrives here rather than as
                        --  a call node, and refusing it would have made
                        --  `Status` unusable in the form Ada writes it.
                        Is_Known :=
                          Which = 0
                            and then Adash.Predefined.Find
                                       (Symbols.Name (Sym), Known);

                        if Which /= 0 then
                           Emit_Routine_Call (Node, Which, S.No_Node, Sym);
                        elsif Is_Known then
                           --  Some of these the machine answers itself, and it
                           --  answers them the same whether the program wrote
                           --  the parentheses or not: the clock is the
                           --  machine's, and asking the shell for it would be
                           --  a round trip to be told what is already here.
                           declare
                              Op : VM.Opcode;
                           begin
                              if Computed_Here (Known, Op) then
                                 Emit (Op);
                              else
                                 Emit_Ask
                                   (Node, Symbols.Name (Sym), S.No_Node,
                                    Adash.Predefined.Describe (Known).Of_Type);
                              end if;
                           end;
                        else
                           Refuse (Node, Adash.Messages.Msg_Lower_Call_To,
                                   [1 => Adash.Messages.Named
                                           ("name", Symbols.Name (Sym))]);
                        end if;
                     end;

                     return;
                  end if;

                  Emit_Value (Place_Of (Sym));
               end;

            when S.Node_Parenthesized =>
               Emit_Expression (S.First (Tree, Node));

            when S.Node_Unary_Operation =>
               Emit_Expression (S.First (Tree, Node));

               case S.Operator (Tree, Node) is
                  when S.Op_Plus =>
                     null;  --  Unary plus is the identity.

                  when S.Op_Minus =>
                     --  A Float lives in a different field of the cell, so
                     --  negating one with the integer instruction leaves the
                     --  value untouched and the program runs on with the wrong
                     --  number -- which is how `-2.25` printed as 2.25.
                     if Ty.Shape (Sem.Type_Of (Analysis, S.First (Tree, Node)))
                        = Ty.Shape_Float
                     then
                        Emit (VM.Negate_Real);
                     else
                        Emit (VM.Negate_Whole);
                     end if;

                  when S.Op_Not =>
                     Emit (VM.Not_Truth);

                  when S.Op_Abs =>
                     --  A standard function rather than an instruction of its
                     --  own, and one per type for the same reason as the
                     --  negation above: the value is in a different field of
                     --  the cell, so the integer form would take the absolute
                     --  value of a field the Float is not using and leave the
                     --  number untouched.
                     if Ty.Shape (Sem.Type_Of (Analysis, S.First (Tree, Node)))
                        = Ty.Shape_Float
                     then
                        Emit (VM.Absolute_Real);
                     else
                        Emit (VM.Absolute_Whole);
                     end if;

                  when others =>
                     Refuse (Node, Adash.Messages.Msg_Lower_This_Operator);
               end case;

            when S.Node_Aggregate =>
               --  An aggregate only ever appears where a composite is being
               --  built, and the two places that build one -- a declaration
               --  and an assignment -- emit its parts into the slots
               --  themselves. Reaching here means one was written where a
               --  value was wanted, which semantics refuses.
               Refuse (Node, Adash.Messages.Msg_Lower_This_Expression);

            when S.Node_Membership =>
               declare
                  Value : constant S.Node_Id := S.First (Tree, Node);
                  Of_Type : constant Ty.Type_Kind :=
                    Sem.Type_Of (Analysis, Value);

                  --  Two children is a type mark, `X in Small`, and the bounds
                  --  are then the type's own -- known here without evaluating
                  --  anything, which is why the type-mark form emits two
                  --  constants where the range form emits two expressions.
                  Marked : constant Boolean :=
                    S.Child_Count (Tree, Node) = 2;

                  Admits : constant Ty.Type_Kind :=
                    (if Marked
                     then Sem.Type_Of (Analysis, S.Second (Tree, Node))
                     else Ty.Type_None);

                  --  The value is kept, not evaluated twice. `F (X) in 1 .. 9`
                  --  calls F once in Ada, and a lowering that compared the
                  --  expression against each bound would call it twice and run
                  --  whatever else F does a second time.
                  Kept : constant Natural := New_Temporary;

                  --  One bound of the type a mark named. The same answer the
                  --  `for` loop over a named type needs, and for the same
                  --  reason: a subtype is bounded by what it admits, and an
                  --  unconstrained type by what its shape holds.
                  procedure Emit_Admitted (Lowest : Boolean);

                  procedure Emit_Admitted (Lowest : Boolean) is
                     Base  : Positive;
                     Count : Natural;
                  begin
                     if Ty.Has_Bounds (Admits) then
                        Emit_1
                          (VM.Push_Whole,
                           VM.Whole_Number
                             (if Lowest then Ty.Low_Bound (Admits)
                              else Ty.High_Bound (Admits)));
                        return;
                     end if;

                     case Ty.Shape (Admits) is
                        when Ty.Shape_Enumeration =>
                           if Names_Of (Admits, Base, Count) then
                              Emit_1
                                (VM.Push_Whole,
                                 (if Lowest then 0
                                  else VM.Whole_Number (Count - 1)));
                           end if;

                        when Ty.Shape_Boolean =>
                           Emit_1 (VM.Push_Whole, (if Lowest then 0 else 1));

                        when Ty.Shape_Character =>
                           Emit_1
                             (VM.Push_Whole, (if Lowest then 0 else 255));

                        when Ty.Shape_Integer =>
                           Emit_1
                             (VM.Push_Whole,
                              (if Lowest then VM.Whole_Number'First
                               else VM.Whole_Number'Last));

                        when others =>
                           Refuse
                             (Node,
                              Adash.Messages.Msg_Lower_Argument_Of_Type,
                              [1 => Adash.Messages.Named
                                      ("type", Ty.Name (Admits))]);
                     end case;
                  end Emit_Admitted;

                  --  Which comparison instruction the two bounds need.
                  procedure Emit_At_Least;
                  procedure Emit_At_Most;

                  procedure Emit_At_Least is
                  begin
                     if Ty.Shape (Of_Type) = Ty.Shape_Float then
                        Emit (VM.Greater_Equal_Real);
                     elsif Ty.Shape (Of_Type) = Ty.Shape_String then
                        Emit (VM.Greater_Equal_Text);
                     else
                        Emit (VM.Greater_Equal_Whole);
                     end if;
                  end Emit_At_Least;

                  procedure Emit_At_Most is
                  begin
                     if Ty.Shape (Of_Type) = Ty.Shape_Float then
                        Emit (VM.Less_Equal_Real);
                     elsif Ty.Shape (Of_Type) = Ty.Shape_String then
                        Emit (VM.Less_Equal_Text);
                     else
                        Emit (VM.Less_Equal_Whole);
                     end if;
                  end Emit_At_Most;
               begin
                  if not Is_Emittable (Of_Type) then
                     Refuse (Node, Adash.Messages.Msg_Lower_Argument_Of_Type,
                             [1 => Adash.Messages.Named
                                     ("type", Ty.Name (Of_Type))]);
                     return;
                  end if;

                  Emit_2 (VM.Address, 0, VM.Whole_Number (Kept));
                  Emit_Expression (Value);
                  Emit (VM.Store);

                  --  Both bounds, not short-circuited: Ada evaluates both, and
                  --  `and then` here would make a bound with a call in it run
                  --  or not depending on the value.
                  Emit_2 (VM.Load, 0, VM.Whole_Number (Kept));

                  if Marked then
                     Emit_Admitted (Lowest => True);
                  else
                     Emit_Expression (S.Second (Tree, Node));
                  end if;

                  Emit_At_Least;

                  Emit_2 (VM.Load, 0, VM.Whole_Number (Kept));

                  if Marked then
                     Emit_Admitted (Lowest => False);
                  else
                     Emit_Expression (S.Third (Tree, Node));
                  end if;

                  Emit_At_Most;

                  Emit (VM.And_Truth);

                  if S.Operator (Tree, Node) = S.Op_Not_In then
                     Emit (VM.Not_Truth);
                  end if;
               end;

            when S.Node_Binary_Operation =>
               declare
                  Op    : constant S.Operation := S.Operator (Tree, Node);
                  Left  : constant Ty.Type_Kind :=
                    Sem.Type_Of (Analysis, S.First (Tree, Node));
                  Right : constant Ty.Type_Kind :=
                    Sem.Type_Of (Analysis, S.Second (Tree, Node));
               begin
                  --  Short circuits are not two operands and an operator: the
                  --  right side must not run when the left decides the answer.
                  --  They are lowered as jumps below rather than here.
                  if Op = S.Op_And_Then or else Op = S.Op_Or_Else then
                     declare
                        Skip : Natural;
                     begin
                        Emit_Expression (S.First (Tree, Node));

                        --  Duplicate-free short circuit: test without popping,
                        --  and if the answer is already decided, jump past the
                        --  right operand leaving the left value as the result.
                        Skip := Here;

                        if Op = S.Op_And_Then then
                           Emit_1 (VM.Jump_If_False_Keeping, 0);
                        else
                           Emit_1 (VM.Jump_If_True_Keeping, 0);
                        end if;

                        --  The left value is only kept when the jump is taken;
                        --  on the fall-through it is replaced by the right.
                        Emit (VM.Discard);
                        Emit_Expression (S.Second (Tree, Node));

                        Code.Patch (Skip, Here);
                     end;

                     return;
                  end if;

                  --  Two composites, compared slot by slot. A composite has
                  --  no value on the stack, so what goes there is where each
                  --  run starts -- and comparing the first cell of each, which
                  --  is what an ordinary comparison would have done, called
                  --  two different records equal whenever their first
                  --  components matched.
                  if Ty.Is_Composite (Left) then
                     if Op not in S.Op_Equal | S.Op_Not_Equal then
                        Refuse (Node, Adash.Messages.Msg_Lower_This_Operator);
                        return;
                     end if;

                     declare
                        Ok : Boolean;
                     begin
                        Emit_Place (S.First (Tree, Node), Ok);

                        if Ok then
                           Emit_Place (S.Second (Tree, Node), Ok);
                        end if;

                        if not Ok then
                           return;
                        end if;
                     end;

                     Emit_1 (VM.Same_Block, VM.Whole_Number (Ty.Width (Left)));

                     if Op = S.Op_Not_Equal then
                        Emit (VM.Not_Truth);
                     end if;

                     return;
                  end if;

                  Emit_Expression (S.First (Tree, Node));
                  Emit_Expression (S.Second (Tree, Node));

                  if not Is_Emittable (Left) then
                     Refuse (Node, Adash.Messages.Msg_Lower_Arithmetic_On,
                             [1 => Adash.Messages.Named ("type", Ty.Name (Left))]);
                     return;
                  end if;

                  --  A String is a whole cell holding variable-length text,
                  --  so its comparisons are not the discrete ones. Emitting
                  --  k_EQL_Integer here would compare the numeric field of two
                  --  cells that do not use it, and answer confidently and
                  --  wrongly -- which is worse than refusing.
                  if Ty.Shape (Left) = Ty.Shape_Float then
                     --  Float has its own instruction for every operation:
                     --  the value lives in a different field of the cell, so
                     --  the integer instructions would read the one that is
                     --  not being used and answer confidently and wrongly.
                     case Op is
                        when S.Op_Add      =>
                           Emit (VM.Add_Real);
                        when S.Op_Subtract =>
                           Emit (VM.Subtract_Real);
                        when S.Op_Multiply =>
                           Emit (VM.Multiply_Real);
                        when S.Op_Divide   =>
                           Emit (VM.Divide_Real);
                        when S.Op_Power    =>
                           Emit (VM.Power_Real);

                        when S.Op_Equal =>
                           Emit (VM.Equal_Real);
                        when S.Op_Not_Equal =>
                           Emit (VM.Unequal_Real);
                        when S.Op_Less =>
                           Emit (VM.Less_Real);
                        when S.Op_Less_Equal =>
                           Emit (VM.Less_Equal_Real);
                        when S.Op_Greater =>
                           Emit (VM.Greater_Real);
                        when S.Op_Greater_Equal =>
                           Emit (VM.Greater_Equal_Real);

                        when others =>
                           --  mod and rem are not defined for a Float in Ada
                           --  either, so this refuses what Ada refuses.
                           Refuse (Node, Adash.Messages.Msg_Lower_Float_Operation);
                     end case;

                     return;
                  end if;

                  --  A String joined with a Character, either way round. The
                  --  operands are on the stack already and the machine has a
                  --  builtin per shape, so which one is chosen by what is on
                  --  each side rather than by the result.
                  if Op = S.Op_Concat
                    and then (Ty.Shape (Left) = Ty.Shape_Character
                              or else Ty.Shape (Right) = Ty.Shape_Character)
                  then
                     if Ty.Shape (Left) = Ty.Shape_String then
                        Emit (VM.Join_Text_Letter);
                     elsif Ty.Shape (Right) = Ty.Shape_String then
                        Emit (VM.Join_Letter_Text);
                     else
                        Refuse (Node, Adash.Messages.Msg_Lower_Joining_Letters);
                     end if;

                     return;
                  end if;

                  if Is_Whole_Cell (Left) then
                     case Op is
                        when S.Op_Equal =>
                           Emit (VM.Equal_Text);
                        when S.Op_Not_Equal =>
                           Emit (VM.Unequal_Text);
                        when S.Op_Less =>
                           Emit (VM.Less_Text);
                        when S.Op_Less_Equal =>
                           Emit (VM.Less_Equal_Text);
                        when S.Op_Greater =>
                           Emit (VM.Greater_Text);
                        when S.Op_Greater_Equal =>
                           Emit (VM.Greater_Equal_Text);
                        when S.Op_Concat =>
                           Emit (VM.Join_Text);
                        when others =>
                           Refuse (Node, Adash.Messages.Msg_Lower_String_Operation);
                     end case;

                     return;
                  end if;

                  case Op is
                     when S.Op_Add      => Emit (VM.Add_Whole);
                     when S.Op_Subtract => Emit (VM.Subtract_Whole);
                     when S.Op_Multiply => Emit (VM.Multiply_Whole);
                     when S.Op_Divide   => Emit (VM.Divide_Whole);
                     when S.Op_Mod      => Emit (VM.Modulo_Whole);
                     when S.Op_Rem      => Emit (VM.Remainder_Whole);
                     when S.Op_Power    => Emit (VM.Power_Whole);

                     when S.Op_Equal         => Emit (VM.Equal_Whole);
                     when S.Op_Not_Equal     => Emit (VM.Unequal_Whole);
                     when S.Op_Less          => Emit (VM.Less_Whole);
                     when S.Op_Less_Equal    => Emit (VM.Less_Equal_Whole);
                     when S.Op_Greater       => Emit (VM.Greater_Whole);
                     when S.Op_Greater_Equal => Emit (VM.Greater_Equal_Whole);

                     --  Said as themselves. These used to be arithmetic on
                     --  the 0 and 1 a Boolean was on the stack -- a product
                     --  for `and`, a sum compared against zero for `or` --
                     --  because the machine had no Boolean. This one does.
                     when S.Op_And =>
                        Emit (VM.And_Truth);

                     when S.Op_Or =>
                        Emit (VM.Or_Truth);

                     when S.Op_Xor =>
                        Emit (VM.Xor_Truth);

                     when S.Op_Concat =>
                        Refuse (Node, Adash.Messages.Msg_Lower_String_Concatenation);

                     when others =>
                        Refuse (Node, Adash.Messages.Msg_Lower_This_Operator);
                  end case;
               end;

            when S.Node_Call =>
               declare
                  Prefix : constant S.Node_Id := S.First (Tree, Node);

                  --  Semantics settled whether this is a call or a String
                  --  taken apart, and said so by the type it gave the node: a
                  --  Character for one position, a String for a range. Asking
                  --  the shape again here would be a second answer to a
                  --  question already answered.
                  --  A range where an argument would stand: no call takes
                  --  one, so what follows can only be a part.
                  Ranged : constant Boolean :=
                    S.Child_Count (Tree, S.Second (Tree, Node)) = 1
                      and then S.Kind
                                 (Tree,
                                  S.First (Tree, S.Second (Tree, Node)))
                               = S.Node_Range;

                  --  The two shapes semantics decided between, read back the
                  --  same way it decided them: a prefix that is itself a call
                  --  yields a value and cannot be one, a range cannot be an
                  --  argument, and a name that denotes something not callable
                  --  is a String being taken apart. Anything else -- a package
                  --  member among them -- is a call.
                  Sliced : constant Boolean :=
                    Ty.Shape (Sem.Type_Of (Analysis, Prefix)) = Ty.Shape_String
                      and then (S.Kind (Tree, Prefix) = S.Node_Call
                                or else Ranged
                                or else (S.Kind (Tree, Prefix) = S.Node_Name
                                         and then not Symbols.Is_Callable
                                                        (Sem.Symbol_Of
                                                           (Analysis,
                                                            Prefix))));

                  Which  : constant Natural :=
                    Find_Routine (Sem.Symbol_Of (Analysis, Prefix));

                  --  Written by Find below, and carrying an initial value
                  --  only so that GNAT does not warn it might be read unset --
                  --  which it cannot be, since every read is guarded by what
                  --  Find returned.
                  --
                  --  The two flags below are not tidiness. Written as one
                  --  condition -- `Find (..., Known) and then
                  --  Describe (Known).Sort = ...` -- GNAT propagates that
                  --  initial value *through* the out parameter and tests the
                  --  sort of Entity_Boolean rather than of what Find just
                  --  wrote, so the branch is never taken. Silencing the
                  --  warning is what causes it: drop the initialiser and the
                  --  same condition works and the warning returns. Splitting
                  --  the call from the test is immune to both.
                  Known : Adash.Predefined.Entity_Id :=
                    Adash.Predefined.Entity_Boolean;

                  Is_Known : Boolean := False;
                  Is_Func  : Boolean := False;
               begin
                  --  `Integer'Value ("42")` and `Integer'Image (N)`: the
                  --  machine has a builtin per type for each direction, and
                  --  the argument is the whole of the call.
                  if S.Kind (Tree, Prefix) = S.Node_Attribute then
                     declare
                        Of_Type : constant Ty.Type_Kind :=
                          Sem.Type_Of (Analysis, Prefix);
                        Asked   : constant String :=
                          Symbols.Fold
                            (S.Text (Tree, S.Second (Tree, Prefix)));
                        Item    : constant S.Node_Id :=
                          S.First (Tree, S.Second (Tree, Node));
                     begin
                        Emit_Expression (Item);

                        --  `'Pos` and `'Val` are one instruction each, and an
                        --  Integer needs neither: an Integer *is* its
                        --  position, so the value on the stack is already the
                        --  answer. `'Succ` and `'Pred` are the two with an
                        --  addition between them, which is what Ada defines
                        --  them as -- and going past the end raises inside the
                        --  Val rather than in a check written three times.
                        if Asked in "pos" | "val" | "succ" | "pred" then
                           if Asked in "pos" | "succ" | "pred" then
                              case Ty.Shape (Of_Type) is
                                 when Ty.Shape_Character =>
                                    Emit (VM.Position_Letter);

                                 when Ty.Shape_Boolean =>
                                    Emit (VM.Position_Truth);

                                 when others =>
                                    --  An Integer and an enumeration are both
                                    --  their own position already.
                                    null;
                              end case;
                           end if;

                           if Asked in "succ" | "pred" then
                              Emit_1 (VM.Push_Whole, 1);
                              Emit (if Asked = "succ" then VM.Add_Whole
                                    else VM.Subtract_Whole);
                           end if;

                           if Asked in "val" | "succ" | "pred" then
                              case Ty.Shape (Of_Type) is
                                 when Ty.Shape_Character =>
                                    Emit (VM.Letter_At_Position);

                                 when Ty.Shape_Boolean =>
                                    Emit (VM.Truth_At_Position);

                                 when Ty.Shape_Enumeration =>
                                    declare
                                       Base  : Positive;
                                       Count : Natural;
                                    begin
                                       if Names_Of (Of_Type, Base, Count) then
                                          Emit_2
                                            (VM.Enumeration_At_Position,
                                             Count, VM.Whole_Number (Base));
                                       end if;
                                    end;

                                 when others =>
                                    null;
                              end case;
                           end if;

                           return;
                        end if;

                        if Ty.Shape (Of_Type) = Ty.Shape_Enumeration
                          and then Asked in "image" | "value"
                        then
                           declare
                              Base  : Positive;
                              Count : Natural;
                           begin
                              if Names_Of (Of_Type, Base, Count) then
                                 Emit_2
                                   ((if Asked = "image" then VM.Image_Enumeration
                                     else VM.Value_Enumeration),
                                    Count, VM.Whole_Number (Base));
                              end if;
                           end;

                           return;
                        end if;

                        if Asked = "value" then
                           case Ty.Shape (Of_Type) is
                              when Ty.Shape_Integer =>
                                 Emit (VM.Value_Whole);

                              when Ty.Shape_Float =>
                                 Emit (VM.Value_Real);

                              when Ty.Shape_Boolean =>
                                 Emit (VM.Value_Truth);

                              when Ty.Shape_Character =>
                                 Emit (VM.Value_Letter);

                              when others =>
                                 Refuse (Node, Adash.Messages.Msg_Lower_Value_Of,
                                    [1 => Adash.Messages.Named
                                            ("type", Ty.Name (Of_Type))]);
                           end case;
                        else
                           case Ty.Shape (Of_Type) is
                              when Ty.Shape_Integer =>
                                 Emit (VM.Image_Whole);

                              when Ty.Shape_Float =>
                                 Emit (VM.Image_Real);

                              when Ty.Shape_Boolean =>
                                 Emit (VM.Image_Truth);

                              when Ty.Shape_Character =>
                                 Emit (VM.Image_Letter);

                              when others =>
                                 Refuse (Node,
                                         Adash.Messages.Msg_Lower_Image_Of,
                                         [1 => Adash.Messages.Named
                                                 ("type",
                                                  Ty.Name (Of_Type))]);
                           end case;
                        end if;
                     end;

                     return;
                  end if;

                  if Is_Element (Node) then
                     declare
                        Ok : Boolean;
                     begin
                        Emit_Place (Node, Ok);

                        if Ok then
                           Emit (VM.Fetch);
                        end if;
                     end;

                     return;
                  end if;

                  if Sliced then
                     --  The machine's own instructions do the work, index
                     --  checks and all: a position past the end raises there
                     --  rather than reading whatever was next in the frame.
                     declare
                        Only : constant S.Node_Id :=
                          S.First (Tree, S.Second (Tree, Node));
                     begin
                        Emit_Expression (Prefix);

                        if S.Kind (Tree, Only) = S.Node_Range then
                           Emit_Expression (S.First (Tree, Only));
                           Emit_Expression (S.Second (Tree, Only));
                           Emit (VM.Text_Slice);
                        else
                           Emit_Expression (Only);
                           Emit (VM.Text_Element);
                        end if;
                     end;

                     return;
                  end if;

                  --  A predefined function is answered by the shell rather
                  --  than by emitted code: the value comes back through the
                  --  stub's answer parameter and is pushed as this
                  --  expression's own.
                  Is_Known :=
                    Adash.Predefined.Find (S.Text (Tree, Prefix), Known);

                  Is_Func := Is_Known
                    and then Adash.Predefined."="
                               (Adash.Predefined.Describe (Known).Sort,
                                Adash.Predefined.Sort_Function);

                  if Which = 0 and then Is_Known and then Is_Func then
                     --  Some of these the machine answers itself -- searching
                     --  and shaping text is arithmetic on values it already
                     --  holds -- and the rest the shell answers. Asking the
                     --  shell for something the machine knows would be a
                     --  round trip for nothing.
                     declare
                        Op : VM.Opcode;
                     begin
                        if Computed_Here (Known, Op) then
                           declare
                              Given : constant S.Node_Id :=
                                S.Second (Tree, Node);
                              Names : Parameter_Names
                                (1 .. Adash.Predefined.Max_Parameters);
                           begin
                              for Index in Names'Range loop
                                 Names (Index) :=
                                   Ada.Strings.Unbounded.To_Unbounded_String
                                     (Adash.Messages.Value
                                        (Adash.Predefined.Describe (Known)
                                           .Parameters (Index).Name));
                              end loop;

                              for Position in 1 ..
                                S.Child_Count (Tree, Given)
                              loop
                                 exit when not Lowerable;
                                 Emit_Expression
                                   (Argument_For (Given, Position, Names));
                              end loop;

                              Emit (Op);
                           end;
                        else
                           Emit_Ask
                             (Node, S.Text (Tree, Prefix),
                              S.Second (Tree, Node),
                              Adash.Predefined.Describe (Known).Of_Type);
                        end if;
                     end;

                     return;
                  end if;

                  if Which = 0 then
                     Refuse (Node, Adash.Messages.Msg_Lower_Call_To,
                             [1 => Adash.Messages.Named
                                     ("name", S.Text (Tree, Prefix))]);
                     return;
                  end if;

                  if Ty.Shape (Routines.Element (Which).Returns) = Ty.Shape_None then
                     --  A procedure where a value is wanted. Semantics rejects
                     --  it; refusing here as well means the emitter never
                     --  produces a call whose result nothing pushed.
                     Refuse (Node, Adash.Messages.Msg_Lower_Procedure_As_Value);
                     return;
                  end if;

                  Emit_Routine_Call
                    (Node, Which, S.Second (Tree, Node),
                     Sem.Symbol_Of (Analysis, Prefix));
               end;

            when S.Node_Qualified =>
               --  The expression, and the check the type asks for. A
               --  qualified expression says which reading is meant and Ada
               --  applies the subtype's constraint to it, which is the only
               --  thing here that reaches the machine.
               Emit_Expression (S.Second (Tree, Node));
               Emit_Bounds_Check (Sem.Type_Of (Analysis, Node));

            when S.Node_Attribute =>
               declare
                  Prefix  : constant S.Node_Id := S.First (Tree, Node);
                  Of_Type : constant Ty.Type_Kind :=
                    Sem.Type_Of (Analysis, Prefix);

                  Asked : constant String :=
                    Symbols.Fold (S.Text (Tree, S.Second (Tree, Node)));
                  --  `Integer'First` is the type's own bound: a constant
                  --  this build knows, with nothing to evaluate. `S'First` is
                  --  a question about a value and is answered below. Which
                  --  one was written is settled by what the prefix denotes,
                  --  which semantics recorded rather than left to be guessed
                  --  from the spelling.
                  Names_A_Type : constant Boolean :=
                    S.Kind (Tree, Prefix) = S.Node_Name
                      and then Symbols."="
                                 (Symbols.Kind
                                    (Sem.Symbol_Of (Analysis, Prefix)),
                                  Symbols.Symbol_Type);
               begin
                  if Names_A_Type and then Asked in "first" | "last" then
                     declare
                        Lowest : constant Boolean := Asked = "first";
                     begin
                        --  A subtype's ends are its own. Asking the shape
                        --  instead answered with the base type's, so
                        --  `Percent'First` was Integer'First -- a number the
                        --  subtype refuses, handed back as its own first
                        --  value.
                        if Ty.Has_Bounds (Of_Type) then
                           Emit_1
                             (VM.Push_Whole,
                              VM.Whole_Number
                                (if Lowest then Ty.Low_Bound (Of_Type)
                                 else Ty.High_Bound (Of_Type)));
                           return;
                        end if;

                        case Ty.Shape (Of_Type) is
                           when Ty.Shape_Integer =>
                              Emit_1
                                (VM.Push_Whole,
                                 (if Lowest then VM.Whole_Number'First
                                  else VM.Whole_Number'Last));

                           when Ty.Shape_Character =>
                              Emit_1
                                (VM.Push_Letter,
                                 VM.Whole_Number
                                   (Character'Pos
                                      (if Lowest then Character'First
                                       else Character'Last)));

                           when Ty.Shape_Boolean =>
                              Emit_1
                                (VM.Push_Truth,
                                 (if Lowest then 0 else 1));

                           when Ty.Shape_Float =>
                              Emit_1
                                (VM.Push_Real,
                                 VM.Whole_Number
                                   (Code.Real_Literal
                                      (if Lowest then VM.Real'First
                                       else VM.Real'Last)));

                           when Ty.Shape_Enumeration =>
                              --  The first literal written, and the last. A
                              --  type with no literals cannot be declared, so
                              --  the count is at least one.
                              declare
                                 Base  : Positive;
                                 Count : Natural;
                              begin
                                 if Names_Of (Of_Type, Base, Count) then
                                    Emit_1
                                      (VM.Push_Whole,
                                       (if Lowest then 0
                                        else VM.Whole_Number (Count - 1)));
                                 end if;
                              end;

                           when others =>
                              Refuse
                                (Node,
                                 Adash.Messages.Msg_Lower_Argument_Of_Type,
                                 [1 => Adash.Messages.Named
                                         ("type", Ty.Name (Of_Type))]);
                        end case;
                     end;

                     return;
                  end if;

                  --  How many callers are queued at an entry. A question
                  --  about the entry rather than about a value, so nothing is
                  --  evaluated: which entry it is, and which object it belongs
                  --  to, are both settled when the program is built.
                  if Asked = "count" then
                     declare
                        --  `E'Count` names the entry; `E (I)'Count` names one
                        --  member of a family, and the head of that call is
                        --  the entry.
                        Head : constant S.Node_Id :=
                          (if S.Kind (Tree, Prefix) = S.Node_Call
                           then S.First (Tree, Prefix) else Prefix);
                        Member : constant S.Node_Id :=
                          (if S.Kind (Tree, Prefix) = S.Node_Call
                             and then S.Child_Count
                                        (Tree, S.Second (Tree, Prefix)) = 1
                           then S.Child (Tree, S.Second (Tree, Prefix), 1)
                           else S.No_Node);

                        Sym : constant Symbols.Symbol :=
                          Sem.Symbol_Of (Analysis, Head);
                        Which : constant Natural := Entry_Number (Sym);
                        Whose : constant Natural := Guarding_Object (Sym);
                     begin
                        if Which = 0 then
                           Refuse (Node,
                                   Adash.Messages.Msg_Lower_This_Statement);
                        else
                           --  Which entry, as a value: a member of a family is
                           --  the family's own number plus which member, and
                           --  which member is something the program computes.
                           Emit_1 (VM.Push_Whole, VM.Whole_Number (Which));

                           if Emit_Family_Member (Sym, Member) then
                              Emit (VM.Add_Whole);
                           end if;

                           Emit_2 (VM.Entry_Count, 0,
                                   VM.Whole_Number (Whose));
                        end if;
                     end;

                     return;
                  end if;

                  --  What a task can be asked about itself. Both are
                  --  questions about a strand rather than about a type, so
                  --  both are asked of the task's own value.
                  if (Ty.Is_Task (Of_Type)
                      or else Of_Type = Ty.Type_Task_Id)
                    and then Asked in "terminated" | "callable"
                  then
                     Emit_Expression (Prefix);
                     Emit ((if Asked = "terminated"
                            then VM.Task_Ended else VM.Task_Callable));
                     return;
                  end if;

                  if (Ty.Is_Task (Of_Type)
                      or else Of_Type = Ty.Type_Task_Id)
                    and then Asked = "execution_time"
                  then
                     Emit_Expression (Prefix);
                     Emit (VM.Execution_Time);
                     return;
                  end if;

                  --  The task itself, which is what its identity is here.
                  if Ty.Is_Task (Of_Type) and then Asked = "identity" then
                     Emit_Expression (Prefix);
                     return;
                  end if;

                  --  What it runs at *now*. Either a task's priority or a
                  --  protected object's ceiling may be changed while the
                  --  program runs, so this asks the machine rather than the
                  --  declaration -- which would be answering about the past.
                  if Asked = "priority" then
                     if Ty.Is_Task (Of_Type) then
                        Emit_Expression (Prefix);
                        Emit_2 (VM.Priority_Now, 0, 0);
                     else
                        Emit_2 (VM.Priority_Now, Object_Number (Prefix), 0);
                     end if;

                     return;
                  end if;

                  --  How much room, in slots. What a value takes was worked
                  --  out by the analyser, which is the pass that has been
                  --  through a protected body; what a *task* is given to run
                  --  in is the machine's, and this is the pass that may know
                  --  it.
                  if Asked in "size" | "storage_size" then
                     Emit_1
                       (VM.Push_Whole,
                        VM.Whole_Number
                          (if Asked = "storage_size"
                           then VM.Storage_Per_Task
                           else Sem.Slots_Asked_About (Analysis, Node)));
                     return;
                  end if;

                  --  What a declared array can be asked about itself. All
                  --  three are known when the program is built -- an array
                  --  here has a fixed length and a fixed first index -- so
                  --  each is one push and nothing is evaluated.
                  --  Unless the array is one whose values carry their own
                  --  length. Then `'First` is still one -- a value of an
                  --  unconstrained type begins at one here, as a String does
                  --  -- and the other two are asked of the run itself, which
                  --  is the only thing that knows.
                  if Ty.Is_Open (Of_Type)
                    and then Asked in "length" | "first" | "last"
                  then
                     if Asked = "first" then
                        Emit_1 (VM.Push_Whole, 1);
                        return;
                     end if;

                     declare
                        Ok : Boolean;
                     begin
                        Emit_Place (Prefix, Ok);

                        if not Ok then
                           return;
                        end if;
                     end;

                     Emit (VM.Extent_Of);
                     return;
                  end if;

                  if Ty.Shape (Of_Type) = Ty.Shape_Array
                    and then Asked in "length" | "first" | "last"
                  then
                     declare
                        Count : constant Natural :=
                          Sem.Part_Count (Analysis, Of_Type);
                        First : constant Long_Long_Integer :=
                          Sem.First_Index (Analysis, Of_Type);
                     begin
                        Emit_1
                          (VM.Push_Whole,
                           VM.Whole_Number
                             (case Asked (Asked'First) is
                                 when 'l' =>
                                   (if Asked = "length" then
                                       Long_Long_Integer (Count)
                                    else First + Long_Long_Integer (Count) - 1),
                                 when others => First));
                     end;

                     return;
                  end if;

                  --  What a String can be asked about itself. `'First` is one
                  --  because every String here begins at one -- there are no
                  --  other index ranges to have -- and `'Last` is the length
                  --  for the same reason, which is why neither needs its own
                  --  builtin.
                  if Asked in "length" | "last" then
                     Emit_Expression (Prefix);
                     Emit (VM.Text_Length);
                     return;
                  end if;

                  if Asked = "first" then
                     Emit_1 (VM.Push_Whole, 1);
                     return;
                  end if;

                  --  Semantics has established that this is 'Image and that
                  --  the prefix is a scalar; nothing else reaches here. The
                  --  value goes on the stack and one instruction replaces it
                  --  with its image, so there is no call and no frame.
                  Emit_Expression (Prefix);

                  case Ty.Shape (Of_Type) is
                     when Ty.Shape_Enumeration =>
                        declare
                           Base  : Positive;
                           Count : Natural;
                        begin
                           if Names_Of (Of_Type, Base, Count) then
                              Emit_2 (VM.Image_Enumeration, Count,
                                      VM.Whole_Number (Base));
                           end if;
                        end;

                     when Ty.Shape_Integer =>
                        Emit (VM.Image_Whole);

                     when Ty.Shape_Float =>
                        Emit (VM.Image_Real);

                     when Ty.Shape_Boolean =>
                        Emit (VM.Image_Truth);

                     when Ty.Shape_Character =>
                        Emit (VM.Image_Letter);

                     when others =>
                        Refuse (Node, Adash.Messages.Msg_Lower_Image_Of,
                                [1 => Adash.Messages.Named
                                        ("type", Ty.Name (Of_Type))]);
                  end case;
               end;

            when others =>
               Refuse (Node, Adash.Messages.Msg_Lower_This_Expression);
         end case;
      end Emit_Expression;

      -----------------------
      -- Emit_Builtin_Call --
      -----------------------

      --  A call to one of the predefined output procedures.
      --
      --  The value goes on the stack and one instruction writes it. There is
      --  no format to push and no count to get wrong: the machine carries the
      --  type with the value, so `Write` knows what it is looking at. That is
      --  the whole of the difference from the convention this replaced, where
      --  a console, a value and a per-type run of format defaults all had to be
      --  pushed in the right number or the stack came apart.
      ------------------------
      -- Emit_Command_Call --
      ------------------------

      procedure Emit_Command_Call
        (Node : S.Node_Id; Name : String; Arguments : S.Node_Id)
      is
         Given : constant Natural :=
           (if S.Is_Present (Arguments) then S.Child_Count (Tree, Arguments)
            else 0);
      begin
         if On_Command = null then
            --  The caller cannot run commands. Refused rather than skipped:
            --  quietly dropping the call would make the program mean something
            --  its author did not write.
            Refuse (Node, Adash.Messages.Msg_Lower_Call_In_Context,
                    [1 => Adash.Messages.Named ("name", Name)]);
            return;
         end if;

         if Given > Max_Command_Arguments then
            --  The stub is built for this many slots, and every one of them is
            --  pushed on every call. Refusing says so rather than passing the
            --  first few and losing the rest.
            Refuse (Node, Adash.Messages.Msg_Lower_Command_Arguments,
                    [1 => Adash.Messages.Named
                            ("count",
                             Ada.Strings.Fixed.Trim
                               (Natural'Image (Max_Command_Arguments),
                                Ada.Strings.Both))]);
            return;
         end if;

         --  The name, then the arguments, then the call. Each argument is one
         --  cell carrying its own type, so there is nothing here to say about
         --  which slot it travels in and no absent ones to pad with.
         Emit_Text (Name);

         declare
            --  A command's parameter names, asked of the one package the
            --  language may ask: `Adash.Commands` is above this one, and
            --  `Adash.Predefined` answers for a command as well as for its
            --  own entities precisely so that nothing here has to reach up.
            About : constant Adash.Predefined.Profile :=
              Adash.Predefined.Profile_Of (Name);
            Names : Parameter_Names (1 .. Adash.Predefined.Max_Parameters) :=
              [others => Ada.Strings.Unbounded.Null_Unbounded_String];
         begin
            if About.Known then
               for Index in Names'Range loop
                  Names (Index) :=
                    Ada.Strings.Unbounded.To_Unbounded_String
                      (Adash.Messages.Value (About.Types_Of (Index).Name));
               end loop;
            end if;

            for Position in 1 .. Given loop
               exit when not Lowerable;
               Emit_Argument
                 (Node, Argument_For (Arguments, Position, Names));
            end loop;
         end;

         if not Lowerable then
            return;
         end if;

         Emit_1 (VM.Call_Host, VM.Whole_Number (Given));

         --  A command produces no value, and every host call pushes one
         --  answer. Whether the session should end is the shell's own answer
         --  rather than a slot read afterwards: `quit` stops the program where
         --  it stands, which is what `quit (0); pwd;` has to mean.
         Emit (VM.Discard);
      end Emit_Command_Call;

      ----------------
      -- Emit_Ask --
      ----------------

      --  Ask the shell for something and leave the answer on the stack.
      --
      --  The same road a command call travels, with the answer coming back
      --  through a parameter passed by reference -- the only direction that
      --  works, because the record the call is given is popped when it
      --  returns.
      procedure Emit_Ask
        (Node      : S.Node_Id;
         Named     : String;
         Arguments : S.Node_Id;
         Yields    : Ty.Type_Kind)
      is
         pragma Unreferenced (Yields);

         Given : constant Natural :=
           (if S.Is_Present (Arguments) then S.Child_Count (Tree, Arguments)
            else 0);
      begin
         if On_Command = null then
            Refuse (Node, Adash.Messages.Msg_Lower_Call_In_Context,
                    [1 => Adash.Messages.Named ("name", Named)]);
            return;
         end if;

         --  What is being asked for travels as the name, and its arguments
         --  follow it. What the shell answers is what the machine pushes, so
         --  this expression's value lands where an expression's value goes: on
         --  the stack. There is no cell to reserve and no slot to read back,
         --  and nothing has to agree about which of them the answer went into.
         Emit_Text (Ask_Marker);
         Emit_Text (Named);

         declare
            Which : Adash.Predefined.Entity_Id;
            Found : constant Boolean := Adash.Predefined.Find (Named, Which);
            Names : Parameter_Names (1 .. Adash.Predefined.Max_Parameters) :=
              [others => Ada.Strings.Unbounded.Null_Unbounded_String];
         begin
            if Found then
               for Index in Names'Range loop
                  Names (Index) :=
                    Ada.Strings.Unbounded.To_Unbounded_String
                      (Adash.Messages.Value
                         (Adash.Predefined.Describe (Which)
                            .Parameters (Index).Name));
               end loop;
            end if;

            for Position in 1 .. Given loop
               exit when not Lowerable;
               Emit_Argument
                 (Node, Argument_For (Arguments, Position, Names));
            end loop;
         end;

         if not Lowerable then
            return;
         end if;

         Emit_1 (VM.Call_Host, VM.Whole_Number (Given + 1));
      end Emit_Ask;

      --------------------
      -- Emit_Argument --
      --------------------

      function Argument_For
        (Arguments : S.Node_Id;
         Position  : Positive;
         Names     : Parameter_Names) return S.Node_Id
      is
         Given : constant Natural :=
           (if S.Is_Present (Arguments) then S.Child_Count (Tree, Arguments)
            else 0);
      begin
         --  Named first: a list may mix the two, and Ada's rule is that
         --  everything after the first named one is named as well -- so a
         --  position that some argument names is that argument's, whatever
         --  stands at that index.
         for Index in 1 .. Given loop
            declare
               One : constant S.Node_Id := S.Child (Tree, Arguments, Index);
            begin
               if S.Kind (Tree, One) = S.Node_Named_Argument
                 and then Position <= Names'Last
                 and then Symbols.Fold (S.Text (Tree, S.First (Tree, One)))
                          = Symbols.Fold
                              (Ada.Strings.Unbounded.To_String
                                 (Names (Position)))
               then
                  return S.Second (Tree, One);
               end if;
            end;
         end loop;

         if Position <= Given
           and then S.Kind (Tree, S.Child (Tree, Arguments, Position))
                    /= S.Node_Named_Argument
         then
            return S.Child (Tree, Arguments, Position);
         end if;

         return S.No_Node;
      end Argument_For;

      procedure Emit_Argument (Node : S.Node_Id; Item : S.Node_Id) is
         Of_Type : constant Ty.Type_Kind := Sem.Type_Of (Analysis, Item);
      begin
         --  One cell, carrying its own type. What used to be here was a triple
         --  -- a kind, a number slot and a text slot -- because the record the
         --  machine took had one cell for each shape a value could have, and
         --  which one an argument travelled in had to be decided twice.
         if Is_Emittable (Of_Type) then
            Emit_Expression (Item);
         else
            Refuse (Node, Adash.Messages.Msg_Lower_Argument_Of_Type,
                       [1 => Adash.Messages.Named ("type", Ty.Name (Of_Type))]);
         end if;
      end Emit_Argument;

      ----------------------
      -- Emit_Handlers --
      ----------------------

      --  What a block does about what went wrong.
      --
      --  The machine arrives here having put back the frames and the operands
      --  the block started with, and having pushed what was raised: its name,
      --  then what it said. Both are kept in slots of this frame, because
      --  choosing among the handlers reads the name more than once and
      --  re-raising needs them both afterwards.
      --
      --  A handler that matches nothing raises again rather than swallowing:
      --  an exception nobody answered for must not be lost by having been
      --  looked at.
      procedure Emit_Handlers (Handlers : S.Node_Id) is
         --  What this handler caught, and what a `raise;` inside it raises
         --  again. Kept while its statements are lowered and put back after,
         --  so a handler inside a handler raises again what *it* caught.
         Outer_Named  : constant Natural := Caught_Named;
         Outer_Detail : constant Natural := Caught_Detail;

         Named  : constant Natural := New_Temporary;
         Detail : constant Natural := New_Temporary;
         Total  : constant Natural := S.Child_Count (Tree, Handlers);

         --  Where each handler jumps to when it is done.
         Leaving    : array (1 .. Natural'Max (Total, 1)) of Natural :=
           [others => 0];
         Departures : Natural := 0;
      begin
         --  Kept in the order the machine pushed them: the detail is on top.
         Emit_2 (VM.Address, 0, VM.Whole_Number (Detail));
         Emit (VM.Swap);
         Emit (VM.Store);
         Emit_2 (VM.Address, 0, VM.Whole_Number (Named));
         Emit (VM.Swap);
         Emit (VM.Store);

         for Index in 1 .. Total loop
            exit when not Lowerable;

            declare
               One    : constant S.Node_Id := S.Child (Tree, Handlers, Index);
               Listed : constant S.Node_Id := S.First (Tree, One);
               Count  : constant Natural := S.Child_Count (Tree, Listed);

               Catches : Boolean := False;
               Tested  : Natural := 0;
               Onward  : Natural := 0;
            begin
               for Position in 1 .. Count loop
                  declare
                     Which : constant S.Node_Id :=
                       S.Child (Tree, Listed, Position);
                  begin
                     if S.Kind (Tree, Which) = S.Node_Others then
                        --  Whatever is left, reached by falling past every
                        --  test above rather than by one of its own.
                        Catches := True;
                     else
                        Emit_2 (VM.Load, 0, VM.Whole_Number (Named));
                        Emit_Text (S.Text (Tree, Which));
                        Emit (VM.Equal_Text);
                        Tested := Tested + 1;

                        if Tested > 1 then
                           Emit (VM.Or_Truth);
                        end if;
                     end if;
                  end;
               end loop;

               if not Catches then
                  Onward := Here;
                  Emit_1 (VM.Jump_If_False, 0);
               end if;

               Caught_Named  := Named;
               Caught_Detail := Detail;
               Emit_Sequence (S.Second (Tree, One));
               Caught_Named  := Outer_Named;
               Caught_Detail := Outer_Detail;

               Departures := Departures + 1;
               Leaving (Departures) := Here;
               Emit_1 (VM.Jump, 0);

               if not Catches then
                  Code.Patch (Onward, Here);
               end if;
            end;
         end loop;

         --  Nothing answered for it. Raised again, with what it came with, so
         --  a handler further out still sees it.
         Emit_2 (VM.Load, 0, VM.Whole_Number (Named));
         Emit_2 (VM.Load, 0, VM.Whole_Number (Detail));
         Emit (VM.Raise_Again);

         for Index in 1 .. Departures loop
            Code.Patch (Leaving (Index), Here);
         end loop;
      end Emit_Handlers;

      ----------------------
      -- Emit_Survivors --
      ----------------------

      --  Hand every top-level variable's value back before the program ends.
      --
      --  This is the only way a value crosses out of the machine: the frame it
      --  lives in is gone once the run returns. So the program reports its own
      --  variables, on the road a command call already travels.
      --
      --  Emitted after the statements and before the halt, so it runs when the
      --  program runs to its end. A program stopped early -- by `quit`, by
      --  `return`, by an exception -- never reaches it, and its variables do
      --  not survive. That is the honest outcome: what a half-run program left
      --  in a variable is not a value anyone chose.
      procedure Emit_Survivors is
         --  How the declaration reads when it is written out again: the type,
         --  and `constant` when it was one, so a constant does not come back
         --  assignable.
         --  The definition rather than the name for an anonymous type: a
         --  name is bounded and a definition is not, so the name may have
         --  been cut to fit and what is written out has to be readable again.
         function Written_As (Sym : Symbols.Symbol; Of_Type : Ty.Type_Kind)
                              return String
         is ((if Symbols.Kind (Sym) = Symbols.Symbol_Constant
              then "constant " else "")
             & (if Sem.As_Written (Analysis, Of_Type) /= ""
                then Sem.As_Written (Analysis, Of_Type)
                else Ty.Name (Of_Type)));

         --  One part of a composite, as the text this language reads back.
         --  A Character comes quoted, a Boolean comes as TRUE, and a String
         --  comes as a literal rather than as its contents -- it is going
         --  inside something larger either way.
         procedure Emit_Part_Image (Holds : Ty.Type_Kind; Named : S.Node_Id);

         --  A variable whose value cannot be written as one expression:
         --  it has none yet, or only some of its parts do. What is carried
         --  is the text the next submission is given -- the declaration, and
         --  an assignment for each part that holds something -- told as two
         --  things rather than three, which is how the host tells the two
         --  forms apart.
         --
         --  A part that holds nothing is written as nothing at all. There is
         --  no text for a value nobody wrote, and inventing one would hand
         --  the next submission a value this one never had.
         procedure Carry_As_Written
           (Sym     : Symbols.Symbol;
            Named   : S.Node_Id;
            Of_Type : Ty.Type_Kind);

         procedure Emit_Part_Image (Holds : Ty.Type_Kind; Named : S.Node_Id) is
         begin
            case Ty.Shape (Holds) is
               when Ty.Shape_Integer =>
                  Emit (VM.Image_Whole);

               when Ty.Shape_Float =>
                  Emit (VM.Image_Real);

               when Ty.Shape_Boolean =>
                  Emit (VM.Image_Truth);

               when Ty.Shape_Character =>
                  Emit (VM.Image_Letter);

               when Ty.Shape_String =>
                  Emit (VM.Quote_Text);

               when Ty.Shape_Enumeration =>
                  declare
                     Base  : Positive;
                     Count : Natural;
                  begin
                     if Names_Of (Holds, Base, Count) then
                        Emit_2 (VM.Image_Enumeration, Count,
                                VM.Whole_Number (Base));
                     end if;
                  end;

               when others =>
                  Refuse
                    (Named,
                     Adash.Messages.Msg_Lower_Writing_Type,
                     [1 => Adash.Messages.Named ("type", Ty.Name (Holds))]);
            end case;
         end Emit_Part_Image;

         procedure Carry_As_Written
           (Sym     : Symbols.Symbol;
            Named   : S.Node_Id;
            Of_Type : Ty.Type_Kind)
         is
            Name : constant String := Symbols.Name (Sym);
         begin
            Emit_Text (Keep_Marker);
            Emit_Text (Name);
            Emit_Text (Name & " : " & Written_As (Sym, Of_Type) & ";");

            if not Ty.Is_Composite (Of_Type) then
               Emit_1 (VM.Call_Host, 2);
               Emit (VM.Discard);
               return;
            end if;

            for Part in 1 .. Sem.Part_Count (Analysis, Of_Type) loop
               exit when not Lowerable;

               declare
                  Holds : constant Ty.Type_Kind :=
                    Sem.Part_Type (Analysis, Of_Type, Part);

                  Called : constant String :=
                    Sem.Part_Name (Analysis, Of_Type, Part);

                  --  Where the part is written: a record's component by name,
                  --  an array's element by the index it answers to, which is
                  --  where the array begins plus how far along this part is.
                  Reached : constant String :=
                    (if Called = ""
                     then " ("
                          & Ada.Strings.Fixed.Trim
                              (Long_Long_Integer'Image
                                 (Sem.First_Index (Analysis, Of_Type)
                                  + Long_Long_Integer (Part) - 1),
                               Ada.Strings.Both)
                          & ")"
                     else "." & Called);

                  Offset : constant VM.Whole_Number :=
                    VM.Whole_Number (Sem.Part_Offset (Analysis, Of_Type, Part));

                  Absent, Written : Natural := 0;
                  Ok : Boolean;
               begin
                  Emit_Place (Named, Ok);
                  exit when not Ok;

                  Emit_1 (VM.Offset_Place, Offset);
                  Emit_1 (VM.Has_Value, 1);
                  Absent := Here;
                  Emit_1 (VM.Jump_If_False, 0);

                  Emit_Text (" " & Name & Reached & " := ");
                  Emit_Place (Named, Ok);
                  exit when not Ok;

                  Emit_1 (VM.Offset_Place, Offset);
                  Emit (VM.Fetch);
                  Emit_Part_Image (Holds, Named);
                  Emit (VM.Join_Text);
                  Emit_Text (";");
                  Emit (VM.Join_Text);

                  Written := Here;
                  Emit_1 (VM.Jump, 0);
                  Code.Patch (Absent, Here);
                  Emit_Text ("");
                  Code.Patch (Written, Here);

                  Emit (VM.Join_Text);
               end;
            end loop;

            Emit_1 (VM.Call_Host, 2);
            Emit (VM.Discard);
         end Carry_As_Written;

      begin
         if Survivors.Is_Empty or else On_Command = null then
            return;
         end if;

         for Item of Survivors loop
            declare
               Sym : constant Symbols.Symbol :=
                 Sem.Symbol_Of (Analysis, Item.Named);

               --  Where the jump around each half goes. Whether a variable
               --  has a value is a question only the running program can
               --  answer, so both answers are emitted and one is taken.
               Unset, Carried : Natural := 0;

               Asked : Boolean;
            begin
               exit when not Lowerable;

               if Symbols.Is_Nothing (Sym)
                 or else not Is_Emittable (Item.Of_Type)
               then
                  null;

               elsif Ty.Is_Composite (Item.Of_Type) then
                  --  Written out as the aggregate that rebuilds it. A
                  --  composite has no one value on the stack, so this is the
                  --  one survivor that has to be *assembled* -- part by part,
                  --  each in the form this language reads back, joined with
                  --  the commas and parentheses an aggregate is written with.
                  Emit_Place (Item.Named, Asked);
                  exit when not Asked;

                  Emit_1 (VM.Has_Value,
                          VM.Whole_Number (Ty.Width (Item.Of_Type)));
                  Unset := Here;
                  Emit_1 (VM.Jump_If_False, 0);

                  Emit_Text (Keep_Marker);
                  Emit_Text (Symbols.Name (Sym));
                  Emit_Text (Written_As (Sym, Item.Of_Type));

                  Emit_Text ("(");

                  for Part in 1 .. Sem.Part_Count (Analysis, Item.Of_Type) loop
                     exit when not Lowerable;

                     if Part > 1 then
                        Emit_Text (", ");
                        Emit (VM.Join_Text);
                     end if;

                     declare
                        Holds : constant Ty.Type_Kind :=
                          Sem.Part_Type (Analysis, Item.Of_Type, Part);
                        Ok : Boolean;
                     begin
                        Emit_Place (Item.Named, Ok);
                        exit when not Ok;

                        Emit_1
                          (VM.Offset_Place,
                           VM.Whole_Number
                             (Sem.Part_Offset
                                (Analysis, Item.Of_Type, Part)));
                        Emit (VM.Fetch);
                        Emit_Part_Image (Holds, Item.Named);
                        exit when not Lowerable;

                        Emit (VM.Join_Text);
                     end;
                  end loop;

                  Emit_Text (")");
                  Emit (VM.Join_Text);

                  Emit_1 (VM.Call_Host, 3);
                  Emit (VM.Discard);

                  Carried := Here;
                  Emit_1 (VM.Jump, 0);
                  Code.Patch (Unset, Here);
                  Carry_As_Written (Sym, Item.Named, Item.Of_Type);
                  Code.Patch (Carried, Here);

               else
                  --  Three things: which variable, how it was declared, and
                  --  what it holds. Whether it was a constant has to travel,
                  --  or a constant would come back assignable.
                  Emit_Address (Place_Of (Sym));
                  Emit_1 (VM.Has_Value, 1);
                  Unset := Here;
                  Emit_1 (VM.Jump_If_False, 0);

                  Emit_Text (Keep_Marker);
                  Emit_Text (Symbols.Name (Sym));
                  Emit_Text (Written_As (Sym, Item.Of_Type));

                  --  The value as text, for every type. `'Image` renders each
                  --  as something this language reads back -- a Character
                  --  comes quoted, a Boolean comes as TRUE -- and a String is
                  --  already the text it stands for.
                  Emit_Value (Place_Of (Sym));

                  case Ty.Shape (Item.Of_Type) is
                     when Ty.Shape_Integer =>
                        Emit (VM.Image_Whole);

                     when Ty.Shape_Float =>
                        Emit (VM.Image_Real);

                     when Ty.Shape_Boolean =>
                        Emit (VM.Image_Truth);

                     when Ty.Shape_Character =>
                        Emit (VM.Image_Letter);

                     when Ty.Shape_Enumeration =>
                        --  The literal's own name, which is what the next
                        --  submission reads back: the declaration is carried
                        --  forward too, so the name means the same thing there
                        --  as it does here.
                        declare
                           Base  : Positive;
                           Count : Natural;
                        begin
                           if Names_Of (Item.Of_Type, Base, Count) then
                              Emit_2 (VM.Image_Enumeration, Count,
                                      VM.Whole_Number (Base));
                           end if;
                        end;

                     when others =>
                        null;
                  end case;

                  Emit_1 (VM.Call_Host, 3);
                  Emit (VM.Discard);

                  Carried := Here;
                  Emit_1 (VM.Jump, 0);
                  Code.Patch (Unset, Here);
                  Carry_As_Written (Sym, Item.Named, Item.Of_Type);
                  Code.Patch (Carried, Here);
               end if;
            end;
         end loop;
      end Emit_Survivors;

      procedure Emit_Builtin_Call (Node, Prefix, Arguments : S.Node_Id) is
         Name  : constant String := S.Text (Tree, Prefix);
         Which : Adash.Predefined.Entity_Id;

         --  A subprogram this program declared, identified by the declaration
         --  the scope chain resolved to rather than by its spelling: with
         --  nesting the same name may be declared in more than one body.
         Declared : constant Natural :=
           Find_Routine (Sem.Symbol_Of (Analysis, Prefix));

         --  A task entry, which is not called but met. Told apart by what the
         --  name denotes: only an entry has a rendezvous behind it, and only a
         --  task's entry has a task to meet.
         Met : constant Symbols.Symbol := Sem.Symbol_Of (Analysis, Prefix);
      begin
         if not Symbols.Is_Nothing (Met)
           and then Symbols.Kind (Met) = Symbols.Symbol_Entry
           and then Ty.Is_Task
                      (Symbols.Of_Type
                         (Sem.Symbol_Of (Analysis, S.First (Tree, Prefix))))
         then
            Emit_Rendezvous (Node, Prefix, Arguments);
            return;
         end if;

         if Declared /= 0 then
            Emit_Routine_Call (Node, Declared, Arguments,
                               Sem.Symbol_Of (Analysis, Prefix));
            return;
         end if;

         if not Adash.Predefined.Find (Name, Which) then
            --  Not one of the language's own subprograms. It may still be a
            --  shell command: Adash.Predefined answers for both, and the
            --  difference between the two lookups is exactly "is this a
            --  command".
            if Adash.Predefined.Profile_Of (Name).Known then
               Emit_Command_Call (Node, Name, Arguments);
            else
               Refuse (Node, Adash.Messages.Msg_Lower_Call_To,
                       [1 => Adash.Messages.Named ("name", Name)]);
            end if;

            return;
         end if;

         case Which is
            when Adash.Predefined.Entity_New_Line =>
               Emit (VM.New_Line);

            when Adash.Predefined.Entity_Put
               | Adash.Predefined.Entity_Put_Line =>
               declare
                  Named : constant Parameter_Names (1 .. 1) :=
                    [1 => Ada.Strings.Unbounded.To_Unbounded_String
                            (Adash.Messages.Value
                               (Adash.Predefined.Describe (Which)
                                  .Parameters (1).Name))];
                  Item    : constant S.Node_Id :=
                    Argument_For (Arguments, 1, Named);
                  Of_Type : constant Ty.Type_Kind :=
                    Sem.Type_Of (Analysis, Item);
               begin
                  --  Written as its own image, whatever it is. What used to be
                  --  here was a count of format parameters per type, and the
                  --  machine took exactly that many off the stack -- so a count
                  --  copied from the wrong branch did not fail, it produced the
                  --  wrong thing somewhere later.
                  Emit_Expression (Item);

                  case Ty.Shape (Of_Type) is
                     when Ty.Shape_Integer =>
                        Emit (VM.Image_Whole_Bare);

                     when Ty.Shape_Float =>
                        Emit (VM.Image_Real);

                     when Ty.Shape_Boolean =>
                        Emit (VM.Image_Truth);

                     when Ty.Shape_Character =>
                        --  Ada writes a Character in quotes. `put` writes what
                        --  the character is, not how Ada writes it down.
                        Emit (VM.Image_Letter_Bare);

                     when Ty.Shape_String =>
                        null;

                     when Ty.Shape_Enumeration =>
                        --  The name the declaration gave it. Ada's own
                        --  `Put_Line` does not take an enumeration at all;
                        --  this one takes anything and writes what it is, and
                        --  what an enumeration value *is* is its name.
                        declare
                           Base  : Positive;
                           Count : Natural;
                        begin
                           if Names_Of (Of_Type, Base, Count) then
                              Emit_2 (VM.Image_Enumeration, Count,
                                      VM.Whole_Number (Base));
                           else
                              Refuse (Node,
                                      Adash.Messages.Msg_Lower_Writing_Type,
                                      [1 => Adash.Messages.Named
                                              ("type", Ty.Name (Of_Type))]);
                              return;
                           end if;
                        end;

                     when others =>
                        Refuse (Node, Adash.Messages.Msg_Lower_Writing_Type,
                                [1 => Adash.Messages.Named
                                        ("type", Ty.Name (Of_Type))]);
                        return;
                  end case;

                  Emit ((if Which = Adash.Predefined.Entity_Put_Line
                         then VM.Write_Line else VM.Write));
               end;

            when others =>
               Refuse (Node, Adash.Messages.Msg_Lower_Call_To,
                       [1 => Adash.Messages.Named ("name", Name)]);
         end case;
      end Emit_Builtin_Call;

      --------------------
      -- Emit_Statement --
      --------------------

      procedure Emit_Statement (Node : S.Node_Id) is
      begin
         if not Lowerable then
            return;
         end if;

         case S.Kind (Tree, Node) is
            when S.Node_Null_Statement =>
               null;

            when S.Node_Exception_Declaration =>
               --  Nothing to emit. An exception is a name a raise and a
               --  handler agree on, and both of them carry it as text.
               null;

            when S.Node_Raise =>
               declare
                  What : constant S.Node_Id := S.First (Tree, Node);
               begin
                  if S.Is_Present (What) then
                     Emit_1 (VM.Raise_Named,
                             VM.Whole_Number
                               (Code.Text_Literal (S.Text (Tree, What))));

                  elsif Caught_Named = 0 then
                     --  Refused by the analyser, so reaching here is a defect
                     --  rather than a program's mistake.
                     Refuse (Node, Adash.Messages.Msg_Lower_This_Statement);

                  else
                     --  What this handler caught, raised again from where the
                     --  handler is: its own guard is already gone, so an
                     --  outer one catches it.
                     Emit_2 (VM.Load, 0, VM.Whole_Number (Caught_Named));
                     Emit_2 (VM.Load, 0, VM.Whole_Number (Caught_Detail));
                     Emit (VM.Raise_Again);
                  end if;
               end;

            when S.Node_Generic_Declaration =>
               --  Nothing to emit. A generic is a template; what runs is what
               --  an instantiation made from it, and that is an ordinary
               --  subprogram body emitted with the rest.
               null;

            when S.Node_Instantiation =>
               --  Likewise. The copy the analyser made is collected with every
               --  other body, so there is nothing here but the declaration
               --  itself, which declares no storage.
               null;

            when S.Node_Use =>
               --  Nothing to emit. A `use` says how a name is spelled, which
               --  the analyser has already settled: every name that reached
               --  the lowering carries the symbol it resolved to.
               null;

            when S.Node_Protected_Declaration | S.Node_Protected_Body =>
               --  What it holds, in order: its data, and the bodies of its
               --  operations -- which are collected and emitted with every
               --  other body, each wrapped in taking and giving back the lock.
               --
               --  A protected *type* holds nothing of its own: its state and
               --  its lock belong to its objects, and each object is a copy
               --  emitted where it was declared.
               if not Is_Guarded_Template (Node) then
                  --  What it may be called by, said where it is elaborated:
                  --  the ceiling lives with the object, because a program may
                  --  change it and every operation has to be asking the same
                  --  question.
                  if S.Kind (Tree, Node) = S.Node_Protected_Body then
                     declare
                        Which : constant Natural :=
                          Object_Number (S.First (Tree, Node));
                     begin
                        if Which /= 0 then
                           Emit_1
                             (VM.Push_Whole,
                              VM.Whole_Number
                                (Priority_Of
                                   (S.Text (Tree, S.First (Tree, Node)))));
                           Emit_2 (VM.Ceiling_Is, Which, 0);
                        end if;
                     end;
                  end if;

                  Emit_Sequence (S.Second (Tree, Node));
               end if;

            when S.Node_Accept =>
               declare
                  Which : constant Natural :=
                    Entry_Number
                      (Sem.Symbol_Of (Analysis, S.First (Tree, Node)));
               begin
                  if Which = 0 then
                     Refuse (Node, Adash.Messages.Msg_Lower_This_Statement);
                     return;
                  end if;

                  --  Try, and wait only when nobody is there. The wait goes
                  --  back to the try rather than carrying on, because what
                  --  woke the strand is that *somebody* called -- which entry
                  --  they called is settled by looking again.
                  declare
                     Again  : constant Natural := Here;
                     Absent : Natural;
                     Taken  : Natural;

                     Served : constant Symbols.Symbol :=
                       Sem.Symbol_Of (Analysis, S.First (Tree, Node));
                     Member : constant S.Node_Id :=
                       (if S.Child_Count (Tree, Node) >= 4
                        then S.Child (Tree, Node, 4) else S.No_Node);
                  begin
                     --  What this accept is open for, said the same way a
                     --  select says it: an accept on its own is a select with
                     --  one alternative and no guard, and a strand waiting at
                     --  either has to be able to answer somebody who asks
                     --  whether a rendezvous could start.
                     Emit_1 (VM.Choose, 1);

                     if Emit_Family_Member (Served, Member) then
                        Emit_1 (VM.Push_Truth, 1);
                        Emit_2 (VM.Offer_Entry, Which, 1);
                     else
                        Emit_1 (VM.Push_Truth, 1);
                        Emit_2 (VM.Offer_Entry, Which, 0);
                     end if;

                     if Emit_Family_Member (Served, Member) then
                        Emit_2 (VM.Try_Accept, Which, 1);
                     else
                        Emit_2 (VM.Try_Accept, Which, 0);
                     end if;

                     Absent := Here;
                     Emit_1 (VM.Jump_If_False, 0);
                     Taken := Here;
                     Emit_1 (VM.Jump, 0);
                     Code.Patch (Absent, Here);
                     Emit_1 (VM.Await_Caller, VM.Whole_Number (Again));
                     Code.Patch (Taken, Here);
                  end;

                  Emit_Accept_Body (Node, Which);
               end;

            when S.Node_Requeue =>
               declare
                  Moves_To : constant Symbols.Symbol :=
                    Sem.Symbol_Of (Analysis, S.First (Tree, Node));
                  Target : constant Natural := Entry_Number (Moves_To);
                  Member : constant S.Node_Id :=
                    (if S.Child_Count (Tree, Node) >= 2
                     then S.Second (Tree, Node) else S.No_Node);
               begin
                  if Serving_Entry = 0 then
                     --  Not in an accept body, so this is a protected entry
                     --  body: the caller queues by being *inside* the entry it
                     --  called, so moving it is leaving this body and entering
                     --  that one.
                     declare
                        Where : constant Natural :=
                          Find_Routine
                            (Sem.Symbol_Of (Analysis, S.First (Tree, Node)));
                     begin
                        if Where = 0 then
                           Refuse (Node,
                                   Adash.Messages.Msg_Lower_This_Statement);
                        else
                           --  What the entry it moves to takes, which is which
                           --  member when it is a family's.
                           declare
                              Ignored : constant Boolean :=
                                Emit_Family_Member (Moves_To, Member);
                              pragma Unreferenced (Ignored);
                           begin
                              null;
                           end;

                           Emit_2 (VM.Requeue_Guarded, 0,
                                   VM.Whole_Number
                                     (Routines.Element (Where).Ident));
                        end if;
                     end;

                  elsif Target = 0 then
                     Refuse (Node, Adash.Messages.Msg_Lower_This_Statement);
                  else
                     --  Where the caller was taken from, then where it goes:
                     --  either may be a member of a family, and a member's
                     --  number is one the body works out.
                     Emit_1 (VM.Push_Whole,
                             VM.Whole_Number (Serving_Entry));

                     if Emit_Family_Member (Serving_Symbol, Serving_Member)
                     then
                        Emit (VM.Add_Whole);
                     end if;

                     Emit_1 (VM.Push_Whole, VM.Whole_Number (Target));

                     if Emit_Family_Member (Moves_To, Member) then
                        Emit (VM.Add_Whole);
                     end if;

                     --  `with abort` travels with the instruction: what it
                     --  says is about the caller being moved, and the machine
                     --  is where the caller is.
                     Emit_2 (VM.Requeue_Entry, 0,
                             (if S.Text (Tree, Node) = "abort" then 1 else 0));

                     --  And out of the body, past the instruction that lets a
                     --  caller go: this one has none any more.
                     Requeue_Sites.Append (Here);
                     Emit_1 (VM.Jump, 0);
                  end if;
               end;

            when S.Node_Then_Abort =>
               Emit_Then_Abort (Node);

            when S.Node_Selective_Accept =>
               Emit_Selective_Accept (Node);

            when S.Node_Select_Alternative =>
               --  Emitted by the select that holds it, in the order its
               --  alternatives are tried.
               null;

            when S.Node_Delay =>
               Emit_Expression (S.First (Tree, Node));
               Emit ((if S.Text (Tree, Node) = "until"
                      then VM.Delay_Until else VM.Delay_For));

            when S.Node_Abort =>
               --  The task itself, which is a value naming the strand running
               --  it. Several objects of one task type run one routine, so
               --  what is stopped has to be named by the object rather than by
               --  the work.
               declare
                  Count : constant Natural := S.Child_Count (Tree, Node);
                  Ready : Boolean := True;
               begin
                  for Index in 1 .. Count loop
                     declare
                        Named : constant S.Node_Id :=
                          S.Child (Tree, Node, Index);
                        Sym   : constant Symbols.Symbol :=
                          Sem.Symbol_Of (Analysis, Named);
                     begin
                        if Symbols.Is_Nothing (Sym) then
                           Refuse (Node,
                                   Adash.Messages.Msg_Lower_Unresolved_Name);
                           Ready := False;
                        else
                           Emit_Value (Place_Of (Sym));
                        end if;
                     end;
                  end loop;

                  --  One instruction for all of them, so that no caller of one
                  --  runs before the last is stopped.
                  if Ready then
                     Emit_1 (VM.Abort_Task, VM.Whole_Number (Count));
                  end if;
               end;

            when S.Node_Select =>
               declare
                  Call      : constant S.Node_Id := S.First (Tree, Node);
                  Taken     : constant S.Node_Id := S.Second (Tree, Node);
                  How_Long  : constant S.Node_Id := S.Third (Tree, Node);
                  Otherwise : constant S.Node_Id := S.Child (Tree, Node, 4);

                  Named : constant S.Node_Id :=
                    (if S.Kind (Tree, Call) = S.Node_Procedure_Call
                     then S.First (Tree, Call) else Call);

                  Which : constant Natural :=
                    Find_Routine (Sem.Symbol_Of (Analysis, Named));

                  Barrier : S.Node_Id := S.No_Node;
                  Object  : Natural := 0;

                  --  The object's own, so that taking its lock to look at a
                  --  barrier answers to the same rule as calling it.
                  Ceiling : Natural := VM.Highest_Priority;

                  Closed, Done : Natural;
               begin
                  if Which /= 0 then
                     Barrier :=
                       S.Second (Tree, Routines.Element (Which).Node);
                     Object := Routines.Element (Which).Guarded_By;
                     Ceiling := Routines.Element (Which).Ceiling;
                  end if;

                  --  A task's entry is not a barrier but a meeting, so what
                  --  bounds the wait is the call itself: it joins the queue
                  --  with a deadline and leaves it again if nobody comes.
                  --
                  --  Only the timed form. What the other one asks -- whether a
                  --  rendezvous could start *now* -- is a question about what
                  --  the task it calls is waiting for at this instant, and
                  --  this machine does not record that: an acceptor decides
                  --  what to take by looking, which is why a select over
                  --  several entries reads the way it does.
                  declare
                     --  What the trigger names, dug out of the statement it
                     --  was parsed as: a call with arguments is a call node
                     --  inside a statement node, and one without is the name
                     --  inside it.
                     Inner : constant S.Node_Id :=
                       (if S.Kind (Tree, Call) = S.Node_Procedure_Call
                        then S.First (Tree, Call) else Call);
                     Head : constant S.Node_Id :=
                       (if S.Kind (Tree, Inner) = S.Node_Call
                        then S.First (Tree, Inner) else Inner);
                     Args : constant S.Node_Id :=
                       (if S.Kind (Tree, Inner) = S.Node_Call
                        then S.Second (Tree, Inner) else S.No_Node);
                     Whom : constant Symbols.Symbol :=
                       Sem.Symbol_Of (Analysis, Head);
                  begin
                     if not Symbols.Is_Nothing (Whom)
                       and then Symbols.Kind (Whom) = Symbols.Symbol_Entry
                       and then S.Kind (Tree, Head) = S.Node_Selected
                       and then Ty.Is_Task
                                  (Symbols.Of_Type
                                     (Sem.Symbol_Of
                                        (Analysis, S.First (Tree, Head))))
                     then
                        --  Bounded by a wait, or by nothing at all: a call
                        --  with an else part is made only if the task it
                        --  calls is waiting to take it, and both forms answer
                        --  the same way -- whether the rendezvous began.
                        Emit_Rendezvous
                          (Call, Head, Args,
                           Wait_For => How_Long,
                           Only_If_Ready => not S.Is_Present (How_Long));

                        Closed := Here;
                        Emit_1 (VM.Jump_If_False, 0);
                        Emit_Sequence (Taken);
                        Done := Here;
                        Emit_1 (VM.Jump, 0);
                        Code.Patch (Closed, Here);
                        Emit_Sequence (Otherwise);
                        Code.Patch (Done, Here);
                        return;
                     end if;
                  end;

                  if Which = 0
                    or else Object = 0
                    or else not S.Is_Present (Barrier)
                  then
                     --  A select waits on an entry, and an entry is a barrier.
                     --  Anything else has nothing to wait for.
                     Refuse (Node, Adash.Messages.Msg_Lower_This_Statement);
                     return;
                  end if;

                  --  The timed form queues like an ordinary call and gives
                  --  up where it waits. A caller of a protected entry queues
                  --  by being inside the entry's own body, parked at its
                  --  barrier, so what a deadline has to reach is that parking
                  --  -- and reaching it is what makes a barrier that opens
                  --  during the wait taken when it opens rather than when the
                  --  wait ends.
                  if S.Is_Present (How_Long) then
                     Emit_Expression (How_Long);
                     Emit (VM.Call_Deadline);
                     Emit_Statement (Call);
                     Emit (VM.Call_Answer);

                     Closed := Here;
                     Emit_1 (VM.Jump_If_False, 0);
                     Emit_Sequence (Taken);
                     Done := Here;
                     Emit_1 (VM.Jump, 0);
                     Code.Patch (Closed, Here);
                     Emit_Sequence (Otherwise);
                     Code.Patch (Done, Here);
                     return;
                  end if;

                  --  The conditional form asks the barrier under the lock,
                  --  and nothing changes strand while it is held -- so the
                  --  barrier cannot close between being asked and being acted
                  --  on. That window is the whole difficulty of a conditional
                  --  entry call, and this is where it is closed.
                  Emit_2 (VM.Enter_Protected, Ceiling,
                          VM.Whole_Number (Object));
                  Emit_Expression (Barrier);

                  Closed := Here;
                  Emit_1 (VM.Jump_If_False, 0);

                  --  Open. The entry itself asks again -- it is the same code
                  --  either way in -- and finds it open, because nothing has
                  --  run in between.
                  Emit_Statement (Call);
                  Emit_Sequence (Taken);

                  Done := Here;
                  Emit_1 (VM.Jump, 0);

                  Code.Patch (Closed, Here);
                  Emit_1 (VM.Leave_Protected, VM.Whole_Number (Object));
                  Emit_Sequence (Otherwise);
                  Code.Patch (Done, Here);
               end;

            when S.Node_Task_Declaration =>
               --  Nothing to emit. What a task declaration says is that a task
               --  exists; what makes it run is its body.
               null;

            when S.Node_Task_Body =>
               --  Started here, where it was written, which is where Ada
               --  elaborates it. The strand runs interleaved from now on, and
               --  the submission will not finish until it has ended.
               --
               --  A task *type*'s body starts nothing. It is what its objects
               --  run, and each of those is where a task begins.
               declare
                  Named : constant S.Node_Id := S.First (Tree, Node);
                  Sym   : constant Symbols.Symbol :=
                    Sem.Symbol_Of (Analysis, Named);
                  Which : constant Natural := Find_Routine (Sym);
               begin
                  if Symbols.Kind (Sym) = Symbols.Symbol_Type then
                     null;
                  elsif Which = 0 then
                     Refuse (Node, Adash.Messages.Msg_Lower_This_Statement);
                  else
                     --  A single task takes nothing: there is nowhere to
                     --  write what it would take, which is why discriminants
                     --  belong to a task type and are refused on one task.
                     Emit_Start_Task (Sym, Which, S.No_Node);
                  end if;
               end;

            when S.Node_Entry =>
               --  An entry declaration says an entry exists; its body is
               --  collected and emitted with the other operations of the
               --  object it stands in.
               null;

            when S.Node_Pragma =>
               --  Nothing to emit. What a pragma says is read where what it
               --  says something about is made.
               null;

            when S.Node_Package_Declaration | S.Node_Package_Body =>
               --  What it holds, in order. A package member is an ordinary
               --  declaration under a dotted name, so this is the sequence and
               --  nothing else: no scope to enter, no frame to make, nothing
               --  the machine has to be told about.
               Emit_Sequence (S.Second (Tree, Node));

            when S.Node_Record_Declaration | S.Node_Array_Declaration =>
               --  Nothing to emit. What the type is made of was worked out by
               --  the analyser and is asked for where a value is reached into;
               --  the declaration itself makes no room, because room is made
               --  by the variables that have the type.
               null;

            when S.Node_Subtype_Declaration =>
               --  Nothing to emit. A subtype is a compile-time fact and its
               --  bounds travel inside the type, to the places that store a
               --  value into something declared with it.
               null;

            when S.Node_Type_Declaration =>
               --  Nothing to emit. The names were interned before anything
               --  ran, the type is a compile-time fact, and its literals are
               --  positions rather than storage.
               null;

            when S.Node_Object_Declaration =>
               declare
                  Name_Node : constant S.Node_Id := S.First (Tree, Node);
                  Value     : constant S.Node_Id := S.Third (Tree, Node);
                  Sym       : constant Symbols.Symbol :=
                    Sem.Symbol_Of (Analysis, Name_Node);

                  --  The declared variable's type, taken from the symbol
                  --  rather than from the declaration node. The node carries
                  --  the initial expression's type, which is absent when there
                  --  is no initializer -- and a String declared without one
                  --  would then be lowered as though it were discrete, which
                  --  is silently wrong rather than refused.
                  Of_Type   : constant Ty.Type_Kind := Symbols.Of_Type (Sym);
               begin
                  if Ty.Is_Protected (Sem.Type_Of (Analysis, Node)) then
                     --  What the object is: the declaration and body the
                     --  analyser copied out of the type, emitted where the
                     --  object was declared. Its state gets its slots there,
                     --  and its operations are collected with every other.
                     declare
                        Copy : constant S.Node_Id :=
                          Sem.Expansion_Of (Analysis, Node);
                     begin
                        if S.Is_Present (Copy) then
                           Emit_Sequence (Copy);
                        end if;
                     end;

                     return;
                  end if;

                  if Symbols.Is_Nothing (Sym) then
                     Refuse (Node, Adash.Messages.Msg_Lower_Declaration_Unresolved);
                     return;
                  end if;

                  if not Is_Emittable (Of_Type) then
                     Refuse (Node, Adash.Messages.Msg_Lower_Variable_Of_Type,
                             [1 => Adash.Messages.Named ("type", Ty.Name (Of_Type))]);
                     return;
                  end if;

                  --  Only the submission's own top-level variables are handed
                  --  back. One inside a subprogram belongs to a frame that is
                  --  gone by the time the program ends, and one inside a loop
                  --  would be handed back once per turn.
                  --
                  --  A task is not handed back at all, and neither is an
                  --  identity of one. What either holds names a strand, the
                  --  submission that declared it is its master, and Ada says a
                  --  task does not outlive its master -- so what would be
                  --  carried is the name of something that has ended.
                  --
                  --  There is nothing to carry it as, either: a value is
                  --  handed back as the text a program could have written, and
                  --  a task has no such text. It was handed back as nothing,
                  --  which the next submission read as a missing expression.
                  --  Nor a constant *member*. What declares one is the
                  --  package or protected body it stands in, and that is
                  --  carried as the text it was written as and elaborated
                  --  again -- so the value comes back by being computed
                  --  rather than by being handed over, and handing it over
                  --  would be an assignment to something that cannot be
                  --  assigned to.
                  if Current_Routine = 0
                    and then Current_Level = 1
                    and then Block_Depth = 0
                    and then not Ty.Is_Task (Of_Type)
                    and then Of_Type /= Ty.Type_Task_Id
                    and then not (Symbols.Kind (Sym) = Symbols.Symbol_Constant
                                  and then Is_Member (Symbols.Name (Sym)))
                  then
                     Survivors.Append
                       (Survivor'(Named => Name_Node, Of_Type => Of_Type));
                  end if;

                  --  Allocating before the initial value is emitted would be
                  --  wrong for `X : Integer := X;` -- but semantics already
                  --  refused that, so the order here only has to match what
                  --  Place_Of expects.
                  if Ty.Is_Task (Of_Type) then
                     --  Started where it is declared, which is where Ada
                     --  elaborates it, and kept in the object: what the object
                     --  holds is which strand runs it.
                     declare
                        Which : constant Natural := Find_Task (Ty.Name (Of_Type));
                     begin
                        if Which = 0 then
                           Refuse (Node,
                                   Adash.Messages.Msg_Lower_This_Statement);
                        else
                           Emit_Start_Task
                             (Sym, Which, S.Child (Tree, Node, 4));
                        end if;
                     end;

                     return;
                  end if;

                  declare
                     Where : constant Place := Place_Of (Sym);
                  begin
                     if Ty.Is_Composite (Of_Type) then
                        --  A composite has no value on the stack: it is a run
                        --  of slots, already allocated by Place_Of. What an
                        --  initial value does is fill them.
                        if S.Is_Present (Value) then
                           if S.Kind (Tree, Value) = S.Node_Aggregate then
                              Emit_Aggregate
                                (Name_Node, Of_Type, S.First (Tree, Value));
                           else
                              Emit_Copy (Name_Node, Value, Of_Type);
                           end if;
                        end if;

                     elsif S.Is_Present (Value) then
                        --  The machine's store takes the destination address
                        --  from the stack, under the value: Store's own
                        --  operand is a type code, not an address. Emitting the
                        --  address first is the whole of the convention.
                        Emit_Address (Where);
                        Emit_Expression (Value);
                        Emit_Bounds_Check (Of_Type);
                        Emit_Store (Of_Type);

                     elsif Is_Whole_Cell (Of_Type)
                       or else Of_Type = Ty.Type_Task_Id
                     then
                        --  `X : String;` is refused rather than given a value.
                        --
                        --  Ada does not allow it either: String is
                        --  unconstrained, so a declaration needs a constraint
                        --  or an initial value. Inventing an empty string here
                        --  would make Adash accept a declaration that real Ada
                        --  rejects, which is the one thing a subset must not
                        --  do -- a program written against the subset would
                        --  then fail to compile as Ada.
                        --
                        --  It also removes a question the machine cannot
                        --  answer: a String cell holds a variable-length
                        --  value, and an unwritten one holds whatever the
                        --  stack held before. A Task_Id is refused for the
                        --  second reason alone -- an identity with nothing in
                        --  it names no task, and Ada's answer to that is a
                        --  value of its own that this build does not have.
                        Refuse (Node, Adash.Messages.Msg_Lower_Variable_Of_Type,
                                [1 => Adash.Messages.Named
                                        ("type", Ty.Name (Of_Type))]);
                        return;
                     end if;
                  end;
               end;

            when S.Node_Assignment =>
               declare
                  Target  : constant S.Node_Id := S.First (Tree, Node);
                  Value   : constant S.Node_Id := S.Second (Tree, Node);
                  Of_Type : constant Ty.Type_Kind :=
                    Sem.Type_Of (Analysis, Target);
                  Ok : Boolean;
               begin
                  --  `A'Priority := 20;` -- the one attribute a program may
                  --  assign to. What it names decides which of the two things
                  --  it changes: a task's own priority, or the ceiling of a
                  --  protected object.
                  if S.Kind (Tree, Target) = S.Node_Attribute then
                     declare
                        Named : constant S.Node_Id := S.First (Tree, Target);
                        Whose : constant Ty.Type_Kind :=
                          Sem.Type_Of (Analysis, Named);
                        Which : constant Natural := Object_Number (Named);
                     begin
                        if Ty.Is_Task (Whose) then
                           Emit_Expression (Named);
                           Emit_Expression (Value);
                           Emit (VM.Set_Priority);

                        elsif Which /= 0 then
                           Emit_Expression (Value);
                           Emit_2 (VM.Ceiling_Is, Which, 0);

                        else
                           Refuse (Node,
                                   Adash.Messages.Msg_Lower_This_Statement);
                        end if;
                     end;

                     return;
                  end if;

                  if Ty.Is_Composite (Of_Type) then
                     if S.Kind (Tree, Value) = S.Node_Aggregate then
                        Emit_Aggregate (Target, Of_Type, S.First (Tree, Value));
                     else
                        Emit_Copy (Target, Value, Of_Type);
                     end if;

                     return;
                  end if;

                  --  `S (2) := 'x';` and `S (2 .. 4) := "xyz";`. A String is
                  --  one cell rather than a run of slots, so there is no place
                  --  inside it to store to: the machine builds the whole text
                  --  changed and this stores that, which is the same
                  --  assignment written the long way and is where the checks
                  --  on the position live.
                  if Is_Text_Part (Target) then
                     declare
                        --  The variable the chain of parts bottoms out at.
                        --  `S (2 .. 5) (1 .. 2)` is a part of a part of S, and
                        --  S is where the whole changed text is stored.
                        Owner : S.Node_Id := Target;
                        Into  : Boolean;

                        --  Each level, from the owner outwards: the text the
                        --  level starts from, and where in it the level sits.
                        --  Written in this order because the instruction pops
                        --  its replacement first, so the innermost part has to
                        --  be the last thing pushed.
                        procedure Emit_Levels (Part : S.Node_Id);

                        --  One instruction per level, innermost first: each
                        --  yields the text of the level outside it, which is
                        --  the replacement that level's own instruction takes.
                        procedure Emit_Changes (Part : S.Node_Id);

                        procedure Emit_Levels (Part : S.Node_Id) is
                           Prefix : constant S.Node_Id := S.First (Tree, Part);
                           Only   : constant S.Node_Id :=
                             S.First (Tree, S.Second (Tree, Part));
                        begin
                           if Is_Text_Part (Prefix) then
                              Emit_Levels (Prefix);
                           end if;

                           Emit_Expression (Prefix);

                           if S.Kind (Tree, Only) = S.Node_Range then
                              Emit_Expression (S.First (Tree, Only));
                              Emit_Expression (S.Second (Tree, Only));
                           else
                              Emit_Expression (Only);
                           end if;
                        end Emit_Levels;

                        procedure Emit_Changes (Part : S.Node_Id) is
                           Prefix : constant S.Node_Id := S.First (Tree, Part);
                           Only   : constant S.Node_Id :=
                             S.First (Tree, S.Second (Tree, Part));
                        begin
                           if S.Kind (Tree, Only) = S.Node_Range then
                              Emit (VM.Text_Set_Slice);
                           else
                              Emit (VM.Text_Set_Element);
                           end if;

                           if Is_Text_Part (Prefix) then
                              Emit_Changes (Prefix);
                           end if;
                        end Emit_Changes;
                     begin
                        while Is_Text_Part (Owner) loop
                           Owner := S.First (Tree, Owner);
                        end loop;

                        Emit_Place (Owner, Into);

                        if not Into then
                           return;
                        end if;

                        Emit_Levels (Target);
                        Emit_Expression (Value);
                        Emit_Changes (Target);
                        Emit_Store (Ty.Type_String);
                     end;

                     return;
                  end if;

                  Emit_Place (Target, Ok);

                  if not Ok then
                     return;
                  end if;

                  Emit_Expression (Value);
                  Emit_Bounds_Check (Of_Type);
                  Emit_Store (Of_Type);
               end;

            when S.Node_If =>
               declare
                  Over_Then : Natural;
                  Over_Else : Natural;
                  Has_Else  : constant Boolean :=
                    S.Is_Present (S.Third (Tree, Node));
               begin
                  Emit_Expression (S.First (Tree, Node));

                  Over_Then := Here;
                  Emit_1 (VM.Jump_If_False, 0);

                  Emit_Sequence (S.Second (Tree, Node));

                  if Has_Else then
                     Over_Else := Here;
                     Emit_1 (VM.Jump, 0);

                     --  The false branch lands here, after the then part and
                     --  its jump over the else.
                     Code.Patch (Over_Then, Here);

                     --  An elsif is a nested if, so this dispatches on what is
                     --  actually there rather than assuming a sequence.
                     if S.Kind (Tree, S.Third (Tree, Node)) = S.Node_Sequence then
                        Emit_Sequence (S.Third (Tree, Node));
                     else
                        Emit_Statement (S.Third (Tree, Node));
                     end if;

                     Code.Patch (Over_Else, Here);
                  else
                     Code.Patch (Over_Then, Here);
                  end if;
               end;

            when S.Node_Case =>
               declare
                  Listed : constant S.Node_Id := S.Second (Tree, Node);
                  Total  : constant Natural := S.Child_Count (Tree, Listed);

                  --  The value being examined, evaluated once and kept.
                  --  `case Next_Line is` must not call Next_Line again for
                  --  every alternative it tests.
                  Subject : constant Natural := New_Temporary;
                  Held    : constant Natural := 0;

                  --  Where each alternative jumps to when it is done. Patched
                  --  once the end is known, which is only after the last one.
                  Leaving : array (1 .. Natural'Max (Total, 1)) of Natural :=
                    [others => 0];
                  Departures : Natural := 0;

                  --  Push the kept value.
                  procedure Push_Subject;

                  procedure Push_Subject is
                  begin
                     Emit_2 (VM.Load, Held, VM.Whole_Number (Subject));
                  end Push_Subject;

                  --  Leave a Boolean on the stack saying whether the value is
                  --  one this choice covers.
                  procedure Emit_Test (Choice : S.Node_Id);

                  procedure Emit_Test (Choice : S.Node_Id) is
                     Low  : Long_Long_Integer := 0;
                     High : Long_Long_Integer := 0;
                  begin
                     if S.Kind (Tree, Choice) = S.Node_Range then
                        --  Two comparisons and an `and`, which is a product
                        --  because a Boolean is 0 or 1 on this machine -- the
                        --  same identity the binary operators use.
                        if not Sem.Static_Choice
                                 (Analysis, Tree, S.First (Tree, Choice), Low)
                          or else not Sem.Static_Choice
                                        (Analysis, Tree,
                                         S.Second (Tree, Choice), High)
                        then
                           Refuse (Choice, Adash.Messages.Msg_Lower_Case_Choice);
                           return;
                        end if;

                        Push_Subject;
                        Emit_1 (VM.Push_Whole, VM.Whole_Number (Low));
                        Emit (VM.Greater_Equal_Whole);

                        Push_Subject;
                        Emit_1 (VM.Push_Whole, VM.Whole_Number (High));
                        Emit (VM.Less_Equal_Whole);

                        --  Both ends: said as `and` rather than as a product
                        --  of the 0 and 1 a Boolean used to be on the stack.
                        Emit (VM.And_Truth);
                        return;
                     end if;

                     if not Sem.Static_Choice (Analysis, Tree, Choice, Low)
                     then
                        Refuse (Choice, Adash.Messages.Msg_Lower_Case_Choice);
                        return;
                     end if;

                     Push_Subject;
                     Emit_1 (VM.Push_Whole, VM.Whole_Number (Low));
                     Emit (VM.Equal_Whole);
                  end Emit_Test;

               begin
                  --  Boolean and Character are discrete values on the stack
                  --  exactly as an Integer is, so one comparison serves all
                  --  three and the choices are their positions in the type.
                  Emit_2 (VM.Address, Held, VM.Whole_Number (Subject));
                  Emit_Expression (S.First (Tree, Node));
                  Emit (VM.Store);

                  for Index in 1 .. Total loop
                     exit when not Lowerable;

                     declare
                        Alternative : constant S.Node_Id :=
                          S.Child (Tree, Listed, Index);
                        Choices     : constant S.Node_Id :=
                          S.First (Tree, Alternative);
                        Given       : constant Natural :=
                          S.Child_Count (Tree, Choices);

                        Catches : Boolean := False;
                        Onward  : Natural := 0;
                        Tested  : Natural := 0;
                     begin
                        for Position in 1 .. Given loop
                           if S.Kind (Tree, S.Child (Tree, Choices, Position))
                             = S.Node_Others
                           then
                              --  `others` is what is left, so it is reached by
                              --  falling past every test above rather than by
                              --  one of its own.
                              Catches := True;
                           else
                              Emit_Test (S.Child (Tree, Choices, Position));
                              Tested := Tested + 1;

                              if Tested > 1 then
                                 --  Either of them, said as `or`.
                                 Emit (VM.Or_Truth);
                              end if;
                           end if;
                        end loop;

                        if not Catches then
                           Onward := Here;
                           Emit_1 (VM.Jump_If_False, 0);
                        end if;

                        Emit_Sequence (S.Second (Tree, Alternative));

                        --  Alternatives do not fall through to one another, so
                        --  each one that ran is done with the statement.
                        Departures := Departures + 1;
                        Leaving (Departures) := Here;
                        Emit_1 (VM.Jump, 0);

                        if not Catches then
                           Code.Patch (Onward, Here);
                        end if;
                     end;
                  end loop;

                  for Index in 1 .. Departures loop
                     Code.Patch (Leaving (Index), Here);
                  end loop;
               end;

            when S.Node_While_Loop =>
               declare
                  Top  : constant Natural := Here;
                  Over : Natural;
               begin
                  --  A while loop has its own way out and can still hold an
                  --  exit: Ada allows one in any loop, and a loop that
                  --  accepted the statement without leaving would be worse
                  --  than one that refused it.
                  Open_Loop;
                  Emit_Expression (S.First (Tree, Node));

                  Over := Here;
                  Emit_1 (VM.Jump_If_False, 0);

                  Emit_Sequence (S.Second (Tree, Node));
                  Emit_1 (VM.Jump, VM.Whole_Number (Top));

                  Code.Patch (Over, Here);
                  Close_Loop;
               end;

            when S.Node_For_Loop | S.Node_For_Reverse_Loop =>
               declare
                  --  Counting down rather than up. Everything else about the
                  --  two is the same, so they share this: what changes is
                  --  which bound the parameter starts at, which way the tests
                  --  point, and whether the step adds or subtracts.
                  Backwards : constant Boolean :=
                    S.Kind (Tree, Node) = S.Node_For_Reverse_Loop;

                  --  Three children is a range; two is a type name, and the
                  --  bounds are then the type's own -- which this build knows
                  --  without evaluating anything.
                  Over_A_Type : constant Boolean :=
                    S.Child_Count (Tree, Node) = 3;

                  Counted : constant Ty.Type_Kind :=
                    Sem.Type_Of (Analysis, S.First (Tree, Node));

                  --  What to count from and to, when a type was named.
                  procedure Emit_Bound (Lowest : Boolean);

                  procedure Emit_Bound (Lowest : Boolean) is
                     Base  : Positive;
                     Count : Natural;
                  begin
                     --  A subtype counts over what it admits, not over what
                     --  its base type holds. Without this `for D in Digit`
                     --  walks every Integer there is.
                     if Ty.Has_Bounds (Counted) then
                        Emit_1
                          (VM.Push_Whole,
                           VM.Whole_Number
                             (if Lowest then Ty.Low_Bound (Counted)
                              else Ty.High_Bound (Counted)));
                        return;
                     end if;

                     case Ty.Shape (Counted) is
                        when Ty.Shape_Enumeration =>
                           if Names_Of (Counted, Base, Count) then
                              Emit_1
                                (VM.Push_Whole,
                                 (if Lowest then 0
                                  else VM.Whole_Number (Count - 1)));
                           end if;

                        when Ty.Shape_Boolean =>
                           Emit_1 (VM.Push_Whole, (if Lowest then 0 else 1));

                        when Ty.Shape_Character =>
                           Emit_1
                             (VM.Push_Whole, (if Lowest then 0 else 255));

                        when Ty.Shape_Integer =>
                           Emit_1
                             (VM.Push_Whole,
                              (if Lowest then VM.Whole_Number'First
                               else VM.Whole_Number'Last));

                        when others =>
                           Refuse
                             (Node,
                              Adash.Messages.Msg_Lower_Argument_Of_Type,
                              [1 => Adash.Messages.Named
                                      ("type", Ty.Name (Counted))]);
                     end case;
                  end Emit_Bound;

                  Variable : constant S.Node_Id := S.First (Tree, Node);
                  Sym      : constant Symbols.Symbol :=
                    Sem.Symbol_Of (Analysis, Variable);
                  Where    : constant Place := Place_Of (Sym);
                  Address  : constant Natural := Where.Address;
                  Level    : constant Natural := Outward (Where.Level);

                  --  Whether the counting needs a slot of its own.
                  --
                  --  The loop counts in positions and the variable holds a
                  --  value of its type: a Character loop counts 0 .. 255 and
                  --  the variable holds a Character, and writing the position
                  --  into it would hand the body a number wearing a
                  --  Character's name. For an Integer and an enumeration the
                  --  two coincide, so a range of either counts in the variable
                  --  itself.
                  --
                  --  A named type always splits them, which costs a slot where
                  --  it need not and is cheaper than a rule per type.
                  Split : constant Boolean :=
                    S.Child_Count (Tree, Node) = 3
                      or else Ty.Shape (Counted) in Ty.Shape_Boolean
                                                  | Ty.Shape_Character;

                  Counter : constant Natural :=
                    (if Split then New_Temporary else 0);

                  --  Where the upper bound is kept for the life of the loop.
                  --  Allocated per `for` in the source rather than reused, so
                  --  that nested loops do not share one; each activation has
                  --  its own frame, so a recursive call does not either.
                  Bound : constant Natural := New_Temporary;
                  Held  : constant Natural := 0;

                  Top    : Natural;
                  Over   : Natural;
                  Again  : Natural;
               begin
                  Open_Loop;

                  --  Both bounds, once each, in the order they were written.
                  --  The loop parameter is not visible in its own range, so
                  --  which of the two it ends up holding cannot change what
                  --  the other evaluates to -- and going backwards must not
                  --  change the order they are evaluated in, only which one is
                  --  started from.
                  --  Where the counting is kept and how deep it is: the
                  --  visible variable for a range, a temporary of this frame
                  --  when a type was named.
                  declare
                     Step_At : constant Natural :=
                       (if Split then Counter else Address);
                     Step_In : constant Natural :=
                       (if Split then Held else Level);

                     --  A bound of a range, as a position: what the counting
                     --  is done in. A Character or a Boolean bound is a value
                     --  and has to be asked for its position; the other two
                     --  are their positions already.
                     procedure Emit_Range_Bound (Which : S.Node_Id);

                     procedure Emit_Range_Bound (Which : S.Node_Id) is
                     begin
                        Emit_Expression (Which);

                        case Ty.Shape (Counted) is
                           when Ty.Shape_Boolean =>
                              Emit (VM.Position_Truth);

                           when Ty.Shape_Character =>
                              Emit (VM.Position_Letter);

                           when others =>
                              null;
                        end case;
                     end Emit_Range_Bound;
                  begin
                     if Backwards then
                        Emit_2 (VM.Address, Held, VM.Whole_Number (Bound));

                        if Over_A_Type then
                           Emit_Bound (Lowest => True);
                        else
                           Emit_Range_Bound (S.Second (Tree, Node));
                        end if;

                        Emit (VM.Store);

                        Emit_2 (VM.Address, Step_In, VM.Whole_Number (Step_At));

                        if Over_A_Type then
                           Emit_Bound (Lowest => False);
                        else
                           Emit_Range_Bound (S.Third (Tree, Node));
                        end if;

                        Emit (VM.Store);
                     else
                        Emit_2 (VM.Address, Step_In, VM.Whole_Number (Step_At));

                        if Over_A_Type then
                           Emit_Bound (Lowest => True);
                        else
                           Emit_Range_Bound (S.Second (Tree, Node));
                        end if;

                        Emit (VM.Store);

                        Emit_2 (VM.Address, Held, VM.Whole_Number (Bound));

                        if Over_A_Type then
                           Emit_Bound (Lowest => False);
                        else
                           Emit_Range_Bound (S.Third (Tree, Node));
                        end if;

                        Emit (VM.Store);
                     end if;

                     --  A null range runs the body no times, so the first test
                     --  comes before it rather than after.
                     Emit_2 (VM.Load, Step_In, VM.Whole_Number (Step_At));
                     Emit_2 (VM.Load, Held, VM.Whole_Number (Bound));
                     Emit (if Backwards then VM.Greater_Equal_Whole
                           else VM.Less_Equal_Whole);

                     Over := Here;
                     Emit_1 (VM.Jump_If_False, 0);

                     Top := Here;

                     if Split then
                        --  The visible variable, written from the counter and
                        --  wearing its own type. A no-op for an Integer and an
                        --  enumeration, an instruction for the other two.
                        Emit_2 (VM.Address, Level, VM.Whole_Number (Address));
                        Emit_2 (VM.Load, Held, VM.Whole_Number (Counter));

                        case Ty.Shape (Counted) is
                           when Ty.Shape_Boolean =>
                              Emit (VM.Truth_At_Position);

                           when Ty.Shape_Character =>
                              Emit (VM.Letter_At_Position);

                           when others =>
                              null;
                        end case;

                        Emit (VM.Store);
                     end if;

                     Emit_Sequence
                       (S.Child (Tree, Node, (if Over_A_Type then 3 else 4)));

                  --  Test *before* incrementing, not after. The last turn has
                  --  the parameter equal to the bound, and adding one to it
                  --  would overflow when the bound is the largest value the
                  --  type holds -- a loop that ran to the end of the range
                  --  used to fail there rather than finish.
                     Emit_2 (VM.Load, Step_In, VM.Whole_Number (Step_At));
                     Emit_2 (VM.Load, Held, VM.Whole_Number (Bound));
                     Emit (if Backwards then VM.Greater_Whole
                           else VM.Less_Whole);

                     Again := Here;
                     Emit_1 (VM.Jump_If_False, 0);

                     Emit_2 (VM.Address, Step_In, VM.Whole_Number (Step_At));
                     Emit_2 (VM.Load, Step_In, VM.Whole_Number (Step_At));
                     Emit_1 (VM.Push_Whole, 1);
                     Emit (if Backwards then VM.Subtract_Whole
                           else VM.Add_Whole);
                     Emit (VM.Store);

                     Emit_1 (VM.Jump, VM.Whole_Number (Top));
                  end;

                  Code.Patch (Over, Here);
                  Code.Patch (Again, Here);
                  Close_Loop;
               end;

            when S.Node_Loop =>
               declare
                  Top : constant Natural := Here;
               begin
                  Open_Loop;
                  Emit_Sequence (S.First (Tree, Node));

                  --  Back to the top unconditionally: a bare loop has no test
                  --  of its own, so `exit` is the only way out and the only
                  --  thing that ends it.
                  Emit_1 (VM.Jump, VM.Whole_Number (Top));
                  Close_Loop;
               end;

            when S.Node_Exit =>
               if Loop_Marks.Is_Empty then
                  --  Nothing to leave. The analyser reports this, so reaching
                  --  here would mean the two disagree about what a loop is.
                  Refuse (Node, Adash.Messages.Msg_Lower_Exit_Outside_Loop);
                  return;
               end if;

               declare
                  Condition : constant S.Node_Id := S.First (Tree, Node);
               begin
                  if S.Is_Present (Condition) then
                     --  `exit when C` is a jump over a jump: leave when the
                     --  condition holds, carry on when it does not. Written
                     --  this way rather than by negating the condition, so
                     --  what it does is visible in the instructions.
                     declare
                        Carry_On : Natural;
                     begin
                        Emit_Expression (Condition);

                        --  Taken after the condition, not before it: a
                        --  condition is however many instructions it needs --
                        --  `N = 3` is three -- so an address computed from
                        --  where it started patches something in the middle of
                        --  it. That does not fail; it makes a loop that never
                        --  leaves.
                        Carry_On := Here;
                        Emit_1 (VM.Jump_If_False, 0);

                        Emit_Leaving_Blocks;
                        Exit_Sites.Append (Here);
                        Emit_1 (VM.Jump, 0);

                        Code.Patch (Carry_On, Here);
                     end;
                  else
                     Emit_Leaving_Blocks;
                     Exit_Sites.Append (Here);
                     Emit_1 (VM.Jump, 0);
                  end if;
               end;

            when S.Node_Return =>
               if Current_Routine = 0 then
                  if S.Is_Present (S.First (Tree, Node)) then
                     --  A submission is not a function, so there is nothing for
                     --  a value to be returned to. Refused rather than treated
                     --  as a bare return, which would run and lose the
                     --  expression.
                     Refuse (Node, Adash.Messages.Msg_Lower_Return_With_Value);
                     return;
                  end if;

                  --  A submission is lowered as one procedure and the machine
                  --  stops when that procedure ends, so leaving it early is
                  --  exactly what halting is. There is no frame above to
                  --  return into.
                  Emit (VM.Halt);
                  return;
               end if;

               declare
                  Leaving : constant Routine :=
                    Routines.Element (Current_Routine);
               begin
                  if Ty.Shape (Leaving.Returns) = Ty.Shape_None then
                     Emit (VM.Return_Plain);
                     return;
                  end if;

                  --  A function's result is what it leaves on the stack. The
                  --  frame goes and the value stays, which is where the caller
                  --  finds it -- so there is no result slot to reserve, and
                  --  nothing to agree about where it sits.
                  Emit_Expression (S.First (Tree, Node));

                  --  A result arriving is a value arriving, which is the fifth
                  --  place and the last: a function declared to return a
                  --  subtype has to keep its word, and without this it could
                  --  hand back something it says it cannot hold.
                  Emit_Bounds_Check (Leaving.Returns);

                  Emit (VM.Return_Value);
               end;

            when S.Node_Procedure_Call =>
               declare
                  Called : constant S.Node_Id := S.First (Tree, Node);
               begin
                  if S.Kind (Tree, Called) = S.Node_Call then
                     Emit_Builtin_Call
                       (Called, S.First (Tree, Called), S.Second (Tree, Called));
                  else
                     Emit_Builtin_Call (Called, Called, S.No_Node);
                  end if;
               end;

            when S.Node_Subprogram_Declaration =>
               --  Bodies are emitted after the submission, not where they were
               --  written: a body reached in sequence would run as though it
               --  had been called.
               null;

            when S.Node_Block =>
               --  All three parts, in the order they were written. Emitting
               --  only the first ran a block's declarations and none of its
               --  statements -- which this did, for as long as the node kind
               --  existed and nothing produced one.
               declare
                  Handlers : constant S.Node_Id := S.Third (Tree, Node);
                  Guarded  : constant Boolean :=
                    S.Is_Present (Handlers)
                      and then S.Child_Count (Tree, Handlers) > 0;

                  --  Where the handlers start, and where the whole block ends.
                  Catching : Natural := 0;
                  Leaving  : Natural := 0;

                  --  Where the region around this one is kept while this one
                  --  lasts. A block is a master in Ada and makes no frame
                  --  here, so what says which of them a task belongs to is a
                  --  region number rather than a frame -- and leaving one has
                  --  to put back the one it was written inside.
                  Outer : constant Natural := New_Temporary;
               begin
                  Block_Depth := Block_Depth + 1;
                  Region_Slots.Append (Outer);

                  Emit_2 (VM.Address, 0, VM.Whole_Number (Outer));
                  Emit (VM.Enter_Region);
                  Emit (VM.Store);

                  if Guarded then
                     Catching := Here;
                     Emit_1 (VM.Push_Handler, 0);
                  end if;

                  Emit_Sequence (S.First (Tree, Node));
                  Emit_Sequence (S.Second (Tree, Node));

                  if Guarded then
                     --  Reached the end without raising, so the handler is no
                     --  longer waiting and the handlers themselves are jumped
                     --  over.
                     Emit (VM.Pop_Handler);
                     Leaving := Here;
                     Emit_1 (VM.Jump, 0);

                     Code.Patch (Catching, Here);

                     --  Where the unwind lands, and before the handler runs:
                     --  an exception on its way out completes what it leaves,
                     --  and completing a master waits for its dependents. The
                     --  unwind itself cannot wait -- it is reached from inside
                     --  whatever raised -- so the wait stands here, which is
                     --  the same moment from the program's point of view.
                     Emit (VM.Await_Abandoned);

                     Emit_Handlers (Handlers);
                     Code.Patch (Leaving, Here);
                  end if;

                  --  After the handlers rejoin, so that a block which answered
                  --  for its own failure waits for what it started exactly as
                  --  one that did not.
                  Emit_2 (VM.Load, 0, VM.Whole_Number (Outer));
                  Emit (VM.Leave_Region);

                  Region_Slots.Delete_Last;
                  Block_Depth := Block_Depth - 1;
               end;

            when S.Node_Sequence =>
               Emit_Sequence (Node);

            when others =>
               Refuse (Node, Adash.Messages.Msg_Lower_This_Statement);
         end case;
      end Emit_Statement;

      -------------------
      -- Emit_Sequence --
      -------------------

      procedure Emit_Sequence (Node : S.Node_Id) is
      begin
         for Index in 1 .. S.Child_Count (Tree, Node) loop
            exit when not Lowerable;
            Emit_Statement (S.Child (Tree, Node, Index));
         end loop;
      end Emit_Sequence;

   begin
      Result := Refused;
      Instruction_Count := 0;

      if S.Has_Errors (Tree) or else not Sem.Is_Legal (Analysis) then
         --  Refused before anything runs. Whichever pass found the problem
         --  reported it, and running anyway would produce a failure from the
         --  virtual machine instead of the diagnostic the user needs.
         return;
      end if;

      Code.Reset;

      --  What the program asked for about itself, before anything is emitted:
      --  a configuration pragma is about the whole of it, so it cannot be an
      --  instruction that only what follows it obeys.
      --  The profile is a name for these pragmas said at once, so what it
      --  says is asked for here as well: a program that named it and one that
      --  wrote them out run the same way.
      if Asked_For ("detect_blocking") or else Asked_For ("profile") then
         Code.Detect_Blocking;
      end if;

      --  First-in-first-out within a priority means a strand keeps its turn
      --  until it waits for something. The other policy this accepts, round
      --  robin within priorities, is what the machine does when nobody says:
      --  a turn of a fixed number of instructions, shared out.
      if Asked_For ("task_dispatching_policy", "fifo_within_priorities")
        or else Asked_For ("profile")
      then
         Code.Run_To_Completion;
      end if;

      Take_Dispatching_Ranges;

      --  Only the one that changes something: order of arrival is what the
      --  machine does anyway.
      if Asked_For ("queuing_policy", "priority_queuing") then
         Code.Queue_By_Priority;
      end if;

      declare
         Most : Natural;
      begin
         if Sem.Task_Bound (Analysis, Most) then
            Code.Allow_Tasks (Most);
         end if;

         if Sem.Queue_Bound (Analysis, Most) then
            Code.Allow_Queued (Most);
         end if;

         if Sem.Forbids_Termination (Analysis) then
            Code.Forbid_Termination;
         end if;
      end;

      Collect_Types;
      Collect_Routines;
      Emit_Sequence (S.Root (Tree));

      if not Lowerable then
         Result := Not_Lowerable;
         return;
      end if;

      --  Every task this submission started, waited for. Before the survivors
      --  rather than after: what a task wrote into a variable of the
      --  submission has to be there when the value is handed back.
      if Started_A_Task then
         Emit (VM.Await_Tasks);
      end if;

      Emit_Survivors;
      Emit (VM.Halt);

      --  Bodies follow the submission. A call names its routine by an index
      --  handed out before anything is emitted, so where a body lands is
      --  settled when it is laid down rather than before.
      Emit_Bodies;

      if not Lowerable then
         Result := Not_Lowerable;
         return;
      end if;

      Code.Set_Frame (Next_Address);
      Instruction_Count := Code.Length;

      declare
         Shell : aliased Bridge;
         Ran   : VM.Result;

         --  Whatever run is already in progress, if any.
         Outer_Sink   : Sink_Access;
         Outer_Cancel : Cancellation_Access;
      begin
         --  Live for exactly this run. Saved and put back rather than set and
         --  cleared: a command may run a script, that script may be a program,
         --  and this is then re-entered while the outer machine is still
         --  running -- and clearing on the way out would leave the outer
         --  program unable to call anything.
         Outer_Sink := Current_Sink;
         Outer_Cancel := Current_Cancel;

         Current_Sink := On_Command;
         Current_Cancel := Cancel;

         Code.Run (Shell'Unchecked_Access, Ran);

         Current_Sink := Outer_Sink;
         Current_Cancel := Outer_Cancel;

         Result :=
           (case Ran.What is
               when VM.Stopped => Cancelled,
               when VM.Ran     => Evaluated,
               when others     => Raised);

         if Result = Raised then
            --  Said out loud. A program that died has to report it: the exit
            --  status deliberately survives a failed statement, so silence
            --  here is indistinguishable from having worked -- and a runaway
            --  recursion or a function that never returned would look like a
            --  program that simply printed nothing.
            declare
               Raised_Name : constant String :=
                 Ada.Strings.Unbounded.To_String (Ran.Raised_Name);

               use type Adash.Messages.Message_Id;

               Said : constant Adash.Messages.Message_Id := Ran.Detail;

               --  What the machine said, quoted rather than rendered. It has
               --  no catalog and must not have one: what it knows is which
               --  message and what fills it, and this is not the boundary
               --  either -- the diagnostic carries both outward and the
               --  frontend turns them into a sentence.
               --
               --  The values arrive in the order the message declares its
               --  placeholders, so the names come from the message itself and
               --  are not written down a second time in the machine.
               Names : constant Adash.Messages.Placeholder_Names :=
                 Adash.Messages.Placeholders (Said);

               Filled : constant Natural :=
                 Natural'Min (Ran.Detail_Count, Names'Length);

               Given : Adash.Messages.Argument_List (1 .. Filled);
            begin
               for Index in 1 .. Filled loop
                  Given (Index) :=
                    Adash.Messages.Named
                      (Ada.Strings.Unbounded.To_String
                         (Names (Names'First + Index - 1)),
                       Ada.Strings.Unbounded.To_String
                         (Ran.Detail_Given (Index)));
               end loop;

               Report.Emit
                 (D.Make
                    (Message   =>
                       Adash.Errors.Message
                         (if Said = Adash.Messages.Msg_Error_None
                          then Adash.Errors.Error_Program_Raised
                          else Adash.Errors.Error_Program_Raised_With_Detail),
                     Level     => D.Severity_Error,
                     Of_Kind   => D.Category_Runtime,
                     Raised_By => D.Owner_Language,
                     Origin    => Origin,
                     Extent    => S.Extent (Tree, S.Root (Tree)),
                     Arguments =>
                       [1 => Adash.Messages.Named
                               ("exception", Raised_Name)],
                     Quoted    =>
                       (if Said = Adash.Messages.Msg_Error_None
                        then Adash.Messages.Msg_Error_None else Said),
                     Fills     => "detail",
                     Quoted_Arguments => Given));
            end;
         end if;
      end;

   end Run;

end Adash.Language.Evaluation;
