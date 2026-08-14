private with Ada.Containers.Vectors;
private with Ada.Strings.Unbounded;

private with Adash.Language.Syntax;
private with Adash.Language.Tokens;

with Adash.Commands;
with Adash.Configuration;
with Adash.Diagnostics;
with Adash.Execution;
with Adash.Execution.Cancellation;
with Adash.Execution.Environment;

--  Visible rather than private: Submit names Origin_Kind, so a caller has to
--  be able to see it.
with Adash.Source;

--  The one coordinator.
--
--  Everything that runs Adash source goes through here: the interactive
--  frontend, a script, a startup file, and the tests. None of them repeats what
--  this does. A frontend that grew its own pipeline would be a second engine,
--  and the difference between the two would be found by users rather than by
--  tests.
--
--  A Session is what persists between submissions: the environment children
--  inherit, whether the user has asked to leave, and the cancellation token. A
--  submission is one piece of source with an identity -- a typed line, a file, a
--  startup file -- and produces a structured result.
--
--  **This package renders nothing.** It returns identities, statuses and
--  diagnostics; the frontend turns them into text. That is what lets a script
--  run silently, a test assert on outcomes, and the interactive shell decide
--  where output goes -- from one engine rather than three.
--
--  How a submission is classified
--  ------------------------------
--
--  Source is lexed and parsed once. The *tree* then decides what it was: a
--  sequence whose statements are all calls to internal commands is dispatched
--  to Adash.Commands; anything else is analysed and run as a program.
--
--  There is one lexer, one parser and one tree, so this is not a second
--  language -- `pwd;` is an ordinary Ada procedure call and is parsed as one.
--  What differs is only who executes it, which is exactly the difference
--  between a command that must change this process and a program that must
--  not.
--
--  A submission *mixes* the two freely: `pwd; X : Integer := 1;` runs the
--  command and declares the variable, because a command is an entity a program
--  can call and the machine evaluates its arguments like any other call's. The
--  dispatch above is a shortcut for the submission that is nothing but
--  commands, not a fence between two languages. `docs/command-calls.md` records
--  what the shortcut used to be and why it stopped being the whole answer.
package Adash.Engine is

   --  What a submission turned out to be.
   type Submission_Kind is
     (
      --  Nothing to run: empty source, or only comments.
      Nothing_Submitted,

      --  A program, analysed and run on the virtual machine.
      --
      --  Every submission that runs is one of these. There used to be a
      --  Command_Invocation beside it, for a submission that held only
      --  commands -- and the two could not be mixed, so a script could not
      --  compute a value and then exit with it. Commands are calls in the
      --  language now, so there is one kind of submission and one path
      --  through the engine.
      Language_Program,

      --  It did not get far enough to be either.
      Not_Understood);

   --  What became of a submission.
   type Result is record
      Kind : Submission_Kind := Nothing_Submitted;

      --  The shell's one exit-status model, whichever path ran.
      Status : Adash.Execution.Exit_Status;

      --  True when something actually ran. False when the source was rejected,
      --  which a caller must be able to tell apart from a program that ran and
      --  failed.
      Ran : Boolean := False;
   end record;

   --  A shell session.
   type Session is tagged limited private;

   --  Start a session.
   --
   --  @param Item Session to open.
   procedure Open (Item : in out Session);

   --  Give the session a way to run scripts.
   --
   --  Without one, `source` refuses rather than doing nothing. The engine
   --  cannot supply this itself: running a script means submitting to the
   --  engine, so the implementation lives above it and is handed down.
   --
   --  @param Item Session to equip.
   --  @param Runner What to run scripts with, or null to take the ability away.
   procedure Use_Script_Runner
     (Item : in out Session; Runner : Adash.Commands.Runner_Access);

   --  Give the session a history to report.
   --
   --  Without one, `history` says it cannot report rather than reporting
   --  nothing: a script has no history, and an empty answer would claim it had
   --  typed nothing.
   --
   --  @param Item Session to equip.
   --  @param Source What has been typed, or null to take the ability away.
   procedure Use_History
     (Item : in out Session; Source : Adash.Commands.History_Access);

   ---------------------------------------------------------------------
   --  Where a command's output goes, as it is produced.
   --
   --  A command produces structured lines and a frontend renders them; that
   --  much is unchanged. What changed is *when*. The lines used to be
   --  accumulated and rendered after the submission had finished, which was
   --  invisible until a program could write anything of its own -- and then
   --  `pwd; put_line ("after");` printed `after` first, because a program
   --  writes as the machine runs it.
   --
   --  So the frontend supplies a sink and the engine writes each line through
   --  it at the moment the command produced it. The lines are still
   --  accumulated, so Output_Count and Output_Line still answer; the sink is
   --  about ordering, not about storage.
   ---------------------------------------------------------------------

   --  Where a command's output lines go.
   type Output_Sink is limited interface;

   --  Render one line.
   --
   --  @param Sink The frontend's renderer.
   --  @param Item The line, as the command produced it: an identifier and its
   --         arguments, never text. Turning it into a sentence is the
   --         frontend's job and this does not take it away.
   procedure Write
     (Sink : in out Output_Sink; Item : Adash.Commands.Line) is abstract;

   --  A sink to hand to Submit.
   type Output_Sink_Access is access all Output_Sink'Class;

   --  Whether a piece of source stops in the middle of something.
   --
   --  What an interactive frontend needs before it submits: a line at a time is
   --  how a user types, and `if C then` is not a mistake -- it is unfinished.
   --  Asked here rather than answered by the frontend so that the judgement
   --  comes from the grammar that will parse it, and so that a second frontend
   --  cannot come to a different conclusion.
   --
   --  Nothing is reported and no session state changes: this is a question
   --  about text the user may still be typing.
   --
   --  @param Text The source so far.
   --  @param Name What to call it in diagnostics, unused unless it is
   --         submitted.
   --  @return True when more input could still complete it.
   function Wants_More (Text : String; Name : String) return Boolean;

   --  Run one piece of source.
   --
   --  @param Item The session it runs in.
   --  @param Text The source.
   --  @param Name What to call it in diagnostics -- a file path, or a label
   --         for a typed line.
   --  @param Kind What sort of source it is.
   --  @param Outcome What became of it.
   --  @param Report Where diagnostics go. Not cleared: a caller running several
   --         submissions may want them together, and one that does not clears
   --         between calls.
   procedure Submit
     (Item    : in out Session;
      Text    : String;
      Name    : String;
      Kind    : Adash.Source.Origin_Kind := Adash.Source.Origin_Interactive;
      Outcome : out Result;
      Report  : in out Adash.Diagnostics.List;
      On_Output : Output_Sink_Access := null);

   --  Whether the session has been asked to end.
   --
   --  Set by the `exit` command. The frontend reads it and stops; nothing in
   --  the engine ends the process, because that decision belongs to whoever is
   --  driving the session.
   --
   --  @param Item Session to inspect.
   --  @return True when the user asked to leave.
   function Exit_Requested (Item : Session) return Boolean;

   --  The status the session should end with.
   --
   --  @param Item Session to inspect.
   --  @return Its exit status.
   function Exit_Status (Item : Session) return Adash.Execution.Exit_Status;

   --  How many lines the last command produced.
   --
   --  Zero after a submission that was a program: a program writes through the
   --  runtime rather than producing lines. The two are different channels
   --  because they have different renderers.
   --
   --  @param Item Session to inspect.
   --  @return The line count.
   function Output_Count (Item : Session) return Natural;

   --  One line the last command produced.
   --
   --  Accessed rather than returned as a whole, because the output is part of
   --  the session and handing out a copy would invite a caller to hold one
   --  past the next submission.
   --
   --  @param Item Session to inspect.
   --  @param Index Which line, from one.
   --  @return That line.
   function Output_Line
     (Item : Session; Index : Positive) return Adash.Commands.Line;

   --  Ask whatever is running to stop.
   --
   --  Safe from another task: the token is protected. A submission already
   --  under way observes it; one not yet started sees it at its first check.
   --
   --  @param Item Session to interrupt.
   procedure Request_Cancellation (Item : in out Session);

   --  Clear a cancellation, so the next submission is not stopped by the last
   --  one's interrupt.
   --
   --  @param Item Session to reset.
   procedure Clear_Cancellation (Item : in out Session);

   --  Whether a cancellation is outstanding.
   --
   --  @param Item Session to inspect.
   --  @return True when one has been asked for and not cleared.
   function Cancellation_Requested (Item : Session) return Boolean;

   --  The environment children of this session inherit.
   --
   --  Exposed so a frontend can show it and a test can assert on it, not so
   --  that anything may change it -- `set` and `unset` are how it changes.
   --
   --  @param Item Session to inspect.
   --  @return Its environment.
   function Environment
     (Item : Session) return Adash.Execution.Environment.Block;

   --  The settings in force for this session.
   --
   --  Held here rather than in a process-wide variable so that a test can run
   --  two sessions with different settings without one leaking into the other,
   --  and so that every subsystem that needs a setting is handed the session it
   --  is working on rather than reaching for a global.
   --
   --  @param Item Session to inspect.
   --  @return Its settings; the defaults until Apply_Settings says otherwise.
   function Settings (Item : Session) return Adash.Configuration.Settings;

   --  Put settings into force for a session.
   --
   --  Called by whoever read them -- a frontend at start-up -- rather than by
   --  the engine reading a file for itself: the engine has no business knowing
   --  where configuration lives, and a test has every reason to want to set
   --  them without one.
   --
   --  Give the session the arguments a script was invoked with.
   --
   --  Set by whoever started the session, because only the frontend knows what
   --  the process was given. An interactive session leaves them empty, which is
   --  the truthful answer rather than a special case: nothing was passed.
   --
   --  @param Item Session to equip.
   --  @param Position Which argument, from one, in the order they were written.
   --  @param Value The argument.
   procedure Add_Argument
     (Item     : in out Session;
      Position : Positive;
      Value    : String)
     with Pre => Position = Argument_Count (Item) + 1;

   --  @param Item Session to inspect.
   --  @return How many arguments it was given.
   function Argument_Count (Item : Session) return Natural;

   --  @param Item Session to configure.
   --  @param To The settings.
   procedure Apply_Settings
     (Item : in out Session; To : Adash.Configuration.Settings);

