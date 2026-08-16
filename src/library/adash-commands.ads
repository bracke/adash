private with Ada.Containers.Vectors;
private with Ada.Strings.Unbounded;

with Adash.Configuration;
with Adash.Diagnostics;
with Adash.Execution;
with Adash.Language.Types;
with Adash.Language.Values;
with Adash.Execution.Cancellation;
with Adash.Execution.Environment;
with Adash.Execution.Jobs;
with Adash.Execution.Pipelines;
with Adash.Messages;

--  Commands the shell runs itself.
--
--  Some things cannot be a child process. `cd` in a child changes that child's
--  directory and then the child exits; `exit` in a child ends the child. These
--  run inside the shell because their whole effect is on the shell, and that is
--  the test for whether something belongs here -- not whether it would be
--  convenient or fast.
--
--  This is not a place to reimplement POSIX utilities. `ls`, `grep` and `cat`
--  are programs, they work, and a shell that shipped its own subtly different
--  versions would be giving users two behaviours to learn for one name.
--
--  **Commands do not print.** They produce structured output: a message
--  identifier and typed arguments per line, exactly as diagnostics do, and the
--  frontend renders them. That is what lets `pwd` be tested by identity rather
--  than by string comparison, be written to a log as data, and be translated --
--  and it is why this package has no dependency on the catalog.
--
--  Every command carries metadata for the same reasons the predefined entities
--  do: a signature so its arguments can be checked, a documentation key so it
--  can be written about, a description key so completion can show it, and an
--  availability so a command whose subsystem does not exist yet can say "not in
--  this build" rather than "no such command".
package Adash.Commands is

   --  Every internal command, by stable identifier.
   type Command_Id is
     (
      --  The directory the shell is in.
      Command_Change_Directory,
      Command_Print_Directory,

      --  Ending the session.
      --
      --  Spelled `quit`, not `exit`: `exit` is Ada's loop-exit keyword, so the
      --  parser makes `exit;` an exit statement before anything could decide
      --  it was a command. A shell whose language is Ada does not get to take
      --  that word back, and a parser that guessed which was meant is the
      --  second dialect this project exists to avoid.
      Command_Exit,

      --  The environment children inherit.
      Command_Set,
      Command_Unset,
      Command_Environment,

      --  What the shell is running.
      Command_Jobs,

      --  Telling the user about the shell.
      Command_Help,
      Command_Version,

      --  Reading what a session has done, and reading a file into it. Both
      --  needed a subsystem that did not exist when they were registered, and
      --  both have it: history is durable through Adash.Persistence.History,
      --  and `source` reads a script through Adash.Scripting. `history` in a
      --  session with no log -- a script -- reports that it has nothing, which
      --  is an answer rather than a refusal. `forget` is the other direction:
      --  a line already recorded, taken out of the session and out of the
      --  file, for the user who typed a secret without the space that would
      --  have kept it out in the first place.
      Command_History,
      Command_Forget,
      Command_Source,

      --  Job control. `start` is what creates a job at all: nothing else in
      --  this language runs an external program, so without it `jobs` has
      --  nothing to list and the subsystem beneath it is unreachable.
      Command_Run,
      Command_Run_Into,
      Command_Run_From,
      Command_Run_Append,
      Command_Run_New,
      Command_Pipe,
      Command_Pipe_Run,
      Command_Start,
      Command_Wait,
      Command_Stop,
      Command_Suspend,
      Command_Resume,

      --  Putting text a script computed into a file. `run_into` already
      --  writes files, but only ever what a program printed; without these,
      --  a script can work something out and has nowhere to put it.
      Command_Write_File,
      Command_Make_Directory,
      Command_Append_File,

      --  The user's own settings.
      Command_Settings,
      Command_Save_Settings);

   --  Whether a command can be run in this build.
   type Availability is (Available, Not_In_This_Build);

   --  What a command does to the shell.
   type Effect is
     (
      --  Reports something and changes nothing.
      Reports_Only,

      --  Changes shell state.
      Changes_State,

      --  Ends the session.
      Ends_Session);

   --  Largest number of parameters a command takes.
   --
   --  The same number of value slots the machine's stub carries, and it has to
   --  be: the lowering refuses a call with more than the record holds, and a
   --  command layer that accepted fewer would take the extra ones off again
   --  without a word. `Adash.Language.Evaluation.Max_Command_Arguments` is the
   --  other half of the pair -- it cannot be named here, because the language
   --  sits above this and not below it.
   Max_Parameters : constant := 5;

   --  One formal parameter of a command.
   --
   --  Commands have typed profiles for the same reason predefined subprograms
   --  do: so that `quit ("later")` is a diagnostic naming the type, rather than
   --  something the command discovers at run time by failing to convert a
   --  string somebody typed.
   type Parameter is record
      --  The name, for completion to show and for a named association.
      Name : Adash.Messages.Argument;

      --  What it accepts. Type_None marks a parameter that accepts any type;
      --  no command has one today, and the case exists so that adding one does
      --  not need a new shape.
      Of_Type : Adash.Language.Types.Type_Kind :=
        Adash.Language.Types.Type_None;
   end record;

   type Parameter_List is array (1 .. Max_Parameters) of Parameter;

   --  Everything known about one command.
   type Metadata is record
      Id   : Command_Id := Command_Help;

      --  As a user types it. Case-insensitive on lookup, as Ada names are.
      Name : Adash.Messages.Argument;

      Minimum_Arguments : Natural := 0;

      --  Natural'Last for a command that takes any number.
      Maximum_Arguments : Natural := 0;

      --  The type of each position, whether or not it is required. Arity is
      --  still Minimum_Arguments .. Maximum_Arguments: a command may take a
      --  parameter optionally -- `quit` with or without a status -- which one
      --  count cannot express.
      Parameters : Parameter_List;

      Does : Effect := Reports_Only;

      --  Message identifiers, not prose: this package holds no text.
      Documentation : Adash.Messages.Message_Id := Adash.Messages.Msg_Error_None;
      Description   : Adash.Messages.Message_Id := Adash.Messages.Msg_Error_None;

      Status : Availability := Available;
   end record;

   --  @return How many commands are registered.
   function Count return Natural;

   --  @param Index Which command, from one. For iteration only; nothing may
   --         depend on the order.
   --  @return Its metadata.
   function Entry_At (Index : Positive) return Metadata;

   --  @param Id The command.
   --  @return Its metadata.
   function Describe (Id : Command_Id) return Metadata;

   --  Find a command by the name a user typed.
   --
   --  @param Name The name as written.
   --  @param Id The command, when this returns True.
   --  @return True when the name is an internal command.
   function Find (Name : String; Id : out Command_Id) return Boolean;

   ---------------------------------------------------------------------------
   --  Structured output
   ---------------------------------------------------------------------------

   --  One line a command produced.
   type Line is private;

   --  @param Item Line to inspect.
   --  @return Its message identifier.
   function Message (Item : Line) return Adash.Messages.Message_Id;

   --  @param Item Line to inspect.
   --  @return Its arguments, ready for rendering.
   function Arguments (Item : Line) return Adash.Messages.Argument_List;

   --  A message this line's text quotes.
   --
   --  A command may not render -- it produces identifiers and typed arguments,
   --  and an argument is text in its final form. So a line that has to say
   --  what another message says cannot pass that text: it does not have it and
   --  must not produce it. It names the message instead, and the frontend
   --  renders that one into this one.
   --
   --  `help` is why this exists. Listing a command's name beside what the
   --  command is for means quoting the message that says so, and without this
   --  the listing had a name and a blank where the summary belongs -- for as
   --  long as `help` has existed.
   --
   --  @param Item Line to inspect.
   --  @return The quoted message, or Msg_Error_None when it quotes none.
   function Detail (Item : Line) return Adash.Messages.Message_Id;

   --  @param Item Line to inspect.
   --  @return The placeholder Detail's text fills, without braces.
   function Detail_Placeholder (Item : Line) return String;

   --  What a command produced, in order.
   type Output is tagged limited private;

   --  @param Item Output to measure.
   --  @return How many lines it holds.
   function Count (Item : Output) return Natural;

   --  @param Item Output to read.
   --  @param Index Which line, from one.
   --  @return That line.
   function Element (Item : Output; Index : Positive) return Line;

   --  Forget everything.
   --
   --  @param Item Output to empty.
   procedure Clear (Item : in out Output);

   ---------------------------------------------------------------------------
   --  Shell state
   ---------------------------------------------------------------------------

   --  The state internal commands read and change.
   --
   --  Defined here rather than in Adash.Engine, which owns a session: the
   --  commands are what determine this record's contents, and a state record
   --  designed away from them would be a guess. The engine holds one and hands
   --  it to whichever command was called.
   --
   --  The working directory is deliberately *not* in here. `cd` changes the
   --  process's own directory and `pwd` asks the process, so there is one
   --  answer rather than a copy that can drift from it -- and a child inherits
   --  the real one without the shell having to pass it.
   ---------------------------------------------------------------------
   --  How a command runs a script.
   --
   --  `source` has to read a file and submit it to the engine, and the engine
   --  is what calls commands: this package cannot reach it without the two
   --  depending on each other. So the capability arrives as an interface, and
   --  whoever owns the session supplies it -- the same shape the language uses
   --  to call commands from inside the virtual machine, for the same reason.
   ---------------------------------------------------------------------

   --  What a session has typed, for `history` to report.
   --
   --  An interface for the same reason `source` needs one: the log belongs to
   --  the interactive frontend, which sits above this package, and a command
   --  cannot reach up. A session that has no log -- a script, a test --
   --  supplies none, and `history` says so rather than reporting an empty one:
   --  "nothing was typed" and "nobody is keeping track" are different answers.
   type History_Source is limited interface;

   --  @param Source The session's log.
   --  @return How many lines it holds.
   function Recorded (Source : History_Source) return Natural is abstract;

   --  @param Source The session's log.
   --  @param Index Which line, from one, oldest first.
   --  @return The line as it was typed.
   function Recorded_Line
     (Source : History_Source; Index : Positive) return String is abstract;

   --  Take the most recent entries out, here and on disk.
   --
   --  The `forget` line itself goes too, and is not counted: a history whose
   --  last entry is the command that emptied it has kept a record of the act,
   --  and a user who wanted the line gone did not want a note saying so.
   --
   --  @param Source The session's log.
   --  @param Count How many entries before this one to forget.
   --  @param Forgotten How many went, which is fewer than Count when the log
   --         is shorter than that.
   --  @param Failed True when the durable file could not be rewritten. What is
   --         forgotten in the session is forgotten either way; this says the
   --         file still holds it, which is the half that matters and the half
   --         a caller must not report as done.
   procedure Forget_Recent
     (Source    : in out History_Source;
      Count     : Positive;
      Forgotten : out Natural;
      Failed    : out Boolean) is abstract;

   --  Take out every entry that is exactly this line, here and on disk.
   --
   --  The other way of saying which: a user who can see the line names it,
   --  rather than counting backwards to it. It reaches further than a count
   --  does -- a count can only remove what the session's log holds, and this
   --  removes what the *file* holds as well, including what was written before
   --  the log's limit and never read back.
   --
   --  The `forget` line itself goes too, as it does for a count -- and here it
   --  matters more, because the line that names a secret contains it.
   --
   --  @param Source The session's log.
   --  @param Text The entry, exactly as it was typed.
   --  @param Forgotten How many entries went, in the session and in the files
   --         together, not counting the `forget` line.
   --  @param Failed True when a file could not be rewritten.
   procedure Forget_Line
     (Source    : in out History_Source;
      Text      : String;
      Forgotten : out Natural;
      Failed    : out Boolean) is abstract;

   type History_Access is access all History_Source'Class;

   type Script_Runner is limited interface;

   --  Run a script in this session.
   --
   --  @param Runner The implementation, which owns the session and the loading
   --         chain that detects a file sourcing itself.
   --  @param Path The file, as the user wrote it.
   --  @param Status What it exited with, when it ran.
   --  @param Failed True when it could not be run at all -- missing,
   --         unreadable, or already being loaded. The runner has reported why.
   procedure Run_Script
     (Runner : in out Script_Runner;
      Path   : String;
      Status : out Adash.Execution.Exit_Status;
      Failed : out Boolean) is abstract;

   type Runner_Access is access all Script_Runner'Class;

   --  A list of strings the shell was given, in order.
   --
   --  Private, and with only the three operations the shell needs, so that the
   --  container it is built from stays a private dependency of this package.
   type Text_List is private;

   --  @param Item List to measure.
   --  @return How many strings it holds.
   function Length (Item : Text_List) return Natural;

   --  @param Item List to read.
   --  @param Index Which string, from one.
   --  @return That string, or "" when Index is past the end -- which is not an
   --          error: a script asking for an argument it was not given is
   --          asking whether it was given one.
   function Element (Item : Text_List; Index : Positive) return String;

   --  Add one string to the end.
   --
   --  @param Item List to add to.
   --  @param Value The string.
   procedure Append (Item : in out Text_List; Value : String);

   type State is limited record
      --  What children inherit. Separate from the process's own environment,
      --  so `set` for the session does not alter the shell's.
      Environment : Adash.Execution.Environment.Block :=
        Adash.Execution.Environment.Empty;

      --  Set by `exit`. The frontend reads it and stops; nothing here can end
      --  the process, because a command that called Halt would take the
      --  decision away from whoever is driving.
      Exit_Requested : Boolean := False;
      Exit_Status    : Adash.Execution.Exit_Status;

      --  Whether the last read of the shell's input found the end of it.
      --
      --  Read_Line answers with a line and this answers whether there was one:
      --  an empty line is a line a file may contain, so a program that could
      --  only see the text could not tell the two apart.
      Input_Ended : Boolean := False;

      --  The user's settings, as this session is running with them.
      --
      --  Session state like the environment, and here for the same reason: a
      --  command changes them, so the command layer has to be able to see
      --  them. The engine hands them over at startup and reads them back.
      Chosen : Adash.Configuration.Settings := Adash.Configuration.Defaults;

      --  What the script was invoked with, after its own path.
      --
      --  A script that cannot see its arguments is not a tool anybody can
      --  call, and until this existed `adash build.adash release` ran the
      --  script and dropped the word -- silently, which is worse than
      --  refusing it. Empty for an interactive session, which is the truthful
      --  answer rather than a special case: nothing was passed.
      Arguments : Text_List;

      --  What the last command did, for a program that wants to know.
      --
      --  Kept in the session rather than handed back from a call because a
      --  command is a procedure: `run ("false");` produces no value, and a
      --  program that could not ask afterwards could not act on a failure at
      --  all. Every shell has this and spells it `$?`; the name here is
      --  `Status` and the number is the one exit-status model, so a program
      --  reading it and a caller reading the shell's own exit see the same
      --  scale.
      Last_Status : Adash.Execution.Exit_Status := Adash.Execution.Success;

      --  How a foreground program learns the user asked it to stop.
      --
      --  `run` waits for a program, and a shell that could not be interrupted
      --  while waiting would be one where Ctrl-C did nothing at exactly the
      --  moment it is most wanted. The child is in a process group of its own,
      --  so the signal does not reach it by itself: the shell records the
      --  interrupt and this is how the command sees it.
      Interrupt : access Adash.Execution.Cancellation.Token;

      --  The pipeline being built, a stage at a time.
      --
      --  Held between commands because a pipeline is a list of command lines
      --  and this language has no lists: `pipe` adds one and `pipe_run` starts
      --  them together. That mirrors what the subsystem underneath actually
      --  does -- add stages, then start -- rather than inventing a notation
      --  inside a string for a shell that will not grow a `|`.
      Pending : Adash.Execution.Pipelines.Plan :=
        Adash.Execution.Pipelines.Empty_Plan;

      --  What this session has started and not yet forgotten. Held here rather
      --  than in the engine because a job outlives the command that started it
      --  and every command that asks about one reads the same table.
      Jobs : Adash.Execution.Jobs.Table;

      --  What this session has typed, or null where nothing is keeping track.
      History : History_Access := null;

      --  How to run a script, or null where nothing can. `source` refuses
      --  rather than doing nothing when it is null: a caller that cannot run
      --  scripts has to be told, not quietly obeyed.
      Scripts : Runner_Access := null;
   end record;

   --  Give a state its starting environment: the shell's own.
   --
   --  @param Item State to initialise.
   procedure Initialize (Item : in out State);

   --  What a command was given.
   --
   --  Typed values, not text. A command used to receive the source it was
   --  written with and convert it itself, which meant `quit ("later")` was
   --  discovered by Integer'Value failing at the moment the session was
   --  ending -- the worst possible time to find out, and a diagnostic the
   --  analyser could have given before anything ran. The types are checked
   --  against the profile in Adash.Predefined now, and what arrives here has
   --  already been through that.
   type Argument_Array is
     array (1 .. Max_Parameters) of Adash.Language.Values.Value;

   type Argument_Set is record
      Count  : Natural range 0 .. Max_Parameters := 0;
      Given  : Argument_Array;
   end record;

   --  A command called with nothing.
   No_Arguments : constant Argument_Set;

   --  Run an internal command.
   --
   --  @param Id Which command.
   --  @param Arguments Its arguments, as values.
   --  @param Shell The state it may read and change.
   --  @param Produced Where its output lines go, replaced.
   --  @param Report Where diagnostics go.
   --  @return What became of it, in the shell's one exit-status model.
   function Execute
     (Id        : Command_Id;
      Arguments : Argument_Set;
      Shell     : in out State;
      Produced  : in out Output;
      Report    : in out Adash.Diagnostics.List)
      return Adash.Execution.Exit_Status;

