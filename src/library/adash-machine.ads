with System;

with Ada.Strings.Unbounded;

with Adash.Messages;

--  The virtual machine Adash programs run on.
--
--  A stack machine with frames, static links and a host call. It exists because
--  the language front end -- lexer, parser, semantics, lowering -- is Adash's
--  own, and a front end that owns everything up to the instruction stream and
--  then hands that stream to somebody else's compiler internals is paying for a
--  seam it does not need. What this replaces was not an interpreter but an
--  impersonation of one compiler's output: identifier tables, block tables,
--  activation records of a fixed shape, a display vector to keep in step.
--
--  The instruction set is what the lowering emits and nothing else. There is no
--  general Ada machine here and there is not meant to be: every instruction has
--  a construct behind it, and one nobody emits is one nobody can test.
--
--  Three things this owes its predecessor, and keeps deliberately:
--
--  * Ada's own arithmetic and comparison semantics, including that a Float is
--    `digits System.Max_Digits` so that `'Image` renders as Ada renders it.
--  * Bounds that raise rather than read past themselves.
--  * An exception carrying a name and a detail, so a program that failed says
--    what failed rather than stopping.
package Adash.Machine is

   --  What a task's priority is when it says nothing.
   --
   --  Ada's Default_Priority, which is the middle of the range: a task that
   --  says nothing is neither preferred nor put off, and one that says
   --  something can go either way from there.
   Default_Priority : constant := 15;

   --  The range a priority may be written in, which is Ada's for a single
   --  range of them.
   Lowest_Priority  : constant := 0;
   Highest_Priority : constant := 30;

   --  How many alternatives one selective accept may offer at once.
   --
   --  A bound like the others here, and it exists because a strand records
   --  what it is waiting to accept: that is what lets a conditional call ask
   --  whether a rendezvous could start, and a record has to be a fixed size.
   --  A select with more alternatives than this is refused where it runs
   --  rather than answered wrongly.
   Max_Offers : constant := 32;

   --  What a policy is said about: one answer per priority. A program that
   --  says nothing gets the whole of it False, which is the machine sharing
   --  turns out as it always did.
   type Priority_Policy is
     array (Lowest_Priority .. Highest_Priority) of Boolean;

   --  How many protected objects one run may have.
   --
   --  A bound rather than growth, for the reason every other bound here is
   --  one. Each costs a lock and a ceiling and nothing else.
   Max_Objects : constant := 64;

   --  How much room one task gets, in slots.
   --
   --  A strand has a region of the store and a region of the stack, and this
   --  is the two together: what `T'Storage_Size` answers, and the only honest
   --  answer this machine has. Ada counts storage elements, which is a host's
   --  bytes; a slot here holds a value of any type, so a byte count would be a
   --  number nothing in this machine means.
   Storage_Per_Task : constant := 65_536 / (2 * 16) + 4_096 / (2 * 16);

   --  The widest real this host offers, which is what Ada's own default
   --  formatting is defined against. A narrower one would render `'Image`
   --  differently from every Ada compiler on the same machine.
   type Real is digits System.Max_Digits;

   --  And the widest whole number, which is what this language's Integer has
   --  always been: a program written against `Integer'Last` means the one it
   --  had, and narrowing it would change what programs mean rather than how
   --  they run.
   type Whole_Number is range -(2 ** 63) .. 2 ** 63 - 1;

   --  What a stack cell holds.
   --
   --  A tagged union rather than one field per type: a stack is the hottest
   --  structure here, and the text field is the only one that cannot live in a
   --  register.
   type Cell_Kind is
     (
      --  Nothing. A frame slot before anything is stored in it.
      Cell_None,

      Cell_Whole,
      Cell_Real,
      Cell_Truth,
      Cell_Letter,
      Cell_Text,

      --  A place, not a value: the frame slot a by-reference parameter or an
      --  assignment target names. Kept apart from Cell_Whole so that storing
      --  through something that is not an address is a defect the machine
      --  catches rather than a number it follows.
      Cell_Place,

      --  A task. What a task object holds, and what names the strand running
      --  it: one task type may have several objects, so a rendezvous cannot
      --  find its other side by which routine is being run. Kept apart from
      --  Cell_Whole for the same reason a place is -- calling an entry of
      --  something that is not a task is a defect the machine catches rather
      --  than a number it follows.
      Cell_Task,

      --  What a raise said, on its way to a handler. A message and the values
      --  that fill it, never the sentence: this machine is below the
      --  presentation boundary. It is a cell because a handler keeps it in a
      --  frame slot -- choosing among handlers reads the name more than once,
      --  and re-raising needs it afterwards -- and a frame slot holds cells.
      Cell_Detail);

   --  How many values one detail message takes. Three, which is what the
   --  widest of them -- a slice outside a String -- needs.
   Max_Detail_Arguments : constant := 3;

   --  A detail's values, in the order the message declares its placeholders.
   --
   --  Positional rather than named because the names are the message's own:
   --  Adash.Messages.Placeholders answers for them, and carrying a copy beside
   --  every value would be a second place for them to be written.
   type Detail_Values is
     array (1 .. Max_Detail_Arguments)
       of Ada.Strings.Unbounded.Unbounded_String;

   type Cell (Kind : Cell_Kind := Cell_None) is record
      case Kind is
         when Cell_Whole =>
            Whole : Whole_Number := 0;

         when Cell_Real =>
            Number : Real := 0.0;

         when Cell_Truth =>
            Truth : Boolean := False;

         when Cell_Letter =>
            Letter : Character := Character'Val (0);

         when Cell_Text =>
            Text : Ada.Strings.Unbounded.Unbounded_String;

         when Cell_Task =>
            --  Which strand runs it. Zero for a task object whose strand
            --  has not been started, which nothing can be called on.
            Strand : Natural := 0;

         when Cell_Place =>
            --  An absolute index into the machine's stack. Absolute rather
            --  than frame-relative because a place outlives the expression
            --  that produced it: it is handed to a callee, stored, and
            --  followed after the frame it was taken in has moved.
            Place : Natural := 0;

            --  How many elements the run at it holds, for a place that stands
            --  for an array. Zero for everything else, and unread there.
            --
            --  Carried by the place rather than by the type because that is
            --  what an unconstrained array parameter needs: the callee is
            --  given a run and has to be told how long it is, and the place is
            --  the one thing that travels from the caller to it. A second
            --  slot in every call would say the same thing at the cost of the
            --  calling convention.
            Extent : Natural := 0;

         when Cell_Detail =>
            Detail : Adash.Messages.Message_Id := Adash.Messages.Msg_Error_None;
            Filled : Natural range 0 .. Max_Detail_Arguments := 0;
            Values : Detail_Values;

         when Cell_None =>
            null;
      end case;
   end record;

   --  What the machine can be told to do.
   --
   --  Named for the construct rather than for the encoding: a reader looking
   --  for how `exit` works should find something called Jump, and a reader
   --  looking for how a String is joined should not have to know which numbered
   --  concatenation it is. Every one of these exists because the lowering emits
   --  it; there is no opcode here waiting for a use.
   type Opcode is
     (
      --  Values onto the stack.
      Push_Whole,        --  Operand is the value
      Push_Real,         --  Operand indexes the real pool
      Push_Text,         --  Operand indexes the text pool
      Push_Truth,        --  Operand is 0 or 1
      Push_Letter,       --  Operand is the position

      --  Frame access. Level is how many static links to walk out: zero is
      --  this frame, one is the frame it was declared in, and so on. A
      --  difference rather than an absolute level, because a routine called
      --  from two depths has one body.
      Load,              --  Push the value in that slot
      Load_Indirect,     --  The slot holds a place; push what is there
      Address,           --  Push the slot itself, as a place

      --  Composite values, which are their parts laid end to end in the
      --  slots. A record's component and an array's element are both `where
      --  the value starts, plus an offset` -- the difference is only that a
      --  record's offset is known when the program is built and an array's is
      --  computed from the subscript.

      --  Move a place along by a fixed number of slots. Operand is the
      --  distance. What reaching a record's component is.
      Offset_Place,

      --  Move a place along by the number on the stack, after checking that
      --  the number is within the array's bounds. What reaching an array's
      --  element is.
      --
      --  Level carries the index of the bound entry -- the first index, the
      --  last, and where the type's name is -- because an index outside an
      --  array has to say which array and what was asked for.
      Element_Place,

      --  Copy a run of slots from one place to another. Operand is how many.
      --  What assigning a whole record or a whole array is.
      --
      --  The destination is under the source on the stack, which is the same
      --  order Store takes them in: a reader of the lowering sees one
      --  convention rather than two.
      Copy_Block,

      --  Push a run of slots as a place, so that a composite value can be
      --  handed on without being taken apart. Operand is the slot.
      Block_At,

      --  Say how long the run at the place on top of the stack is. Operand is
      --  how many elements. What every place standing for an array of a known
      --  length carries, so that a callee given one can ask.
      Run_Of,

      --  Pop a place and push how long the run at it is. What `'Length` is for
      --  an array whose length is not in its type.
      Extent_Of,

      --  Move a place along by the number on the stack, after checking that
      --  the number is within the run the place itself says it has. What
      --  reaching an element of an unconstrained array parameter is: the
      --  bound is the value's rather than the type's. Level carries where the
      --  type's name is, for the message; Operand is how wide one element is.
      Element_Place_Counted,

      --  Pop a place and push what is at it. What reading a component or an
      --  element is, once the place has been worked out.
      Fetch,

      ------------------------------------------------------------------
      --  Concurrency.
      --
      --  Interleaved rather than parallel: the machine runs one strand at a
      --  time and changes strand at defined points. Ada does not require
      --  parallelism -- a single-processor implementation is conforming -- and
      --  what a program may rely on is that its tasks make progress and that
      --  its synchronisation holds, both of which this gives.
      --
      --  Interleaving rather than threads is also the only answer this
      --  repository can give. Anything platform-specific belongs to hostkit,
      --  and a machine that reached for threads of its own would be a second
      --  provider of them.
      ------------------------------------------------------------------

      --  Set a task's priority to the number on the stack, under the task.
      --  Ada's `Set_Priority`.
      --
      --  What it changes is what the scheduler prefers from the next choice
      --  onwards. A running strand is not interrupted by it -- this machine
      --  changes strand at defined points -- so a task that raises its own
      --  priority keeps its turn and is preferred at the next one.
      Set_Priority,

      --  Push what something runs at now. Level is which protected object, or
      --  zero when a task is on the stack instead.
      --
      --  Now, rather than what it was declared with: either may be changed
      --  while the program runs, and a reader that answered from the
      --  declaration would be answering about the past.
      Priority_Now,

      --  Set a protected object's ceiling to the number on the stack. Level is
      --  which object.
      --
      --  Said once where the object is elaborated, and again wherever a
      --  program assigns to its `'Priority`. The ceiling lives with the object
      --  rather than in the instruction that takes its lock, because a program
      --  may change it and every operation has to be asking the same question.
      Ceiling_Is,

      --  Say what priority the next task started will run at. Operand is the
      --  priority.
      --
      --  Said before starting rather than carried by Start_Task, whose two
      --  fields already say which routine and at what level -- and a priority
      --  is a property of the task rather than of the instruction that makes
      --  it.
      Priority_Is,

      --  Start a task. Operand is the routine to run; Level is the level it
      --  was declared at, so it finds the frame it was declared in.
      --
      --  Pushes the task, which is a value naming the strand. A task type may
      --  have several objects and each is a task of its own, so what a
      --  rendezvous or an abort names is the strand rather than the routine --
      --  one routine may be being run by several.
      Start_Task,

      --  End the strand running this. What a task body reaches instead of
      --  returning: there is no caller to return to.
      End_Task,

      --  Wait until every strand this one started has ended. What a
      --  declarative region does when it is left, which is Ada's rule: a
      --  master does not finish while what depends on it is still running.
      Await_Tasks,

      --  Begin and end a region inside a frame, for a block statement.
      --
      --  A block is a master in Ada and makes no frame here, so the frame
      --  alone cannot say which of them a task belongs to. Enter_Region pushes
      --  the region being left, for the block to keep and hand back;
      --  Leave_Region waits for what the block started and takes it back off
      --  the stack.
      --
      --  A region is numbered rather than counted, so that leaving one and
      --  entering another does not make the second look like the first: what
      --  the numbers are for is telling two regions apart, and a depth cannot.
      Enter_Region,
      Leave_Region,

      --  Wait for what a raise abandoned, before a handler runs.
      --
      --  An exception on its way out of a block or a body completes what it
      --  leaves, and completing a master waits for its dependents -- so a
      --  handler runs after them, not beside them. The unwind itself cannot
      --  wait: it is reached from inside whatever raised, and waiting means
      --  giving up the turn. This stands where the unwind lands instead, which
      --  is the same moment from the program's point of view and a place a
      --  strand can be set aside from.
      Await_Abandoned,

      --  Take and release the lock on a protected object. Operand is which
      --  object -- an index into the run's protected objects -- and Level is
      --  the ceiling it was declared with, which stands until the object is
      --  elaborated and says its own.
      --
      --  A task of higher priority than the ceiling may not call it: Ada's
      --  rule, and the reason for one is that a task inside a protected
      --  operation runs at the ceiling, so a caller above it would be lowered
      --  by calling. Here nothing changes strand inside one, so the ceiling
      --  has nothing to raise; what is left is the rule, and a program that
      --  breaks it is told rather than left to think it was honoured.
      --
      --  Between these two the machine does not change strand, which is what
      --  makes a protected operation mutually exclusive. On an interleaving
      --  machine that is not an optimisation, it is the whole implementation.
      Enter_Protected,
      Leave_Protected,

      --  Join the queue of a protected entry. Which entry is on the stack,
      --  because a member of a family is one the caller computes; Operand is
      --  which object.
      --
      --  A caller of a *task* entry says which one when it calls; a caller of a
      --  *protected* entry is set aside by the barrier, which knows the object
      --  and not the entry. This is what tells them apart, and it is what
      --  `'Count` counts by -- a strand is in the queue from here until it is
      --  through the barrier, whether it is asleep on it at the moment or
      --  awake and about to ask it again.
      Waiting_At,

      --  Push how many callers are queued at an entry. Ada's `E'Count`.
      --
      --  Which entry is on the stack, because a member of a family is one the
      --  program computes; Operand is the protected object, or zero for an
      --  entry of a task. The two queue in different places -- a task's caller
      --  waits for a rendezvous and a protected object's waits on a barrier --
      --  and what `'Count` means is the same question about either.
      Entry_Count,

      --  Wait for a barrier, whose value is on the stack. Level is the
      --  protected object; Operand is where the barrier's own instructions
      --  begin.
      --
      --  A strand that finds it closed is set aside until the object is next
      --  left, and *re-evaluates* the barrier when it wakes -- which is what
      --  the retry address is for. Testing the old value again would answer
      --  the question the strand went to sleep on rather than the one that
      --  woke it.
      Await_Barrier,

      --  Push the seconds on the clock. Ada's `Ada.Real_Time.Clock`, as a
      --  number this language has: seconds since the session began, from the
      --  monotonic clock -- monotonic rather than calendar, so a program that
      --  measures an interval measures one whatever somebody does to the
      --  system time.
      Read_Clock,

      --  Suspend this strand until the clock reads the number on the stack.
      --  Ada's `delay until`.
      --
      --  Absolute where the other is relative, and that is the whole reason
      --  Ada has both: a loop that delays for a tenth of a second drifts by
      --  however long its own body takes, and one that delays until the next
      --  tenth does not.
      Delay_Until,

      --  Pop a task and push how many seconds it has run for.
      --
      --  Run for, not waited: what it has had turns for. A task that spends
      --  its life at a barrier has used none of it, which is what makes this
      --  worth asking rather than reading the clock twice.
      Execution_Time,

      --  Suspend this strand for the number of seconds on the stack, letting
      --  the others run. Ada's `delay`.
      --
      --  Real time, from Ada's own clock. A delay that only yielded would make
      --  `delay 1.0` a lie, and a script that waits a second for something is
      --  the commonest reason to write one at all.
      Delay_For,

      ------------------------------------------------------------------
      --  Rendezvous.
      --
      --  A caller and a task meeting at an entry. The caller waits for the
      --  task to accept; the task waits for a caller; and between the two
      --  moments the accept body runs, reading and writing the caller's own
      --  arguments.
      --
      --  The arguments travel as a *place*: the caller writes them into a run
      --  of its own slots and hands over where the run starts, and the accept
      --  body's formals are references into it. That is the same mechanism a
      --  composite parameter already uses, and it is what makes an `out`
      --  parameter of an entry come back -- the callee wrote into the caller's
      --  slots, because that is where the formals pointed.
      ------------------------------------------------------------------

      --  Call an entry of a task. Level is which entry. The task and then the
      --  place of the argument block are on the stack.
      --
      --  Operand says whether the entry is one of a *family*: a family is a
      --  run of entries rather than one, and which member was meant is a value
      --  the program computes. When it is 1 the member's offset within the run
      --  is on the stack, under the task, and the entry is Level plus it.
      Call_Entry,

      --  Take a caller waiting at this entry, if one is. Level is which entry,
      --  and Operand says whether an offset within a family is on the stack.
      --
      --  Pushes the caller's argument place and True when one was taken, and
      --  False alone when none was. Never waits: waiting is Await_Caller's
      --  business, and keeping the two apart is what lets one accept and a
      --  select over several read the same way.
      --
      --  Callers are taken in the order they arrived, or by priority where
      --  the program said so: an entry queue is a queue, and an acceptor that
      --  chose by strand number would starve whoever happened to be late in
      --  the array.
      --
      --  Inside a selective accept it takes only from the entry the choice
      --  settled on, so that the alternative served is the one holding the
      --  caller who comes first across all of them rather than whichever is
      --  written first.
      Try_Accept,

      --  Give the call that follows a deadline. The stack holds how long, in
      --  seconds.
      --
      --  A call to a *protected* entry is a call to its body, which waits at
      --  the barrier inside it -- so there is no call instruction to carry the
      --  deadline the way a rendezvous carries one, and it is said before
      --  instead.
      Call_Deadline,

      --  Whether the entry call just made was met, for a call that was given
      --  a deadline or made only if it could be met at once. Pushes True when the rendezvous happened and False when
      --  the wait ran out, and takes a caller that ran out off the queue.
      --
      --  A separate instruction because the answer is only knowable where the
      --  caller resumes, and it resumes in the same place either way: what
      --  tells the two apart is whether it is still queued.
      Call_Answer,

      --  Offer the alternative that says this task may end instead of
      --  waiting. Operand is where to go if it is taken, and the stack holds
      --  whether it is open.
      --
      --  Ada's `terminate` alternative, and what makes it different from
      --  every other is that nothing the task itself does decides it: it is
      --  taken when the master this task depends on has finished and every
      --  task that depends on that master is either over or waiting at one of
      --  these. So the strand writes down that it is willing and where to go,
      --  and the scheduler is what notices.
      Offer_End,

      --  Begin or end choosing among a selective accept's alternatives.
      --  Operand is 1 to begin and 0 to end.
      --
      --  Bracketed rather than standing: a plain accept is the same Try_Accept
      --  with no choice around it, and one left over from a select that
      --  finished would refuse the caller it should take.
      Choose,

      --  Offer one alternative. Level is which entry, Operand says whether an
      --  offset within a family is on the stack, and the stack holds whether
      --  the alternative is open.
      --
      --  Two things at once, and both are about what an open alternative is.
      --  An offered entry is written down on the strand, so that a strand set
      --  aside waiting for a caller can be asked what it would take -- which
      --  is the whole of what a conditional call needs to know. And where the
      --  program said priority queuing, the offer also says who is at the head
      --  of this alternative's queue, so the choice can keep the best.
      --
      --  Where the rule that a select serves its best caller lives: each open
      --  alternative says who is at the head of its queue, and the choice
      --  keeps the one that comes first under the queuing policy. Ties keep
      --  the alternative written first, because that is the order they are
      --  offered in.
      Offer_Entry,

      --  Wait until somebody calls an entry of this task. Operand is where to
      --  go back to when one does.
      --
      --  Which entry is deliberately not asked. The strand goes back and tries
      --  its alternatives again, so what it accepts is decided by looking
      --  rather than by having said in advance -- which is what a select over
      --  several entries needs, and what one accept needs too when the caller
      --  that arrives is at a different entry.
      Await_Caller,

      --  Let the caller go on. Level is which entry, and Operand says whether
      --  an offset within a family is on the stack.
      End_Accept,

      --  Put the caller being served on another entry's queue. Ada's
      --  `requeue`. Both entries are on the stack -- the one it was taken
      --  from, then the one it is moved to -- because either may be a member
      --  of a family, and which member is something the body works out.
      --
      --  The caller is not resumed and is not told: from its own point of view
      --  it is still waiting for the call it made, which is the whole of what
      --  makes requeue different from returning and being called again. It
      --  joins the end of the target queue, because it is arriving at it now.
      Requeue_Entry,

      --  Put this strand on another protected entry's queue. Operand is the
      --  entry's routine, and what that routine takes -- which member of a
      --  family, when it is one -- is on the stack, as it would be for a call.
      --
      --  The other kind of queue, and the other way of joining it. A caller of
      --  a *protected* entry queues by being inside that entry's own body,
      --  parked at its barrier -- so moving it to another entry is a matter of
      --  leaving this body and entering that one, keeping the place the call
      --  came from. A tail call, which is what a requeue of this kind is.
      Requeue_Guarded,

      --  Watch a task, so that a wait ends when it does.
      --
      --  Ada's `select ... then abort` needs it: the abortable part runs as a
      --  strand of its own and the trigger waits in this one, and a trigger
      --  that could only end on its own terms would leave the select waiting
      --  for a delay whose reason to exist had already finished.
      --
      --  Watch_Task pops the task to watch; Watch_Nothing goes back to
      --  waiting on nothing else. Explicit rather than cleared by whatever
      --  wait comes next, because "until X ends" is a property of one wait and
      --  the next wait is a different question.
      Watch_Task,
      Watch_Nothing,

      --  Pop a task and push whether it has ended. Ada's `T'Terminated`.
      --
      --  What a select asks after its trigger too: a wait that ended because
      --  the abortable part finished is a cancelled trigger, and its
      --  statements do not run.
      Task_Ended,

      --  Pop a task and push whether a call to it would be met. Ada's
      --  `T'Callable`.
      --
      --  Not the negation of the other one. A task that has run its body out
      --  and is waiting for what depends on it has *completed* without having
      --  *terminated*: it has ended nothing and will meet nobody, so both
      --  questions answer False.
      Task_Callable,

      --  Stop the task on the stack. Ada's `abort`.
      --
      --  It takes effect where the strand next would have run, which is the
      --  next switch point: this machine interleaves rather than pre-empts, so
      --  there is no moment between two instructions at which to intervene.
      --  Stop the tasks on the stack, however many the operand says. All of
      --  them are stopped before any of their callers is told, because Ada
      --  aborts what one statement names as one action -- and telling a
      --  caller resumes it, which would let it run between two of them.
      Abort_Task,

      --  Pop two places and push whether the runs at them hold the same
      --  values. Operand is how many slots. What comparing two records or two
      --  arrays is.
      Same_Block,

      --  Pop text and push it as this language would write it down: in
      --  quotes, with an internal quote doubled. What `'Image` is for every
      --  other type, and a String has none -- Ada images one as the text in
      --  quotes with the non-graphic characters bracketed, which is not what
      --  reads back.
      Quote_Text,
      Store,             --  Pop a value and a place; put the one in the other

      Discard,           --  Pop and forget

      --  Exchange the top two. For the one case where a value arrives before
      --  the place it belongs in: the machine pushes what it raised, and a
      --  handler stores it.
      Swap,

      --  Arithmetic. One opcode per type rather than one with a tag: the
      --  lowering knows the type and a machine that decided at run time would
      --  be deciding something already decided.
      Add_Whole, Subtract_Whole, Multiply_Whole, Divide_Whole,
      Modulo_Whole, Remainder_Whole, Power_Whole, Negate_Whole, Absolute_Whole,

      Add_Real, Subtract_Real, Multiply_Real, Divide_Real,
      Power_Real, Negate_Real, Absolute_Real,

      --  Comparison, per type, each leaving a truth on the stack.
      Equal_Whole, Unequal_Whole, Less_Whole, Less_Equal_Whole,
      Greater_Whole, Greater_Equal_Whole,

      Equal_Real, Unequal_Real, Less_Real, Less_Equal_Real,
      Greater_Real, Greater_Equal_Real,

      Equal_Text, Unequal_Text, Less_Text, Less_Equal_Text,
      Greater_Text, Greater_Equal_Text,

      And_Truth, Or_Truth, Xor_Truth, Not_Truth,

      --  Control. Operand is the instruction to go to.
      Jump,
      Jump_If_False,          --  Pops the truth it tested
      Jump_If_False_Keeping,  --  Leaves it, for `and then`
      Jump_If_True_Keeping,   --  Leaves it, for `or else`

      --  Calls. Operand names a routine in the program's table; the arguments
      --  are already on the stack, in order.
      Call,
      Return_Plain,
      Return_Value,

      --  The shell. Operand is how many arguments follow the name on the
      --  stack; the name is deepest. What comes back is one cell, and whether
      --  the program should stop.
      Call_Host,

      --  Text.
      Join_Text,            --  two texts
      Join_Text_Letter,     --  text then letter
      Join_Letter_Text,     --  letter then text
      Text_Length,
      Text_Element,         --  text, position
      Text_Slice,           --  text, first, last

      --  Writing into a String rather than reading out of one. Each takes the
      --  whole text and yields the whole text changed, because a String is one
      --  cell here rather than a run of slots: what a program calls assigning
      --  to a part of one is building the new whole and storing it, and the
      --  instruction is where the checks live.
      Text_Set_Element,     --  text, position, letter
      Text_Set_Slice,       --  text, first, last, replacement

      --  Searching and shaping. Ada spells these in packages --
      --  Ada.Strings.Fixed.Index, Ada.Characters.Handling.To_Upper -- and this
      --  language has no packages to spell, so they are named directly. The
      --  names are Ada's own; what is missing is only the road to them.
      Text_Index,           --  whole, piece: where it starts, or zero
      Text_Trim,
      Text_Upper,
      Text_Lower,
      Text_Starts,          --  whole, piece
      Text_Ends,

      --  Between text and the scalar types, both ways. `'Image` and `'Value`.
      Image_Whole, Image_Real, Image_Truth, Image_Letter,

      --  What `put` writes rather than what Ada writes down. Ada images a
      --  number with a space where the sign would go and a Character in
      --  quotes; a shell writing 42 should write `42`.
      Image_Whole_Bare,

      --  A Character as itself rather than as Ada writes it down. What `put`
      --  puts: `q`, not `'q'`.
      Image_Letter_Bare,
      Value_Whole, Value_Real, Value_Truth, Value_Letter,

      --  Between a discrete value and its position, both ways. `'Pos` and
      --  `'Val`. An Integer is its own position, so there is no instruction
      --  for it -- the lowering emits nothing and the value is already right.
      --
      --  `'Succ` and `'Pred` are these two with an addition between them,
      --  which is what Ada defines them as, so they need no instruction of
      --  their own either. What they do need is the check: going past the last
      --  Character raises, and it raises in the Val below rather than in three
      --  places that would each have to remember to.
      Position_Letter, Letter_At_Position,
      Position_Truth, Truth_At_Position,

      --  Between an enumeration value and its name, both ways.
      --
      --  A value of an enumeration *is* its position, so there is nothing to
      --  convert: what these two do is find the name. The literal names are
      --  interned in the same table string literals go in, one contiguous run
      --  per type -- so the instruction says where the run starts and how long
      --  it is, and needs no table of its own.
      --
      --  Level carries the count and Operand the first name`s index. Both
      --  fields exist on every instruction and neither was doing anything
      --  here, which is what makes a two-number instruction free.
      Image_Enumeration, Value_Enumeration,

      --  Check that a position is one of an enumeration's, and raise when it
      --  is not. What `'Val` does, and what `'Succ` and `'Pred` reach after
      --  their addition -- so going past either end raises in one place.
      --  Level carries the count.
      Enumeration_At_Position,

      --  Check that the value on top of the stack is within a subtype's
      --  bounds, and raise when it is not. The value stays where it is: this
      --  is a check on the way past, emitted wherever a value is stored into
      --  something declared with a range.
      --
      --  Level carries the index of the first of two whole literals holding
      --  the bounds, because an instruction has room for one number and a
      --  range is two. Operand carries the index of the subtype's name.
      Check_In_Range,

      --  Output. The machine writes because the program writes as it runs:
      --  what a program says arrives where it says it, interleaved with what a
      --  command produced, which is the order a reader expects. Holding it
      --  back until the submission finished put a program's own lines after
      --  text written later.
      Write,        --  Pop a text and write it
      Write_Line,   --  Pop a text, write it, and end the line
      New_Line,

      --  A function that fell off its end. Ada raises; so does this, rather
      --  than handing back whatever was on the stack.
      Raise_No_Return,

      --  Handlers.
      --
      --  A handler is a place to go and a mark of how much of the machine to
      --  put back before going there: how deep the frames were, how deep the
      --  operand stack was. Raising unwinds to that mark, which is what makes
      --  a handler in an outer block able to catch what an inner call raised
      --  -- the frames in between are gone by the time it runs.
      --
      --  The exception's name is pushed as text where the handler can read it,
      --  because which one was raised is what a handler chooses on.
      Push_Handler,   --  Operand is where to go
      Pop_Handler,    --  The block ended without raising

      --  Raise again what a handler was given. What `when others` does with
      --  something it does not want, and what a handler that matched nothing
      --  does: an exception nobody handled must not be swallowed by having
      --  been looked at.
      Raise_Again,

      --  Raise what the program named. Operand is which text, and there is no
      --  detail: a program's own exception says what its name says, where the
      --  machine's own carry a message saying what went wrong.
      Raise_Named,

      --  Stop. The program is over and whatever it produced stands.
      Halt);

   --  One instruction.
   type Instruction is record
      Code : Opcode := Halt;

      --  How many static links to walk, for the frame opcodes.
      Level : Natural := 0;

      --  A slot, a literal, a jump target, a routine, an argument count --
      --  whichever the opcode says. Wide enough to carry a whole-number
      --  literal, which is the largest thing an operand ever is.
      Operand : Whole_Number := 0;
   end record;

   --  A program the machine can run.
   type Program is tagged limited private;

   --  Start an empty one.
   --
   --  @param Item Program to clear.
   procedure Reset (Item : in out Program);

   --  Add an instruction.
   --
   --  @param Item Program to add to.
   --  @param Code The opcode.
   --  @param Level Static-link distance, where the opcode uses one.
   --  @param Operand Its operand, where the opcode uses one.
   --  @return Where it landed, so a jump can be patched to it later.
   function Add
     (Item    : in out Program;
      Code    : Opcode;
      Level   : Natural := 0;
      Operand : Whole_Number := 0) return Natural;

   --  Add an instruction whose landing place nothing needs.
   --
   --  @param Item Program to add to.
   --  @param Code The opcode.
   --  @param Level Static-link distance, where the opcode uses one.
   --  @param Operand Its operand, where the opcode uses one.
   procedure Add
     (Item    : in out Program;
      Code    : Opcode;
      Level   : Natural := 0;
      Operand : Whole_Number := 0);

   --  Where the next instruction will land.
   --
   --  @param Item Program to measure.
   --  @return The index Add would return.
   function Next (Item : Program) return Natural;

   --  Point a jump at somewhere decided after it was written.
   --
   --  @param Item Program to change.
   --  @param At_Index The jump.
   --  @param Target Where it should go.
   procedure Patch (Item : in out Program; At_Index : Natural; Target : Natural);

   --  Keep a text literal, and say where it went.
   --
   --  @param Item Program to add to.
   --  @param Value The text.
   --  @return Its index, for Push_Text.
   function Text_Literal (Item : in out Program; Value : String) return Natural;

   --  Keep a real literal, and say where it went.
   --
   --  @param Item Program to add to.
   --  @param Value The number.
   --  @return Its index, for Push_Real.
   function Real_Literal (Item : in out Program; Value : Real) return Natural;

   --  Record what a constraint admits and say where it went.
   --
   --  Three numbers in one entry, because an instruction has room for one and
   --  a constraint is more than one: the two bounds, and -- for an enumeration
   --  -- where its literal names begin, so that a value outside the range can
   --  be reported as the name somebody wrote rather than as a position.
   --
   --  @param Item The program being built.
   --  @param Low The first value admitted.
   --  @param High The last.
   --  @param Names Where the type's literal names begin, or zero when it has
   --         none.
   --  @return The index of the entry.
   function Bound_Entry
     (Item  : in out Program;
      Low   : Whole_Number;
      High  : Whole_Number;
      Names : Natural := 0) return Natural;

   --  Record a routine so calls can name it.
   --
   --  Declared before its body is emitted, because a call may come first: the
   --  entry point and frame size are filled in when the body is done.
   --
   --  @param Item Program to add to.
   --  @return Its index, for Call.
   function Declare_Routine (Item : in out Program) return Positive;

   --  Say where a routine's body is and how big its frame must be.
   --
   --  @param Item Program to change.
   --  @param Which The routine.
   --  @param Entry_At Its first instruction.
   --  @param Frame How many slots its frame holds, parameters included.
   --  @param Parameters How many of those the caller pushes.
   --  @param Level How deep it is declared: zero at the outermost.
   procedure Define_Routine
     (Item       : in out Program;
      Which      : Positive;
      Entry_At   : Natural;
      Frame      : Natural;
      Parameters : Natural;
      Level      : Natural);

   --  How many slots the outermost frame holds.
   --
   --  @param Item Program to change.
   --  @param Slots The count.
   procedure Set_Frame (Item : in out Program; Slots : Natural);

   --  Say how many callers this program allows at one entry's queue.
   --
   --  Ada's `pragma Restrictions (Max_Entry_Queue_Length => N)`, and a
   --  run-time question for the reason Max_Tasks is: what a program queues is
   --  not something a reader can count.
   --
   --  @param Item Program to bound.
   --  @param Most How many, at one entry.
   procedure Allow_Queued (Item : in out Program; Most : Natural);

   --  Say that this program runs its tasks first-in-first-out within a
   --  priority, rather than sharing the processor out between them.
   --
   --  Ada's `pragma Task_Dispatching_Policy (FIFO_Within_Priorities)`, and
   --  Ravenscar's. What it means here is that a strand keeps its turn until it
   --  waits for something: no quantum, so nothing is taken from it. That is
   --  what Ada's policy says on one processor, and it is why Ravenscar names
   --  it -- an interleaving nobody slices is one a reader can follow.
   --
   --  The cost is Ada's too: a task that computes for ever and waits for
   --  nothing keeps the machine. Ada's answer is that such a program is
   --  wrong, and this one's is the same, with the interrupt still asked for
   --  between instructions.
   --
   --  Ada's `pragma Priority_Specific_Dispatching` gives the policy to a
   --  range of priorities rather than to all of them, which is why this takes
   --  one: a policy that could only be said about the whole program would
   --  make that pragma a lie or a second mechanism.
   --
   --  @param Item Program to mark.
   --  @param First Lowest priority the policy is given to.
   --  @param Last Highest priority the policy is given to.
   procedure Run_To_Completion
     (Item : in out Program;
      First : Natural := Lowest_Priority;
      Last : Natural := Highest_Priority);

   --  Say that this program takes callers off an entry queue by priority
   --  rather than in the order they arrived.
   --
   --  Ada's `pragma Queuing_Policy (Priority_Queuing)`. Among callers of equal
   --  priority the order they arrived in still decides, which is what makes
   --  this an ordering rather than a lottery.
   --
   --  @param Item Program to mark.
   procedure Queue_By_Priority (Item : in out Program);

   --  Say that this program's tasks are not to run out.
   --
   --  Ada's `pragma Restrictions (No_Task_Termination)`: a program whose
   --  concurrency is fixed when it starts has nothing to gain by a task
   --  ending, and something to lose in what it leaves behind.
   --
   --  @param Item Program to mark.
   procedure Forbid_Termination (Item : in out Program);

   --  Say how many tasks this program allows itself at once.
   --
   --  Ada's `pragma Restrictions (Max_Tasks => N)`. Checked while the program
   --  runs rather than where it is written, because what a loop starts is not
   --  something a reader can count.
   --
   --  @param Item Program to bound.
   --  @param Most How many, at once.
   procedure Allow_Tasks (Item : in out Program; Most : Natural);

   --  Say that this program asked for blocking operations to be detected.
   --
   --  Ada's `pragma Detect_Blocking`, which is a configuration pragma: it is
   --  about the whole program rather than about the point it was written at,
   --  so it is a property of the program rather than an instruction in it.
   --
   --  @param Item Program to mark.
   procedure Detect_Blocking (Item : in out Program);

   --  How many instructions it holds.
   --
   --  @param Item Program to measure.
   --  @return The count.
   function Length (Item : Program) return Natural;

   ---------------------------------------------------------------------------
   --  Running
   ---------------------------------------------------------------------------

   --  What the shell answers a Call_Host with.
   type Answer is record
      Value : Cell;

      --  True when the shell has decided the program should stop -- `quit`.
      Halt : Boolean := False;
   end record;

   --  Arguments handed to the shell, in the order they were written.
   type Cell_Array is array (Positive range <>) of Cell;

   --  What the machine calls out to.
   type Host is limited interface;

   --  Run one command or answer one question.
   --
   --  @param Item The implementation.
   --  @param Name What is being called.
   --  @param Arguments What it was given.
   --  @param Count How many of them are meaningful.
   --  @param Result What to push, and whether to stop.
   procedure Call
     (Item      : in out Host;
      Name      : String;
      Arguments : Cell_Array;
      Count     : Natural;
      Result    : out Answer) is abstract;

   --  Whether the user has asked the program to stop.
   --
   --  Asked between instructions. A machine that could not be interrupted
   --  would make one runaway loop the end of the session.
   --
   --  @param Item The implementation.
   --  @return True to stop.
   function Stop_Requested (Item : in out Host) return Boolean is abstract;

   type Host_Access is access all Host'Class;

   --  What became of a run.
   type Outcome is
     (
      --  It reached the end, or a Halt.
      Ran,

      --  It raised: see the name and the detail.
      Raised,

      --  The user interrupted it.
      Stopped,

      --  The machine itself could not go on -- a stack that overflowed, an
      --  instruction that cannot be right. A defect here rather than in the
      --  program, and said differently for that reason.
      Broken);

   --  What a run produced.
   type Result is record
      What : Outcome := Ran;

      --  For Raised: the exception's name, as Ada spells it, and what it said.
      --
      --  The name is a string because it is an Ada identifier -- a handler
      --  chooses on it, and translating it would break the choosing. What it
      --  said is a message, because a user reads it: this package is below the
      --  presentation boundary and has no business producing a sentence.
      Raised_Name  : Ada.Strings.Unbounded.Unbounded_String;
      Detail       : Adash.Messages.Message_Id := Adash.Messages.Msg_Error_None;
      Detail_Count : Natural range 0 .. Max_Detail_Arguments := 0;
      Detail_Given : Detail_Values;

      --  How many instructions were executed, for a test that wants to know
      --  the machine did something rather than returned early.
      Steps : Natural := 0;
   end record;

   --  Run a program.
   --
   --  @param Item The program.
   --  @param On_Host Where a command call goes, or null for a program that
   --         makes none.
   --  @param Produced What became of it.
   procedure Run
     (Item     : in out Program;
      On_Host  : Host_Access;
      Produced : out Result);

   --  Read a slot of the outermost frame after a run.
   --
   --  How a submission's variables are carried into the next one: the frame is
   --  kept until the next run, so what a program declared can still be read.
   --
   --  @param Item The program that ran.
   --  @param Slot Which slot.
   --  @return What is in it.
   function Slot_Value (Item : Program; Slot : Natural) return Cell;