private

   --  Most subprogram declarations a session will carry forward.
   --
   --  Bounded rather than unlimited: a shell that has been open for a week
   --  should not be holding every definition anyone ever typed, and a limit
   --  that is said out loud when it is reached beats memory that grows without
   --  anyone noticing.
   Max_Kept : constant := 256;

   --  A declaration held from one submission to the next.
   type Held_Declaration is record
      --  Name and profile together, so redefining `LL` replaces the `LL` that
      --  was there and declaring a second `LL` of a different profile adds an
      --  overload -- which is the language's own rule, applied across
      --  submissions rather than within one.
      Key : Ada.Strings.Unbounded.Unbounded_String;

      --  Its source, exactly as written. Kept as text rather than as a tree
      --  because it is re-analysed with whatever follows it: a definition and
      --  the line that uses it have to be one program, or the second could not
      --  see the first.
      --
      --  Empty for a variable until the program hands its value back, which it
      --  does as it ends. One still empty afterwards belongs to a program that
      --  stopped early, and is dropped rather than carried with whatever it
      --  had before.
      Text : Ada.Strings.Unbounded.Unbounded_String;

      --  True for a variable. Its place in this list is its place in the
      --  source that declared it, so a subprogram carried alongside it still
      --  finds it declared before itself.
      Is_Object : Boolean := False;
   end record;

   package Held_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Held_Declaration);

   --  What one submission needs to hold while it is being read.
   type Scratch is limited record
      Buffer : Adash.Source.Buffer;
      Stream : Adash.Language.Tokens.Token_Stream;
      Tree   : Adash.Language.Syntax.Tree;
   end record;

   type Scratch_Access is access all Scratch;

   type Session is tagged limited record
      --  Aliased, because a lowered program calling a command needs to reach
      --  them from inside the virtual machine, and the bridge that does so
      --  holds accesses rather than copies -- a command changes the session's
      --  state, so a copy would change nothing.
      Shell  : aliased Adash.Commands.State;
      Output : aliased Adash.Commands.Output;
      Cancel : aliased Adash.Execution.Cancellation.Token;

      --  Reused between submissions rather than rebuilt. An interactive
      --  session submits a line at a time, and allocating a fresh buffer,
      --  token stream and tree for each keystroke-terminated line is the one
      --  cost this loop cannot amortise anywhere else.
      --
      --  Grouped so that a submission made *during* another one can be given a
      --  set of its own. `source` does exactly that, and sharing these would
      --  overwrite the outer submission's tree while it was still being
      --  lowered -- silently, and with whatever the inner file happened to
      --  contain.
      Work : aliased Scratch;

      --  True while a submission is running, which is how a nested one knows
      --  to bring its own.
      Busy : Boolean := False;

      --  Subprograms declared earlier in this session, prepended to whatever
      --  is submitted next. Only subprograms: an object's initialiser would run
      --  again on every line, so its value would not survive and keeping it
      --  would be a lie about what persisted.
      Kept : Held_Vectors.Vector;

      Opened : Boolean := False;

   end record;

end Adash.Engine;
