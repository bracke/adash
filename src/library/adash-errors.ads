with Adash.Messages;

--  Operational failures, as data.
--
--  These are the things that go wrong when a shell is working correctly: a
--  command that is not installed, a file that will not open, a child that could
--  not be started, a lock somebody else holds. None of them is a defect, and
--  none of them is an exception. A caller has to be able to handle every one of
--  them without an exception handler, because handling them *is* the shell's
--  job -- reporting "command not found" is not error recovery, it is the
--  feature.
--
--  Exceptions remain for defects: a violated contract, an impossible state, a
--  broken invariant. If an exception reaches a user, something is wrong with
--  Adash rather than with what they typed.
--
--  An Error_Info carries a code and structured arguments, never a sentence. The
--  code is stable and testable, the arguments are typed, and the words arrive
--  only at the presentation boundary. That is what lets one failure be rendered
--  for a terminal, written to a log, and asserted on by identity in a
--  conformance case, without any of the three parsing another's output.
package Adash.Errors is

   --  Which subsystem's vocabulary a code belongs to.
   --
   --  Recorded so that a failure can be attributed without parsing its code:
   --  a report that groups by subsystem, or a test that asserts execution
   --  produced no language failures, both need it.
   type Error_Domain is
     (Domain_None,
      Domain_Language,
      Domain_Execution,
      Domain_Platform,
      Domain_Persistence,
      Domain_Configuration);

   --  Every operational failure Adash can report.
   --
   --  One flat enumeration rather than one per subsystem. A failure crosses
   --  subsystems on its way to a user -- the execution subsystem's "not found"
   --  is reported by the engine and rendered by the frontend -- and a code that
   --  has to be translated at each boundary loses its identity at the first one.
   type Error_Code is
     (
      --  Not a failure. The default, so a defaulted Error_Info is success.
      Error_None,

      --  Execution: starting a program.
      Error_Command_Not_Found,
      Error_Command_Not_Executable,
      Error_Command_Denied,
      Error_Command_Start_Failed,

      --  Execution: streams and redirection.
      Error_Redirection_Open_Failed,
      Error_Redirection_Conflict,
      Error_Pipe_Creation_Failed,
      Error_Stream_Write_Failed,
      Error_Stream_Read_Failed,

      --  Writing a file the script named. Two codes rather than one because
      --  a path that cannot be written at all is the user's mistake, and a
      --  write that started and stopped is the machine's.
      Error_File_Not_Writable,
      Error_File_Write_Failed,

      --  Execution: jobs and cancellation.
      Error_Job_Unknown,

      --  A suspended job, where the caller wanted one that would end.
      Error_Job_Is_Suspended,
      Error_Cancelled,

      --  Platform: something this host cannot do.
      Error_Capability_Unavailable,

      --  Working directory.
      Error_Directory_Not_Found,
      Error_Directory_Denied,

      --  Source acquisition.
      Error_Source_Unreadable,

      --  A script named by something that resolves to no file.
      Error_Module_Not_Found,
      Error_Source_Invalid_Encoding,

      --  Language: names and types.
      Error_Type_Mismatch,
      Error_Name_Undeclared,
      Error_Name_Already_Declared,

      --  Language: lexical.
      Error_Lexical_Stray_Character,
      Error_Lexical_Unterminated_String,
      Error_Lexical_Unterminated_Character,
      Error_Lexical_Malformed_Number,
      Error_Lexical_Malformed_Identifier,

      --  A backslash escape inside an interpolated string that this build does
      --  not define, and a closing brace that was not escaped.
      Error_Lexical_Bad_Escape,
      Error_Lexical_Brace_Unescaped,

      --  A doubled quote inside an interpolated string. Ada 2022 forbids it:
      --  the escape is what puts a quote in one.
      Error_Lexical_Quote_In_Interpolation,

      --  Language: syntax.
      Error_Syntax_Unexpected,
      Error_Syntax_Missing,
      Error_Syntax_Mixed_Logical_Operators,

      --  Language: semantics.
      Error_Not_Assignable,
      Error_Not_A_Type,
      Error_Not_Callable,

      --  A handler naming something nothing raises.
      Error_Not_An_Exception,

      --  A case statement that cannot be run as written: something that is not
      --  a discrete value, a choice that is not static, a value covered twice,
      --  a range that runs backwards, `others` somewhere other than last, or a
      --  set of choices that leaves a value unaccounted for. Each is separate
      --  because each is a different mistake with a different fix.
      --  A String indexed or sliced by something that is neither one
      --  position nor one range of them.
      --  A statement written where a declaration belongs. Ada draws the
      --  line at `begin` and so does this, even though a declaration is
      --  parsed as a statement here.
      Error_Statement_Among_Declarations,

      Error_String_Index_Malformed,
      Error_Not_Taken_Apart,
      Error_No_Such_Slice,
      Error_Needs_Bounds,
      Error_Open_By_Element,
      Error_Too_Many_At_Once,
      Error_Too_Many_Parameters,

      Error_Case_Not_Discrete,
      Error_Case_Choice_Not_Static,
      Error_Case_Choice_Covered_Twice,
      Error_Case_Range_Is_Empty,
      Error_Case_Others_Not_Last,
      Error_Case_Incomplete,

      --  A call that yields a value, written where a statement belongs. Ada
      --  has no expression statement, and neither does this: `F (2);` on its
      --  own computes something and discards it, which is more often a
      --  forgotten assignment than an intention.
      Error_Function_As_Statement,

      --  An exit statement outside any loop. Illegal Ada, and illegal here for
      --  the same reason: there is nothing for it to leave.
      Error_Exit_Outside_Loop,

      --  A subprogram nested deeper than this build analyses. The analyser and
      --  the lowering each recurse once per level, and refusing by name is a
      --  better answer than the compiler's own stack running out.
      Error_Nested_Subprogram,

      --  An expression passed where the subprogram writes back. There is
      --  nowhere for the write to go: the argument would be a value on the
      --  stack that the return pops.
      Error_Actual_Not_Variable,

      --  An attribute the prefix's type does not have.
      Error_Attribute_Not_Defined,

      --  A subprogram named after something the shell already provides.
      --
      --  Ada would let this overload. Here it is refused, because the shell's
      --  own subprograms take any type -- `put_line` images whatever it is
      --  given -- so a user's version of one would fit every call the original
      --  does, and every such call would be ambiguous. A declaration whose
      --  every use is an error is worse than no declaration.
      Error_Name_Is_Predefined,

      --  A specification whose body never arrived. The name exists and calls
      --  to it would jump to code nobody wrote.
      Error_Body_Missing,

      --  A name that denotes several subprograms, where the arguments fit none
      --  of them or fit more than one.
      Error_No_Matching_Subprogram,
      Error_Ambiguous_Call,

      --  `return;` where a value is required, and `return X;` where none is.
      Error_Return_Without_Value,
      Error_Return_With_Value,
      Error_Condition_Not_Boolean,
      Error_Operator_Not_Defined,

      --  Language: lowering.
      Error_Not_Lowerable,

      --  The program ran and raised. Two codes because the machine sometimes
      --  has a detail worth quoting and sometimes does not, and a message
      --  ending in a colon with nothing after it reads as truncated output.
      Error_Program_Raised,
      Error_Program_Raised_With_Detail,
      Error_Wrong_Argument_Count,

      --  A call naming a parameter this subprogram has not got, naming one
      --  twice, or putting a positional argument after a named one. Three
      --  different mistakes, because a diagnostic saying only `wrong
      --  arguments` sends the reader back to count them.
      Error_No_Such_Parameter,
      Error_Parameter_Given_Twice,
      Error_Positional_After_Named,
      Error_Parameter_Not_Given,

      --  A default that is not a literal, or one on a parameter that is
      --  somewhere to put a value rather than something to be given.
      Error_Default_Not_Literal,
      Error_Number_Not_A_Literal,
      Error_Number_Not_Numeric,
      Error_Default_Not_In_Mode,

      --  A subtype whose range this build cannot make sense of.
      Error_Subtype_Not_Discrete,
      Error_Subtype_Bound_Not_Static,
      Error_Subtype_Range_Is_Empty,

      --  Records and arrays: what a program declared, and what it then wrote.
      Error_Part_Not_Simple,
      Error_Part_Given_Twice,
      Error_Record_Is_Empty,
      Error_Array_Bound_Not_Static,
      Error_Array_Is_Empty,
      Error_Array_Too_Long,
      Error_Not_A_Record,
      Error_No_Such_Component,
      Error_Not_An_Array,
      Error_Aggregate_Wrong_Count,
      Error_Aggregate_Not_Expected,
      Error_Result_Not_Simple,
      Error_Cannot_Write,

      --  Packages and generics.
      Error_Not_A_Package,
      Error_Package_Not_Declared,
      Error_Not_A_Generic,
      Error_Generic_Wrong_Actuals,
      Error_Generic_Not_Callable,
      Error_Not_A_Task,
      Error_Not_An_Entry,

      --  An accept whose formals are not the entry's. Ada has the accept
      --  repeat the profile, and repeating it differently would leave the
      --  caller writing one thing where the body reads another.
      Error_Accept_Differs,

      --  A protected entry with parameters. A rendezvous is what carries
      --  them, and a protected entry has no second side to carry them to.
      Error_Protected_Entry_Parameters,

      --  A composite parameter on an entry. The arguments of a rendezvous
      --  live one to a slot, and a composite is itself a run of slots.
      Error_Entry_Parameter_Not_Simple,

      --  An alternative of a selective accept that is neither an accept nor a
      --  delay. Those are the two things a task waits for.
      Error_Select_Alternative,

      --  A `then abort` trigger that is neither an entry call nor a delay.
      --  A trigger is something that happens on somebody else's terms, which
      --  is the point of abandoning work when it does.
      Error_Select_Trigger,

      --  A selective accept that says twice what to do when nothing can be
      --  accepted: two delay alternatives, or a delay beside an `else`.
      Error_Select_Waits_Twice,

      --  A discriminant part on a single task or protected object rather than
      --  on a type. There is nowhere to write what one of them would take.
      Error_Discriminants_Need_A_Type,

      --  An object given the wrong number of discriminants.
      Error_Discriminants_Wrong_Count,

      --  Values in parentheses after a type that takes none.
      Error_Nothing_To_Constrain,

      --  `E'Count` written where E is not an entry of the unit being
      --  analysed. A queue's length keeps only while the unit is held.
      Error_Count_Outside_Its_Unit,

      --  A type name written where a value belongs. Not the same complaint as
      --  a name that is not a type, and it used to be reported as one.
      Error_Is_A_Type,

      --  `requeue` naming something that is not an entry of the unit it
      --  stands in.
      Error_Requeue_Not_An_Entry,

      --  `requeue` naming an entry that takes parameters. What the caller
      --  gave sits in a run of its own slots, laid out by the entry it
      --  called.
      Error_Requeue_Takes_Nothing,

      --  An entry family indexed by something that is not a discrete type, or
      --  by one with more values than a run of entries may have.
      Error_Family_Index_Not_Discrete,

      --  An entry family whose members take parameters. Ada writes one as two
      --  parenthesised lists, which is a second shape for a call.
      Error_Family_Takes_Nothing,

      --  A member written for an entry that is not a family.
      Error_Not_A_Family,

      --  A family named without saying which member.
      Error_Family_Needs_A_Member,

      --  A task or a protected object copied. Both are limited in Ada's
      --  sense: what one is is the thing that runs or the state that is
      --  shared.
      Error_Cannot_Be_Copied,

      --  A pragma this language does not have.
      Error_Unknown_Pragma,

      --  A restriction name this language does not know.
      Error_Unknown_Restriction,

      --  A policy this machine does not implement. One accepted and not
      --  implemented would be the same lie a restriction nobody checks is.
      Error_Unknown_Policy,

      --  A profile this language does not have.
      Error_Unknown_Profile,

      --  Two dispatching policies given to one priority.
      Error_Dispatching_Twice,

      --  Two queuing policies given to one program.
      Error_Queuing_Twice,

      --  `terminate;` where no select is waiting.
      Error_Terminate_Outside_Select,

      --  An enumeration literal named by more than one type, where nothing
      --  says which is meant.
      Error_Ambiguous_Literal,

      --  `raise;` where nothing was caught to raise again.
      Error_Raise_Outside_A_Handler,

      --  `others` in an aggregate where every part was already named.
      Error_Aggregate_Others_Covers_Nothing,

      --  A range of priorities that runs backwards, so names none.
      Error_Empty_Priority_Range,

      --  A statement the program forbade itself with pragma Restrictions.
      Error_Restriction_Broken,

      --  A priority that is not a number this build can read where it stands.
      Error_Priority_Not_Static,

      --  A task identity declared without one. An identity with nothing in it
      --  names no task, and this build has no way to write the value that
      --  names none on purpose.
      Error_Identity_Needs_A_Task,

      --  Internal commands.
      Error_Command_Wrong_Arguments,
      Error_Command_Unavailable,

      --  A history was asked for where nothing is keeping one. Distinct from
      --  Error_Command_Unavailable: the command exists and works, and it is
      --  this session -- a script, a test -- that has no lines to report.
      --  Saying "not available in this build" there would send a user looking
      --  for a build that has it.
      Error_No_History_Here,

      --  `pipe_run` with nothing added. A pipeline of no stages would succeed
      --  and look like it had run something.
      Error_Empty_Pipeline,

      --  More subprograms declared in one session than it will carry forward.
      Error_Too_Many_Kept,
      Error_Command_Bad_Assignment,

      --  Scripting.
      Error_Script_Cycle);

   --  Which domain a code belongs to.
   --
   --  A case statement with no `others`, so a code added without a domain fails
   --  to compile rather than being attributed to whichever domain sorts first.
   --
   --  @param Code Error code.
   --  @return Its owning domain.
   function Domain (Code : Error_Code) return Error_Domain;

   --  The message identifier that reports a code to a user.
   --
   --  The mapping lives here, next to the codes, rather than at each
   --  presentation boundary: a second boundary would otherwise grow a second
   --  table, and the two would disagree about one code for a release.
   --
   --  @param Code Error code.
   --  @return The message that reports it.
   function Message (Code : Error_Code) return Adash.Messages.Message_Id;

   --  Largest number of structured arguments a failure carries.
   Max_Arguments : constant := 4;

   subtype Argument_Storage is
     Adash.Messages.Argument_List (1 .. Max_Arguments);

   --  One operational failure, or the absence of one.
   type Error_Info is record
      Code : Error_Code := Error_None;

      --  How many of Arguments are meaningful.
      Argument_Count : Natural range 0 .. Max_Arguments := 0;

      Arguments : Argument_Storage;

      --  A message this failure's text quotes, and the placeholder it fills.
      --
      --  An argument is text in its final form, and a subsystem below the
      --  presentation boundary has none to give: what it has is a name for a
      --  thing -- a signal, a capability, a reason the host refused -- and the
      --  name is an identifier, not words. Passing the identifier as the
      --  argument is what put `this system does not support JOB_CONTROL` in
      --  front of users. Naming the message that says it in words, and letting
      --  the boundary render it, is the same road `help` takes to say what a
      --  command is for.
      Detail : Adash.Messages.Message_Id := Adash.Messages.Msg_Error_None;
      Fills  : Adash.Messages.Placeholder_Name;

   end record;

   --  Success.
   Success : constant Error_Info;

   --  @param Item Failure to test.
   --  @return True when Item records a failure.
   function Is_Failure (Item : Error_Info) return Boolean;

   --  @param Item Failure to inspect.
   --  @return Its arguments, as a slice ready for rendering.
   function Arguments (Item : Error_Info) return Adash.Messages.Argument_List;

   --  Build a failure.
   --
   --  @param Code What went wrong. Passing Error_None builds Success, which is
   --         allowed so that a caller mapping a host outcome need not special-
   --         case the successful one.
   --  @param Arguments Structured detail the message expects.
   --  @return The failure.
   function Failure
     (Code      : Error_Code;
      Arguments : Adash.Messages.Argument_List := Adash.Messages.No_Arguments;
      Quoted    : Adash.Messages.Message_Id := Adash.Messages.Msg_Error_None;
      Fills     : String := "") return Error_Info;

private

   Success : constant Error_Info :=
     (Code           => Error_None,
      Argument_Count => 0,
      Arguments      => [others => <>],
      Detail         => Adash.Messages.Msg_Error_None,
      Fills          => [others => ' ']);

end Adash.Errors;