private

   type Instruction_Array is array (Positive range <>) of Instruction;
   type Instruction_Access is access Instruction_Array;

   type Text_Array is
     array (Positive range <>) of Ada.Strings.Unbounded.Unbounded_String;
   type Text_Access is access Text_Array;

   type Real_Array is array (Positive range <>) of Real;
   type Real_Access is access Real_Array;

   type Bound_Array is array (Positive range <>) of Whole_Number;
   type Bound_Access is access Bound_Array;

   type Routine is record
      Entry_At   : Natural := 0;
      Frame      : Natural := 0;
      Parameters : Natural := 0;
      Level      : Natural := 0;
   end record;

   type Routine_Array is array (Positive range <>) of Routine;
   type Routine_Access is access Routine_Array;

   type Cell_Access is access Cell_Array;

   type Program is tagged limited record
      Code       : Instruction_Access;
      Code_Used  : Natural := 0;

      Texts      : Text_Access;
      Texts_Used : Natural := 0;

      Reals      : Real_Access;
      Reals_Used : Natural := 0;

      --  What a Check_In_Range admits, three numbers to an entry. Whole
      --  numbers rather than reals because every constrained type here is
      --  discrete.
      Bounds      : Bound_Access;
      Bounds_Used : Natural := 0;

      Routines      : Routine_Access;
      Routines_Used : Natural := 0;

      --  The outermost frame's size, and the frame itself once it has run.
      Frame  : Natural := 0;
      Kept   : Cell_Access;

      --  Whether this program asked for blocking operations inside a
      --  protected action to be caught. Ada's `pragma Detect_Blocking`.
      Detecting : Boolean := False;

      --  How many tasks it allows itself at once, and whether it said.
      Task_Limit : Natural := 0;
      Bounded    : Boolean := False;

      --  How many callers it allows at one entry, and whether it said.
      Queue_Limit : Natural := 0;
      Queue_Bound : Boolean := False;

      --  Whether its tasks are forbidden to run out.
      Endless : Boolean := False;

      --  Which priorities a strand keeps its turn at until it waits for
      --  something. Per priority rather than per program, because Ada lets a
      --  program say it of a range.
      Uninterrupted : Priority_Policy := [others => False];

      --  Whether an entry queue is taken from by priority rather than in the
      --  order callers arrived.
      By_Priority : Boolean := False;
   end record;

end Adash.Machine;
