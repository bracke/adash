with Ada.Real_Time;
with Ada.Characters.Handling;
with Ada.Numerics.Generic_Elementary_Functions;
with Ada.Strings;
with Ada.Strings.Fixed;
with Ada.Text_IO;
with Ada.Unchecked_Deallocation;

package body Adash.Machine is

   use Ada.Strings.Unbounded;

   package M renames Adash.Messages;

   --  Ada's own, for the one operation the language operators do not cover: a
   --  real raised to a real power. Ada spells `**` for a float with an integer
   --  exponent only.
   package Elementary is new Ada.Numerics.Generic_Elementary_Functions (Real);

   --  When the session began, which is what the clock counts from.
   --
   --  Once for the whole session rather than once per submission: a program
   --  that reads the clock, is interrupted by the user typing the next line,
   --  and reads it again must see time having passed rather than having gone
   --  back to nothing.
   Session_Began : constant Ada.Real_Time.Time := Ada.Real_Time.Clock;

   --  How much room a run gets.
   --
   --  Bounds rather than growth: a program that needs more than this is one
   --  that has run away, and a machine that grew to meet it would take the
   --  session down with it instead of saying so.
   Max_Stack  : constant := 4_096;
   Max_Slots  : constant := 65_536;
   Max_Frames : constant := 256;

   --  How many handlers may be waiting at once. One per block or body entered
   --  and not yet left, which nests exactly as they do.
   Max_Guards : constant := 256;

   --  How many strands may run at once: the environment task and fifteen
   --  tasks. A bound rather than growth for the same reason every other bound
   --  here is one -- a program that wants more has run away, and each strand
   --  costs a region of the slots and of the stack.
   --
   --  At once, and not in total. A strand goes back to being nobody when the
   --  region that declared it has waited for it, which is the moment nothing
   --  can still name it: a script that starts a task in a loop wants the
   --  sixteenth turn to work, and a bound that counted every task a run ever
   --  started would be saying a program had run away when it had not.
   Max_Strands : constant := 16;

   --  How much of the slots and of the stack each task gets. The environment
   --  task keeps the front of both, which is what makes a submission with no
   --  tasks in it run exactly as it did.
   Task_Slots : constant := Max_Slots / (2 * Max_Strands);
   Task_Stack : constant := Max_Stack / (2 * Max_Strands);

   --  What a program is told one task costs, checked against what one gets.
   --  Two spellings of one number would drift; this is the one that would say
   --  so.
   pragma Assert (Storage_Per_Task = Task_Slots + Task_Stack);

   --  What one call is doing.
   type Activation is record
      --  Where this frame's slot zero is.
      Base : Natural := 0;

      --  The frame this one was declared inside, as an index into the frame
      --  stack. Zero means the outermost. A static link rather than a display
      --  vector: a display has to be kept in step on every call and return,
      --  and forgetting one is a read from the wrong frame that answers
      --  confidently.
      Static : Natural := 0;

      --  How deep the routine is declared, which is what a static link is
      --  found by.
      Level : Natural := 0;

      --  Where to go back to.
      Return_To : Natural := 0;
   end record;

   procedure Free is new Ada.Unchecked_Deallocation
     (Instruction_Array, Instruction_Access);
   procedure Free is new Ada.Unchecked_Deallocation (Text_Array, Text_Access);
   procedure Free is new Ada.Unchecked_Deallocation (Real_Array, Real_Access);
   procedure Free is new Ada.Unchecked_Deallocation (Bound_Array, Bound_Access);
   procedure Free is new Ada.Unchecked_Deallocation
     (Routine_Array, Routine_Access);
   procedure Free is new Ada.Unchecked_Deallocation (Cell_Array, Cell_Access);

   -----------
   -- Reset --
   -----------

   procedure Reset (Item : in out Program) is
   begin
      Free (Item.Code);
      Free (Item.Texts);
      Free (Item.Reals);
      Free (Item.Bounds);
      Free (Item.Routines);
      Free (Item.Kept);

      Item.Code_Used     := 0;
      Item.Texts_Used    := 0;
      Item.Reals_Used    := 0;
      Item.Bounds_Used   := 0;
      Item.Routines_Used := 0;
      Item.Frame         := 0;
   end Reset;

   --  Room for one more of something, doubling when it runs out.
   procedure Widen (Item : in out Program);

   procedure Widen (Item : in out Program) is
   begin
      if Item.Code = null then
         Item.Code := new Instruction_Array (1 .. 256);
      elsif Item.Code_Used = Item.Code'Last then
         declare
            Bigger : constant Instruction_Access :=
              new Instruction_Array (1 .. Item.Code'Last * 2);
         begin
            Bigger (1 .. Item.Code_Used) := Item.Code (1 .. Item.Code_Used);
            Free (Item.Code);
            Item.Code := Bigger;
         end;
      end if;
   end Widen;

   ---------
   -- Add --
   ---------

   function Add
     (Item    : in out Program;
      Code    : Opcode;
      Level   : Natural := 0;
      Operand : Whole_Number := 0) return Natural is
   begin
      Widen (Item);
      Item.Code_Used := Item.Code_Used + 1;
      Item.Code (Item.Code_Used) :=
        (Code => Code, Level => Level, Operand => Operand);
      return Item.Code_Used;
   end Add;

   procedure Add
     (Item    : in out Program;
      Code    : Opcode;
      Level   : Natural := 0;
      Operand : Whole_Number := 0)
   is
      Ignored : constant Natural := Add (Item, Code, Level, Operand);
   begin
      null;
   end Add;

   ----------
   -- Next --
   ----------

   function Next (Item : Program) return Natural is
   begin
      return Item.Code_Used + 1;
   end Next;

   -----------
   -- Patch --
   -----------

   procedure Patch
     (Item : in out Program; At_Index : Natural; Target : Natural) is
   begin
      if At_Index in 1 .. Item.Code_Used then
         Item.Code (At_Index).Operand := Whole_Number (Target);
      end if;
   end Patch;

   ------------------
   -- Text_Literal --
   ------------------

   function Text_Literal (Item : in out Program; Value : String) return Natural
   is
   begin
      if Item.Texts = null then
         Item.Texts := new Text_Array (1 .. 64);
      elsif Item.Texts_Used = Item.Texts'Last then
         declare
            Bigger : constant Text_Access :=
              new Text_Array (1 .. Item.Texts'Last * 2);
         begin
            Bigger (1 .. Item.Texts_Used) := Item.Texts (1 .. Item.Texts_Used);
            Free (Item.Texts);
            Item.Texts := Bigger;
         end;
      end if;

      Item.Texts_Used := Item.Texts_Used + 1;
      Item.Texts (Item.Texts_Used) := To_Unbounded_String (Value);
      return Item.Texts_Used;
   end Text_Literal;

   ------------------
   -- Real_Literal --
   ------------------

   function Real_Literal (Item : in out Program; Value : Real) return Natural is
   begin
      if Item.Reals = null then
         Item.Reals := new Real_Array (1 .. 32);
      elsif Item.Reals_Used = Item.Reals'Last then
         declare
            Bigger : constant Real_Access :=
              new Real_Array (1 .. Item.Reals'Last * 2);
         begin
            Bigger (1 .. Item.Reals_Used) := Item.Reals (1 .. Item.Reals_Used);
            Free (Item.Reals);
            Item.Reals := Bigger;
         end;
      end if;

      Item.Reals_Used := Item.Reals_Used + 1;
      Item.Reals (Item.Reals_Used) := Value;
      return Item.Reals_Used;
   end Real_Literal;

   -----------------
   -- Bound_Pair --
   -----------------

   function Bound_Entry
     (Item  : in out Program;
      Low   : Whole_Number;
      High  : Whole_Number;
      Names : Natural := 0) return Natural is
   begin
      if Item.Bounds = null then
         Item.Bounds := new Bound_Array (1 .. 32);
      elsif Item.Bounds_Used + 3 > Item.Bounds'Last then
         declare
            Bigger : constant Bound_Access :=
              new Bound_Array (1 .. Item.Bounds'Last * 2);
         begin
            Bigger (1 .. Item.Bounds_Used) :=
              Item.Bounds (1 .. Item.Bounds_Used);
            Free (Item.Bounds);
            Item.Bounds := Bigger;
         end;
      end if;

      Item.Bounds (Item.Bounds_Used + 1) := Low;
      Item.Bounds (Item.Bounds_Used + 2) := High;
      Item.Bounds (Item.Bounds_Used + 3) := Whole_Number (Names);
      Item.Bounds_Used := Item.Bounds_Used + 3;

      return Item.Bounds_Used - 2;
   end Bound_Entry;

   ----------------------
   -- Declare_Routine --
   ----------------------

   function Declare_Routine (Item : in out Program) return Positive is
   begin
      if Item.Routines = null then
         Item.Routines := new Routine_Array (1 .. 32);
      elsif Item.Routines_Used = Item.Routines'Last then
         declare
            Bigger : constant Routine_Access :=
              new Routine_Array (1 .. Item.Routines'Last * 2);
         begin
            Bigger (1 .. Item.Routines_Used) :=
              Item.Routines (1 .. Item.Routines_Used);
            Free (Item.Routines);
            Item.Routines := Bigger;
         end;
      end if;

      Item.Routines_Used := Item.Routines_Used + 1;
      Item.Routines (Item.Routines_Used) := (others => <>);
      return Item.Routines_Used;
   end Declare_Routine;

   ---------------------
   -- Define_Routine --
   ---------------------

   procedure Define_Routine
     (Item       : in out Program;
      Which      : Positive;
      Entry_At   : Natural;
      Frame      : Natural;
      Parameters : Natural;
      Level      : Natural) is
   begin
      if Which <= Item.Routines_Used then
         Item.Routines (Which) :=
           (Entry_At   => Entry_At,
            Frame      => Frame,
            Parameters => Parameters,
            Level      => Level);
      end if;
   end Define_Routine;

   -----------------
   -- Set_Frame --
   -----------------

   procedure Allow_Queued (Item : in out Program; Most : Natural) is
   begin
      Item.Queue_Limit := Most;
      Item.Queue_Bound := True;
   end Allow_Queued;

   procedure Run_To_Completion
     (Item : in out Program;
      First : Natural := Lowest_Priority;
      Last : Natural := Highest_Priority) is
   begin
      for Each in Natural'Max (First, Lowest_Priority)
                  .. Natural'Min (Last, Highest_Priority)
      loop
         Item.Uninterrupted (Each) := True;
      end loop;
   end Run_To_Completion;

   procedure Queue_By_Priority (Item : in out Program) is
   begin
      Item.By_Priority := True;
   end Queue_By_Priority;

   procedure Forbid_Termination (Item : in out Program) is
   begin
      Item.Endless := True;
   end Forbid_Termination;

   procedure Allow_Tasks (Item : in out Program; Most : Natural) is
   begin
      Item.Task_Limit := Most;
      Item.Bounded    := True;
   end Allow_Tasks;

   procedure Detect_Blocking (Item : in out Program) is
   begin
      Item.Detecting := True;
   end Detect_Blocking;

   procedure Set_Frame (Item : in out Program; Slots : Natural) is
   begin
      Item.Frame := Slots;
   end Set_Frame;

   ------------
   -- Length --
   ------------

   function Length (Item : Program) return Natural is
   begin
      return Item.Code_Used;
   end Length;

   ------------------
   -- Slot_Value --
   ------------------

   function Slot_Value (Item : Program; Slot : Natural) return Cell is
   begin
      if Item.Kept = null or else Slot + 1 not in Item.Kept'Range then
         return (Kind => Cell_None);
      end if;

      return Item.Kept (Slot + 1);
   end Slot_Value;

   ---------
   -- Run --
   ---------

   procedure Run
     (Item     : in out Program;
      On_Host  : Host_Access;
      Produced : out Result)
   is
      --  On the heap rather than in this frame. Together they are megabytes,
      --  and a local that size is a stack overflow waiting for the first host
      --  with a smaller default than this one.
      Held : constant Cell_Access := new Cell_Array (1 .. Max_Stack);
      Top  : Natural := 0;

      Room       : constant Cell_Access := new Cell_Array (1 .. Max_Slots);
      Slots_Used : Natural := 0;

      Stack : Cell_Array renames Held.all;
      Slots : Cell_Array renames Room.all;

      Counter : Natural := 0;
      Point   : Natural := 1;

      Finished : Boolean := False;

      --  Where a raise goes, and how much to put back before it gets there.
      type Guard is record
         Target : Natural := 0;
         Frames : Natural := 0;
         Slots  : Natural := 0;
         Top    : Natural := 0;

         --  Which region was running when the handler was set. A raise that
         --  jumps out of a block leaves that block behind, and a strand that
         --  went on thinking it was still inside one would give what it
         --  started afterwards to a region already left.
         Region : Natural := 0;
      end record;

      ------------------------------------------------------------------
      --  Strands.
      --
      --  Everything above is the *current* strand's registers, and they stay
      --  ordinary variables so that the interpreter reads as one machine
      --  rather than as a machine with a subscript on every line. A switch
      --  saves them into the strand being left and loads the one being
      --  entered, which is what a context switch is.
      ------------------------------------------------------------------

      type Strand_State is
        (
         --  Nothing here. A strand that has never been started.
         Idle,

         --  Runnable.
         Ready,

         --  Waiting for a barrier to open.
         Waiting,

         --  Waiting for a time to arrive.
         Sleeping,

         --  Waiting at an entry for the task to accept.
         Calling,

         --  Taken by an acceptor, and waiting for it to finish.
         Met,

         --  Waiting for a caller at an entry.
         Accepting,

         --  Waiting for the strands it started to end.
         Joining,

         --  Ran to its end.
         Done);

      type Frame_Store is array (1 .. Max_Frames) of Activation;
      type Guard_Store is array (1 .. Max_Guards) of Guard;

      --  The running strand's registers.
      Frames      : Frame_Store;
      Frames_Used : Natural := 0;
      Guards      : Guard_Store;
      Guards_Used : Natural := 0;

      --  What one strand is waiting to accept, offered alternative by
      --  alternative.
      type Offer_List is array (1 .. Max_Offers) of Natural;

      type Strand is record
         State : Strand_State := Idle;

         Point       : Natural := 0;
         Top         : Natural := 0;
         Ceiling     : Natural := 0;
         Slots_Used  : Natural := 0;
         Slots_Limit : Natural := 0;
         Frames      : Frame_Store;
         Frames_Used : Natural := 0;
         Guards      : Guard_Store;
         Guards_Used : Natural := 0;

         --  Which protected object's entry queue it is in, and where to go
         --  back to when it wakes. The object is set when it joins the queue
         --  and cleared when it is through the barrier, which is longer than
         --  it is asleep: a strand woken and about to ask the barrier again is
         --  still queued, and `'Count` says so.
         Object : Natural := 0;
         Entry_At : Natural := 0;

         --  When it wakes, when it is Sleeping. A monotonic clock rather than
         --  a calendar one: a script that waits half a second should wait half
         --  a second whatever somebody does to the system time.
         Until_Then : Ada.Real_Time.Time := Ada.Real_Time.Time_First;

         --  Which routine it is running, so that an abort naming a task can
         --  find the strand running it.
         Runs : Natural := 0;

         --  A rendezvous in progress or waited for. For a caller: which task
         --  and which entry it is calling, and where its arguments are. For an
         --  acceptor: which entry it is waiting at.
         Calls_Task  : Natural := 0;
         Calls_Entry : Natural := 0;
         Arguments   : Natural := 0;

         --  When it joined the entry queue, so that callers are taken in the
         --  order they arrived rather than in the order the array happens to
         --  be walked.
         Queued_At : Natural := 0;

         --  Which strand started it, and from which of that strand's frames.
         --
         --  A master is a *region*, not a strand: Ada has a subprogram wait
         --  for what it declared before it returns, and a submission that
         --  waited for all of it at the end would let a frame be dropped while
         --  something was still reading through it. The frame is the region
         --  the machine can see, so it is the one it waits for.
         Master        : Natural := 0;
         Master_Frame  : Natural := 0;

         --  Which region of that frame. Zero for the frame's own, and a
         --  number of its own for each block statement inside it: a block is
         --  a master in Ada and makes no frame here, so the frame alone
         --  cannot say which of them a task belongs to.
         Master_Region : Natural := 0;

         --  The region this strand is running in now.
         Region : Natural := 0;

         --  Which of its own frames it is waiting for, while it is Joining,
         --  which region of it -- zero for every region, which is what a frame
         --  being left waits for -- and whether frames inside that one count
         --  too, which is what a raise asks.
         Joins_Frame  : Natural := 0;
         Joins_Region : Natural := 0;
         Joins_Deeper : Boolean := False;

         --  A task whose ending ends this strand's wait, for
         --  `select ... then abort`. Zero when it is waiting on nothing but
         --  its own reason.
         Cancels_On : Natural := 0;

         --  How long it has had turns for, which is not how long it has
         --  existed: a task that spends its life at a barrier has used none of
         --  it.
         Ran_Time : Ada.Real_Time.Time_Span := Ada.Real_Time.Time_Span_Zero;

         --  What it runs at. A strand of higher priority is preferred to one
         --  of lower whenever the machine chooses which runs next; among equal
         --  ones nothing changes, which is what keeps a program with no
         --  priorities in it interleaving exactly as it did.
         Priority : Natural := Default_Priority;

         --  Whether the call this strand is queued with may still be taken
         --  back.
         --
         --  Ada's `with abort` on a requeue, and the reason it is written: a
         --  call moved to another queue is a call the caller never made, so
         --  whether the caller may still give up on it is the requeueing
         --  body's to say. Without `with abort` it may not -- a deadline
         --  stops applying and an abandoned trigger no longer pulls it out.
         Can_Give_Up : Boolean := True;

         --  When a bounded entry call gives up, and whether this call is one.
         --
         --  Ada cancels a timed call that has not been *started* by then, so
         --  the deadline stops mattering the moment the rendezvous begins --
         --  which is why this is asked of a caller still queued and of nobody
         --  else.
         Calls_Until : Ada.Real_Time.Time := Ada.Real_Time.Time_First;
         Calls_Timed : Boolean := False;

         --  What this strand would take if somebody called it now, and how
         --  many there are.
         --
         --  Written down where the alternatives are offered and kept while
         --  the strand is set aside waiting for a caller, because that is
         --  exactly when somebody may ask: a conditional call is a question
         --  about what the task it calls is waiting for at this instant, and
         --  a task that is running is not waiting for anything.
         Open_At    : Offer_List := [others => 0];
         Open_Count : Natural := 0;

         --  Whether the entry call this strand last made was met. Read by the
         --  instruction that answers for a call which was given a deadline or
         --  made only if it could be met at once.
         Call_Met : Boolean := False;

         --  Whether this strand is asleep inside a selective accept's own
         --  wait, rather than in a delay of its own.
         --
         --  The difference is who may end it. A `delay` waits for the clock
         --  and nothing else; a select waiting `or delay D` is waiting for a
         --  caller *or* the clock, so a caller arriving cuts the wait short.
         Naps_In_Select : Boolean := False;

         --  Whether this strand is waiting at a select that says it may end
         --  instead, and where to go when it may.
         May_Terminate : Boolean := False;
         Ends_At       : Natural := 0;

         --  Whether it is choosing among a selective accept's alternatives,
         --  which entry the choice settled on, and which caller settled it.
         --
         --  Kept on the strand because a select is a strand's own business:
         --  two tasks may be in one at the same moment, over the same entries
         --  of two objects of one task type.
         Choosing      : Boolean := False;
         Chosen        : Natural := 0;
         Chosen_Caller : Natural := 0;

         --  Whether it has run its body out. Between that and the end of it
         --  there is the wait for what depends on it, and a task waiting there
         --  has completed without having terminated -- which is the whole of
         --  the difference between Ada's two questions about one.
         Completed : Boolean := False;

         --  An exception this strand is to raise where it next runs.
         --
         --  Ada re-raises at the point of an entry call what the accept body
         --  failed with, and the caller is not running when that happens: it
         --  is set aside in the rendezvous. So the exception is carried to it
         --  and raised where it resumes, which is the point of the call --
         --  the same place a caller would have raised it had the entry been a
         --  procedure.
         Pending        : Boolean := False;
         Pending_Name   : Unbounded_String := Null_Unbounded_String;
         Pending_Detail : Adash.Messages.Message_Id :=
           Adash.Messages.Msg_Error_None;
         Pending_Filled : Natural := 0;
         Pending_Given  : Detail_Values :=
           [others => Null_Unbounded_String];
      end record;

      Strands : array (1 .. Max_Strands) of Strand;

      --  Which one is running. One always is: the environment task, which is
      --  the submission itself, and which is strand one.
      Me : Positive := 1;

      --  How many instructions a strand runs before the machine looks for
      --  another. A quantum rather than a switch per instruction, because
      --  switching is saving and loading a register set and a program that did
      --  it every instruction would spend its life doing it.
      --
      --  Fixed rather than timed, so that a program interleaves the same way
      --  on every machine and a conformance case can say what it printed.
      Quantum : constant := 64;
      Ran_For : Natural := 0;

      --  What the next task started will run at, said by the instruction
      --  before it and put back to the default afterwards -- so a task that
      --  says nothing about its priority gets the default rather than
      --  whatever the last one that did say asked for.
      Starting_Priority : Natural := Default_Priority;

      --  What each protected object's ceiling is. Set where the object is
      --  elaborated and wherever a program assigns to its `'Priority`: the
      --  ceiling lives with the object rather than in the instruction that
      --  takes its lock, because a program may change it and every operation
      --  has to be asking the same question.
      Ceilings : array (1 .. Max_Objects) of Natural :=
        [others => Highest_Priority];

      --  Whether this run has ever started a task.
      --
      --  Every return asks whether anything depends on the frame it is
      --  leaving, and a run with no tasks in it must not pay for one that has
      --  them: this is the one comparison that answers for all of them.
      Started_Any : Boolean := False;

      --  How many callers have queued, ever. What gives each its place in the
      --  order.
      Queued : Natural := 0;

      --  Which protected object the current strand holds, or zero. One at a
      --  time is enough: a protected operation that called another would be a
      --  second lock, and Ada's own rules make that a bounded error.
      Holding : Natural := 0;

      procedure Push (Value : Cell);

      --  Stop, saying what went wrong and where the fault lies.
      procedure Fail
        (What   : Outcome;
         Name   : String;
         Detail : Adash.Messages.Message_Id := Adash.Messages.Msg_Error_None;
         Given  : Detail_Values := [others => Null_Unbounded_String];
         Filled : Natural := 0);

      --  Text for a detail's placeholder.
      --
      --  Numbers arrive as Ada spells them, with the leading space `Image`
      --  puts on a positive one. A message reading `position  9` would be this
      --  package deciding how a number looks, which is not its decision.
      function Counted (Value : Whole_Number) return Unbounded_String;
      function Counted (Value : Natural) return Unbounded_String;

      function Counted (Value : Whole_Number) return Unbounded_String is
         Text : constant String := Whole_Number'Image (Value);
      begin
         return To_Unbounded_String
           (if Text (Text'First) = ' '
            then Text (Text'First + 1 .. Text'Last) else Text);
      end Counted;

      function Counted (Value : Natural) return Unbounded_String is
      begin
         return Counted (Whole_Number (Value));
      end Counted;

      procedure Fail
        (What   : Outcome;
         Name   : String;
         Detail : Adash.Messages.Message_Id := Adash.Messages.Msg_Error_None;
         Given  : Detail_Values := [others => Null_Unbounded_String];
         Filled : Natural := 0)
      is
      begin
         --  A rendezvous this strand was in the middle of ends here, and ends
         --  for the caller too. Ada re-raises at the point of the entry call
         --  what the accept body failed with, and releases the caller: it
         --  asked for a piece of work and is owed the answer, and being left
         --  queued for ever is not one.
         --
         --  Carried rather than raised, because the caller is not running:
         --  what is set aside cannot raise, so the exception waits with it and
         --  is raised where it resumes.
         if What = Raised then
            for Which in Strands'Range loop
               if Strands (Which).State = Met
                 and then Strands (Which).Calls_Task = Me
               then
                  Strands (Which).State          := Ready;
                  Strands (Which).Calls_Task     := 0;
                  Strands (Which).Calls_Entry    := 0;
                  Strands (Which).Pending        := True;
                  Strands (Which).Pending_Name   := To_Unbounded_String (Name);
                  Strands (Which).Pending_Detail := Detail;
                  Strands (Which).Pending_Filled := Filled;
                  Strands (Which).Pending_Given  := Given;
               end if;
            end loop;
         end if;

         --  A raise with a handler waiting is not the end of the run. Unwind
         --  to where that handler was set: the frames and operands of
         --  everything between are gone, which is what lets a handler in an
         --  outer block catch what an inner call raised.
         --
         --  Only an exception is caught. A machine that could not go on --
         --  Broken -- is a defect here rather than in the program, and a
         --  handler catching it would hide the one thing worth reporting.
         if What = Raised and then Guards_Used > 0 then
            declare
               Caught : constant Guard := Guards (Guards_Used);
            begin
               Guards_Used := Guards_Used - 1;

               Frames_Used := Caught.Frames;
               Slots_Used  := Caught.Slots;
               Top         := Caught.Top;
               Strands (Me).Region := Caught.Region;

               --  What was raised, for the handler to choose on, and what it
               --  said, so a handler that re-raises loses neither.
               Push ((Cell_Text, To_Unbounded_String (Name)));
               Push ((Cell_Detail, Detail, Filled, Given));

               Point := Caught.Target;
               return;
            end;
         end if;

         Produced.What := What;
         Produced.Raised_Name := To_Unbounded_String (Name);
         Produced.Detail := Detail;
         Produced.Detail_Count := Filled;
         Produced.Detail_Given := Given;
         Finished := True;
      end Fail;

      procedure Push (Value : Cell) is
      begin
         if Top >= Strands (Me).Ceiling then
            Fail (Broken, "Storage_Error", M.Msg_Machine_Stack_Full);
            return;
         end if;

         Top := Top + 1;
         Stack (Top) := Value;
      end Push;

      function Pop return Cell;

      function Pop return Cell is
      begin
         if Top = 0 then
            Fail (Broken, "Program_Error", M.Msg_Machine_Stack_Empty);
            return (Kind => Cell_None);
         end if;

         Top := Top - 1;
         return Stack (Top + 1);
      end Pop;

      --  The frame a Level_Diff of static links out from the current one.
      function Outward (Steps : Natural) return Natural;

      function Outward (Steps : Natural) return Natural is
         Where : Natural := Frames_Used;
      begin
         for Unused in 1 .. Steps loop
            exit when Where = 0;
            Where := Frames (Where).Static;
         end loop;

         return Where;
      end Outward;

      --  Where a slot named by an instruction actually is.
      function Slot_At (Level : Natural; Offset : Natural) return Natural;

      function Slot_At (Level : Natural; Offset : Natural) return Natural is
         Where : constant Natural := Outward (Level);
      begin
         if Where = 0 then
            return Offset + 1;
         end if;

         return Frames (Where).Base + Offset + 1;
      end Slot_At;

      --  What a discrete cell is worth, as a number.
      --
      --  Boolean, Character and Integer are all discrete, and the lowering
      --  compares them with one instruction because the language does: what
      --  differs is the type, and the type is settled before anything runs.
      function Discrete (Item : Cell) return Whole_Number;

      function Discrete (Item : Cell) return Whole_Number is
      begin
         case Item.Kind is
            when Cell_Whole  => return Item.Whole;
            when Cell_Truth  => return Whole_Number (Boolean'Pos (Item.Truth));
            when Cell_Letter => return Whole_Number (Character'Pos (Item.Letter));

            --  Which strand runs it, which is what one task *is* here -- so
            --  two of them compare equal when they are the same task and not
            --  otherwise. Without this every task was every other: a cell
            --  with no discrete value answered zero, and zero equals zero.
            when Cell_Task   => return Whole_Number (Item.Strand);

            when others      => return 0;
         end case;
      end Discrete;

      --  The two operands of a binary operation, in the order written.
      procedure Two (Left : out Cell; Right : out Cell);

      procedure Two (Left : out Cell; Right : out Cell) is
      begin
         Right := Pop;
         Left := Pop;
      end Two;

      --  Put the running registers away, and take another strand's out.
      procedure Save_Into (Which : Positive);
      procedure Load_From (Which : Positive);

      --  When the strand now running was given its turn, so that what it has
      --  run for can be added up when the turn ends.
      Turn_Began : Ada.Real_Time.Time := Ada.Real_Time.Clock;

      procedure Save_Into (Which : Positive) is
         use type Ada.Real_Time.Time;
         use type Ada.Real_Time.Time_Span;

         Now : constant Ada.Real_Time.Time := Ada.Real_Time.Clock;
      begin
         --  The turn that is ending, added to what this strand has run for.
         --  Here because this is where a turn ends: every switch saves the
         --  strand it is leaving, and nothing else does.
         Strands (Which).Ran_Time :=
           Strands (Which).Ran_Time + (Now - Turn_Began);
         Turn_Began := Now;

         Strands (Which).Point       := Point;
         Strands (Which).Top         := Top;
         Strands (Which).Slots_Used  := Slots_Used;
         Strands (Which).Frames      := Frames;
         Strands (Which).Frames_Used := Frames_Used;
         Strands (Which).Guards      := Guards;
         Strands (Which).Guards_Used := Guards_Used;
      end Save_Into;

      procedure Load_From (Which : Positive) is
      begin
         Turn_Began := Ada.Real_Time.Clock;

         Point       := Strands (Which).Point;
         Top         := Strands (Which).Top;
         Slots_Used  := Strands (Which).Slots_Used;
         Frames      := Strands (Which).Frames;
         Frames_Used := Strands (Which).Frames_Used;
         Guards      := Strands (Which).Guards;
         Guards_Used := Strands (Which).Guards_Used;
      end Load_From;

      --  Whether a strand may run now.
      function Runnable (Which : Positive) return Boolean;

      --  Whether this strand's queued call still has a deadline that applies.
      --
      --  A call requeued without `with abort` keeps its place and loses its
      --  way out, so the deadline it was made with stops being one.
      --
      --  @param Which The caller.
      --  @return Whether it may still give up when the time comes.
      function Giving_Up (Which : Positive) return Boolean
      is (Strands (Which).Calls_Timed and then Strands (Which).Can_Give_Up);

      --  Whether a rendezvous with this task at this entry could start now.
      --
      --  What a conditional call asks. A task that is waiting for a caller
      --  wrote down what it would take when it offered its alternatives, and
      --  a task that is doing anything else is not waiting for anybody --
      --  which is the whole answer, because a task set aside at an accept
      --  cannot have a caller queued at an entry it is open for: queueing one
      --  wakes it.
      --
      --  @param Whom The task called.
      --  @param Wanted Which entry of it.
      --  @return Whether the call would be taken at once.
      function Ready_To_Meet (Whom : Positive; Wanted : Natural)
                             return Boolean
      is ((Strands (Whom).State = Accepting
           or else (Strands (Whom).State = Sleeping
                    and then Strands (Whom).Naps_In_Select))
          and then (for some Index in 1 .. Strands (Whom).Open_Count =>
                      Strands (Whom).Open_At (Index) = Wanted));

      --  Whether a caller is still there to be taken.
      --
      --  A call given a deadline is cancelled when the deadline passes, and
      --  the caller says so for itself when it next runs -- so between the
      --  clock passing and the caller running there is a moment where it is
      --  queued and no longer callable. Ada cancels at the deadline, so this
      --  answers for that moment rather than leaving it to who ran first.
      --
      --  @param Which The caller.
      --  @return Whether a rendezvous with it may still start.
      function Still_Waiting (Which : Positive) return Boolean
      is (not Giving_Up (Which)
          or else Ada.Real_Time."<" (Ada.Real_Time.Clock,
                                     Strands (Which).Calls_Until));

      --  Which of two callers waiting at one entry is ahead of the other.
      --
      --  The order they arrived in, unless the program said priority -- and
      --  then still the order they arrived in among callers of equal
      --  priority, which is what makes it an ordering rather than a lottery.
      --
      --  @param Left One caller.
      --  @param Right The other.
      --  @return Whether Left is ahead of Right.
      function Comes_First (Left : Positive; Right : Positive) return Boolean
      is (if Item.By_Priority
            and then Strands (Left).Priority /= Strands (Right).Priority
          then Strands (Left).Priority > Strands (Right).Priority
          else Strands (Left).Queued_At < Strands (Right).Queued_At);

      --  Give another strand a turn, if there is one that can take it.
      --
      --  Round robin from the one after the current, so that a strand cannot
      --  starve the others by being early in the array. Nothing happens when
      --  the current strand is the only runnable one, which is the common case
      --  and has to cost nothing.
      procedure Yield;

      --  Whether every strand started from one region has ended.
      --
      --  @param Of_Strand The master.
      --  @param Of_Frame Which of its frames, zero for the outermost region.
      --  @param Of_Region Which region of that frame, and every region opened
      --         after it -- so zero is every one of them, which is what a
      --         frame being left asks. Regions are numbered in the order they
      --         are entered, so one opened inside another has the larger
      --         number: a block waits for what it started and for what
      --         anything inside it started, including a block that an
      --         exception jumped out of before it could wait for its own.
      --  @param Deeper Whether frames inside that one count too, which is
      --         what a raise asks: it may have left several frames at once,
      --         and each of them is a master that never reached its own way
      --         out.
      function Dependents_Done
        (Of_Strand : Positive;
         Of_Frame  : Natural;
         Of_Region : Natural := 0;
         Deeper    : Boolean := False) return Boolean;

      function Dependents_Done
        (Of_Strand : Positive;
         Of_Frame  : Natural;
         Of_Region : Natural := 0;
         Deeper    : Boolean := False) return Boolean is
      begin
         --  Nothing was ever started, so nothing depends on anything. Asked
         --  first because every return asks this question and a run with no
         --  tasks in it must not pay for one that has them.
         if not Started_Any then
            return True;
         end if;

         for Which in Strands'Range loop
            if Strands (Which).Master = Of_Strand
              and then
                ((Deeper and then Strands (Which).Master_Frame > Of_Frame)
                 or else (Strands (Which).Master_Frame = Of_Frame
                          and then Strands (Which).Master_Region
                                   >= Of_Region))
              and then Strands (Which).State /= Done
              and then Strands (Which).State /= Idle
            then
               return False;
            end if;
         end loop;

         return True;
      end Dependents_Done;

      function Runnable (Which : Positive) return Boolean is
      begin
         case Strands (Which).State is
            when Ready =>
               return True;

            when Joining =>
               return Dependents_Done (Which,
                                       Strands (Which).Joins_Frame,
                                       Strands (Which).Joins_Region,
                                       Strands (Which).Joins_Deeper);

            when Sleeping =>
               --  Its own clock rather than somebody else's doing: a delay
               --  ends when the time comes, whatever the other strands are up
               --  to -- unless it is watching a task, in which case that task
               --  ending is the other way it ends.
               return Ada.Real_Time.">=" (Ada.Real_Time.Clock,
                                          Strands (Which).Until_Then)
                 or else (Strands (Which).Cancels_On /= 0
                          and then Strands (Strands (Which).Cancels_On).State
                                   = Done);

            when Calling =>
               --  A caller waits to be taken, and one that gave itself a
               --  deadline waits only that long: when the time comes it runs
               --  again to leave the queue and say so.
               return Giving_Up (Which)
                 and then Ada.Real_Time.">=" (Ada.Real_Time.Clock,
                                              Strands (Which).Calls_Until);

            when Waiting =>
               --  Waiting on a barrier, which somebody else opens -- unless
               --  it gave itself a deadline, and then the clock is the other
               --  thing it waits for. It wakes to give up rather than to be
               --  let through: what the deadline cancels is a call whose
               --  entry body has not started.
               return Giving_Up (Which)
                 and then Ada.Real_Time.">=" (Ada.Real_Time.Clock,
                                              Strands (Which).Calls_Until);

            when Idle | Met | Accepting | Done =>
               --  A waiting strand is woken when the object it waits on is
               --  left, not by being looked at here: a barrier is a condition
               --  on state somebody else changes, and polling it would run the
               --  barrier's own code at moments the program did not reach.
               return False;
         end case;
      end Runnable;

      --  Hand Tasking_Error to a strand waiting at an entry of a task that
      --  has ended.
      --
      --  Ada's answer to a call that can never be met, and raised where the
      --  call left off: the caller is resumed there, so a handler around the
      --  call catches it exactly as one around any other call would. The
      --  current strand is left where it was and will be picked up again.
      --
      --  @param Of_Task The routine the ended task was running.
      --  @return True when a caller was found and given it.
      function Strand_A_Caller (Of_Task : Natural) return Boolean;

      function Strand_A_Caller (Of_Task : Natural) return Boolean is
         Stranded : Natural := 0;
      begin
         --  A call whose caller was waiting for *this* task to end is not a
         --  call that failed: it is `select ... then abort` saying the trigger
         --  is cancelled because the abortable part finished first. Taken out
         --  of the queue and let go, with nothing raised -- what it does next
         --  is ask whether the task ended, which is how it tells the two
         --  outcomes apart.
         --
         --  Both kinds of queue, because a trigger may be a call to either.
         --  A caller of a *task* entry is parked in a queue and leaves it by
         --  being written out of it. A caller of a *protected* entry is parked
         --  inside that entry's own body, at its barrier, and leaves by
         --  returning from it without running it -- which is the same unwind a
         --  return does, done to a strand that is not the one running.
         for Which in Strands'Range loop
            if Strands (Which).Cancels_On = Of_Task
              and then Strands (Which).Can_Give_Up
            then
               if Strands (Which).State = Calling then
                  Strands (Which).State       := Ready;
                  Strands (Which).Calls_Task  := 0;
                  Strands (Which).Calls_Entry := 0;

               elsif Strands (Which).State = Waiting
                 and then Strands (Which).Frames_Used > 0
               then
                  declare
                     Leaving : constant Natural :=
                       Strands (Which).Frames_Used;
                  begin
                     Strands (Which).State :=  Ready;
                     Strands (Which).Slots_Used :=
                       Strands (Which).Frames (Leaving).Base;
                     Strands (Which).Point :=
                       Strands (Which).Frames (Leaving).Return_To;
                     Strands (Which).Frames_Used := Leaving - 1;
                     Strands (Which).Object      := 0;
                     Strands (Which).Calls_Entry := 0;
                  end;
               end if;
            end if;
         end loop;

         for Which in Strands'Range loop
            if Strands (Which).State = Calling
              and then Strands (Which).Calls_Task = Of_Task
            then
               Stranded := Which;
               exit;
            end if;
         end loop;

         if Stranded = 0 then
            return False;
         end if;

         Save_Into (Me);
         Me := Stranded;
         Strands (Me).State := Ready;
         Load_From (Me);
         Ran_For := 0;
         Fail (Raised, "Tasking_Error", M.Msg_Machine_Task_Finished);
         return True;
      end Strand_A_Caller;

      --  Which entry an instruction names.
      --
      --  Level is the entry, or the first of a family; Operand says whether
      --  the member's offset within that family is on the stack. Popping it
      --  here rather than at each opcode keeps the two spellings one question.
      --
      --  @param Named The instruction.
      --  @return The entry it names.
      function Entry_Named (Named : Instruction) return Natural;

      function Entry_Named (Named : Instruction) return Natural is
      begin
         --  The operand carries more than one answer: whether an offset
         --  within a family is on the stack is the first of them, and a call
         --  says in the second whether a deadline was pushed under everything
         --  else. Only the first is this question's business.
         if Named.Operand mod 2 = 0 then
            return Named.Level;
         end if;

         return Named.Level + Natural (Discrete (Pop));
      end Entry_Named;

      --  Whether any strand other than this one has been set aside waiting
      --  for something another strand has to do.
      --
      --  Asked when nothing can run: a strand ending is the end of the run
      --  only if nobody is left waiting. One that is waiting on a barrier, at
      --  an entry, or for a rendezvous is waiting for something that will now
      --  never happen, and stopping quietly would leave a program abandoned
      --  in the middle of a statement with nothing said about it.
      function Set_Aside_Elsewhere return Boolean;

      function Set_Aside_Elsewhere return Boolean is
      begin
         for Which in Strands'Range loop
            if Which /= Me
              and then Strands (Which).State in Waiting | Calling
                                                | Met | Accepting
            then
               return True;
            end if;
         end loop;

         return False;
      end Set_Aside_Elsewhere;

      --  Another strand that can run, waiting for the clock if that is all
      --  that stands in the way.
      --
      --  Sleeping is not stuck. A strand waiting for a time will run when the
      --  time comes, so a machine with nothing else to do waits for it rather
      --  than reporting a program that cannot go on -- and waits by sleeping
      --  rather than by spinning.
      function Pick_Next return Natural;

      --  The runnable strand of highest priority, or zero.
      --
      --  Ties go to whichever comes first in the scan, which is what this did
      --  before priorities existed -- so a program that mentions none
      --  interleaves exactly as it did.
      function Best_Runnable return Natural;

      function Best_Runnable return Natural is
         Best : Natural := 0;
      begin
         for Which in Strands'Range loop
            if Which /= Me and then Runnable (Which)
              and then (Best = 0
                        or else Strands (Which).Priority
                                > Strands (Best).Priority)
            then
               Best := Which;
            end if;
         end loop;

         return Best;
      end Best_Runnable;

      --  Let every task waiting at a terminate alternative end, if between
      --  them they are all that is left.
      --
      --  Ada's condition, said in this machine's terms: the master each of
      --  them depends on has finished its own work and is waiting for what
      --  depends on it, and every task that is not over is either waiting at
      --  one of these alternatives or is such a master. Anything else -- a
      --  task computing, sleeping, queued at an entry, waiting on a barrier --
      --  is something that could still call, so nobody ends.
      --
      --  Asked only when nothing can run and nothing is waiting for the
      --  clock, which is exactly when the question has an answer.
      --
      --  @return A strand to run, or zero when nobody may end.
      function Let_Them_End return Natural;

      function Let_Them_End return Natural is
         Willing : Natural := 0;
      begin
         for Which in Strands'Range loop
            case Strands (Which).State is
               when Done | Idle =>
                  null;

               when Accepting =>
                  if not Strands (Which).May_Terminate then
                     return 0;
                  end if;

                  Willing := Which;

               when Joining =>
                  --  A master with something still depending on it. If that
                  --  something is only the willing ones, it goes on when they
                  --  are over.
                  null;

               when others =>
                  return 0;
            end case;
         end loop;

         if Willing = 0 then
            return 0;
         end if;

         for Which in Strands'Range loop
            if Strands (Which).State = Accepting
              and then Strands (Which).May_Terminate
            then
               Strands (Which).State := Ready;
               Strands (Which).Point := Strands (Which).Ends_At;
            end if;
         end loop;

         return Willing;
      end Let_Them_End;

      function Pick_Next return Natural is
         use type Ada.Real_Time.Time;
         --  Initialised so that GNAT can see it is never read unset: the
         --  first sleeper found writes it, and nothing reads it before Found.
         Soonest : Ada.Real_Time.Time := Ada.Real_Time.Time_First;
         Found   : Boolean := False;

         Ready_Now : constant Natural := Best_Runnable;
      begin
         if Ready_Now /= 0 then
            return Ready_Now;
         end if;

         --  The earliest wake among *every* sleeper, this one included. A
         --  scan that skipped the current strand would sleep past its own
         --  deadline whenever another strand had a later one -- which is how a
         --  task waiting a tenth of a second waited a whole one because
         --  something else was waiting that long.
         for Which in Strands'Range loop
            if Strands (Which).State = Sleeping then
               if not Found or else Strands (Which).Until_Then < Soonest then
                  Soonest := Strands (Which).Until_Then;
                  Found   := True;
               end if;

            --  A caller waiting a bounded time is waiting for the clock as
            --  much as a sleeper is. Left out, a program whose every other
            --  strand was set aside would be called stuck a moment before the
            --  wait it wrote ran out.
            elsif Strands (Which).State in Calling | Waiting
              and then Giving_Up (Which)
            then
               if not Found or else Strands (Which).Calls_Until < Soonest then
                  Soonest := Strands (Which).Calls_Until;
                  Found   := True;
               end if;
            end if;
         end loop;

         if not Found then
            --  Nothing to run and nothing to wait for. If what is left is
            --  tasks that said they would rather end than wait, this is the
            --  moment they were waiting for.
            declare
               Ending : constant Natural := Let_Them_End;
            begin
               if Ending = 0 then
                  return 0;
               end if;

               declare
                  Other : constant Natural := Best_Runnable;
               begin
                  return (if Other /= 0 then Other else Ending);
               end;
            end;
         end if;

         delay until Soonest;

         declare
            Other : constant Natural := Best_Runnable;
         begin
            if Other /= 0 then
               return Other;
            end if;

            --  Nobody else, and the wait was this strand's own: a caller
            --  whose deadline has come is the one thing that can run, and
            --  answering zero here would call it stuck a moment after it
            --  stopped being.
            return (if Runnable (Me) then Me else 0);
         end;
      end Pick_Next;

      --  Wait here until the region being left has no dependents.
      --
      --  Ada's rule about masters, and the machine is where it belongs: a
      --  master is a region, every way of leaving one goes through an
      --  instruction, and a rule written at each of those would be the same
      --  rule three times. It re-executes the instruction when it wakes, so
      --  what asks the question again is the thing that asked it.
      --
      --  @return True when the caller must give up its turn.
      function Wait_For_Dependents return Boolean;

      --  Region numbers, handed out in order. Unique within a run, which is
      --  all that telling two of them apart needs.
      Regions_Made : Natural := 0;

      --  Wait here until one region of the frame being left has no dependents.
      --
      --  @param Of_Region Which region, or zero for every one of them.
      --  @return True when the caller must give up its turn.
      function Wait_For_Region (Of_Region : Natural) return Boolean;

      --  Wait for what a raise abandoned: every region inside the one it
      --  landed in, and every frame inside the one it landed in.
      --
      --  @return True when the caller must give up its turn.
      function Wait_For_Abandoned return Boolean;

      function Wait_For_Abandoned return Boolean is
      begin
         if Holding /= 0 then
            return False;
         end if;

         --  Regions are numbered in the order they are entered, so everything
         --  inside the one this landed in has a larger number.
         if Dependents_Done (Me, Frames_Used, Strands (Me).Region + 1,
                             Deeper => True)
         then
            return False;
         end if;

         Strands (Me).State        := Joining;
         Strands (Me).Joins_Frame  := Frames_Used;
         Strands (Me).Joins_Region := Strands (Me).Region + 1;
         Strands (Me).Joins_Deeper := True;
         Point := Point - 1;
         Save_Into (Me);

         declare
            Next : constant Natural := Pick_Next;
         begin
            if Next = 0 then
               Fail (Broken, "Program_Error", M.Msg_Machine_Tasks_Stuck);
            else
               Me := Next;

               if Strands (Me).State in Joining | Sleeping then
                  Strands (Me).State := Ready;
               end if;

               Load_From (Me);
               Ran_For := 0;
            end if;
         end;

         return True;
      end Wait_For_Abandoned;

      function Wait_For_Region (Of_Region : Natural) return Boolean is
      begin
         --  Never inside a protected operation, for the reason given in
         --  Wait_For_Dependents.
         if Holding /= 0 then
            return False;
         end if;

         if Dependents_Done (Me, Frames_Used, Of_Region) then
            --  The region is being left and everything it started has
            --  finished, so those strands are free to be somebody else.
            --
            --  Here rather than where a task ends, because here is where it is
            --  known that nothing can still name it: the task object holding
            --  its number is going out of scope with the region that declared
            --  it, and a strand recycled while a value still named it would be
            --  aborted or called by mistake.
            for Which in Strands'Range loop
               if Strands (Which).Master = Me
                 and then Strands (Which).Master_Frame = Frames_Used
                 and then Strands (Which).Master_Region >= Of_Region
                 and then Strands (Which).State = Done
               then
                  Strands (Which).State := Idle;
               end if;
            end loop;

            return False;
         end if;

         Strands (Me).State        := Joining;
         Strands (Me).Joins_Frame  := Frames_Used;
         Strands (Me).Joins_Region := Of_Region;
         Strands (Me).Joins_Deeper := False;
         Point := Point - 1;
         Save_Into (Me);

         declare
            Next : constant Natural := Pick_Next;
         begin
            if Next = 0 then
               Fail (Broken, "Program_Error", M.Msg_Machine_Tasks_Stuck);
            else
               Me := Next;

               if Strands (Me).State in Joining | Sleeping then
                  Strands (Me).State := Ready;
               end if;

               Load_From (Me);
               Ran_For := 0;
            end if;
         end;

         return True;
      end Wait_For_Region;

      function Wait_For_Dependents return Boolean is
      begin
         --  Never inside a protected operation. Not changing strand there is
         --  what makes one mutually exclusive, and a wait that broke it would
         --  be worse than one that is skipped -- Ada calls starting a task
         --  inside a protected action potentially blocking and forbids it, so
         --  what is skipped here is a wait no correct program asks for.
         if Holding /= 0 then
            return False;
         end if;

         --  Every region of it, because leaving a frame leaves every block
         --  inside it too. What it waits for that can never end is reported
         --  rather than hung on, which is what every other wait here does.
         return Wait_For_Region (0);
      end Wait_For_Dependents;

      procedure Yield is
         Next : Natural := 0;
      begin
         --  Never inside a protected operation. Not changing strand there is
         --  what makes one mutually exclusive, and it is the whole of the
         --  implementation rather than an optimisation.
         if Holding /= 0 then
            return;
         end if;

         --  Round robin from the one after this, so that a strand cannot
         --  starve the others by being early in the array -- and among those,
         --  the highest priority. A turn ending is a choice of who runs next
         --  like any other, so the same preference applies.
         for Step in 1 .. Max_Strands - 1 loop
            declare
               Try : constant Positive :=
                 (if Me + Step > Max_Strands then Me + Step - Max_Strands
                  else Me + Step);
            begin
               if Runnable (Try)
                 and then (Next = 0
                           or else Strands (Try).Priority
                                   > Strands (Next).Priority)
               then
                  Next := Try;
               end if;
            end;
         end loop;

         if Next = 0 then
            return;
         end if;

         if Strands (Me).State = Ready or else Strands (Me).State = Joining
         then
            Save_Into (Me);
         end if;

         Me := Next;

         if Strands (Me).State = Joining
           and then Dependents_Done (Me, Strands (Me).Joins_Frame,
                                     Strands (Me).Joins_Region,
                                     Strands (Me).Joins_Deeper)
         then
            Strands (Me).State := Ready;
         elsif Strands (Me).State = Sleeping then
            Strands (Me).State := Ready;
         end if;

         Load_From (Me);
         Ran_For := 0;
      end Yield;

      Here : Instruction;

   begin
      Produced := (What => Ran, others => <>);

      if Item.Code = null or else Item.Code_Used = 0 then
         return;
      end if;

      --  The outermost frame, which outlives the run: what a submission
      --  declared is read out of it afterwards.
      Slots_Used := Item.Frame;

      --  The environment task, which is the submission itself.
      Strands (1).State       := Ready;
      Strands (1).Ceiling     := Max_Stack - (Max_Strands - 1) * Task_Stack;
      Strands (1).Slots_Limit := Max_Slots - (Max_Strands - 1) * Task_Slots;

      for Index in 1 .. Slots_Used loop
         Slots (Index) := (Kind => Cell_None);
      end loop;

      while not Finished and then Point in 1 .. Item.Code_Used loop
         Counter := Counter + 1;
         Ran_For := Ran_For + 1;

         --  A turn ends after so many instructions. Fixed rather than timed,
         --  so that a program interleaves the same way on every machine and a
         --  conformance case can say what it printed.
         --
         --  Unless the program said first-in-first-out within a priority, in
         --  which case a strand keeps its turn until it waits for something:
         --  that is what Ada's policy means on one processor, and an
         --  interleaving nobody slices is one a reader can follow.
         --  Asked of the priority the running strand is at, because a
         --  program may have given the policy to a range: a strand at 20 may
         --  keep its turn while one at 5 does not.
         if not Item.Uninterrupted (Strands (Me).Priority)
           and then Ran_For >= Quantum
         then
            Yield;
         end if;

         --  Asked between instructions rather than inside one: a program that
         --  cannot be interrupted is one runaway loop away from ending the
         --  session.
         if Counter mod 1_024 = 0
           and then On_Host /= null
           and then On_Host.Stop_Requested
         then
            Produced.What := Stopped;
            exit;
         end if;

         --  What this strand was handed while it was set aside, raised where
         --  it resumes. Before the instruction rather than after, so that the
         --  point of the raise is the point of the call.
         if Strands (Me).Pending then
            declare
               Carried : constant String :=
                 To_String (Strands (Me).Pending_Name);
            begin
               Strands (Me).Pending := False;
               Fail (Raised, Carried,
                     Strands (Me).Pending_Detail,
                     Strands (Me).Pending_Given,
                     Strands (Me).Pending_Filled);
            end;

            --  Nothing caught it, so there is nothing left to run.
            exit when Finished;
         end if;

         Here := Item.Code (Point);
         Point := Point + 1;

         --  A potentially blocking operation inside a protected action. Ada
         --  lists them, and this is that list: what they have in common is
         --  that each may set the strand aside, and a strand set aside while
         --  it holds a lock is holding it against everybody.
         --
         --  Asked here rather than at each of them, because what makes one
         --  blocking is not something each has to say about itself -- and a
         --  list in one place is a list that can be read.
         --
         --  An entry's own barrier is not on it: waiting there is how a
         --  protected entry is *meant* to wait, and it gives the lock up to do
         --  so. Nor is a requeue, which is Ada's answer to wanting to wait
         --  without holding anything.
         if Item.Detecting and then Holding /= 0
           and then Here.Code in Delay_For | Delay_Until | Call_Entry
                               | Try_Accept | Await_Caller | Await_Tasks
                               | Start_Task | Abort_Task
         then
            Fail (Raised, "Program_Error",
                  M.Msg_Machine_Blocking_In_Protected);
         end if;

         exit when Finished;

         case Here.Code is
            when Push_Whole =>
               Push ((Kind => Cell_Whole, Whole => Here.Operand));

            when Push_Truth =>
               Push ((Kind => Cell_Truth, Truth => Here.Operand /= 0));

            when Push_Letter =>
               Push ((Kind => Cell_Letter,
                      Letter => Character'Val (Natural (Here.Operand))));

            when Push_Real =>
               Push ((Kind => Cell_Real,
                      Number => Item.Reals (Positive (Here.Operand))));

            when Push_Text =>
               Push ((Kind => Cell_Text,
                      Text => Item.Texts (Positive (Here.Operand))));

            when Load =>
               declare
                  Held : constant Cell :=
                    Slots (Slot_At (Here.Level, Natural (Here.Operand)));
               begin
                  --  A slot that holds nothing is a variable that was never
                  --  given a value. Ada calls reading one erroneous and says
                  --  nothing about what happens; what happens here is a
                  --  failure with a name, because the alternative is a value
                  --  nobody wrote being used as though somebody had.
                  if Held.Kind = Cell_None then
                     Fail (Broken, "Program_Error", M.Msg_Machine_No_Value);
                  else
                     Push (Held);
                  end if;
               end;

            when Load_Indirect =>
               declare
                  Held : constant Cell :=
                    Slots (Slot_At (Here.Level, Natural (Here.Operand)));
               begin
                  if Held.Kind /= Cell_Place then
                     Fail (Broken, "Program_Error", M.Msg_Machine_No_Place);
                  elsif Slots (Held.Place).Kind = Cell_None then
                     Fail (Broken, "Program_Error", M.Msg_Machine_No_Value);
                  else
                     Push (Slots (Held.Place));
                  end if;
               end;

            when Address =>
               Push ((Kind   => Cell_Place,
                      Place  => Slot_At (Here.Level, Natural (Here.Operand)),
                      Extent => 0));

            when Offset_Place =>
               declare
                  Where : constant Cell := Pop;
               begin
                  if Where.Kind /= Cell_Place then
                     Fail (Broken, "Program_Error", M.Msg_Machine_No_Place);
                  else
                     --  The run carries on being however long it was: an
                     --  offset moves the start and says nothing about the
                     --  length, which whoever knows it sets with Run_Of.
                     Push ((Kind   => Cell_Place,
                            Place  => Where.Place + Natural (Here.Operand),
                            Extent => Where.Extent));
                  end if;
               end;

            when Element_Place =>
               declare
                  Wanted : constant Cell := Pop;
                  Where  : constant Cell := Pop;

                  Low  : constant Whole_Number := Item.Bounds (Here.Level);
                  High : constant Whole_Number :=
                    Item.Bounds (Here.Level + 1);
                  Named : constant Natural :=
                    Natural (Item.Bounds (Here.Level + 2));
               begin
                  if Where.Kind /= Cell_Place then
                     Fail (Broken, "Program_Error", M.Msg_Machine_No_Place);
                  elsif Wanted.Whole < Low or else Wanted.Whole > High then
                     --  Checked here rather than at the store, because a read
                     --  is as wrong as a write: an index past the end would
                     --  hand back whatever the next variable holds.
                     Fail (Raised, "Index_Error",
                           M.Msg_Machine_Outside_Array,
                           [Counted (Wanted.Whole),
                            Item.Texts (Named),
                            Null_Unbounded_String],
                           2);
                  else
                     Push ((Kind   => Cell_Place,
                            Place  =>
                              Where.Place
                              + Natural (Wanted.Whole - Low)
                                * Natural (Here.Operand),
                            Extent => 0));
                  end if;
               end;

            when Run_Of =>
               declare
                  Where : constant Cell := Pop;
               begin
                  if Where.Kind /= Cell_Place then
                     Fail (Broken, "Program_Error", M.Msg_Machine_No_Place);
                  else
                     Push ((Kind   => Cell_Place,
                            Place  => Where.Place,
                            Extent => Natural (Here.Operand)));
                  end if;
               end;

            when Extent_Of =>
               declare
                  Where : constant Cell := Pop;
               begin
                  if Where.Kind /= Cell_Place then
                     Fail (Broken, "Program_Error", M.Msg_Machine_No_Place);
                  else
                     Push ((Cell_Whole, Whole_Number (Where.Extent)));
                  end if;
               end;

            when Run_Covers =>
               declare
                  Where : constant Cell := Pop;
                  Named : constant Natural := Here.Level;
               begin
                  if Where.Kind /= Cell_Place then
                     Fail (Broken, "Program_Error", M.Msg_Machine_No_Place);

                  elsif Here.Operand > Whole_Number (Where.Extent) then
                     Fail (Raised, "Index_Error",
                           M.Msg_Machine_Outside_Array,
                           [Counted (Here.Operand),
                            Item.Texts (Named),
                            Null_Unbounded_String],
                           2);
                  else
                     Push (Where);
                  end if;
               end;

            when Element_Place_Counted =>
               declare
                  Wanted : constant Cell := Pop;
                  Where  : constant Cell := Pop;

                  Named : constant Natural := Here.Level;
               begin
                  if Where.Kind /= Cell_Place then
                     Fail (Broken, "Program_Error", M.Msg_Machine_No_Place);

                  elsif Wanted.Whole < 1
                    or else Wanted.Whole > Whole_Number (Where.Extent)
                  then
                     --  The run's own length rather than the type's: what a
                     --  parameter of an unconstrained type was given is the
                     --  only thing that says how far it goes.
                     Fail (Raised, "Index_Error",
                           M.Msg_Machine_Outside_Array,
                           [Counted (Wanted.Whole),
                            Item.Texts (Named),
                            Null_Unbounded_String],
                           2);
                  else
                     Push ((Kind   => Cell_Place,
                            Place  =>
                              Where.Place
                              + Natural (Wanted.Whole - 1)
                                * Natural (Here.Operand),
                            Extent => 0));
                  end if;
               end;

            when Same_Block =>
               declare
                  Right : constant Cell := Pop;
                  Left  : constant Cell := Pop;
                  Span  : constant Natural := Natural (Here.Operand);
                  Same  : Boolean := True;
               begin
                  if Left.Kind /= Cell_Place or else Right.Kind /= Cell_Place
                  then
                     Fail (Broken, "Program_Error", M.Msg_Machine_No_Place);
                  else
                     for Step in 0 .. Span - 1 loop
                        --  Slot by slot, and each by what its own kind means:
                        --  a String cell holds text and a number cell holds a
                        --  number, and comparing the wrong field of a variant
                        --  is how two different values look alike.
                        declare
                           A : constant Cell := Slots (Left.Place + Step);
                           B : constant Cell := Slots (Right.Place + Step);
                        begin
                           if A.Kind /= B.Kind then
                              Same := False;
                           else
                              case A.Kind is
                                 when Cell_Whole =>
                                    Same := Same and then A.Whole = B.Whole;
                                 when Cell_Real =>
                                    Same := Same and then A.Number = B.Number;
                                 when Cell_Truth =>
                                    Same := Same and then A.Truth = B.Truth;
                                 when Cell_Letter =>
                                    Same := Same and then A.Letter = B.Letter;
                                 when Cell_Text =>
                                    Same := Same and then A.Text = B.Text;
                                 when others =>
                                    --  A place, a detail or nothing at all.
                                    --  None of those is a value a program put
                                    --  in a component.
                                    Same := False;
                              end case;
                           end if;

                           exit when not Same;
                        end;
                     end loop;

                     Push ((Cell_Truth, Same));
                  end if;
               end;

            when Quote_Text =>
               declare
                  Only : constant Cell := Pop;
                  Text : constant String := To_String (Only.Text);
                  Built : Unbounded_String;
               begin
                  Append (Built, '"');

                  for Position in Text'Range loop
                     Append (Built, Text (Position));

                     if Text (Position) = '"' then
                        Append (Built, '"');
                     end if;
                  end loop;

                  Append (Built, '"');
                  Push ((Cell_Text, Built));
               end;

            when Fetch =>
               declare
                  Where : constant Cell := Pop;
               begin
                  if Where.Kind /= Cell_Place then
                     Fail (Broken, "Program_Error", M.Msg_Machine_No_Place);
                  elsif Slots (Where.Place).Kind = Cell_None then
                     Fail (Broken, "Program_Error", M.Msg_Machine_No_Value);
                  else
                     Push (Slots (Where.Place));
                  end if;
               end;

            when Has_Value =>
               declare
                  Where : constant Cell := Pop;
                  Held  : Boolean := True;
               begin
                  if Where.Kind /= Cell_Place then
                     Fail (Broken, "Program_Error", M.Msg_Machine_No_Place);
                  else
                     for Offset in 0 .. Natural (Here.Operand) - 1 loop
                        if Slots (Where.Place + Offset).Kind = Cell_None then
                           Held := False;
                        end if;
                     end loop;

                     Push ((Cell_Truth, Held));
                  end if;
               end;

            when Block_At =>
               Push ((Kind   => Cell_Place,
                      Place  => Slot_At (Here.Level, Natural (Here.Operand)),
                      Extent => 0));

            when Copy_Block =>
               declare
                  From : constant Cell := Pop;
                  Onto : constant Cell := Pop;
                  Span : constant Natural := Natural (Here.Operand);
               begin
                  if From.Kind /= Cell_Place or else Onto.Kind /= Cell_Place
                  then
                     Fail (Broken, "Program_Error", M.Msg_Machine_No_Place);
                  else
                     --  Forwards or backwards depending on which way they
                     --  overlap, so `A := A` and a copy between two parts of
                     --  one value cannot tread on what it has not read yet.
                     if Onto.Place <= From.Place then
                        for Step in 0 .. Span - 1 loop
                           Slots (Onto.Place + Step) :=
                             Slots (From.Place + Step);
                        end loop;
                     else
                        for Step in reverse 0 .. Span - 1 loop
                           Slots (Onto.Place + Step) :=
                             Slots (From.Place + Step);
                        end loop;
                     end if;
                  end if;
               end;

            when Store =>
               declare
                  Value : constant Cell := Pop;
                  Where : constant Cell := Pop;
               begin
                  if Where.Kind /= Cell_Place then
                     Fail (Broken, "Program_Error", M.Msg_Machine_No_Store_Place);
                  else
                     Slots (Where.Place) := Value;
                  end if;
               end;

            when Swap =>
               if Top >= 2 then
                  declare
                     Above : constant Cell := Stack (Top);
                  begin
                     Stack (Top) := Stack (Top - 1);
                     Stack (Top - 1) := Above;
                  end;
               else
                  Fail (Broken, "Program_Error", M.Msg_Machine_Swap_Empty);
               end if;

            when Discard =>
               declare
                  Ignored : constant Cell := Pop;
               begin
                  null;
               end;

            when Add_Whole | Subtract_Whole | Multiply_Whole | Divide_Whole
               | Modulo_Whole | Remainder_Whole | Power_Whole =>
               declare
                  Left, Right : Cell;
               begin
                  Two (Left, Right);

                  if Left.Kind /= Cell_Whole or else Right.Kind /= Cell_Whole
                  then
                     Fail (Broken, "Program_Error", M.Msg_Machine_Not_A_Number);
                  else
                     begin
                        case Here.Code is
                           when Add_Whole =>
                              Push ((Cell_Whole, Left.Whole + Right.Whole));
                           when Subtract_Whole =>
                              Push ((Cell_Whole, Left.Whole - Right.Whole));
                           when Multiply_Whole =>
                              Push ((Cell_Whole, Left.Whole * Right.Whole));
                           when Divide_Whole =>
                              Push ((Cell_Whole, Left.Whole / Right.Whole));
                           when Modulo_Whole =>
                              Push ((Cell_Whole, Left.Whole mod Right.Whole));
                           when Remainder_Whole =>
                              Push ((Cell_Whole, Left.Whole rem Right.Whole));
                           when others =>
                              Push ((Cell_Whole, Left.Whole ** Natural (Right.Whole)));
                        end case;
                     exception
                        when Constraint_Error =>
                           --  Division by zero, overflow, a negative exponent.
                           --  Ada's own failure, reported as Ada names it.
                           Fail (Raised, "Constraint_Error", M.Msg_Machine_Arithmetic);
                     end;
                  end if;
               end;

            when Negate_Whole | Absolute_Whole =>
               declare
                  Only : constant Cell := Pop;
               begin
                  if Only.Kind /= Cell_Whole then
                     Fail (Broken, "Program_Error", M.Msg_Machine_Not_A_Number);
                  elsif Here.Code = Negate_Whole then
                     Push ((Cell_Whole, -Only.Whole));
                  else
                     Push ((Cell_Whole, abs Only.Whole));
                  end if;
               end;

            when Add_Real | Subtract_Real | Multiply_Real | Divide_Real
               | Power_Real =>
               declare
                  Left, Right : Cell;
               begin
                  Two (Left, Right);

                  if Left.Kind /= Cell_Real or else Right.Kind /= Cell_Real then
                     Fail (Broken, "Program_Error", M.Msg_Machine_Not_A_Number);
                  else
                     begin
                        case Here.Code is
                           when Add_Real =>
                              Push ((Cell_Real, Left.Number + Right.Number));
                           when Subtract_Real =>
                              Push ((Cell_Real, Left.Number - Right.Number));
                           when Multiply_Real =>
                              Push ((Cell_Real, Left.Number * Right.Number));
                           when Divide_Real =>
                              Push ((Cell_Real, Left.Number / Right.Number));
                           when others =>
                              Push ((Cell_Real,
                                     Elementary."**" (Left.Number, Right.Number)));
                        end case;
                     exception
                        when Constraint_Error =>
                           Fail (Raised, "Constraint_Error", M.Msg_Machine_Arithmetic);
                     end;
                  end if;
               end;

            when Negate_Real | Absolute_Real =>
               declare
                  Only : constant Cell := Pop;
               begin
                  if Only.Kind /= Cell_Real then
                     Fail (Broken, "Program_Error", M.Msg_Machine_Not_A_Number);
                  elsif Here.Code = Negate_Real then
                     Push ((Cell_Real, -Only.Number));
                  else
                     Push ((Cell_Real, abs Only.Number));
                  end if;
               end;

            when Equal_Whole | Unequal_Whole | Less_Whole | Less_Equal_Whole
               | Greater_Whole | Greater_Equal_Whole =>
               declare
                  Left, Right : Cell;
                  Held : Boolean;
               begin
                  Two (Left, Right);
                  Held :=
                    (case Here.Code is
                        when Equal_Whole      =>
                          Discrete (Left) = Discrete (Right),
                        when Unequal_Whole    =>
                          Discrete (Left) /= Discrete (Right),
                        when Less_Whole       =>
                          Discrete (Left) < Discrete (Right),
                        when Less_Equal_Whole =>
                          Discrete (Left) <= Discrete (Right),
                        when Greater_Whole    =>
                          Discrete (Left) > Discrete (Right),
                        when others           =>
                          Discrete (Left) >= Discrete (Right));
                  Push ((Cell_Truth, Held));
               end;

            when Equal_Real | Unequal_Real | Less_Real | Less_Equal_Real
               | Greater_Real | Greater_Equal_Real =>
               declare
                  Left, Right : Cell;
                  Held : Boolean;
               begin
                  Two (Left, Right);
                  Held :=
                    (case Here.Code is
                        when Equal_Real       => Left.Number = Right.Number,
                        when Unequal_Real     => Left.Number /= Right.Number,
                        when Less_Real        => Left.Number < Right.Number,
                        when Less_Equal_Real  => Left.Number <= Right.Number,
                        when Greater_Real     => Left.Number > Right.Number,
                        when others           => Left.Number >= Right.Number);
                  Push ((Cell_Truth, Held));
               end;

            when Equal_Text | Unequal_Text | Less_Text | Less_Equal_Text
               | Greater_Text | Greater_Equal_Text =>
               declare
                  Left, Right : Cell;
                  Held : Boolean;
               begin
                  Two (Left, Right);
                  Held :=
                    (case Here.Code is
                        when Equal_Text       => Left.Text = Right.Text,
                        when Unequal_Text     => Left.Text /= Right.Text,
                        when Less_Text        => Left.Text < Right.Text,
                        when Less_Equal_Text  => Left.Text <= Right.Text,
                        when Greater_Text     => Left.Text > Right.Text,
                        when others           => Left.Text >= Right.Text);
                  Push ((Cell_Truth, Held));
               end;

            when And_Truth | Or_Truth | Xor_Truth =>
               declare
                  Left, Right : Cell;
               begin
                  Two (Left, Right);
                  Push ((Cell_Truth,
                         (case Here.Code is
                             when And_Truth => Left.Truth and then Right.Truth,
                             when Or_Truth  => Left.Truth or else Right.Truth,
                             when others    => Left.Truth xor Right.Truth)));
               end;

            when Not_Truth =>
               declare
                  Only : constant Cell := Pop;
               begin
                  Push ((Cell_Truth, not Only.Truth));
               end;

            when Jump =>
               Point := Natural (Here.Operand);

            when Jump_If_False =>
               declare
                  Only : constant Cell := Pop;
               begin
                  if not Only.Truth then
                     Point := Natural (Here.Operand);
                  end if;
               end;

            when Jump_If_False_Keeping =>
               if Top > 0 and then not Stack (Top).Truth then
                  Point := Natural (Here.Operand);
               end if;

            when Jump_If_True_Keeping =>
               if Top > 0 and then Stack (Top).Truth then
                  Point := Natural (Here.Operand);
               end if;

            when Call =>
               declare
                  Called : constant Routine :=
                    Item.Routines (Positive (Here.Operand));
                  Base   : constant Natural := Slots_Used;
               begin
                  if Frames_Used = Max_Frames then
                     Fail (Raised, "Storage_Error", M.Msg_Machine_Too_Many_Calls);
                  elsif Base + Called.Frame > Max_Slots then
                     Fail (Raised, "Storage_Error", M.Msg_Machine_No_Frame_Room);
                  else
                     Slots_Used := Base + Called.Frame;

                     for Index in Base + 1 .. Slots_Used loop
                        Slots (Index) := (Kind => Cell_None);
                     end loop;

                     --  The arguments, in the order they were written: the
                     --  last pushed is the last parameter.
                     for Position in reverse 1 .. Called.Parameters loop
                        Slots (Base + Position) := Pop;
                     end loop;

                     Frames_Used := Frames_Used + 1;
                     Frames (Frames_Used) :=
                       (Base      => Base,
                        --  Its lexical parent is the innermost frame one level
                        --  further out than it is. Found by walking, which is
                        --  what a static link is.
                        Static    =>
                          (if Called.Level = 0 then 0
                           else Outward (0)),
                        Level     => Called.Level,
                        Return_To => Point);

                     --  A routine declared inside another finds its parent by
                     --  walking out from where it was called, which may be
                     --  deeper than the parent.
                     if Called.Level > 0 then
                        declare
                           Where : Natural := Frames_Used - 1;
                        begin
                           while Where > 0
                             and then Frames (Where).Level >= Called.Level
                           loop
                              Where := Frames (Where).Static;
                           end loop;

                           Frames (Frames_Used).Static := Where;
                        end;
                     end if;

                     Point := Called.Entry_At;
                  end if;
               end;

            when Return_Plain | Return_Value =>
               if Frames_Used = 0 then
                  Fail (Broken, "Program_Error", M.Msg_Machine_No_Return_To);

               --  A frame is not dropped while something started inside it is
               --  still running: what a task reads through its static link is
               --  that frame, and a master that returned first would leave it
               --  reading slots the next call had taken.
               elsif not Wait_For_Dependents then
                  Slots_Used := Frames (Frames_Used).Base;
                  Point := Frames (Frames_Used).Return_To;
                  Frames_Used := Frames_Used - 1;
               end if;

            when Call_Host =>
               if On_Host = null then
                  Fail (Broken, "Program_Error", M.Msg_Machine_No_Shell);
               else
                  declare
                     Count  : constant Natural := Natural (Here.Operand);
                     Given  : Cell_Array (1 .. Natural'Max (Count, 1)) :=
                       [others => (Kind => Cell_None)];
                     Named  : Cell;
                     Reply  : Answer;
                  begin
                     for Position in reverse 1 .. Count loop
                        Given (Position) := Pop;
                     end loop;

                     Named := Pop;

                     On_Host.Call
                       (To_String (Named.Text), Given, Count, Reply);

                     Push (Reply.Value);

                     if Reply.Halt then
                        Finished := True;
                     end if;
                  end;
               end if;

            when Join_Text =>
               declare
                  Left, Right : Cell;
               begin
                  Two (Left, Right);
                  Push ((Cell_Text, Left.Text & Right.Text));
               end;

            when Join_Text_Letter =>
               declare
                  Left, Right : Cell;
               begin
                  Two (Left, Right);
                  Push ((Cell_Text, Left.Text & Right.Letter));
               end;

            when Join_Letter_Text =>
               declare
                  Left, Right : Cell;
               begin
                  Two (Left, Right);
                  Push ((Cell_Text, Left.Letter & Right.Text));
               end;

            when Text_Length =>
               declare
                  Only : constant Cell := Pop;
               begin
                  Push ((Cell_Whole, Whole_Number (Length (Only.Text))));
               end;

            when Text_Element =>
               declare
                  Left, Right : Cell;
               begin
                  Two (Left, Right);

                  if Right.Whole < 1
                    or else Natural (Right.Whole) > Length (Left.Text)
                  then
                     Fail (Raised, "Index_Error", M.Msg_Machine_Index_Outside,
                           [Counted (Right.Whole),
                            Counted (Length (Left.Text)),
                            Null_Unbounded_String],
                           2);
                  else
                     Push ((Cell_Letter,
                            Element (Left.Text, Natural (Right.Whole))));
                  end if;
               end;

            when Text_Slice =>
               declare
                  Last  : constant Cell := Pop;
                  First : constant Cell := Pop;
                  Whole : constant Cell := Pop;
               begin
                  if First.Whole < 1
                    or else Natural (Last.Whole) > Length (Whole.Text)
                  then
                     --  A range that runs backwards is empty and legal, which
                     --  is Ada's rule; one that reaches past the end is not.
                     if First.Whole > Last.Whole then
                        Push ((Cell_Text, Null_Unbounded_String));
                     else
                        Fail (Raised, "Index_Error", M.Msg_Machine_Slice_Outside,
                              [Counted (First.Whole),
                               Counted (Last.Whole),
                               Counted (Length (Whole.Text))],
                              3);
                     end if;
                  elsif First.Whole > Last.Whole then
                     Push ((Cell_Text, Null_Unbounded_String));
                  else
                     Push ((Cell_Text,
                            To_Unbounded_String
                              (Slice (Whole.Text,
                                      Natural (First.Whole),
                                      Natural (Last.Whole)))));
                  end if;
               end;

            when Text_Set_Element =>
               declare
                  Letter : constant Cell := Pop;
                  Where  : constant Cell := Pop;
                  Whole  : constant Cell := Pop;
               begin
                  if Where.Whole < 1
                    or else Natural (Where.Whole) > Length (Whole.Text)
                  then
                     Fail (Raised, "Index_Error", M.Msg_Machine_Index_Outside,
                           [Counted (Where.Whole),
                            Counted (Length (Whole.Text)),
                            Null_Unbounded_String],
                           2);
                  else
                     declare
                        Changed : Unbounded_String := Whole.Text;
                     begin
                        Replace_Element
                          (Changed, Natural (Where.Whole), Letter.Letter);
                        Push ((Cell_Text, Changed));
                     end;
                  end if;
               end;

            when Text_Set_Slice =>
               declare
                  Given : constant Cell := Pop;
                  Last  : constant Cell := Pop;
                  First : constant Cell := Pop;
                  Whole : constant Cell := Pop;

                  --  How many the slice covers. A range that runs backwards
                  --  covers none, which is Ada's rule and is why this is not
                  --  simply Last - First + 1.
                  Covered : constant Whole_Number :=
                    (if First.Whole > Last.Whole then 0
                     else Last.Whole - First.Whole + 1);
               begin
                  if First.Whole < 1
                    or else (Covered > 0
                             and then Natural (Last.Whole)
                                        > Length (Whole.Text))
                  then
                     Fail (Raised, "Index_Error", M.Msg_Machine_Slice_Outside,
                           [Counted (First.Whole),
                            Counted (Last.Whole),
                            Counted (Length (Whole.Text))],
                           3);

                  elsif Covered /= Whole_Number (Length (Given.Text)) then
                     --  Ada's rule, and the reason a slice is assigned rather
                     --  than spliced: the target is a String of a known length
                     --  and what goes in has to be that length. A shorter one
                     --  would leave the rest of the target holding what it
                     --  held, which no reading of the assignment expects.
                     Fail (Raised, "Constraint_Error",
                           M.Msg_Machine_Slice_Lengths,
                           [Counted (Covered),
                            Counted (Length (Given.Text)),
                            Null_Unbounded_String],
                           2);

                  elsif Covered = 0 then
                     --  An empty slice assigned an empty String changes
                     --  nothing, and is legal in Ada. Nothing to write.
                     Push (Whole);

                  else
                     Push ((Cell_Text,
                            To_Unbounded_String
                              (Slice (Whole.Text, 1, Natural (First.Whole) - 1)
                               & To_String (Given.Text)
                               & Slice (Whole.Text,
                                        Natural (Last.Whole) + 1,
                                        Length (Whole.Text)))));
                  end if;
               end;

            when Text_Index =>
               declare
                  Left, Right : Cell;
               begin
                  Two (Left, Right);

                  --  Zero when it is not there, which is what Ada's own Index
                  --  answers and what lets a caller test without a second
                  --  question.
                  Push ((Cell_Whole,
                         Whole_Number
                           (Ada.Strings.Fixed.Index
                              (To_String (Left.Text),
                               To_String (Right.Text)))));
               end;

            when Text_Starts | Text_Ends =>
               declare
                  Left, Right : Cell;
               begin
                  Two (Left, Right);

                  declare
                     Subject : constant String := To_String (Left.Text);
                     Wanted  : constant String := To_String (Right.Text);
                     Held    : Boolean := Wanted'Length <= Subject'Length;
                  begin
                     if Held then
                        Held :=
                          (if Here.Code = Text_Starts
                           then Subject
                                  (Subject'First
                                   .. Subject'First + Wanted'Length - 1)
                                = Wanted
                           else Subject
                                  (Subject'Last - Wanted'Length + 1
                                   .. Subject'Last)
                                = Wanted);
                     end if;

                     Push ((Cell_Truth, Held));
                  end;
               end;

            when Text_Trim =>
               declare
                  Only : constant Cell := Pop;
               begin
                  Push ((Cell_Text,
                         Trim (Only.Text, Ada.Strings.Both)));
               end;

            when Text_Upper | Text_Lower =>
               declare
                  Only : constant Cell := Pop;
                  Text : constant String := To_String (Only.Text);
               begin
                  Push ((Cell_Text,
                         To_Unbounded_String
                           (if Here.Code = Text_Upper
                            then Ada.Characters.Handling.To_Upper (Text)
                            else Ada.Characters.Handling.To_Lower (Text))));
               end;

            when Whole_Of_Real =>
               declare
                  Only : constant Cell := Pop;
               begin
                  if Only.Kind /= Cell_Real then
                     Fail (Broken, "Program_Error", M.Msg_Machine_Not_A_Number);
                  else
                     declare
                        Rounded : constant Real := Real'Rounding (Only.Number);
                     begin
                        --  Ada's rule: to the nearest, and away from zero at a
                        --  half. The check is here rather than left to the
                        --  conversion, so what a program sees is the failure
                        --  Ada names rather than this build's own.
                        Push ((Cell_Whole, Whole_Number (Rounded)));
                     exception
                        when Constraint_Error =>
                           Fail (Raised, "Constraint_Error",
                                 M.Msg_Machine_Arithmetic);
                     end;
                  end if;
               end;

            when Real_Of_Whole =>
               declare
                  Only : constant Cell := Pop;
               begin
                  if Only.Kind /= Cell_Whole then
                     Fail (Broken, "Program_Error", M.Msg_Machine_Not_A_Number);
                  else
                     Push ((Cell_Real, Real (Only.Whole)));
                  end if;
               end;

            when Image_Whole =>
               declare
                  Only : constant Cell := Pop;
               begin
                  Push ((Cell_Text,
                         To_Unbounded_String
                           (Whole_Number'Image (Only.Whole))));
               end;

            when Image_Real =>
               declare
                  Only : constant Cell := Pop;
               begin
                  Push ((Cell_Text,
                         To_Unbounded_String (Real'Image (Only.Number))));
               end;

            when Image_Truth =>
               declare
                  Only : constant Cell := Pop;
               begin
                  Push ((Cell_Text,
                         To_Unbounded_String (Boolean'Image (Only.Truth))));
               end;

            when Image_Letter =>
               declare
                  Only : constant Cell := Pop;
               begin
                  Push ((Cell_Text,
                         To_Unbounded_String (Character'Image (Only.Letter))));
               end;

            when Image_Whole_Bare =>
               declare
                  Only : constant Cell := Pop;
                  Text : constant String := Whole_Number'Image (Only.Whole);
               begin
                  --  Integer'Image puts a space where the sign would go. What
                  --  a program writes is the number.
                  Push ((Cell_Text,
                         To_Unbounded_String
                           (if Text (Text'First) = ' '
                            then Text (Text'First + 1 .. Text'Last)
                            else Text)));
               end;

            when Image_Letter_Bare =>
               declare
                  Only : constant Cell := Pop;
               begin
                  Push ((Cell_Text,
                         To_Unbounded_String ([1 => Only.Letter])));
               end;

            when Value_Whole | Value_Real | Value_Truth | Value_Letter =>
               declare
                  Only : constant Cell := Pop;
                  Text : constant String := To_String (Only.Text);
               begin
                  begin
                     case Here.Code is
                        when Value_Whole =>
                           Push ((Cell_Whole, Whole_Number'Value (Text)));
                        when Value_Real =>
                           Push ((Cell_Real, Real'Value (Text)));
                        when Value_Truth =>
                           Push ((Cell_Truth, Boolean'Value (Text)));
                        when others =>
                           Push ((Cell_Letter, Character'Value (Text)));
                     end case;
                  exception
                     when Constraint_Error =>
                        Fail (Raised, "Constraint_Error",
                              M.Msg_Machine_Bad_Value_Text,
                              [To_Unbounded_String (Text),
                               Null_Unbounded_String,
                               Null_Unbounded_String],
                              1);
                  end;
               end;

            when Position_Letter =>
               declare
                  Only : constant Cell := Pop;
               begin
                  Push ((Cell_Whole,
                         Whole_Number (Character'Pos (Only.Letter))));
               end;

            when Position_Truth =>
               declare
                  Only : constant Cell := Pop;
               begin
                  Push ((Cell_Whole,
                         Whole_Number (Boolean'Pos (Only.Truth))));
               end;

            when Letter_At_Position | Truth_At_Position =>
               declare
                  Only  : constant Cell := Pop;
                  Limit : constant Whole_Number :=
                    (if Here.Code = Letter_At_Position
                     then Whole_Number (Character'Pos (Character'Last))
                     else Whole_Number (Boolean'Pos (Boolean'Last)));
               begin
                  --  Checked here rather than at each of the three places that
                  --  reach it. `Val` is written directly, and `Succ` and
                  --  `Pred` are an addition between a `Pos` and a `Val` --
                  --  which is what Ada defines them as -- so going past the
                  --  last value arrives here whichever of the three was
                  --  written.
                  if Only.Whole < 0 or else Only.Whole > Limit then
                     Fail (Raised, "Constraint_Error",
                           M.Msg_Machine_Position_Outside,
                           [Counted (Only.Whole),
                            To_Unbounded_String
                              (if Here.Code = Letter_At_Position
                               then "Character" else "Boolean"),
                            Null_Unbounded_String],
                           2);
                  elsif Here.Code = Letter_At_Position then
                     Push ((Cell_Letter,
                            Character'Val (Natural (Only.Whole))));
                  else
                     Push ((Cell_Truth, Only.Whole = 1));
                  end if;
               end;

            when Check_In_Range =>
               declare
                  --  Looked at rather than taken: this is a check on the way
                  --  past, and the value goes on to be stored.
                  Only  : constant Cell := Stack (Top);
                  Low   : constant Whole_Number := Item.Bounds (Here.Level);
                  High  : constant Whole_Number :=
                    Item.Bounds (Here.Level + 1);
                  Names : constant Natural :=
                    Natural (Item.Bounds (Here.Level + 2));
               begin
                  if Top = 0 then
                     Fail (Broken, "Program_Error", M.Msg_Machine_Stack_Empty);
                  elsif Only.Whole < Low or else Only.Whole > High then
                     --  Said as the user would write it. For an enumeration
                     --  that is the literal's name, which is why the run of
                     --  names travels with the bounds: `Blue is outside the
                     --  range of Warm` is a sentence somebody can act on, and
                     --  `2 is outside the range of Warm` is a puzzle.
                     Fail (Raised, "Constraint_Error",
                           M.Msg_Machine_Outside_Bounds,
                           [(if Names > 0
                               and then Only.Whole >= 0
                               and then Names + Natural (Only.Whole)
                                        <= Item.Texts_Used
                             then Item.Texts (Names + Natural (Only.Whole))
                             else Counted (Only.Whole)),
                            Item.Texts (Natural (Here.Operand)),
                            Null_Unbounded_String],
                           2);
                  end if;
               end;

            when Enumeration_At_Position =>
               declare
                  Only  : constant Cell := Pop;
                  Count : constant Natural := Here.Level;
                  Base  : constant Natural := Natural (Here.Operand);
               begin
                  if Only.Whole < 0
                    or else Only.Whole >= Whole_Number (Count)
                  then
                     --  The type's own name sits just past its literals, which
                     --  is why the run is interned with it on the end: a
                     --  diagnostic naming the type costs no second table.
                     Fail (Raised, "Constraint_Error",
                           M.Msg_Machine_Position_Outside,
                           [Counted (Only.Whole),
                            Item.Texts (Base + Count),
                            Null_Unbounded_String],
                           2);
                  else
                     Push (Only);
                  end if;
               end;

            when Image_Enumeration =>
               declare
                  Only  : constant Cell := Pop;
                  Count : constant Natural := Here.Level;
                  Base  : constant Natural := Natural (Here.Operand);
               begin
                  if Only.Whole < 0
                    or else Only.Whole >= Whole_Number (Count)
                  then
                     --  A position outside the type. It cannot come from a
                     --  literal, and `Val` checks its own argument, so
                     --  reaching here means something upstream is wrong --
                     --  which is worth saying rather than reading whatever
                     --  name is at that offset.
                     Fail (Raised, "Constraint_Error",
                           M.Msg_Machine_Position_Outside,
                           [Counted (Only.Whole),
                            Item.Texts (Base + Count),
                            Null_Unbounded_String],
                           2);
                  else
                     Push ((Cell_Text,
                            Item.Texts (Base + Natural (Only.Whole))));
                  end if;
               end;

            when Value_Enumeration =>
               declare
                  Only  : constant Cell := Pop;
                  Count : constant Natural := Here.Level;
                  Base  : constant Natural := Natural (Here.Operand);
                  Text  : constant String := To_String (Only.Text);
                  Found : Integer := -1;
               begin
                  --  Case-insensitively, because Ada identifiers are and these
                  --  names are identifiers. `Colour'Value ("red")` is the same
                  --  question as `Colour'Value ("Red")`.
                  for Index in 0 .. Count - 1 loop
                     if Ada.Characters.Handling.To_Lower
                          (To_String (Item.Texts (Base + Index)))
                        = Ada.Characters.Handling.To_Lower (Text)
                     then
                        Found := Index;
                        exit;
                     end if;
                  end loop;

                  if Found < 0 then
                     Fail (Raised, "Constraint_Error",
                           M.Msg_Machine_Bad_Value_Text,
                           [To_Unbounded_String (Text),
                            Null_Unbounded_String,
                            Null_Unbounded_String],
                           1);
                  else
                     Push ((Cell_Whole, Whole_Number (Found)));
                  end if;
               end;

            when Write | Write_Line =>
               declare
                  Only : constant Cell := Pop;
               begin
                  Ada.Text_IO.Put (To_String (Only.Text));

                  if Here.Code = Write_Line then
                     Ada.Text_IO.New_Line;
                  end if;
               end;

            when New_Line =>
               Ada.Text_IO.New_Line;

            when Push_Handler =>
               if Guards_Used = Max_Guards then
                  Fail (Broken, "Storage_Error", M.Msg_Machine_Too_Many_Handlers);
               else
                  Guards_Used := Guards_Used + 1;
                  Guards (Guards_Used) :=
                    (Target => Natural (Here.Operand),
                     Frames => Frames_Used,
                     Slots  => Slots_Used,
                     Top    => Top,
                     Region => Strands (Me).Region);
               end if;

            when Pop_Handler =>
               if Guards_Used > 0 then
                  Guards_Used := Guards_Used - 1;
               end if;

            when Raise_Again =>
               declare
                  Said  : constant Cell := Pop;
                  Named : constant Cell := Pop;
               begin
                  if Said.Kind /= Cell_Detail or else Named.Kind /= Cell_Text
                  then
                     Fail (Broken, "Program_Error", M.Msg_Machine_Not_A_Raise);
                  else
                     --  Raised again from where the handler is, so an outer
                     --  one catches it. Its own guard is already gone: a
                     --  handler does not catch what it raises.
                     Fail (Raised, To_String (Named.Text),
                           Said.Detail, Said.Values, Said.Filled);
                  end if;
               end;

            when Raise_Named =>
               Fail (Raised,
                     To_String (Item.Texts (Positive (Here.Operand))));

            when Raise_No_Return =>
               Fail (Raised, "Program_Error", M.Msg_Machine_No_Return_Value);

            when Priority_Is =>
               Starting_Priority := Natural (Here.Operand);

            when Set_Priority =>
               declare
                  Level : constant Cell := Pop;
                  Whom  : constant Cell := Pop;
               begin
                  if Whom.Kind /= Cell_Task then
                     Fail (Broken, "Program_Error", M.Msg_Machine_No_Place);
                  elsif Whom.Strand /= 0 then
                     Strands (Whom.Strand).Priority :=
                       Natural (Discrete (Level));
                  end if;
               end;

            when Priority_Now =>
               if Here.Level in Ceilings'Range then
                  Push ((Kind  => Cell_Whole,
                         Whole => Whole_Number (Ceilings (Here.Level))));
               else
                  declare
                     Whom : constant Cell := Pop;
                  begin
                     if Whom.Kind /= Cell_Task or else Whom.Strand = 0 then
                        Fail (Broken, "Program_Error", M.Msg_Machine_No_Place);
                     else
                        Push ((Kind  => Cell_Whole,
                               Whole =>
                                 Whole_Number
                                   (Strands (Whom.Strand).Priority)));
                     end if;
                  end;
               end if;

            when Ceiling_Is =>
               declare
                  Level : constant Cell := Pop;
               begin
                  if Here.Level in Ceilings'Range then
                     Ceilings (Here.Level) := Natural (Discrete (Level));
                  end if;
               end;

            when Start_Task =>
               declare
                  Called : constant Routine :=
                    Item.Routines (Natural (Here.Operand));
                  Fresh  : Natural := 0;

                  --  What it is elaborated with, taken off the stack before
                  --  anything else so that a failure to find room leaves the
                  --  stack where a failure always leaves it. Ada's
                  --  discriminants, which arrive the way a parameter does and
                  --  sit where one sits.
                  Given : Cell_Array (1 .. Natural'Max (Called.Parameters, 1));
               begin
                  Started_Any := True;

                  --  How many are running, against what the program allowed
                  --  itself. Counted here because here is where one begins,
                  --  and a strand that has gone back to being nobody is not
                  --  one of them.
                  if Item.Bounded then
                     declare
                        Running : Natural := 0;
                     begin
                        for Which in Strands'Range loop
                           if Which /= 1
                             and then Strands (Which).State /= Idle
                             and then Strands (Which).State /= Done
                           then
                              Running := Running + 1;
                           end if;
                        end loop;

                        if Running >= Item.Task_Limit then
                           Fail (Raised, "Storage_Error",
                                 M.Msg_Machine_Too_Many_Allowed);
                        end if;
                     end;
                  end if;

                  for Index in reverse 1 .. Called.Parameters loop
                     Given (Index) := Pop;
                  end loop;

                  for Which in 2 .. Max_Strands loop
                     if Strands (Which).State = Idle then
                        Fresh := Which;
                        exit;
                     end if;
                  end loop;

                  if Fresh = 0 then
                     Fail (Raised, "Storage_Error", M.Msg_Machine_Too_Many_Tasks);
                  else
                     declare
                        Base : constant Natural :=
                          Max_Slots - (Fresh - 1) * Task_Slots;
                        Room : constant Natural :=
                          Max_Stack - (Fresh - 1) * Task_Stack;
                     begin
                        --  Its own region of the slots and of the stack. The
                        --  environment task keeps the front of both, which is
                        --  what makes a submission with no tasks in it run
                        --  exactly as it did.
                        --  The frames it was started inside, copied so that
                        --  the new strand can walk the chain that leads out of
                        --  it. A static link is an index into a frame array
                        --  and every strand has one of its own, so a link
                        --  handed over on its own would point at whatever that
                        --  index happened to be in the *new* array -- which
                        --  for a strand's first frame is itself, and a read of
                        --  something enclosing then answered with the task's
                        --  own slot.
                        --
                        --  Copying is sound because a frame's base is an
                        --  absolute place in the store and the master outlives
                        --  what depends on it: what the copy points at is
                        --  still there for as long as the strand is.
                        Strands (Fresh) :=
                          (State       => Ready,
                           Point       => Called.Entry_At,
                           Top         => Room - Task_Stack,
                           Ceiling     => Room,
                           Slots_Used  => Base - Task_Slots + Called.Frame,
                           Slots_Limit => Base,
                           Frames      => Frames,
                           Frames_Used => Frames_Used + 1,
                           Guards      => [others => <>],
                           Guards_Used => 0,
                           Object      => 0,
                           Entry_At    => 0,
                           Until_Then  => Ada.Real_Time.Time_First,
                           Runs        => Natural (Here.Operand),
                           Calls_Task  => 0,
                           Calls_Entry => 0,
                           Calls_Until => Ada.Real_Time.Time_First,
                           Calls_Timed => False,
                           Can_Give_Up => True,
                           Open_At     => [others => 0],
                           Open_Count  => 0,
                           Call_Met    => False,
                           May_Terminate => False,
                           Ends_At       => 0,
                           Naps_In_Select => False,
                           Arguments   => 0,
                           Queued_At   => 0,

                           --  A dependent of the region it was started in,
                           --  which is the frame that was current when the
                           --  instruction ran.
                           Master        => Me,
                           Master_Frame  => Frames_Used,
                           Master_Region => Strands (Me).Region,
                           Region        => 0,
                           Joins_Frame   => 0,
                           Joins_Region  => 0,
                           Joins_Deeper  => False,
                           Cancels_On    => 0,
                           Priority      => Starting_Priority,
                           Ran_Time      => Ada.Real_Time.Time_Span_Zero,
                           Choosing      => False,
                           Chosen        => 0,
                           Chosen_Caller => 0,
                           Completed     => False,
                           Pending       => False,
                           Pending_Name  => Null_Unbounded_String,
                           Pending_Detail => Adash.Messages.Msg_Error_None,
                           Pending_Filled => 0,
                           Pending_Given  => [others =>
                                                Null_Unbounded_String]);

                        --  Its own frame, standing where a call would have
                        --  made one, on top of the chain it was started
                        --  inside. The link into that chain is the whole of
                        --  how a task reads what encloses it.
                        Strands (Fresh).Frames (Frames_Used + 1) :=
                          (Base      => Base - Task_Slots,
                           Static    => (if Called.Level = 0 then 0
                                         else Outward (0)),
                           Level     => Called.Level,
                           Return_To => 0);

                        for Index in Base - Task_Slots + 1
                                     .. Base - Task_Slots + Called.Frame
                        loop
                           Slots (Index) := (Kind => Cell_None);
                        end loop;

                        --  The discriminants, in the frame's first slots. The
                        --  same place a parameter lands, because that is what
                        --  they are to everything below here.
                        for Index in 1 .. Called.Parameters loop
                           Slots (Base - Task_Slots + Index) := Given (Index);
                        end loop;
                     end;

                     --  The task itself, for whatever declared it to keep. It
                     --  is the strand that a rendezvous and an abort name:
                     --  one routine may be being run by several.
                     Push ((Kind => Cell_Task, Strand => Fresh));

                     --  Back to the default, so the next task that says
                     --  nothing about its priority is not given this one's.
                     Starting_Priority := Default_Priority;
                  end if;
               end;

            when End_Task =>
               if Item.Endless then
                  --  A task ran out where the program said none would. Said
                  --  here because here is where one does.
                  Fail (Raised, "Program_Error",
                        M.Msg_Machine_Task_Ran_Out);
               end if;

               --  Its body is run out, which is not the same as its being
               --  over: what depends on it is still to be waited for, and a
               --  task waiting there will meet nobody.
               Strands (Me).Completed := True;

               --  A task body is a master too, and its own frame is the region
               --  that waits.
               if not Wait_For_Dependents then
                  Strands (Me).State := Done;

                  --  A caller waiting at an entry of a task that has ended is
                  --  waiting for something that will not happen. Ada raises
                  --  Tasking_Error in it, and so does this: the caller is resumed
                  --  where its call left off and the exception is raised there,
                  --  so a handler around the call catches it exactly as one
                  --  around any other call would.
                  if not Strand_A_Caller (Me) then
                     declare
                        --  Nothing left to run in this one. Whether anything else
                        --  can is the scheduler's question, and asking it here is
                        --  what keeps a finished task from being resumed.
                        Next : constant Natural := Pick_Next;
                     begin
                        if Next = 0 then
                           --  A strand ending is the end of the run only if
                           --  nobody is left waiting.
                           if Set_Aside_Elsewhere then
                              Fail (Broken, "Program_Error",
                                    M.Msg_Machine_Tasks_Stuck);
                           else
                              Finished := True;
                           end if;
                        else
                           Me := Next;

                           if Strands (Me).State in Joining | Sleeping then
                              Strands (Me).State := Ready;
                           end if;

                           Load_From (Me);
                           Ran_For := 0;
                        end if;
                     end;
                  end if;
               end if;

            when Await_Abandoned =>
               declare
                  Waiting : constant Boolean := Wait_For_Abandoned;
                  pragma Unreferenced (Waiting);
               begin
                  null;
               end;

            when Enter_Region =>
               --  The region being left, for the block to keep and hand back.
               Push ((Kind  => Cell_Whole,
                      Whole => Whole_Number (Strands (Me).Region)));

               Regions_Made := Regions_Made + 1;
               Strands (Me).Region := Regions_Made;

            when Leave_Region =>
               if not Wait_For_Region (Strands (Me).Region) then
                  declare
                     Outer : constant Cell := Pop;
                  begin
                     Strands (Me).Region := Natural (Discrete (Outer));
                  end;
               end if;

            when Await_Tasks =>
               if not Dependents_Done (Me, Frames_Used) then
                  Strands (Me).State        := Joining;
                  Strands (Me).Joins_Frame  := Frames_Used;
                  Strands (Me).Joins_Region := 0;
                  Strands (Me).Joins_Deeper := False;
                  Save_Into (Me);

                  declare
                     Next : constant Natural := Pick_Next;
                  begin
                     if Next = 0 then
                        --  Everything that could run has, and what this waits
                        --  for never ended. A program that cannot go on is
                        --  worth saying so about rather than stopping quietly.
                        Fail (Broken, "Program_Error",
                              M.Msg_Machine_Tasks_Stuck);
                     else
                        Me := Next;
                        Load_From (Me);
                        Ran_For := 0;
                     end if;
                  end;
               end if;

            when Enter_Protected =>
               if Natural (Here.Operand) in Ceilings'Range
                 and then Strands (Me).Priority
                          > Ceilings (Natural (Here.Operand))
               then
                  Fail (Raised, "Program_Error", M.Msg_Machine_Above_Ceiling);
               end if;

               --  Taken without waiting. Nothing else can be running inside
               --  one, because the machine does not change strand between
               --  these two -- so the lock is never held when this is reached.
               Holding := Natural (Here.Operand);

            when Leave_Protected =>
               Holding := 0;

               --  Everything waiting on this object is made runnable, and each
               --  tests its own barrier when it gets there. Waking them all
               --  rather than choosing is what keeps the barrier's meaning in
               --  one place: the barrier is a condition, and only the strand
               --  that waits on it can say whether it holds now.
               for Which in Strands'Range loop
                  if Strands (Which).State = Waiting
                    and then Strands (Which).Object = Natural (Here.Operand)
                  then
                     Strands (Which).State := Ready;
                  end if;
               end loop;

            when Waiting_At =>
               --  Where a caller joins a protected object's queue, which is
               --  where it takes its place in it. Once per call: the barrier
               --  is asked again every time the object is left, and a place
               --  renewed at each asking would be no place at all.
               Queued := Queued + 1;

               Strands (Me).Calls_Entry := Natural (Discrete (Pop));
               Strands (Me).Object      := Natural (Here.Operand);
               Strands (Me).Queued_At   := Queued;

            when Entry_Count =>
               declare
                  Wanted      : constant Natural := Natural (Discrete (Pop));
                  Queued_Here : Natural := 0;
               begin
                  for Which in Strands'Range loop
                     if Strands (Which).Calls_Entry = Wanted
                       and then
                         (if Here.Operand = 0
                          then Strands (Which).State = Calling
                               and then Strands (Which).Calls_Task = Me
                          else Strands (Which).Object
                               = Natural (Here.Operand)
                               and then Strands (Which).State
                                        not in Idle | Done)
                     then
                        Queued_Here := Queued_Here + 1;
                     end if;
                  end loop;

                  Push ((Kind => Cell_Whole, Whole => Whole_Number (Queued_Here)));
               end;

            when Await_Barrier =>
               declare
                  Open : constant Cell := Pop;

                  --  Whether somebody else queued at this same entry is ahead
                  --  of this strand.
                  --
                  --  An open barrier is not a turn. Everything waiting on the
                  --  object is woken and each tests its own barrier, which is
                  --  what keeps a barrier's meaning in one place -- so the
                  --  queue's order has to be kept here, where a strand would
                  --  otherwise go through by having been picked first.
                  --
                  --  A strand ahead is Ready rather than Waiting when the
                  --  object has just been left, so what identifies one is
                  --  where it is queued and not what state it is in.
                  function Somebody_Ahead return Boolean is
                  begin
                     for Which in Strands'Range loop
                        if Which /= Me
                          and then Strands (Which).State in Ready | Waiting
                          and then Strands (Which).Object = Strands (Me).Object
                          and then Strands (Which).Calls_Entry
                                   = Strands (Me).Calls_Entry
                          and then Comes_First (Which, Me)
                        then
                           return True;
                        end if;
                     end loop;

                     return False;
                  end Somebody_Ahead;

               begin
                  if Giving_Up (Me)
                    and then Ada.Real_Time.">=" (Ada.Real_Time.Clock,
                                                 Strands (Me).Calls_Until)
                  then
                     --  The wait ran out. Out of the entry body without
                     --  running it, which is the same unwind a return does --
                     --  and the same one an abandoned trigger is given, for
                     --  the same reason: a caller waiting at a barrier queues
                     --  by being inside the body, so leaving the queue is
                     --  leaving the body.
                     Holding := 0;
                     Strands (Me).Object      := 0;
                     Strands (Me).Calls_Entry := 0;
                     Strands (Me).Calls_Timed := False;
                     Strands (Me).Call_Met    := False;

                     declare
                        Leaving : constant Natural := Frames_Used;
                     begin
                        Slots_Used  := Frames (Leaving).Base;
                        Point       := Frames (Leaving).Return_To;
                        Frames_Used := Leaving - 1;
                     end;

                  elsif Open.Kind = Cell_Truth and then Open.Truth
                    and then not Somebody_Ahead
                  then
                     --  Through, and holding the lock: an entry body runs
                     --  under mutual exclusion like every other protected
                     --  operation, and the strand gave the lock up when it
                     --  went to sleep.
                     --
                     --  Out of the queue, which is what `'Count` counts: a
                     --  strand is in it from the moment it asks until the
                     --  moment it is through.
                     Holding := Here.Level;
                     Strands (Me).Calls_Entry := 0;
                     Strands (Me).Object      := 0;

                     --  The entry body is starting, so a deadline the call
                     --  was given has nothing left to cancel.
                     Strands (Me).Call_Met    := True;
                     Strands (Me).Calls_Timed := False;
                  else
                     --  Set aside until the object is next left. The lock goes
                     --  with it: a strand that waited while holding one would
                     --  be the deadlock this design exists to avoid.
                     Holding := 0;
                     Strands (Me).State   := Waiting;
                     Strands (Me).Object  := Here.Level;
                     Strands (Me).Entry_At := Natural (Here.Operand);

                     --  Back to the *barrier*, not to this instruction: waking
                     --  has to ask the question again, and the answer is what
                     --  the barrier's own instructions compute.
                     Point := Natural (Here.Operand);
                     Save_Into (Me);

                     declare
                        Next : constant Natural := Pick_Next;
                     begin
                        if Next = 0 then
                           Fail (Broken, "Program_Error",
                                 M.Msg_Machine_Tasks_Stuck);
                        else
                           Me := Next;

                           if Strands (Me).State in Joining | Sleeping then
                              Strands (Me).State := Ready;
                           end if;

                           Load_From (Me);
                           Ran_For := 0;
                        end if;
                     end;
                  end if;
               end;

            when Read_Clock =>
               declare
                  use type Ada.Real_Time.Time;
               begin
                  Push ((Kind   => Cell_Real,
                         Number =>
                           Real (Ada.Real_Time.To_Duration
                                   (Ada.Real_Time.Clock - Session_Began))));
               end;

            when Execution_Time =>
               declare
                  use type Ada.Real_Time.Time;
                  use type Ada.Real_Time.Time_Span;

                  Whom : constant Cell := Pop;
               begin
                  if Whom.Kind /= Cell_Task or else Whom.Strand = 0 then
                     Fail (Broken, "Program_Error", M.Msg_Machine_No_Place);
                  else
                     --  What it has run for, and the turn it is having now
                     --  when it is the one asking: a strand's own turn has not
                     --  been added up yet, and leaving it out would say a task
                     --  had run for no time at all.
                     Push
                       ((Kind   => Cell_Real,
                         Number =>
                           Real (Ada.Real_Time.To_Duration
                                   (Strands (Whom.Strand).Ran_Time
                                    + (if Whom.Strand = Me
                                       then Ada.Real_Time.Clock - Turn_Began
                                       else Ada.Real_Time.Time_Span_Zero)))));
                  end if;
               end;

            when Delay_Until =>
               declare
                  use type Ada.Real_Time.Time;

                  When_To : constant Cell := Pop;
                  Seconds : constant Duration :=
                    Duration (if When_To.Kind = Cell_Real
                              then Long_Long_Float (When_To.Number)
                              else Long_Long_Float (Discrete (When_To)));

                  Wakes : constant Ada.Real_Time.Time :=
                    Session_Began + Ada.Real_Time.To_Time_Span (Seconds);
               begin
                  if Wakes > Ada.Real_Time.Clock then
                     Strands (Me).State      := Sleeping;
                     Strands (Me).Until_Then := Wakes;

                     Save_Into (Me);

                     declare
                        Next : constant Natural := Pick_Next;
                     begin
                        if Next = 0 then
                           --  Nothing else to run, so the wait is the only
                           --  thing left to do. Slept through rather than spun
                           --  through, as a relative delay is.
                           delay until Strands (Me).Until_Then;
                           Strands (Me).State := Ready;
                        else
                           Me := Next;

                           if Strands (Me).State in Joining | Sleeping then
                              Strands (Me).State := Ready;
                           end if;

                           Load_From (Me);
                           Ran_For := 0;
                        end if;
                     end;
                  end if;
               end;

            when Delay_For =>
               declare
                  How_Long : constant Cell := Pop;

                  --  Ada's own Duration, from the number the program wrote.
                  --  A negative one has already passed, which is Ada's rule
                  --  too: `delay -1.0` is not an error, it is no wait at all.
                  Seconds : constant Duration :=
                    Duration (if How_Long.Kind = Cell_Real
                              then Long_Long_Float (How_Long.Number)
                              else Long_Long_Float (Discrete (How_Long)));

                  use type Ada.Real_Time.Time;
               begin
                  if Seconds > 0.0 then
                     Strands (Me).State := Sleeping;
                     Strands (Me).Until_Then :=
                       Ada.Real_Time.Clock
                       + Ada.Real_Time.To_Time_Span (Seconds);

                     --  Whether a caller may cut this short, which the
                     --  instruction says because only the lowering knows
                     --  which kind of wait this is.
                     Strands (Me).Naps_In_Select := Here.Operand = 1;

                     Save_Into (Me);

                     declare
                        Next : constant Natural := Pick_Next;
                     begin
                        if Next = 0 then
                           --  Nothing else to run, so the wait is the only
                           --  thing left to do. Slept through rather than spun
                           --  through: a shell that burned a core waiting for
                           --  a second to pass would be a shell nobody leaves
                           --  running.
                           delay until Strands (Me).Until_Then;
                           Strands (Me).State := Ready;
                        else
                           Me := Next;

                           if Strands (Me).State in Joining | Sleeping then
                              Strands (Me).State := Ready;
                           end if;

                           Load_From (Me);
                           Ran_For := 0;
                        end if;
                     end;
                  end if;
               end;

            when Call_Entry =>
               declare
                  --  In the order they were pushed: the offset within a
                  --  family, then the task, then where the arguments are.
                  Where  : constant Cell := Pop;
                  Whom   : constant Cell := Pop;
                  Wanted : constant Natural := Entry_Named (Here);

                  --  Whether the call was given a deadline, and when it runs
                  --  out. Pushed under everything else, so it is taken last:
                  --  a call that says how long to wait says it before it says
                  --  what it is calling.
                  --
                  --  The operand says which kind of call this is: a family
                  --  offset on the stack is one bit of it, a deadline under
                  --  everything the next, and a call to be made only if it
                  --  can be met at once the one after.
                  Bounded : constant Boolean := Here.Operand mod 4 >= 2;
                  At_Once : constant Boolean := Here.Operand >= 4;
                  Waits   : constant Cell :=
                    (if Bounded then Pop else (Kind => Cell_None));
                  Seconds : constant Duration :=
                    (if not Bounded then 0.0
                     elsif Waits.Kind = Cell_Real
                     then Duration (Long_Long_Float (Waits.Number))
                     else Duration (Long_Long_Float (Discrete (Waits))));
                  Gives_Up_At : constant Ada.Real_Time.Time :=
                    Ada.Real_Time."+" (Ada.Real_Time.Clock,
                                       Ada.Real_Time.To_Time_Span
                                         (Duration'Max (Seconds, 0.0)));

                  --  Which strand, and whether it is one that can still be
                  --  met. A task that has ended will never reach an accept,
                  --  and Ada's answer is Tasking_Error raised in the caller,
                  --  which is what a handler around the call is there for.
                  Target : constant Natural :=
                    (if Whom.Kind = Cell_Task then Whom.Strand else 0);
                  Gone   : constant Boolean :=
                    Target = 0
                      or else Strands (Target).State in Idle | Done;
               begin
                  if Where.Kind /= Cell_Place or else Whom.Kind /= Cell_Task
                  then
                     Fail (Broken, "Program_Error", M.Msg_Machine_No_Place);
                  elsif Gone then
                     Fail (Raised, "Tasking_Error",
                           M.Msg_Machine_Task_Finished);

                  elsif At_Once and then not Ready_To_Meet (Target, Wanted)
                  then
                     --  Nobody is waiting to take this call, so there is no
                     --  rendezvous to start and the call is not made. The
                     --  else part is what the program said to do instead.
                     Strands (Me).Call_Met := False;

                  else
                     --  How many are already waiting there, against what the
                     --  program allowed. Counted here because here is where
                     --  one joins.
                     if Item.Queue_Bound then
                        declare
                           Waiting_There : Natural := 0;
                        begin
                           for Which in Strands'Range loop
                              if Strands (Which).State = Calling
                                and then Strands (Which).Calls_Task = Target
                                and then Strands (Which).Calls_Entry = Wanted
                              then
                                 Waiting_There := Waiting_There + 1;
                              end if;
                           end loop;

                           if Waiting_There >= Item.Queue_Limit then
                              Fail (Raised, "Program_Error",
                                    M.Msg_Machine_Queue_Too_Long);
                              return;
                           end if;
                        end;
                     end if;

                     Queued := Queued + 1;

                     Strands (Me).State       := Calling;
                     Strands (Me).Calls_Task  := Target;
                     Strands (Me).Calls_Entry := Wanted;
                     Strands (Me).Arguments   := Where.Place;
                     Strands (Me).Queued_At   := Queued;
                     Strands (Me).Calls_Timed := Bounded;
                     Strands (Me).Calls_Until := Gives_Up_At;
                     Strands (Me).Call_Met    := False;
                     Strands (Me).Can_Give_Up := True;

                     --  Wake it, if it is waiting for a caller. An acceptor
                     --  waits on state somebody else changes, and this is the
                     --  change: polling would run its own code at moments the
                     --  program did not reach.
                     --
                     --  Which entry it was waiting at is not asked. It goes
                     --  back and looks, so what it accepts is decided by
                     --  looking rather than by having said in advance.
                     --  Woken whether it was waiting for a caller or waiting
                     --  a bounded time for one: a select that says `or delay`
                     --  is waiting for both, and a caller arriving is the
                     --  first of them to happen.
                     --
                     --  What it was open for is forgotten with the waking, so
                     --  a second caller asking whether a rendezvous could
                     --  start at once is told no -- this task is running now,
                     --  and one of them is going to be taken.
                     if Strands (Target).State = Accepting
                       or else (Strands (Target).State = Sleeping
                                and then Strands (Target).Naps_In_Select)
                     then
                        Strands (Target).State          := Ready;
                        Strands (Target).Naps_In_Select := False;
                        Strands (Target).Open_Count     := 0;
                     end if;

                     Save_Into (Me);

                     declare
                        Next : constant Natural := Pick_Next;
                     begin
                        if Next = 0 then
                           --  Nobody to accept and nobody who could come to.
                           Fail (Broken, "Program_Error",
                                 M.Msg_Machine_Tasks_Stuck);
                        else
                           Me := Next;

                           if Strands (Me).State in Joining | Sleeping then
                              Strands (Me).State := Ready;
                           end if;

                           Load_From (Me);
                           Ran_For := 0;
                        end if;
                     end;
                  end if;
               end;

            when Call_Deadline =>
               declare
                  Waits : constant Cell := Pop;
                  Seconds : constant Duration :=
                    (if Waits.Kind = Cell_Real
                     then Duration (Long_Long_Float (Waits.Number))
                     else Duration (Long_Long_Float (Discrete (Waits))));
               begin
                  Strands (Me).Calls_Timed := True;
                  Strands (Me).Can_Give_Up := True;
                  Strands (Me).Call_Met    := False;
                  Strands (Me).Calls_Until :=
                    Ada.Real_Time."+" (Ada.Real_Time.Clock,
                                       Ada.Real_Time.To_Time_Span
                                         (Duration'Max (Seconds, 0.0)));
               end;

            when Call_Answer =>
               --  Back to being nobody's caller. A strand woken by its own
               --  deadline is still in the state it waited in, and one left
               --  there would count as set aside while it ran.
               Strands (Me).State := Ready;

               --  Whether the rendezvous began, which is what both bounded
               --  forms ask. Leaving the queue is done here rather than where
               --  the clock ran out, so that giving up is in one place: what
               --  the scheduler does is wake the caller, and what the caller
               --  does is answer for itself.
               Strands (Me).Calls_Task  := 0;
               Strands (Me).Calls_Entry := 0;
               Strands (Me).Calls_Timed := False;

               Push ((Kind => Cell_Truth, Truth => Strands (Me).Call_Met));

            when Choose =>
               --  Only where Ada asks for it. Under priority queuing the
               --  alternative served is the one holding the caller who comes
               --  first; under order of arrival Ada leaves the choice
               --  arbitrary, and this machine's arbitrary answer is the one
               --  written first -- which costs nothing to keep and keeps
               --  every program that says nothing interleaving as it did.
               Strands (Me).Choosing      :=
                 Here.Operand = 1 and then Item.By_Priority;
               Strands (Me).Chosen         := 0;
               Strands (Me).Chosen_Caller  := 0;
               Strands (Me).Open_Count     := 0;
               Strands (Me).May_Terminate  := False;
               Strands (Me).Naps_In_Select := False;

            when Offer_End =>
               declare
                  Open_Now : constant Cell := Pop;
               begin
                  if Open_Now.Kind = Cell_Truth and then Open_Now.Truth then
                     Strands (Me).May_Terminate := True;
                     Strands (Me).Ends_At := Natural (Here.Operand);
                  end if;
               end;

            when Offer_Entry =>
               declare
                  Open_Now : constant Cell := Pop;
                  Wanted   : constant Natural := Entry_Named (Here);
               begin
                  --  What this strand would take, written down whatever the
                  --  queuing policy is: it is not about choosing between
                  --  callers but about being able to answer somebody who asks
                  --  whether a rendezvous could start.
                  if Open_Now.Kind = Cell_Truth and then Open_Now.Truth then
                     if Strands (Me).Open_Count = Max_Offers then
                        Fail (Broken, "Program_Error",
                              M.Msg_Machine_Too_Many_Alternatives);
                        return;
                     end if;

                     Strands (Me).Open_Count := Strands (Me).Open_Count + 1;
                     Strands (Me).Open_At (Strands (Me).Open_Count) := Wanted;
                  end if;

                  if Strands (Me).Choosing
                    and then Open_Now.Kind = Cell_Truth
                    and then Open_Now.Truth
                  then
                     for Which in Strands'Range loop
                        if Strands (Which).State = Calling
                          and then Strands (Which).Calls_Task = Me
                          and then Strands (Which).Calls_Entry = Wanted
                          and then Still_Waiting (Which)
                          and then (Strands (Me).Chosen_Caller = 0
                                    or else Comes_First
                                              (Which,
                                               Strands (Me).Chosen_Caller))
                        then
                           Strands (Me).Chosen        := Wanted;
                           Strands (Me).Chosen_Caller := Which;
                        end if;
                     end loop;
                  end if;
               end;

            when Try_Accept =>
               declare
                  Wanted : constant Natural := Entry_Named (Here);
                  --  The caller who has waited longest at this entry of this
                  --  task. Of *this* task: a task type may have several
                  --  objects running one routine, and a caller of one is not
                  --  a caller of another.
                  Taken   : Natural := 0;
               begin
                  --  Inside a select, only the entry the choice settled on
                  --  may take a caller: the alternatives are tried in the
                  --  order they are written, and the one that serves is the
                  --  one holding the caller who comes first.
                  if not Strands (Me).Choosing
                    or else Wanted = Strands (Me).Chosen
                  then
                     for Which in Strands'Range loop
                        if Strands (Which).State = Calling
                          and then Strands (Which).Calls_Task = Me
                          and then Strands (Which).Calls_Entry = Wanted
                          and then Still_Waiting (Which)
                          and then (Taken = 0
                                    or else Comes_First (Which, Taken))
                        then
                           Taken := Which;
                        end if;
                     end loop;
                  end if;

                  if Taken = 0 then
                     Push ((Kind => Cell_Truth, Truth => False));
                  else
                     --  Met. The caller stays put while the body runs, and
                     --  what the body reaches through is where the caller put
                     --  its arguments.
                     Strands (Taken).State    := Met;
                     Strands (Taken).Call_Met := True;
                     Strands (Me).Open_Count  := 0;

                     --  The choice is spent. What follows is the body, and
                     --  an accept inside it is a plain one with no choice
                     --  around it.
                     Strands (Me).Choosing := False;

                     Push ((Kind   => Cell_Place,
                            Place  => Strands (Taken).Arguments,
                            Extent => 0));
                     Push ((Kind => Cell_Truth, Truth => True));
                  end if;
               end;

            when Await_Caller =>
               --  Set aside until somebody calls, and go back to where the
               --  alternatives are tried so that the queues are looked at
               --  again. Testing what was true before sleeping would answer
               --  the question the strand went to sleep on rather than the one
               --  that woke it.
               Strands (Me).State := Accepting;
               Point := Natural (Here.Operand);
               Save_Into (Me);

               declare
                  Next : constant Natural := Pick_Next;
               begin
                  if Next = 0 then
                     Fail (Broken, "Program_Error", M.Msg_Machine_Tasks_Stuck);
                  else
                     Me := Next;

                     if Strands (Me).State in Joining | Sleeping then
                        Strands (Me).State := Ready;
                     end if;

                     Load_From (Me);
                     Ran_For := 0;
                  end if;
               end;

            when End_Accept =>
               declare
                  Wanted : constant Natural := Entry_Named (Here);
               begin
                  for Which in Strands'Range loop
                     if Strands (Which).State = Met
                       and then Strands (Which).Calls_Task = Me
                       and then Strands (Which).Calls_Entry = Wanted
                     then
                        Strands (Which).State       := Ready;
                        Strands (Which).Calls_Task  := 0;
                        Strands (Which).Calls_Entry := 0;
                     end if;
                  end loop;
               end;

            when Watch_Task =>
               declare
                  Whom : constant Cell := Pop;
               begin
                  if Whom.Kind /= Cell_Task then
                     Fail (Broken, "Program_Error", M.Msg_Machine_No_Place);
                  else
                     Strands (Me).Cancels_On := Whom.Strand;
                  end if;
               end;

            when Watch_Nothing =>
               Strands (Me).Cancels_On := 0;

            when Task_Ended =>
               declare
                  Whom : constant Cell := Pop;
               begin
                  if Whom.Kind /= Cell_Task then
                     Fail (Broken, "Program_Error", M.Msg_Machine_No_Place);
                  else
                     Push ((Kind  => Cell_Truth,
                            Truth => Whom.Strand = 0
                                     or else Strands (Whom.Strand).State
                                             in Idle | Done));
                  end if;
               end;

            when Task_Callable =>
               declare
                  Whom : constant Cell := Pop;
               begin
                  if Whom.Kind /= Cell_Task then
                     Fail (Broken, "Program_Error", M.Msg_Machine_No_Place);
                  else
                     Push ((Kind  => Cell_Truth,
                            Truth => Whom.Strand /= 0
                                     and then Strands (Whom.Strand).State
                                              not in Idle | Done
                                     and then not Strands (Whom.Strand)
                                                    .Completed));
                  end if;
               end;

            when Requeue_Entry =>
               declare
                  --  In the order they were pushed: where the caller was
                  --  taken from, then where it goes.
                  Moves_To   : constant Natural := Natural (Discrete (Pop));
                  Taken_From : constant Natural := Natural (Discrete (Pop));

                  Taken : Natural := 0;
               begin
                  for Which in Strands'Range loop
                     if Strands (Which).State = Met
                       and then Strands (Which).Calls_Task = Me
                       and then Strands (Which).Calls_Entry = Taken_From
                     then
                        Taken := Which;
                        exit;
                     end if;
                  end loop;

                  if Taken = 0 then
                     --  Nobody is being served, so there is nobody to move.
                     --  A defect here rather than in the program: the lowering
                     --  emits this inside an accept body and nowhere else.
                     Fail (Broken, "Program_Error", M.Msg_Machine_No_Caller);
                  else
                     Queued := Queued + 1;

                     Strands (Taken).State       := Calling;
                     Strands (Taken).Calls_Entry := Moves_To;
                     Strands (Taken).Queued_At   := Queued;

                     --  `with abort` or not, which is the whole difference
                     --  between the two spellings: a caller moved without it
                     --  keeps its place and loses its way out.
                     Strands (Taken).Can_Give_Up := Here.Operand = 1;

                     --  And it is waiting again. The rendezvous it was in was
                     --  not the one it called for -- from the caller's own
                     --  point of view it never happened, which is what makes
                     --  a requeue different from returning.
                     Strands (Taken).Call_Met := False;
                  end if;
               end;

            when Requeue_Guarded =>
               declare
                  Called : constant Routine :=
                    Item.Routines (Positive (Here.Operand));
               begin
                  if Frames_Used = 0 then
                     Fail (Broken, "Program_Error", M.Msg_Machine_No_Caller);
                  else
                     declare
                        --  Where the call came from, kept: what a requeue
                        --  moves is where the caller waits, not where it
                        --  came from or where it goes back to.
                        Comes_From : constant Natural :=
                          Frames (Frames_Used).Return_To;
                        Base : constant Natural :=
                          Frames (Frames_Used).Base;
                     begin
                        if Base + Called.Frame > Max_Slots then
                           Fail (Raised, "Storage_Error",
                                 M.Msg_Machine_No_Frame_Room);
                        else
                           --  Out of this body and into that one, in the
                           --  place this one stood: an entry body takes
                           --  nothing, so there is nothing to carry over.
                           Slots_Used := Base + Called.Frame;

                           for Index in Base + 1 .. Slots_Used loop
                              Slots (Index) := (Kind => Cell_None);
                           end loop;

                           --  What the entry it moves to takes: which member
                           --  of a family, when it is one. The same place a
                           --  call would have put it.
                           for Position in reverse 1 .. Called.Parameters loop
                              Slots (Base + Position) := Pop;
                           end loop;

                           Frames (Frames_Used) :=
                             (Base      => Base,
                              Static    => Frames (Frames_Used).Static,
                              Level     => Called.Level,
                              Return_To => Comes_From);

                           Point := Called.Entry_At;
                        end if;
                     end;
                  end if;
               end;

            when Abort_Task =>
               declare
                  --  However many the statement named, in the order they were
                  --  pushed reversed -- which does not matter, because they
                  --  are all stopped before any caller hears of it.
                  How_Many : constant Natural :=
                    Natural'Max (Natural (Here.Operand), 1);
                  Targets  : array (1 .. How_Many) of Natural :=
                    [others => 0];
                  Wrong    : Boolean := False;
               begin
                  for Index in reverse 1 .. How_Many loop
                     declare
                        Whom : constant Cell := Pop;
                     begin
                        if Whom.Kind /= Cell_Task then
                           Wrong := True;
                        else
                           Targets (Index) := Whom.Strand;
                        end if;
                     end;
                  end loop;

                  if Wrong then
                     Fail (Broken, "Program_Error", M.Msg_Machine_No_Place);
                  else
                     for Target of Targets loop
                        if Target /= 0 and then Target /= Me
                          and then Strands (Target).State /= Idle
                        then
                           --  Stopped where it would next have run. This
                           --  machine interleaves rather than pre-empts, so
                           --  there is no moment between two instructions at
                           --  which to intervene -- and none is needed,
                           --  because a strand that is not running cannot be
                           --  in the middle of anything.
                           Strands (Target).State := Done;
                        end if;
                     end loop;

                     --  A caller queued at one of their entries is waiting for
                     --  something that will now never happen, exactly as it
                     --  would be had the task run to its end. Handed the same
                     --  answer, and after every abort has taken effect rather
                     --  than between two of them: being handed it resumes the
                     --  caller, and a caller that ran in between could see
                     --  half a statement's work.
                     for Target of Targets loop
                        declare
                           Handed : constant Boolean :=
                             Strand_A_Caller (Target);
                           pragma Unreferenced (Handed);
                        begin
                           null;
                        end;
                     end loop;
                  end if;
               end;

            when Halt =>
               Finished := True;
         end case;
      end loop;

      --  What the outermost frame ended with, kept so the session can read it.
      Free (Item.Kept);
      Item.Kept := new Cell_Array (1 .. Natural'Max (Item.Frame, 1));

      for Index in 1 .. Item.Frame loop
         Item.Kept (Index) := Slots (Index);
      end loop;

      Produced.Steps := Counter;

      --  The working store goes back now rather than at the next run: an
      --  interactive session holds a Program between submissions, and keeping
      --  megabytes alive between two typed lines is keeping them for nothing.
      declare
         Give_Back_Stack : Cell_Access := Held;
         Give_Back_Slots : Cell_Access := Room;
      begin
         Free (Give_Back_Stack);
         Free (Give_Back_Slots);
      end;
   end Run;

end Adash.Machine;
