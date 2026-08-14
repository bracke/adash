with Ada.Directories;

with AUnit.Assertions;

with Adash.Commands;
with Adash.Diagnostics;
with Adash.Engine;
with Adash.Errors;
with Adash.Execution;
with Adash.Execution.Environment;
with Adash.Messages;
with Adash.Source;

package body Adash_Tests.Engine_Cases is

   use AUnit.Assertions;

   package E renames Adash.Engine;
   package D renames Adash.Diagnostics;
   package M renames Adash.Messages;

   use type E.Submission_Kind;
   use type M.Message_Id;

   function Reported
     (Report : D.List; Code : Adash.Errors.Error_Code) return Boolean is
   begin
      for Index in 1 .. Report.Count loop
         if D.Message (Report.Element (Index)) = Adash.Errors.Message (Code) then
            return True;
         end if;
      end loop;

      return False;
   end Reported;

   ------------------------------------------------------------------

   procedure A_Raise_Costs_Only_Its_Own_Submission
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Shell   : E.Session;
      Outcome : E.Result;
      Report  : D.List;
   begin
      E.Open (Shell);

      E.Submit (Shell, "Kept : Integer := 5;", "<line>",
                Adash.Source.Origin_Interactive, Outcome, Report);
      Assert (Adash.Execution.Succeeded (Outcome.Status),
              "declaring a variable failed");

      --  A submission that stops early keeps nothing of its own -- and takes
      --  nothing of anybody else's. Carrying a variable works by declaring it
      --  again in every submission, so the place the session holds for it must
      --  survive a program that never reaches the hand-back.
      Report.Clear;
      E.Submit (Shell, "Kept := 9; Lost : Integer := 1; raise Constraint_Error;",
                "<line>", Adash.Source.Origin_Interactive, Outcome, Report);
      Assert (Outcome.Ran, "the failing submission did not run");
      Assert (not Adash.Execution.Succeeded (Outcome.Status),
              "a raise was not reported as a failure");

      --  Asked as a program rather than by reading what was printed: a
      --  program writes through the runtime rather than producing lines, and
      --  what this has to know is the value rather than the rendering. An
      --  undeclared name fails the analysis, so one submission answers both
      --  questions -- is it still there, and is it what it was.
      Report.Clear;
      E.Submit (Shell, "if Kept /= 5 then raise Constraint_Error; end if;",
                "<line>", Adash.Source.Origin_Interactive, Outcome, Report);
      Assert (Report.Count = 0,
              "the session lost a variable to somebody else's raise");
      Assert (Adash.Execution.Succeeded (Outcome.Status),
              "a failed submission's assignment was kept");

      Report.Clear;
      E.Submit (Shell, "Put_Line (Lost);", "<line>",
                Adash.Source.Origin_Interactive, Outcome, Report);
      Assert (Report.Count > 0,
              "a variable the failed submission declared was kept");
   end A_Raise_Costs_Only_Its_Own_Submission;

   procedure One_Engine_Serves_Commands_And_Programs
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Shell   : E.Session;
      Outcome : E.Result;
      Report  : D.List;
   begin
      E.Open (Shell);

      --  A program: analysed and run on the virtual machine.
      E.Submit (Shell, "N : Integer := 6 * 7; Put_Line (N);", "<line>",
                Adash.Source.Origin_Interactive, Outcome, Report);
      Assert (Outcome.Kind = E.Language_Program,
              "a program was not classified as one");
      Assert (Outcome.Ran, "a program did not run");
      Assert (Adash.Execution.Succeeded (Outcome.Status), "a program failed");

      --  A command: run in this process. Same session, same engine, same
      --  parse -- the tree is what decided which.
      Report.Clear;
      E.Submit (Shell, "pwd;", "<line>",
                Adash.Source.Origin_Interactive, Outcome, Report);
      Assert (Outcome.Kind = E.Language_Program,
              "a command was not run as part of a program");
      Assert (E.Output_Count (Shell) = 1, "pwd produced no output line");
      Assert (Adash.Commands.Message (E.Output_Line (Shell, 1))
              = M.Msg_Line_Directory,
              "pwd's output is not a directory line");
      Assert (Report.Count = 0, "a working command produced diagnostics");
   end One_Engine_Serves_Commands_And_Programs;

   procedure State_Carries_Between_Submissions
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Shell   : E.Session;
      Outcome : E.Result;
      Report  : D.List;
      Started : constant String := Ada.Directories.Current_Directory;
   begin
      E.Open (Shell);

      --  What makes it a session rather than a series of unrelated runs.
      E.Submit (Shell, "set (""ENGINE_TEST=yes"");", "<line>",
                Adash.Source.Origin_Interactive, Outcome, Report);
      Assert (Adash.Execution.Succeeded (Outcome.Status),
              "set failed through the engine");

      E.Submit (Shell, "pwd;", "<line>",
                Adash.Source.Origin_Interactive, Outcome, Report);
      Assert (Adash.Execution.Environment.Value
                (E.Environment (Shell), "ENGINE_TEST") = "yes",
              "a variable set in one submission did not survive the next");

      --  And the directory, which lives in the process rather than the state.
      E.Submit (Shell, "cd ("".."");", "<line>",
                Adash.Source.Origin_Interactive, Outcome, Report);
      Assert (Adash.Execution.Succeeded (Outcome.Status), "cd failed");
      Assert (Ada.Directories.Current_Directory /= Started,
              "cd through the engine did not move the process");

      E.Submit (Shell, "cd (""" & Started & """);", "<line>",
                Adash.Source.Origin_Interactive, Outcome, Report);
      Assert (Ada.Directories.Current_Directory = Started,
              "cd back through the engine failed");
   end State_Carries_Between_Submissions;

   procedure A_Program_Can_Read_The_Environment
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Shell   : E.Session;
      Outcome : E.Result;
      Report  : D.List;

      --  What the program answered with. Put_Line writes to the process's
      --  own output rather than into the session's line table, so the value
      --  is observed by making the program fail when it is wrong: a division
      --  by zero the program only reaches if the text it read is not the text
      --  that was set. Asserting on the outcome tests the value; asserting on
      --  Put_Line would only test that something was written.
      function Holds (Expression, Expected : String) return Boolean is
      begin
         E.Submit (Shell,
                   "N : Integer := 1; if " & Expression & " /= """
                   & Expected & """ then N := 1 / 0; end if;",
                   "<line>", Adash.Source.Origin_Interactive, Outcome, Report);
         return Adash.Execution.Succeeded (Outcome.Status);
      end Holds;
   begin
      E.Open (Shell);

      --  The direction that did not exist. Every other predefined entity
      --  denotes a type, yields a literal or writes output, so a program could
      --  put things into the session and never take one back out: `set` wrote
      --  a variable that the program which wrote it could not then read.
      E.Submit (Shell, "set (""ENGINE_PROBE=here"");", "<line>",
                Adash.Source.Origin_Interactive, Outcome, Report);
      Assert (Adash.Execution.Succeeded (Outcome.Status), "set failed");

      Assert (Holds ("Env_Value (""ENGINE_PROBE"")", "here"),
              "the value that came back was not the one that was set");

      --  What it returns is an ordinary String and nothing weaker.
      Assert (Holds ("""was "" & Env_Value (""ENGINE_PROBE"") & "".""",
                     "was here."),
              "the value did not compose with other text");

      --  A name that is not set reads as empty rather than failing: a program
      --  testing whether something is set has to be able to ask.
      Assert (Holds ("Env_Value (""ENGINE_NOT_SET_ANYWHERE"")", ""),
              "an unset name did not read as the empty string");

      --  Inside a body, at any depth, and the body's own variables are still
      --  there afterwards. The stub a command or an ask goes through is
      --  declared outermost, so returning from it left the machine's display
      --  pointing at the frame just popped -- the fix-up a call to a
      --  subprogram declared further out has always had, and this had not. A
      --  command as the last statement of a body hid it, because nothing read
      --  a local after it.
      E.Submit (Shell,
                "procedure P is N : Integer := 1; begin "
                & "set (""ENGINE_UNUSED=1""); N := N + 1; "
                & "if N /= 2 then N := 1 / 0; end if; end P; P;",
                "<line>", Adash.Source.Origin_Interactive, Outcome, Report);
      Assert (Adash.Execution.Succeeded (Outcome.Status),
              "a local did not survive a command called in the same body");

      --  Read two frames down: the body that asks is nested inside another,
      --  and the answer still arrives.
      E.Submit (Shell,
                "function Answer return String is "
                & "function Inner return String is "
                & "begin return Env_Value (""ENGINE_PROBE""); end Inner; "
                & "begin return Inner; end Answer;",
                "<line>", Adash.Source.Origin_Interactive, Outcome, Report);
      Assert (Adash.Execution.Succeeded (Outcome.Status),
              "declaring a nested function that asks failed");

      Assert (Holds ("Answer", "here"),
              "a value read two frames down did not come back");

      --  Twice in one expression. The answer arrives through a slot the stub
      --  owns, so a second read that overwrote the first before it was
      --  consumed would give one answer twice -- which two different values
      --  are what catches.
      E.Submit (Shell, "set (""ENGINE_OTHER=there"");", "<line>",
                Adash.Source.Origin_Interactive, Outcome, Report);
      Assert (Holds ("Env_Value (""ENGINE_PROBE"") & ""/"" "
                     & "& Env_Value (""ENGINE_OTHER"")", "here/there"),
              "two reads in one expression did not answer separately");
   end A_Program_Can_Read_The_Environment;

   procedure A_Program_Can_Tell_Whether_Something_Worked
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Shell   : E.Session;
      Outcome : E.Result;
      Report  : D.List;

      --  What the program read, observed by making it fail when the number is
      --  not the expected one. `Status` is an Integer expression, so a
      --  comparison is all that is needed to test it.
      function Reads (Expected : String) return Boolean is
      begin
         E.Submit (Shell,
                   "N : Integer := 1; if Status /= " & Expected
                   & " then N := 1 / 0; end if;",
                   "<line>", Adash.Source.Origin_Interactive, Outcome, Report);
         return Adash.Execution.Succeeded (Outcome.Status);
      end Reads;
   begin
      E.Open (Shell);

      --  Commands are procedures, so a call produces no value: without this a
      --  program could run something and had no way to learn whether it
      --  worked, which is most of what a shell script does.
      Assert (Reads ("0"), "a fresh session did not read as success");

      --  A failed command does not by itself fail the submission -- that is
      --  deliberate and pinned by a conformance case -- so the status is the
      --  only place the failure is visible at all.
      E.Submit (Shell, "cd (""/adash/no/such/directory"");", "<line>",
                Adash.Source.Origin_Interactive, Outcome, Report);
      Assert (Reads ("1"), "a failed command did not show in the status");

      --  Session state, like a variable: set on one submission, read on the
      --  next.
      E.Submit (Shell, "pwd;", "<line>",
                Adash.Source.Origin_Interactive, Outcome, Report);
      Assert (Reads ("0"), "a command that worked did not clear the status");
   end A_Program_Can_Tell_Whether_Something_Worked;

   procedure A_Script_Can_Read_Its_Arguments
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Shell   : E.Session;
      Outcome : E.Result;
      Report  : D.List;

      --  Observed by making the program fail when what it read is not what was
      --  given, the same way the other value-reading cases here do.
      function Holds (Expression, Expected : String) return Boolean is
      begin
         E.Submit (Shell,
                   "N : Integer := 1; if " & Expression & " /= """
                   & Expected & """ then N := 1 / 0; end if;",
                   "<line>", Adash.Source.Origin_Interactive, Outcome, Report);
         return Adash.Execution.Succeeded (Outcome.Status);
      end Holds;
   begin
      E.Open (Shell);

      --  Nothing given is a count of zero rather than a special case.
      Assert (E.Argument_Count (Shell) = 0, "a fresh session has arguments");

      E.Add_Argument (Shell, 1, "one");
      E.Add_Argument (Shell, 2, "-v");
      E.Add_Argument (Shell, 3, "three four");

      Assert (E.Argument_Count (Shell) = 3, "the arguments were not recorded");

      --  In order, and unchanged: an argument with a space in it is one
      --  argument, and one that looks like an option is not one -- there is no
      --  word-splitting and no second parse.
      Assert (Holds ("Argument (1)", "one"), "the first argument came back wrong");
      Assert (Holds ("Argument (2)", "-v"),
              "an argument that looks like an option was taken as one");
      Assert (Holds ("Argument (3)", "three four"),
              "an argument with a space in it was split");

      --  Past either end is the empty string rather than a failure: a script
      --  asking for an argument it was not given is asking whether it was
      --  given one.
      Assert (Holds ("Argument (4)", ""), "an argument past the end was not empty");
      Assert (Holds ("Argument (0)", ""), "argument zero was not empty");
   end A_Script_Can_Read_Its_Arguments;

   procedure Unfinished_Source_Asks_For_More
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);

      function Unfinished (Text : String) return Boolean is
        (Adash.Engine.Wants_More (Text, "<line>"));
   begin
      --  What an interactive frontend needs before it submits. A line at a
      --  time is how a user types, and `if C then` is not a mistake -- it is
      --  unfinished. Each of these used to be a submission of its own, so the
      --  two halves of one construct were two programs and neither was what
      --  was meant.
      Assert (Unfinished ("if 1 = 1 then"), "an unfinished if did not ask for more");
      Assert (Unfinished ("while 1 = 1 loop"),
              "an unfinished while did not ask for more");
      Assert (Unfinished ("for I in 1 .. 3 loop"),
              "an unfinished for did not ask for more");
      Assert (Unfinished ("loop"), "a bare loop did not ask for more");
      Assert (Unfinished ("case 1 is"), "an unfinished case did not ask for more");
      Assert (Unfinished ("procedure P is begin"),
              "an unfinished body did not ask for more");
      Assert (Unfinished ("X : Integer := (1 +"),
              "an unfinished expression did not ask for more");

      --  Finished, however little of a program it is.
      Assert (not Unfinished (""), "nothing at all asked for more");
      Assert (not Unfinished ("put_line (1);"),
              "a whole statement asked for more");
      Assert (not Unfinished ("if 1 = 1 then put_line (1); end if;"),
              "a whole if asked for more");
      Assert (not Unfinished ("-- just a comment"),
              "a comment asked for more");

      --  Wrong is not the same as unfinished, and this is the distinction the
      --  whole thing rests on: waiting for more input after a mistake would
      --  leave the user at a prompt that never comes back.
      Assert (not Unfinished ("X := ;"), "a syntax error asked for more");
      Assert (not Unfinished ("if 1 = 1 than"),
              "a misspelled keyword asked for more");
      Assert (not Unfinished ("put_line (1)) ;"),
              "a stray bracket asked for more");
   end Unfinished_Source_Asks_For_More;

   procedure A_Program_Can_Be_Read_As_A_Value
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Shell   : E.Session;
      Outcome : E.Result;
      Report  : D.List;

      function Holds (Expression, Expected : String) return Boolean is
      begin
         E.Submit (Shell,
                   "N : Integer := 1; if " & Expression & " /= """
                   & Expected & """ then N := 1 / 0; end if;",
                   "<line>", Adash.Source.Origin_Interactive, Outcome, Report);
         return Adash.Execution.Succeeded (Outcome.Status);
      end Holds;
   begin
      E.Open (Shell);

      --  The direction that was missing. A shell whose language could run
      --  programs could not read what any of them said: everything a program
      --  wrote went to the terminal, and nothing could be computed from it.
      Assert (Holds ("Output_Of (""echo"", ""hello"")", "hello"),
              "what a program wrote did not come back");

      --  Arguments arrive as written, without splitting or re-scanning: one
      --  argument with a space in it is one argument.
      Assert (Holds ("Output_Of (""echo"", ""a b"")", "a b"),
              "an argument with a space in it was split");

      --  The newline it ended with is dropped, which is what makes the value
      --  usable as a path or a name. `echo` writes one, so the first
      --  assertions above already depend on this; asserting it against a
      --  program whose whole output is a newline is what says it plainly.
      Assert (Holds ("Output_Of (""echo"")", ""),
              "the final newline was not dropped");

      --  A program that said nothing answers empty rather than failing.
      Assert (Holds ("Output_Of (""true"")", ""),
              "a program that wrote nothing did not answer empty");

      --  Running it is still running a program, so the status says what became
      --  of it -- including the 127 the run family reports, from the same one
      --  place that decides.
      E.Submit (Shell, "S : String := Output_Of (""false"");", "<line>",
                Adash.Source.Origin_Interactive, Outcome, Report);

      E.Submit (Shell,
                "N : Integer := 1; if Status /= 1 then N := 1 / 0; end if;",
                "<line>", Adash.Source.Origin_Interactive, Outcome, Report);
      Assert (Adash.Execution.Succeeded (Outcome.Status),
              "a captured program that failed did not show in the status");
   end A_Program_Can_Be_Read_As_A_Value;

   procedure Exit_Is_Requested_Not_Taken
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Shell   : E.Session;
      Outcome : E.Result;
      Report  : D.List;
   begin
      E.Open (Shell);
      Assert (not E.Exit_Requested (Shell), "a fresh session wants to exit");

      E.Submit (Shell, "quit (4);", "<line>",
                Adash.Source.Origin_Interactive, Outcome, Report);

      --  The engine records it and returns. Whoever is driving decides what to
      --  do about it -- which is what lets a test run this at all.
      Assert (E.Exit_Requested (Shell), "exit did not reach the session");
      Assert (Adash.Execution.Numeric (E.Exit_Status (Shell)) = 4,
              "the exit status did not reach the session");
   end Exit_Is_Requested_Not_Taken;

   procedure Bad_Source_Is_Told_Apart_From_A_Failing_Program
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Shell   : E.Session;
      Outcome : E.Result;
      Report  : D.List;
   begin
      E.Open (Shell);

      --  Did not parse.
      E.Submit (Shell, "X := ;", "<line>",
                Adash.Source.Origin_Interactive, Outcome, Report);
      Assert (Outcome.Kind = E.Not_Understood, "broken source was understood");
      Assert (not Outcome.Ran, "broken source claimed to have run");
      Assert (Adash.Execution.Numeric (Outcome.Status) = 2,
              "a parse failure did not reduce to 2");

      --  Parsed and is illegal.
      Report.Clear;
      E.Submit (Shell, "X := 1;", "<line>",
                Adash.Source.Origin_Interactive, Outcome, Report);
      Assert (Outcome.Kind = E.Not_Understood, "an illegal program was understood");
      Assert (not Outcome.Ran, "an illegal program claimed to have run");
      Assert (Reported (Report, Adash.Errors.Error_Name_Undeclared),
              "an undeclared name was not reported through the engine");

      --  Ran, and failed. The distinction a caller needs: Ran is True.
      Report.Clear;
      E.Submit (Shell, "D : Integer := 1 / 0;", "<line>",
                Adash.Source.Origin_Interactive, Outcome, Report);
      Assert (Outcome.Kind = E.Language_Program, "a running program was misclassified");
      Assert (Outcome.Ran, "a program that raised did not report having run");
      Assert (not Adash.Execution.Succeeded (Outcome.Status),
              "a program that raised reported success");

      --  Nothing to run is not an error.
      Report.Clear;
      E.Submit (Shell, "   -- just a comment", "<line>",
                Adash.Source.Origin_Interactive, Outcome, Report);
      Assert (Outcome.Kind = E.Nothing_Submitted, "a comment was taken for a program");
      Assert (Report.Count = 0, "an empty submission produced diagnostics");
   end Bad_Source_Is_Told_Apart_From_A_Failing_Program;

   procedure Commands_And_Statements_Mix_Freely
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Shell   : E.Session;
      Outcome : E.Result;
      Report  : D.List;
   begin
      E.Open (Shell);

      --  Commands and statements on one line. This was refused until commands
      --  became calls in the language: a command ran in this process while
      --  statements were lowered into one activation record, and splitting a
      --  submission would have given the statements two of those. There is one
      --  path now, so there is nothing to split.
      E.Submit (Shell, "pwd; N : Integer := 1;", "<line>",
                Adash.Source.Origin_Interactive, Outcome, Report);
      Assert (Outcome.Kind = E.Language_Program,
              "a submission mixing a command and a statement was refused");
      Assert (Report.Count = 0, "mixing produced diagnostics");
      Assert (E.Output_Count (Shell) = 1, "the command in the mix did not run");

      --  And in the order they were written, with a value the statements
      --  computed reaching the command. This is what the whole change was for:
      --  the most basic shell script there is -- compute something, exit with
      --  it -- could not be written before.
      Report.Clear;
      E.Submit (Shell,
                "Total : Integer := 0;"
                & " for Index in 1 .. 4 loop Total := Total + Index; end loop;"
                & " quit (Total);",
                "<line>", Adash.Source.Origin_Interactive, Outcome, Report);
      Assert (Report.Count = 0,
              "computing a value and exiting with it produced diagnostics");
      Assert (E.Exit_Requested (Shell), "quit did not record the request");
      Assert (Adash.Execution.Numeric (E.Exit_Status (Shell)) = 10,
              "the computed exit status was"
              & Natural'Image (Adash.Execution.Numeric (E.Exit_Status (Shell)))
              & " rather than 10");

      --  Several commands on one line are still fine.
      E.Open (Shell);
      Report.Clear;
      E.Submit (Shell, "pwd; version;", "<line>",
                Adash.Source.Origin_Interactive, Outcome, Report);
      Assert (Outcome.Kind = E.Language_Program,
              "two commands on one line were refused");
      Assert (E.Output_Count (Shell) = 2, "two commands produced one line");

      --  A failing command does *not* stop what follows, and that is a change.
      --
      --  It used to: `cd nowhere; pwd` reported nothing. That rule came from
      --  neither of the two things Adash is meant to agree with. Ada does not
      --  have it -- a procedure that reports a failure does not end the
      --  enclosing sequence -- and neither does a POSIX shell, where
      --  `cd /nonexistent; pwd` prints the unchanged directory and exits zero.
      --  Commands are calls in a program now, so the program continues, which
      --  is what both would do.
      --
      --  A caller that wants a sequence to stop on failure writes the test.
      --  That is what `if` is for, and it is now possible to write.
      E.Open (Shell);
      Report.Clear;
      E.Submit (Shell, "cd (""./nowhere-at-all""); pwd;", "<line>",
                Adash.Source.Origin_Interactive, Outcome, Report);
      Assert (Report.Count = 1,
              "a failing command did not report exactly one diagnostic");
      Assert (E.Output_Count (Shell) = 1,
              "the command after a failing one did not run");
   end Commands_And_Statements_Mix_Freely;

   procedure Cancellation_Is_Observed_And_Clearable
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Shell   : E.Session;
      Outcome : E.Result;
      Report  : D.List;
   begin
      E.Open (Shell);
      Assert (not E.Cancellation_Requested (Shell),
              "a fresh session is already cancelled");

      E.Request_Cancellation (Shell);
      Assert (E.Cancellation_Requested (Shell), "the request did not take");

      E.Submit (Shell, "N : Integer := 1;", "<line>",
                Adash.Source.Origin_Interactive, Outcome, Report);
      Assert (not Outcome.Ran, "a cancelled submission ran anyway");
      Assert (Adash.Execution.Numeric (Outcome.Status) = 130,
              "a cancelled submission did not reduce to 130");

      --  Cleared between submissions, or one interrupt would stop everything
      --  the user typed afterwards.
      E.Clear_Cancellation (Shell);
      Assert (not E.Cancellation_Requested (Shell), "clearing did not take");

      E.Submit (Shell, "N : Integer := 1;", "<line>",
                Adash.Source.Origin_Interactive, Outcome, Report);
      Assert (Outcome.Ran, "a submission after a cleared cancellation did not run");
   end Cancellation_Is_Observed_And_Clearable;

   ----------
   -- Name --
   ----------

   procedure Declarations_Survive_A_Submission
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Session : E.Session;
      Report  : D.List;
      Outcome : E.Result;

      use type Adash.Execution.Exit_Kind;
   begin
      E.Open (Session);

      --  A definition on one line and the line that uses it are separate
      --  submissions, and the second can only resolve the call if the session
      --  carried the first forward.
      E.Submit (Session, "function Twice (N : Integer) return Integer is "
                & "begin return N * 2; end Twice;",
                "<one>", Adash.Source.Origin_Interactive, Outcome, Report);
      Assert (Report.Count = 0, "declaring a function reported something");

      E.Submit (Session, "X : Integer := Twice (21);",
                "<two>", Adash.Source.Origin_Interactive, Outcome, Report);
      Assert (Report.Count = 0,
              "a call to a function declared earlier was not resolved");
      Assert (Outcome.Ran, "the second submission did not run");

      --  Redefining it replaces what was there rather than colliding with it.
      --  Prepending the old one to a submission that declares the same thing
      --  would report a duplicate, which is what a user redefining something
      --  interactively least wants to see.
      Report.Clear;
      E.Submit (Session, "function Twice (N : Integer) return Integer is "
                & "begin return N * 3; end Twice;",
                "<three>", Adash.Source.Origin_Interactive, Outcome, Report);
      Assert (Report.Count = 0,
              "redefining a function was reported as a duplicate");

      --  The trap raises, and a program that raises now reports it, so the
      --  status is what says whether the redefined body ran -- not the absence
      --  of diagnostics.
      Report.Clear;
      E.Submit (Session, "if Twice (2) = 6 then Y : Integer := 1 / 0; end if;",
                "<four>", Adash.Source.Origin_Interactive, Outcome, Report);
      Assert (Outcome.Status.Kind = Adash.Execution.Exit_Internal_Failure,
              "the redefined body was not the one that ran");

      --  A different profile is an overload, not a replacement, so both stay.
      Report.Clear;
      E.Submit (Session, "function Twice (S : String) return String is "
                & "begin return S & S; end Twice;",
                "<five>", Adash.Source.Origin_Interactive, Outcome, Report);
      Assert (Report.Count = 0, "declaring an overload reported something");
      Report.Clear;
      E.Submit (Session, "if Twice (2) = 6 and Twice (""a"") = ""aa"" "
                & "then Y : Integer := 1 / 0; end if;",
                "<six>", Adash.Source.Origin_Interactive, Outcome, Report);
      Assert (Outcome.Status.Kind = Adash.Execution.Exit_Internal_Failure,
              "both overloads were not callable together");

      --  An object survives with the value it ended with, not the one it was
      --  declared with. The program hands its variables back as it ends, which
      --  is the only way a value crosses out of the machine.
      Report.Clear;
      E.Submit (Session, "Kept : Integer := 5;",
                "<seven>", Adash.Source.Origin_Interactive, Outcome, Report);
      Report.Clear;
      E.Submit (Session, "Kept := 9;",
                "<eight>", Adash.Source.Origin_Interactive, Outcome, Report);
      Assert (Report.Count = 0, "assigning to a carried object reported");

      Report.Clear;
      E.Submit (Session, "if Kept = 9 then Y : Integer := 1 / 0; end if;",
                "<nine>", Adash.Source.Origin_Interactive, Outcome, Report);
      Assert (Outcome.Status.Kind = Adash.Execution.Exit_Internal_Failure,
              "an object came back with the value it was declared with, "
              & "not the one it ended with");

      --  A program stopped before it ends hands nothing back, so what it left
      --  in a variable is not carried. What a half-run program left there is
      --  not a value anyone chose.
      Report.Clear;
      E.Submit (Session, "Gone : Integer := 1; quit (0);",
                "<ten>", Adash.Source.Origin_Interactive, Outcome, Report);
      Report.Clear;
      E.Submit (Session, "put_line (Gone);",
                "<eleven>", Adash.Source.Origin_Interactive, Outcome, Report);
      Assert (Report.Count > 0,
              "a variable from a program that stopped early was carried");
   end Declarations_Survive_A_Submission;

   overriding function Name (T : Case_Type) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Adash.Engine");
   end Name;

   --------------------
   -- Register_Tests --
   --------------------

   overriding procedure Register_Tests (T : in out Case_Type) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Declarations_Survive_A_Submission'Access,
         "a subprogram declared in one submission is callable in the next");
      Register_Routine
        (T, One_Engine_Serves_Commands_And_Programs'Access,
         "engine : one engine serves commands and programs");
      Register_Routine
        (T, State_Carries_Between_Submissions'Access,
         "engine : state carries between submissions");
      Register_Routine
        (T, A_Program_Can_Read_The_Environment'Access,
         "engine : a program can read a value out of the session");
      Register_Routine
        (T, A_Program_Can_Tell_Whether_Something_Worked'Access,
         "engine : a program can tell whether what it ran worked");
      Register_Routine
        (T, A_Script_Can_Read_Its_Arguments'Access,
         "engine : a script can read the arguments it was invoked with");
      Register_Routine
        (T, Unfinished_Source_Asks_For_More'Access,
         "engine : unfinished source asks for more, and wrong source does not");
      Register_Routine
        (T, A_Program_Can_Be_Read_As_A_Value'Access,
         "engine : a program's output can be read as a value");
      Register_Routine
        (T, Exit_Is_Requested_Not_Taken'Access,
         "engine : exit is requested, not taken");
      Register_Routine
        (T, Bad_Source_Is_Told_Apart_From_A_Failing_Program'Access,
         "engine : bad source is told apart from a program that ran and failed");
      Register_Routine
        (T, Commands_And_Statements_Mix_Freely'Access,
         "engine : commands and statements mix, in the order written");
      Register_Routine
        (T, Cancellation_Is_Observed_And_Clearable'Access,
         "engine : cancellation is observed and clearable");
      Register_Routine
        (T, A_Raise_Costs_Only_Its_Own_Submission'Access,
         "engine : a raise costs its own submission and nobody else's");
   end Register_Tests;

end Adash_Tests.Engine_Cases;