private

   No_Arguments : constant Argument_Set :=
     (Count => 0, Given => [others => Adash.Language.Values.None]);

   package Text_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Ada.Strings.Unbounded.Unbounded_String,
      "="          => Ada.Strings.Unbounded."=");

   type Text_List is record
      Items : Text_Vectors.Vector;
   end record;

   Max_Line_Arguments : constant := 4;

   subtype Argument_Storage is
     Adash.Messages.Argument_List (1 .. Max_Line_Arguments);

   type Line is record
      Message        : Adash.Messages.Message_Id := Adash.Messages.Msg_Error_None;
      Argument_Count : Natural range 0 .. Max_Line_Arguments := 0;
      Arguments      : Argument_Storage;

      --  What this line quotes, and where it goes. Msg_Error_None means it
      --  quotes nothing, which is every line but one.
      Detail : Adash.Messages.Message_Id := Adash.Messages.Msg_Error_None;
      Fills  : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   package Line_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Line);

   type Output is tagged limited record
      Lines : Line_Vectors.Vector;
   end record;

   --  Used by Adash.Commands.Builtins to add a line.
   --
   --  Quoted and Fills are for a line whose text embeds another message; see
   --  Detail above.
   procedure Say
     (Item      : in out Output;
      Message   : Adash.Messages.Message_Id;
      Arguments : Adash.Messages.Argument_List := Adash.Messages.No_Arguments;
      Quoted    : Adash.Messages.Message_Id := Adash.Messages.Msg_Error_None;
      Fills     : String := "");

end Adash.Commands;
