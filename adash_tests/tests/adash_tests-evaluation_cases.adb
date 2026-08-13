with Ada.Strings.Unbounded;
with AUnit.Assertions;

with Adash.Diagnostics;
with Adash.Errors;
with Adash.Language.Evaluation;
with Adash.Language.Lexer;
with Adash.Language.Parser;
with Adash.Language.Semantics;
with Adash.Language.Values;
with Adash.Language.Syntax;
with Adash.Language.Tokens;
with Adash.Source;

package body Adash_Tests.Evaluation_Cases is

   use AUnit.Assertions;

   package S renames Adash.Language.Syntax;
   package Sem renames Adash.Language.Semantics;
   package Ev renames Adash.Language.Evaluation;
   package D renames Adash.Diagnostics;
   package Src renames Adash.Source;

   use type Ev.Outcome;

   --  Lex, parse, analyse and run.
   function Execute (Text : String) return Ev.Outcome is
      Buffer : Src.Buffer;
      Stream : Adash.Language.Tokens.Token_Stream;
      Tree   : S.Tree;
      Result : Sem.Analysis;
      Report : D.List;
      Error  : Adash.Errors.Error_Info;
      Origin : constant Src.Origin := Src.Make_Origin (Src.Origin_Text, "<run>");
      Ran    : Ev.Outcome;
   begin
      Assert (Src.Load (Buffer, Origin, Text, Error), "the source did not load");
      Adash.Language.Lexer.Scan (Buffer, Stream, Report);
      Adash.Language.Parser.Parse (Stream, Origin, Tree, Report);
      Sem.Analyse (Tree, Origin, Result, Report);
      Ev.Run (Tree, Result, Origin, Ran, Report);
      return Ran;
   end Execute;

   --  A program that divides by zero only if it reaches the trap.
   function Reaches (Text : String) return Boolean
   is (Execute (Text) = Ev.Raised);

   ------------------------------------------------------------------

   --  A sink that records what a lowered program asked for, so a test can
   --  assert that a command call reached this process with the right name and
   --  the right argument. Adash.Engine will supply the real one; this proves
   --  the machinery without dragging the execution subsystem into a language
   --  test.
   type Recording_Sink is limited new Ev.Command_Sink with record
      Calls    : Natural := 0;
      Last     : Ada.Strings.Unbounded.Unbounded_String;
      Argument : Ada.Strings.Unbounded.Unbounded_String;
      Had      : Boolean := False;

      --  Set by a test that wants this sink to behave like `quit`.
      Halt_On_Call : Boolean := False;
   end record;

   overriding procedure Invoke
     (Sink      : in out Recording_Sink;
      Name      : String;
      Arguments : Ev.Argument_Values;
      Count     : Natural;
      Failed    : out Boolean;
      Halt      : out Boolean);

   overriding procedure Invoke
     (Sink      : in out Recording_Sink;
      Name      : String;
      Arguments : Ev.Argument_Values;
      Count     : Natural;
      Failed    : out Boolean;
      Halt      : out Boolean)
   is
      use Ada.Strings.Unbounded;
   begin
      Sink.Calls := Sink.Calls + 1;
      Sink.Last := To_Unbounded_String (Name);

      --  Image, so the test can assert on one string whatever the type was.
      --  What matters here is that the value arrived; the types themselves are
      --  asserted where they are checked, in the semantics case. Every argument
      --  is recorded, separated, so a test can assert that a call with more
      --  than one delivered all of them and in order.
      Sink.Argument := Null_Unbounded_String;

      for Position in 1 .. Count loop
         if Position > 1 then
            Append (Sink.Argument, "|");
         end if;

         Append (Sink.Argument,
                 Adash.Language.Values.Image (Arguments (Position)));
      end loop;

      Sink.Had := Count > 0;
      Failed := False;

      --  The probe stops the program when it is told to stop, so a test can
      --  assert that the statements after a halting command do not run.
      Halt := Sink.Halt_On_Call;
   end Invoke;

   --  Library-level, deliberately. Sink_Access is a general access type
   --  declared in Adash.Language.Evaluation, so an access to a sink declared
   --  inside a subprogram would not outlive it and Ada refuses the conversion
   --  -- at run time, as an accessibility check. One probe, reset before each
   --  scenario, is the honest way round it and mirrors what Adash.Engine will
   --  do: the sink lives as long as the session.
   Probe : aliased Recording_Sink;

   --  A cancellation source a test can flip. The real one is a session's
   --  token; this is the same shape without an engine behind it.
   type Switch is limited new Ev.Cancellation_Source with record
      Stop_After : Natural := 0;
      Asked      : Natural := 0;
   end record;

   overriding function Is_Cancelled (Source : Switch) return Boolean;

   overriding function Is_Cancelled (Source : Switch) return Boolean is
      Mutable : Switch renames Source'Unrestricted_Access.all;
   begin
      --  Counting how many times the machine asked is the point: it has to ask
      --  while the program is running, not once before it starts, or a program
      --  that never ends could never be stopped.
      Mutable.Asked := Mutable.Asked + 1;
      return Mutable.Asked > Mutable.Stop_After;
   end Is_Cancelled;

   Stopper : aliased Switch;

   procedure Reset_Probe;

   procedure Reset_Probe is
      use Ada.Strings.Unbounded;
   begin
      --  Field by field: a sink is limited, as an interface implementation
      --  should be, so it cannot be assigned whole.
      Probe.Calls := 0;
      Probe.Last := Null_Unbounded_String;
      Probe.Argument := Null_Unbounded_String;
      Probe.Had := False;
      Probe.Halt_On_Call := False;
   end Reset_Probe;

   ------------------------------------------------------------------

   procedure Commands_Reach_This_Process
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      use Ada.Strings.Unbounded;

      function Run_With (Text : String) return Ev.Outcome;

      function Run_With (Text : String) return Ev.Outcome
      is
         Buffer : Src.Buffer;
         Stream : Adash.Language.Tokens.Token_Stream;
         Tree   : S.Tree;
         Result : Sem.Analysis;
         Report : D.List;
         Error  : Adash.Errors.Error_Info;
         Origin : constant Src.Origin :=
           Src.Make_Origin (Src.Origin_Text, "<run>");
         Ran    : Ev.Outcome;
      begin
         Assert (Src.Load (Buffer, Origin, Text, Error), "the source did not load");
         Adash.Language.Lexer.Scan (Buffer, Stream, Report);
         Adash.Language.Parser.Parse (Stream, Origin, Tree, Report);
         Sem.Analyse (Tree, Origin, Result, Report);
         Ev.Run (Tree, Result, Origin, Ran, Report,
                 On_Command => Probe'Access);
         return Ran;
      end Run_With;

   begin
      --  A command with no argument, inside control flow. This is the whole
      --  point of the mechanism: a command runs at the moment the program
      --  reaches it, not before or after, and it runs in this process because
      --  it changes this process's state.
      Reset_Probe;

      declare
      begin
         Assert (Run_With ("if True then pwd; end if;")
                 = Ev.Evaluated,
                 "a program calling a command did not run");
         Assert (Probe.Calls = 1,
                 "the command was called" & Natural'Image (Probe.Calls)
                 & " times rather than once");
         Assert (To_String (Probe.Last) = "pwd",
                 "the sink was told the command was " & To_String (Probe.Last));
         Assert (not Probe.Had, "pwd was reported as having an argument");
      end;

      --  An argument the machine computed. Nothing else in Adash can do this:
      --  the value did not exist when the program was written.
      Reset_Probe;

      declare
      begin
         Assert (Run_With ("N : Integer := 4;"
                           & " if True then quit (N * 2 + 2); end if;")
                 = Ev.Evaluated,
                 "a program calling a command with an expression did not run");
         Assert (Probe.Had, "quit was reported as having no argument");
         Assert (To_String (Probe.Argument) = "10",
                 "the computed argument arrived as ["
                 & To_String (Probe.Argument) & "] rather than [10]");
      end;

      --  A String argument travels in the other slot, and a variable's value
      --  arrives rather than its name.
      Reset_Probe;

      declare
      begin
         Assert (Run_With ("P : String := ""/tmp"";"
                           & " if True then cd (P); end if;")
                 = Ev.Evaluated,
                 "a program calling a command with a String did not run");
         Assert (To_String (Probe.Argument) = "/tmp",
                 "the String argument arrived as ["
                 & To_String (Probe.Argument) & "]");
      end;

      --  Once per iteration, because the call is inside the loop. A design
      --  that ran commands before or after the program could not do this at
      --  all.
      Reset_Probe;

      declare
      begin
         Assert (Run_With ("for I in 1 .. 3 loop pwd; end loop;")
                 = Ev.Evaluated,
                 "a program calling a command in a loop did not run");
         Assert (Probe.Calls = 3,
                 "the command in a loop ran" & Natural'Image (Probe.Calls)
                 & " times rather than three");
      end;

      --  A command that ends the session stops the program there. `quit (0);
      --  pwd;` used to print the directory: the request was recorded and the
      --  rest ran anyway, which is not what anybody writing quit means.
      Reset_Probe;
      Probe.Halt_On_Call := True;

      declare
      begin
         Assert (Run_With ("for I in 1 .. 3 loop pwd; end loop;")
                 = Ev.Evaluated,
                 "a program whose command halted did not run");
         Assert (Probe.Calls = 1,
                 "a halting command ran" & Natural'Image (Probe.Calls)
                 & " times rather than stopping the program at the first");
      end;

      --  And a command that does not ask to stop does not stop anything. The
      --  halt is the command's decision, not a property of calling one.
      Reset_Probe;

      declare
      begin
         Assert (Run_With ("for I in 1 .. 3 loop pwd; end loop;")
                 = Ev.Evaluated,
                 "a program with an ordinary command did not run");
         Assert (Probe.Calls = 3,
                 "an ordinary command stopped the program after"
                 & Natural'Image (Probe.Calls) & " calls");
      end;

      --  Without a sink the caller cannot run commands, so the call is refused
      --  rather than skipped: dropping it would make the program mean
      --  something its author did not write.
      Assert (Execute ("if True then pwd; end if;") = Ev.Not_Lowerable,
              "a command was lowered with no sink to run it");
   end Commands_Reach_This_Process;

   ------------------------------------------------------------------

   procedure Strings_Are_Values (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
   begin
      --  Division by zero is the probe, as everywhere else in this file: a
      --  program can compute a String but cannot yet report one, so the only
      --  way to observe a string value is to make reaching a trap depend on
      --  it. Reaches is True when the trap was hit, so each assertion reads as
      --  "this condition held".

      Assert (Reaches ("N : Integer := 0;"
                       & " if ""abc"" = ""abc"" then N := 1/0; end if;"),
              "a string literal did not equal itself");
      Assert (not Reaches ("N : Integer := 0;"
                           & " if ""abc"" = ""xyz"" then N := 1/0; end if;"),
              "two different string literals compared equal");

      Assert (Reaches ("X : String := ""hello""; N : Integer := 0;"
                       & " if X = ""hello"" then N := 1/0; end if;"),
              "a String variable did not hold its initial value");
      Assert (Reaches ("X : String := ""hello""; Y : String := X;"
                       & " N : Integer := 0;"
                       & " if Y = ""hello"" then N := 1/0; end if;"),
              "copying a String did not preserve it");

      --  Both halves matter: a store that copied only the discrete field would
      --  leave the text behind, and then the first assertion alone would pass
      --  for the wrong reason.
      Assert (Reaches ("X : String := ""a""; N : Integer := 0; X := ""b"";"
                       & " if X = ""b"" then N := 1/0; end if;"),
              "assigning a String did not take effect");
      Assert (not Reaches ("X : String := ""a""; N : Integer := 0; X := ""b"";"
                           & " if X = ""a"" then N := 1/0; end if;"),
              "assigning a String left the old value in place");

      Assert (Reaches ("X : String := """"; N : Integer := 0;"
                       & " if X = """" then N := 1/0; end if;"),
              "the empty string did not equal itself");

      --  Bytes above ASCII survive: the lexer decodes UTF-8 and the machine
      --  carries the text, so an accented string must come back byte for byte.
      Assert (Reaches ("X : String := ""h" & Character'Val (16#C3#)
                       & Character'Val (16#A9#) & "llo""; N : Integer := 0;"
                       & " if X = ""h" & Character'Val (16#C3#)
                       & Character'Val (16#A9#)
                       & "llo"" then N := 1/0; end if;"),
              "a String with a multi-byte character did not survive");
   end Strings_Are_Values;

   ------------------------------------------------------------------

   procedure Strings_Compare_As_Text
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
   begin
      --  Ordering is by text, not by whatever the cell's discrete field holds.
      --  Emitting the Integer comparison opcodes for a String would compare
      --  two fields that are not used and answer confidently and wrongly,
      --  which is why both directions are asserted rather than one.
      Assert (Reaches ("N : Integer := 0;"
                       & " if ""abc"" < ""abd"" then N := 1/0; end if;"),
              "abc did not sort before abd");
      Assert (not Reaches ("N : Integer := 0;"
                           & " if ""abd"" < ""abc"" then N := 1/0; end if;"),
              "abd sorted before abc");
      Assert (Reaches ("N : Integer := 0;"
                       & " if ""a"" /= ""b"" then N := 1/0; end if;"),
              "two different strings compared equal under /=");
      Assert (Reaches ("N : Integer := 0;"
                       & " if ""abc"" <= ""abc"" then N := 1/0; end if;"),
              "a string was not less than or equal to itself");
   end Strings_Compare_As_Text;

   ------------------------------------------------------------------

   procedure A_Running_Program_Can_Be_Stopped
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);

      function Run_Until_Stopped (Text : String; After : Natural)
                                  return Ev.Outcome;

      function Run_Until_Stopped (Text : String; After : Natural)
                                  return Ev.Outcome
      is
         Buffer : Src.Buffer;
         Stream : Adash.Language.Tokens.Token_Stream;
         Tree   : S.Tree;
         Result : Sem.Analysis;
         Report : D.List;
         Error  : Adash.Errors.Error_Info;
         Origin : constant Src.Origin :=
           Src.Make_Origin (Src.Origin_Text, "<run>");
         Ran    : Ev.Outcome;
      begin
         Stopper.Stop_After := After;
         Stopper.Asked := 0;

         Assert (Src.Load (Buffer, Origin, Text, Error),
                 "the source did not load");
         Adash.Language.Lexer.Scan (Buffer, Stream, Report);
         Adash.Language.Parser.Parse (Stream, Origin, Tree, Report);
         Sem.Analyse (Tree, Origin, Result, Report);
         Ev.Run (Tree, Result, Origin, Ran, Report,
                 Cancel => Stopper'Access);
         return Ran;
      end Run_Until_Stopped;

   begin
      --  A program that never ends on its own. Without this the test would
      --  hang rather than fail, which is exactly what happened to the suite
      --  when the bare loop first lowered -- so the assertion is that it
      --  *returns at all*, and what it returns.
      Assert (Run_Until_Stopped ("loop null; end loop;", After => 2)
              = Ev.Cancelled,
              "an endless program was not stopped, or not reported as "
              & "cancelled");
      Assert (Stopper.Asked > 1,
              "the machine asked only once, so it asked before running rather "
              & "than while running");

      --  Cancellation is not a failure of the program: a shell whose scripts
      --  could not tell an interruption from a fault would make both
      --  unactionable.
      Assert (Run_Until_Stopped ("loop null; end loop;", After => 2)
              /= Ev.Raised,
              "a cancelled program was reported as having raised");

      --  A program that ends by itself is not disturbed by being asked. The
      --  switch is set never to fire here.
      Assert (Run_Until_Stopped ("N : Integer := 0;"
                                 & " for I in 1 .. 5 loop N := N + I; end loop;",
                                 After => Natural'Last) = Ev.Evaluated,
              "a program that ends by itself did not run to completion");
   end A_Running_Program_Can_Be_Stopped;

   ------------------------------------------------------------------

   procedure Loops_And_Early_Exit
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
   begin
      --  A bare loop ends only when something leaves it. Every assertion here
      --  is written so that a loop which failed to leave would hang the suite
      --  rather than fail it, so each is a program with a bound of its own.
      Assert (Reaches ("N : Integer := 0;"
                       & " loop N := N + 1; exit when N = 3; end loop;"
                       & " if N = 3 then N := 1/0; end if;"),
              "a bare loop with exit when did not run three times");
      Assert (Reaches ("N : Integer := 0;"
                       & " loop N := N + 1;"
                       & " if N = 4 then exit; end if; end loop;"
                       & " if N = 4 then N := 1/0; end if;"),
              "a bare loop with a plain exit did not leave");

      --  exit is legal in any loop, not only a bare one. A loop that took the
      --  statement without leaving would be worse than one that refused it.
      Assert (Reaches ("T : Integer := 0;"
                       & " for I in 1 .. 10 loop T := T + I;"
                       & " exit when T > 5; end loop;"
                       & " if T = 6 then N2 : Integer := 1/0; end if;"),
              "exit did not leave a for loop at the right turn");
      Assert (Reaches ("N : Integer := 0;"
                       & " while N < 100 loop N := N + 1;"
                       & " exit when N = 2; end loop;"
                       & " if N = 2 then N := 1/0; end if;"),
              "exit did not leave a while loop");

      --  It leaves one loop, not all of them: the inner loop runs once per
      --  turn of the outer.
      Assert (Reaches ("C : Integer := 0;"
                       & " for Outer in 1 .. 3 loop"
                       & "   loop C := C + 1; exit; end loop;"
                       & " end loop;"
                       & " if C = 3 then C := 1/0; end if;"),
              "exit left more than the innermost loop");

      --  return leaves the program where it stands.
      Assert (Reaches ("N : Integer := 0;"
                       & " if True then N := 1/0; end if; return;"),
              "a program did not reach a trap before its return");
      Assert (not Reaches ("N : Integer := 0; return;"
                           & " if True then N := 1/0; end if;"),
              "statements after a return still ran");

      --  A return carrying a value is a function's, and this subset has no
      --  functions to write one in. Refused rather than treated as a bare
      --  return with the value discarded, which would run and lose it.
      Assert (Execute ("return 1;") = Ev.Not_Lowerable,
              "a return with a value was accepted");

      --  An exit with nothing to leave is a fault in the program, so the
      --  analyser refuses it rather than the lowering reporting that this
      --  build cannot run it -- which would say Adash is incomplete when what
      --  is wrong is the exit.
      Assert (Execute ("exit;") = Ev.Refused,
              "an exit outside a loop was not refused");
      Assert (Execute ("if True then exit; end if;") = Ev.Refused,
              "an exit outside a loop inside an if was not refused");
   end Loops_And_Early_Exit;

   ------------------------------------------------------------------

   procedure Numeric_Operations
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
   begin
      --  abs, for both numeric types. It is a standard function rather than an
      --  instruction, and there is one per type: a Float's value is in a
      --  different field of the machine's cell, so the integer form would take
      --  the absolute value of a field the Float is not using and leave the
      --  number untouched -- running on with the wrong answer rather than
      --  failing.
      Assert (Reaches ("N : Integer := 0;"
                       & " if abs (-5) = 5 then N := 1/0; end if;"),
              "abs of a negative Integer was not its magnitude");
      Assert (Reaches ("N : Integer := 0;"
                       & " if abs 5 = 5 then N := 1/0; end if;"),
              "abs of a positive Integer changed it");
      Assert (Reaches ("X : Float := -2.25; N : Integer := 0;"
                       & " if abs X = 2.25 then N := 1/0; end if;"),
              "abs of a negative Float was not its magnitude");
      Assert (not Reaches ("X : Float := -2.25; N : Integer := 0;"
                           & " if abs X = -2.25 then N := 1/0; end if;"),
              "abs of a negative Float left it negative");

      --  Negation has the same shape and the same trap, and it is what caught
      --  it: -2.25 printed as 2.25 because the integer instruction negated a
      --  field the Float was not using.
      Assert (Reaches ("X : Float := 2.25; N : Integer := 0;"
                       & " if -X = -2.25 then N := 1/0; end if;"),
              "negating a Float did not change it");

      --  Float arithmetic and comparison, which have a variant per type for
      --  the same reason.
      Assert (Reaches ("N : Integer := 0;"
                       & " if 1.5 + 2.25 = 3.75 then N := 1/0; end if;"),
              "Float addition was wrong");
      Assert (Reaches ("N : Integer := 0;"
                       & " if 7.0 / 2.0 = 3.5 then N := 1/0; end if;"),
              "Float division was wrong");
      Assert (not Reaches ("N : Integer := 0;"
                           & " if 2.0 < 1.5 then N := 1/0; end if;"),
              "Float ordering was wrong");

      --  Ada has no implicit conversion and neither does this, so a Float and
      --  an Integer do not mix even where the value would fit.
      Assert (Execute ("X : Float := 1;") = Ev.Refused,
              "an Integer initialised a Float");
   end Numeric_Operations;

   ------------------------------------------------------------------

   procedure Strings_Concatenate
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
   begin
      Assert (Reaches ("N : Integer := 0;"
                       & " if ""a"" & ""b"" = ""ab"" then N := 1/0; end if;"),
              "two strings did not concatenate");

      --  The empty string, in every position. These were the cases that were
      --  wrong, and they were wrong because the empty literal was not empty:
      --  Adash.Language.Tokens.Make used the empty string as a sentinel for
      --  "no decoded value supplied" and fell back to the token's source text,
      --  so a written "" decoded to its own two quote characters.
      --
      --  It hid well. Anything that only compared literals with each other
      --  agreed -- "" equalled "" because both sides were the same two
      --  characters -- and only concatenating one with something else made the
      --  extra characters visible. That is why all three positions are
      --  asserted rather than one.
      Assert (Reaches ("N : Integer := 0;"
                       & " if """" & ""z"" = ""z"" then N := 1/0; end if;"),
              "an empty left operand did not concatenate");
      Assert (Reaches ("N : Integer := 0;"
                       & " if ""abc"" & """" = ""abc"" then N := 1/0; end if;"),
              "an empty right operand did not concatenate");
      Assert (Reaches ("N : Integer := 0;"
                       & " if """" & """" = """" then N := 1/0; end if;"),
              "two empty operands did not concatenate to nothing");

      --  And the empty literal really is empty, which is the underlying claim.
      Assert (not Reaches ("X : String := """"; N : Integer := 0;"
                           & " if X = ""z"" then N := 1/0; end if;"),
              "the empty string equalled something");

      --  Building a string up, which is the first thing anybody writes and the
      --  thing that could not be done.
      Assert (Reaches ("X : String := """"; N : Integer := 0;"
                       & " for I in 1 .. 3 loop X := X & ""z""; end loop;"
                       & " if X = ""zzz"" then N := 1/0; end if;"),
              "accumulating a string in a loop gave the wrong result");
   end Strings_Concatenate;

   ------------------------------------------------------------------

   procedure What_Strings_Cannot_Do_Yet
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
   begin
      --  Ada does not allow this either -- String is unconstrained -- so
      --  accepting it would make Adash take a declaration real Ada rejects.
      Assert (Execute ("X : String;") = Ev.Not_Lowerable,
              "a String declared with no initial value was accepted");
   end What_Strings_Cannot_Do_Yet;

   ------------------------------------------------------------------

   procedure A_Program_Runs_On_The_Virtual_Machine
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
   begin
      --  The simplest thing that can work: declare, assign, arrive at the end.
      Assert (Execute ("X : Integer := 1; X := X + 1;") = Ev.Evaluated,
              "a trivial program did not run");
      Assert (Ev.Last_Instruction_Count > 0,
              "running produced no instructions at all");

      --  And the observable: a division by zero really does raise, so the
      --  tests below mean something.
      Assert (Execute ("X : Integer := 1 / 0;") = Ev.Raised,
              "division by zero did not raise");
   end A_Program_Runs_On_The_Virtual_Machine;

   procedure Arithmetic_Is_Actually_Computed
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
   begin
      --  6 * 7 = 42, so 42 - 42 is zero and dividing by it raises. If the
      --  multiplication were wrong the divisor would be non-zero and nothing
      --  would happen -- which is what makes this a test of the arithmetic
      --  rather than of the emitter running at all.
      Assert (Reaches ("D : Integer := 1 / (6 * 7 - 42);"),
              "6 * 7 did not compute 42");
      Assert (not Reaches ("D : Integer := 1 / (6 * 7 - 41);"),
              "the trap fired when the arithmetic was correct");

      --  Precedence, on the machine rather than in the tree.
      Assert (Reaches ("D : Integer := 1 / (1 + 2 * 3 - 7);"),
              "1 + 2 * 3 did not compute 7");

      --  Left associativity: 10 - 3 - 2 is 5, not 9.
      Assert (Reaches ("D : Integer := 1 / (10 - 3 - 2 - 5);"),
              "10 - 3 - 2 did not compute 5");

      --  Division, remainder and negation.
      Assert (Reaches ("D : Integer := 1 / (7 / 2 - 3);"), "7 / 2 was not 3");
      Assert (Reaches ("D : Integer := 1 / (7 mod 3 - 1);"), "7 mod 3 was not 1");
      Assert (Reaches ("D : Integer := 1 / (-5 + 5);"), "unary minus was wrong");
   end Arithmetic_Is_Actually_Computed;

   procedure Variables_Keep_Their_Values
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
   begin
      --  Stored, then loaded back. A slot allocated wrongly would read
      --  something else and the subtraction would not be zero.
      Assert (Reaches ("X : Integer := 41; Y : Integer := X + 1;"
                       & "D : Integer := 1 / (Y - 42);"),
              "a variable did not keep its value across a statement");

      --  Two variables must not share a slot.
      Assert (Reaches ("A : Integer := 3; B : Integer := 4;"
                       & "D : Integer := 1 / (A * B - 12);"),
              "two variables collided in one slot");

      --  Assignment replaces.
      Assert (Reaches ("X : Integer := 1; X := 9; D : Integer := 1 / (X - 9);"),
              "assignment did not replace the value");
   end Variables_Keep_Their_Values;

   procedure Conditionals_Take_The_Right_Branch
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
   begin
      --  The trap is in the taken branch, so it must fire.
      Assert (Reaches ("X : Integer := 1;"
                       & "if X = 1 then X := 1 / 0; end if;"),
              "a true condition did not take the then branch");

      --  The trap is in the untaken branch, so it must not.
      Assert (not Reaches ("X : Integer := 1;"
                           & "if X = 2 then X := 1 / 0; end if;"),
              "a false condition took the then branch anyway");

      --  Both arms, each way round. A jump that landed one instruction out
      --  would show up here and nowhere else.
      Assert (Reaches ("X : Integer := 1;"
                       & "if X = 2 then X := 5; else X := 1 / 0; end if;"),
              "a false condition did not take the else branch");
      Assert (not Reaches ("X : Integer := 1;"
                           & "if X = 1 then X := 5; else X := 1 / 0; end if;"),
              "a true condition took the else branch");

      --  An elsif is a nested if in the tree, and has to land correctly too.
      Assert (Reaches ("X : Integer := 2;"
                       & "if X = 1 then X := 5;"
                       & " elsif X = 2 then X := 1 / 0;"
                       & " else X := 7; end if;"),
              "an elsif branch was not reached");
      Assert (not Reaches ("X : Integer := 3;"
                           & "if X = 1 then X := 5;"
                           & " elsif X = 2 then X := 1 / 0;"
                           & " else X := 7; end if;"),
              "an elsif branch was taken when its condition was false");
   end Conditionals_Take_The_Right_Branch;

   procedure Loops_Run_The_Right_Number_Of_Times
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
   begin
      --  A while loop that counts to 5, then traps on the total.
      Assert (Reaches ("N : Integer := 0;"
                       & "while N < 5 loop N := N + 1; end loop;"
                       & "D : Integer := 1 / (N - 5);"),
              "a while loop did not run five times");

      --  A loop whose condition is false at the top must not run at all.
      Assert (not Reaches ("N : Integer := 9;"
                           & "while N < 5 loop N := 1 / 0; end loop;"),
              "a while loop with a false condition ran its body");

      --  A for loop runs over its whole range, inclusive at both ends.
      Assert (Reaches ("Total : Integer := 0;"
                       & "for I in 1 .. 4 loop Total := Total + I; end loop;"
                       & "D : Integer := 1 / (Total - 10);"),
              "for 1 .. 4 did not sum to 10");

      --  An empty range runs zero times.
      Assert (not Reaches ("for I in 5 .. 1 loop"
                           & " D : Integer := 1 / 0; end loop;"),
              "a for loop with an empty range ran its body");
   end Loops_Run_The_Right_Number_Of_Times;

   procedure Short_Circuits_Do_Not_Evaluate_The_Right_Side
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
   begin
      --  The whole point of `and then`. If the right operand were evaluated
      --  anyway the division would happen and this would raise.
      Assert (not Reaches ("X : Integer := 0;"
                           & "B : Boolean := X /= 0 and then 1 / X = 1;"),
              "and then evaluated its right operand after a False left");

      --  And `or else`, the other way round.
      Assert (not Reaches ("X : Integer := 0;"
                           & "B : Boolean := X = 0 or else 1 / X = 1;"),
              "or else evaluated its right operand after a True left");

      --  When the left does not decide, the right must run.
      Assert (Reaches ("X : Integer := 1;"
                       & "B : Boolean := X /= 0 and then 1 / (X - 1) = 1;"),
              "and then did not evaluate its right operand after a True left");

      --  Plain and/or still work, and produce Booleans conditions accept.
      Assert (Reaches ("B : Boolean := True and False;"
                       & "if B then null; else D : Integer := 1 / 0; end if;"),
              "True and False did not produce False");
      Assert (Reaches ("B : Boolean := True or False;"
                       & "if B then D : Integer := 1 / 0; end if;"),
              "True or False did not produce True");
   end Short_Circuits_Do_Not_Evaluate_The_Right_Side;

   procedure What_Cannot_Be_Lowered_Is_Said_So
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
   begin
      --  Legal Adash the lowering cannot emit yet. Reported as its own outcome
      --  rather than as a refusal, because the program is not wrong -- Adash is
      --  incomplete, and a user deserves to know which.
      --  Float and String were both here. Both lower now, and the assertions
      --  are gone rather than weakened -- what is left is a comment about the
      --  pattern, because the pattern is the point: when a type starts
      --  lowering, the test recording it as unlowerable is supposed to fail,
      --  and updating it is how the change gets noticed rather than slipping
      --  past. All four of the ones that used to be here failed on the day
      --  they were supposed to.
      --
      --  What is still refused is smaller and more specific -- a bare loop, a
      --  return -- and are asserted below.
      --
      --  `abs` was named here too and was not actually asserted: nothing
      --  failed when it started lowering. A comment claiming coverage that
      --  does not exist is worse than no comment, because it stops anybody
      --  looking. It is tested now, in Numeric_Operations, and so are loops
      --  and return, in Loops_And_Early_Exit.
      --
      --  The bare loop was asserted here, as `loop null; end loop;`. When it
      --  started lowering that assertion did not fail -- it *hung*, because
      --  the program it names now runs and never ends. A test whose subject
      --  becomes an infinite loop is a test that stops the suite rather than
      --  reporting, which is worth knowing about before writing another.
      Assert (Execute ("return 1;") = Ev.Not_Lowerable,
              "a return with a value was not reported as un-lowerable");

      --  An illegal program is refused instead, without reaching the machine.
      Assert (Execute ("X := 1;") = Ev.Refused,
              "an illegal program was not refused before running");
      Assert (Execute ("X : Integer := ""text"";") = Ev.Refused,
              "a type error was not refused before running");
   end What_Cannot_Be_Lowered_Is_Said_So;

   -------------------------------------
   -- Subprograms_Are_Called_And_Return --
   -------------------------------------

   procedure Subprograms_Are_Called_And_Return
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      --  The argument arrives, and arrives as itself. The second assertion is
      --  the one with teeth: a call that passed nothing, or passed a stale
      --  cell, would satisfy the first for some value and this one for none.
      Assert (Reaches ("procedure P (N : Integer) is begin "
                       & "if N = 7 then X : Integer := 1 / 0; end if; end P; "
                       & "P (7);"),
              "a parameter did not arrive with the value it was called with");
      Assert (not Reaches ("procedure P (N : Integer) is begin "
                           & "if N = 8 then X : Integer := 1 / 0; end if; end P; "
                           & "P (7);"),
              "a parameter arrived with a value nobody passed");

      --  Two parameters, in the order they were written. Subtraction rather
      --  than addition on purpose: a commutative operation cannot tell the
      --  positions apart, so `Add (10, 3)` would pass with them swapped.
      Assert (Reaches ("function Less (A : Integer; B : Integer) return Integer "
                       & "is begin return A - B; end Less; "
                       & "if Less (10, 3) = 7 then X : Integer := 1 / 0; end if;"),
              "two arguments did not arrive in the order they were written");

      --  A function's result reaches the caller.
      Assert (Reaches ("function Twice (N : Integer) return Integer is "
                       & "begin return N * 2; end Twice; "
                       & "if Twice (21) = 42 then X : Integer := 1 / 0; end if;"),
              "a function did not return its value to the caller");

      --  Recursion. Each call needs its own frame; one shared frame gives the
      --  wrong answer rather than crashing, which is why the value is checked
      --  and not merely that it ran.
      Assert (Reaches ("function Fact (N : Integer) return Integer is begin "
                       & "if N <= 1 then return 1; end if; "
                       & "return N * Fact (N - 1); end Fact; "
                       & "if Fact (5) = 120 then X : Integer := 1 / 0; end if;"),
              "a recursive function did not compute with separate frames");

      --  A subprogram's locals live in its own frame. Declared at the
      --  submission's level they would land on top of whatever the submission
      --  declared at the same offset -- here, on X.
      Assert (Reaches ("X : Integer := 5; "
                       & "procedure P is Y : Integer := 99; begin "
                       & "Y := Y + 1; end P; P; "
                       & "if X = 5 then Z : Integer := 1 / 0; end if;"),
              "a subprogram's locals overwrote the caller's frame");

      --  A call from inside another body. The machine's display still points
      --  at the caller's frame afterwards, so reading a parameter *after* the
      --  inner call has returned is what this actually tests.
      Assert (Reaches ("function Five return Integer is begin return 5; end Five; "
                       & "function Sum (N : Integer) return Integer is "
                       & "begin return Five + N; end Sum; "
                       & "if Sum (3) = 8 then X : Integer := 1 / 0; end if;"),
              "a frame was not restored after a call made inside a body");

      --  Every type this language has, as a parameter.
      Assert (Reaches ("function Same (S : String) return String is "
                       & "begin return S; end Same; "
                       & "if Same (""ab"") = ""ab"" then X : Integer := 1 / 0; end if;"),
              "a String did not survive being passed and returned");
      Assert (Reaches ("procedure P (F : Float) is begin "
                       & "if F > 1.0 then X : Integer := 1 / 0; end if; end P; "
                       & "P (1.5);"),
              "a Float parameter did not arrive");
      Assert (Reaches ("procedure P (B : Boolean; C : Character) is begin "
                       & "if B and C = 'z' then X : Integer := 1 / 0; end if; "
                       & "end P; P (True, 'z');"),
              "a Boolean and a Character parameter did not both arrive");

      --  A parameter hides an outer name for as long as the body lasts, and
      --  the outer one is untouched afterwards.
      Assert (Reaches ("N : Integer := 1; "
                       & "procedure P (N : Integer) is begin null; end P; "
                       & "P (2); if N = 1 then X : Integer := 1 / 0; end if;"),
              "a parameter did not hide, or did not stop hiding, an outer name");
   end Subprograms_Are_Called_And_Return;

   -------------------------------------
   -- What_Subprograms_Cannot_Do_Yet --
   -------------------------------------

   procedure What_Subprograms_Cannot_Do_Yet
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      --  Integer'Image with its leading space removed, for building a name.
      function Trim (Value : Integer) return String is
         Text : constant String := Integer'Image (Value);
      begin
         return Text (Text'First + 1 .. Text'Last);
      end Trim;
   begin
      --  Reported before running, because each is a fact about the program
      --  rather than about what happened when it ran.
      Assert (Execute ("procedure P (N : Integer) is begin null; end P; P;")
                = Ev.Refused,
              "a call with too few arguments was not refused");

      --  Nesting runs out where the machine's display does. Both sides are
      --  asserted, because a limit that refused one level too early would look
      --  exactly like a limit that worked.
      declare
         use Ada.Strings.Unbounded;

         --  Depth levels of nesting: the innermost body sits at level Depth
         --  and its frame one deeper, so Depth of 19 is the last that fits in
         --  a display of 20.
         function Nested (Depth : Positive) return String is
            Text : Unbounded_String;
         begin
            for Level in 1 .. Depth loop
               Append (Text, "procedure P" & Trim (Level) & " is ");
            end loop;

            Append (Text, "begin null; end P" & Trim (Depth) & ";");

            for Level in reverse 1 .. Depth - 1 loop
               Append (Text, " begin P" & Trim (Level + 1)
                       & "; end P" & Trim (Level) & ";");
            end loop;

            return To_String (Text) & " P1;";
         end Nested;
      begin
         Assert (Execute (Nested (19)) = Ev.Evaluated,
                 "nesting that fits the machine's display was refused");
         Assert (Execute (Nested (20)) = Ev.Refused,
                 "nesting past the machine's display was not refused");
      end;
      Assert (Execute ("procedure P is begin return 1; end P; P;") = Ev.Refused,
              "a procedure returning a value was not refused");
      Assert (Execute ("function F return Integer is begin return; end F;")
                = Ev.Refused,
              "a function returning no value was not refused");

      --  Runs, and dies saying so. A function whose end is reached has no
      --  value to give back, and handing over whatever the frame held would
      --  be worse than stopping.
      Assert (Execute ("function F return Integer is begin null; end F; "
                       & "X : Integer := F;") = Ev.Raised,
              "a function that never returned did not raise");
   end What_Subprograms_Cannot_Do_Yet;

   -----------------------------------
   -- Parameters_Can_Be_Written_Back --
   -----------------------------------

   procedure Parameters_Can_Be_Written_Back
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      --  The write reaches the caller's variable. Before `out` was lowered
      --  this exact program ran, printed nothing, and left X at zero: the
      --  argument was passed by value and the write went to a cell the return
      --  popped. That is the failure this test exists for.
      Assert (Reaches ("procedure Assign (N : out Integer) is begin N := 5; end Assign; "
                       & "X : Integer := 0; Assign (X); "
                       & "if X = 5 then Y : Integer := 1 / 0; end if;"),
              "a write to an out parameter did not reach the caller");

      --  `in out` reads what was passed and writes back what it computed.
      --  Both halves matter: a mode that only wrote would give 1 here.
      Assert (Reaches ("procedure Bump (N : in out Integer) is begin "
                       & "N := N + 1; end Bump; X : Integer := 41; Bump (X); "
                       & "if X = 42 then Y : Integer := 1 / 0; end if;"),
              "an in out parameter did not both read and write");

      --  Two of them at once, each reaching its own variable. A single shared
      --  address would leave both at the same value and pass a weaker test.
      Assert (Reaches ("procedure Swap (A : in out Integer; B : in out Integer) "
                       & "is T : Integer := A; begin A := B; B := T; end Swap; "
                       & "X : Integer := 1; Y : Integer := 2; Swap (X, Y); "
                       & "if X = 2 and Y = 1 then Z : Integer := 1 / 0; end if;"),
              "two write-back parameters did not reach separate variables");

      --  Passed on. The address of a by-reference parameter is its own value
      --  rather than its slot, so handing one to another subprogram is the
      --  case that catches getting those two the wrong way round.
      Assert (Reaches ("procedure Inner (N : out Integer) is begin N := 9; "
                       & "end Inner; procedure Outer (M : out Integer) is "
                       & "begin Inner (M); end Outer; X : Integer := 0; "
                       & "Outer (X); if X = 9 then Y : Integer := 1 / 0; end if;"),
              "an out parameter passed on did not reach the original variable");

      --  Every type, not just the discrete ones: a String and a Float each
      --  live in a field of their own, and a store that copied the wrong one
      --  would leave the caller's variable holding a tag and no value.
      Assert (Reaches ("procedure Assign (S : out String) is begin S := ""set""; "
                       & "end Assign; T : String := """"; Assign (T); "
                       & "if T = ""set"" then Y : Integer := 1 / 0; end if;"),
              "a String written through an out parameter did not arrive");
      Assert (Reaches ("procedure Assign (F : out Float) is begin F := 2.5; "
                       & "end Assign; G : Float := 0.0; Assign (G); "
                       & "if G > 2.0 then Y : Integer := 1 / 0; end if;"),
              "a Float written through an out parameter did not arrive");

      --  An out parameter nobody writes leaves the caller's variable alone.
      Assert (Reaches ("procedure Assign (N : out Integer) is begin null; end Assign; "
                       & "X : Integer := 7; Assign (X); "
                       & "if X = 7 then Y : Integer := 1 / 0; end if;"),
              "an unwritten out parameter disturbed the caller's variable");
   end Parameters_Can_Be_Written_Back;

   ------------------------------------
   -- What_Parameter_Modes_Refuse --
   ------------------------------------

   procedure What_Parameter_Modes_Refuse
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      --  An `in` parameter is a value the body was given. Assigning to one was
      --  accepted until modes existed, because every parameter counted as
      --  assignable.
      Assert (Execute ("procedure P (N : in Integer) is begin N := 1; end P; "
                       & "X : Integer := 0; P (X);") = Ev.Refused,
              "assigning to an in parameter was not refused");

      --  There is nowhere to write back to. Not a style rule: the argument
      --  would be a value on the stack that the return pops.
      Assert (Execute ("procedure P (N : out Integer) is begin N := 1; end P; "
                       & "P (1 + 2);") = Ev.Refused,
              "an expression passed to an out parameter was not refused");
      Assert (Execute ("procedure P (N : out Integer) is begin N := 1; end P; "
                       & "C : constant Integer := 3; P (C);") = Ev.Refused,
              "a constant passed to an out parameter was not refused");

      --  A submission declares into the same scope the predefined names and
      --  the shell's commands already occupy, so naming a subprogram after one
      --  is a redeclaration rather than a hiding. That follows from this
      --  language having no overloading, and it is worth pinning down because
      --  the names that collide -- `set`, `put_line` -- are ordinary words
      --  somebody will reach for.
      Assert (Execute ("procedure Put_Line (X : Integer) is begin null; "
                       & "end Put_Line;") = Ev.Refused,
              "a subprogram named after a predefined one was not refused");
      Assert (Execute ("procedure Set (X : Integer) is begin null; end Set;")
                = Ev.Refused,
              "a subprogram named after an internal command was not refused");

      --  A parameter, though, is declared in the body's own scope and does
      --  hide an outer name for as long as the body lasts.
      Assert (Reaches ("procedure P (Put_Line : Integer) is begin "
                       & "if Put_Line = 3 then X : Integer := 1 / 0; end if; "
                       & "end P; P (3);"),
              "a parameter did not hide a predefined name inside the body");
   end What_Parameter_Modes_Refuse;

   ------------------------------
   -- Images_Turn_Values_Into_Text --
   ------------------------------

   procedure Images_Turn_Values_Into_Text
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      --  Ada's own spelling, leading space and all. Asserting the exact text
      --  rather than "some text" is the point: an image that dropped the space
      --  for non-negative numbers would be a different language, and one that
      --  used a shorter float form would lose digits the number was carrying.
      Assert (Reaches ("X : Integer := 42; "
                       & "if X'Image = "" 42"" then Y : Integer := 1 / 0; end if;"),
              "an Integer image was not Ada's own");
      Assert (Reaches ("X : Integer := -7; "
                       & "if X'Image = ""-7"" then Y : Integer := 1 / 0; end if;"),
              "a negative Integer image carried a space it should not");
      Assert (Reaches ("B : Boolean := True; "
                       & "if B'Image = ""TRUE"" then Y : Integer := 1 / 0; end if;"),
              "a Boolean image was not upper case, as Ada writes one");
      Assert (Reaches ("C : Character := 'z'; "
                       & "if C'Image = ""'z'"" then Y : Integer := 1 / 0; end if;"),
              "a Character image was not quoted, as Ada writes one");

      --  What the attribute was wanted for. Before it, a computed number could
      --  not be joined to text at all and had to go on a line of its own.
      Assert (Reaches ("X : Integer := 3; "
                       & "if ""x="" & X'Image = ""x= 3"" "
                       & "then Y : Integer := 1 / 0; end if;"),
              "an image did not concatenate with surrounding text");

      --  The prefix is an expression to be evaluated, not just a slot to be
      --  read: a function result and a by-reference parameter both work.
      Assert (Reaches ("function F return Integer is begin return 9; end F; "
                       & "if F'Image = "" 9"" then Y : Integer := 1 / 0; end if;"),
              "the image of a function result was wrong");
      Assert (Reaches ("procedure P (N : out Integer) is begin N := 8; "
                       & "if N'Image = "" 8"" then Y : Integer := 1 / 0; end if; "
                       & "end P; X : Integer := 0; P (X);"),
              "the image of a write-back parameter did not read through it");
   end Images_Turn_Values_Into_Text;

   --------------------------------
   -- What_Attributes_Refuse --
   --------------------------------

   procedure What_Attributes_Refuse
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      --  Ada 2022 does define `S'Image` for a String, and what it yields is
      --  the text in quotes with non-graphic characters bracketed -- not the
      --  text itself. Returning the text would be the plausible wrong answer,
      --  and a program relying on it would mean something else under a real
      --  compiler. HAC refuses this too.
      Assert (Execute ("S : String := ""hi""; put_line (S'Image);") = Ev.Refused,
              "'Image of a String was not refused");

      --  An attribute the type does not have. Reported as an attribute rather
      --  than as an undeclared name, which used to send the reader looking for
      --  a declaration they never wrote.
      Assert (Execute ("X : Integer := 5; put_line (X'Alignment);")
                = Ev.Refused,
              "an unsupported attribute was not refused");

      --  Neither prefix is a *name*, so both are illegal Ada and rejected as
      --  syntax rather than quietly given a meaning of their own.
      Assert (Execute ("put_line (42'Image);") = Ev.Refused,
              "an attribute on a literal was not refused");
      Assert (Execute ("X : Integer := 5; put_line ((X * 2)'Image);") = Ev.Refused,
              "an attribute on a parenthesized expression was not refused");
   end What_Attributes_Refuse;

   ----------------------------------
   -- Interpolation_Builds_Strings --
   ----------------------------------

   procedure Interpolation_Builds_Strings
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert (Reaches ("W : String := ""world""; "
                       & "if f""hello {W}!"" = ""hello world!"" "
                       & "then Y : Integer := 1 / 0; end if;"),
              "an interpolated string did not build the text it names");

      --  Two expressions, and adjacent ones with no text between them. The
      --  second is where a rewrite that assumed a literal piece between every
      --  pair would put one that is not there.
      Assert (Reaches ("A : String := ""x""; B : String := ""y""; "
                       & "if f""{A} and {B}"" = ""x and y"" "
                       & "then Y : Integer := 1 / 0; end if;"),
              "two interpolated expressions did not both arrive");
      Assert (Reaches ("A : String := ""x""; B : String := ""y""; "
                       & "if f""{A}{B}"" = ""xy"" "
                       & "then Y : Integer := 1 / 0; end if;"),
              "adjacent interpolated expressions did not join");

      --  The degenerate shapes. Each drops to a plain literal, and each used
      --  to be the kind of thing a rewrite gets wrong by emitting an empty
      --  piece and concatenating it.
      Assert (Reaches ("if f""plain"" = ""plain"" "
                       & "then Y : Integer := 1 / 0; end if;"),
              "an interpolated string with no expressions was not itself");
      Assert (Reaches ("if f"""" = """" then Y : Integer := 1 / 0; end if;"),
              "an empty interpolated string was not the empty string");
      Assert (Reaches ("A : String := ""x""; "
                       & "if f""{A}"" = ""x"" then Y : Integer := 1 / 0; end if;"),
              "an interpolated string of one expression was not that expression");

      --  A number goes in through 'Image, which is the pair these two features
      --  make. Neither is much use without the other.
      Assert (Reaches ("N : Integer := 5; "
                       & "if f""n is{N'Image}"" = ""n is 5"" "
                       & "then Y : Integer := 1 / 0; end if;"),
              "an image inside an interpolated string did not render");

      --  The expressions are ordinary expressions: a call works, and so does
      --  another interpolated string inside one, which is what the lexer's
      --  depth counter is for.
      Assert (Reaches ("function N return String is begin return ""ada""; "
                       & "end N; if f""hi {N}"" = ""hi ada"" "
                       & "then Y : Integer := 1 / 0; end if;"),
              "a call inside an interpolated string did not evaluate");
      Assert (Reaches ("X : String := ""in""; "
                       & "if f""a{f""b{X}b""}c"" = ""abinbc"" "
                       & "then Y : Integer := 1 / 0; end if;"),
              "a nested interpolated string did not nest");

      --  Braces and backslashes, which have to be writable.
      Assert (Reaches ("A : String := ""x""; "
                       & "if f""\{{A}\}"" = ""{x}"" "
                       & "then Y : Integer := 1 / 0; end if;"),
              "escaped braces did not become braces");
      Assert (Reaches ("if f""a\\b"" = ""a\b"" "
                       & "then Y : Integer := 1 / 0; end if;"),
              "an escaped backslash did not become one backslash");

      --  The escapes whose result can be written as an ordinary literal, so
      --  the comparison is against something independent of the escape being
      --  tested. What every escape produces is asserted byte for byte in the
      --  lexer cases, which is the level the decoding happens at.
      Assert (Reaches ("if f""a\{b"" = ""a{b"" "
                       & "then Y : Integer := 1 / 0; end if;"),
              "an escaped opening brace was not a brace");
      Assert (Reaches ("if f""say \""hi\"""" = ""say """"hi"""""" "
                       & "then Y : Integer := 1 / 0; end if;"),
              "an escaped quotation mark was not one");
   end Interpolation_Builds_Strings;

   ----------------------------------
   -- What_Interpolation_Refuses --
   ----------------------------------

   procedure What_Interpolation_Refuses
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      --  Ada 2022 expects a String in the braces. A number needs 'Image, and
      --  saying so is the same rule -- and the same message -- as `"n" & N`,
      --  because that is what this rewrites to.
      Assert (Execute ("N : Integer := 5; put_line (f""n is {N}"");")
                = Ev.Refused,
              "an Integer interpolated without 'Image was not refused");

      --  An escape Ada 2022 does not define, named rather than passed through.
      --  `\e` and `\x41` are escapes in other languages and not in this one;
      --  GNAT rejects both, which is where this list came from.
      Assert (Execute ("put_line (f""a \e b"");") = Ev.Refused,
              "an escape Ada does not define was not refused");
      Assert (Execute ("put_line (f""a \x41 b"");") = Ev.Refused,
              "a hexadecimal escape was not refused");

      --  A doubled quote, which Ada 2022 forbids inside an interpolated
      --  literal outright: the escape is what puts a quote in one. Accepting
      --  it would take a program a real compiler rejects.
      Assert (Execute ("put_line (f""a""""b"");") = Ev.Refused,
              "a doubled quote inside an interpolated string was not refused");

      --  A brace that closes nothing would read as the end of an expression
      --  that never began.
      Assert (Execute ("put_line (f""a } b"");") = Ev.Refused,
              "an unescaped closing brace was not refused");

      --  Unterminated, which ends at the line as an ordinary literal does.
      Assert (Execute ("put_line (f""a {") = Ev.Refused,
              "an unterminated interpolated string was not refused");
   end What_Interpolation_Refuses;

   -----------------------------------
   -- For_Loops_Follow_Adas_Range --
   -----------------------------------

   procedure For_Loops_Follow_Adas_Range
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      --  The bound is evaluated once, before the loop. The body raises it
      --  faster than the parameter climbs, so re-evaluating each turn -- which
      --  is how this used to be written -- never ends.
      --
      --  Hence the `exit when`, which is not decoration. Without it this test
      --  would *hang* the suite under the old lowering rather than report,
      --  which has happened here before: a test whose subject becomes an
      --  infinite loop stops the run instead of failing it. With the bound in
      --  place the count tells the two behaviours apart -- three turns under
      --  Ada's rule, eleven under the old one.
      Assert (Reaches ("N : Integer := 3; Runs : Integer := 0; "
                       & "for I in 1 .. N loop Runs := Runs + 1; N := N + 1; "
                       & "exit when Runs > 10; end loop; "
                       & "if Runs = 3 then Y : Integer := 1 / 0; end if;"),
              "a for loop did not evaluate its upper bound exactly once");

      --  A bound with a side effect says out loud how often it was evaluated.
      Assert (Reaches ("Calls : Integer := 0; "
                       & "function Bound return Integer is begin "
                       & "Calls := Calls + 1; return 2; end Bound; "
                       & "for I in 1 .. Bound loop null; end loop; "
                       & "if Calls = 1 then Y : Integer := 1 / 0; end if;"),
              "a bound with a side effect was not evaluated exactly once");

      --  A null range runs the body no times, which needs the first test to
      --  come before the body rather than after it.
      Assert (Reaches ("Runs : Integer := 0; "
                       & "for I in 3 .. 1 loop Runs := Runs + 1; end loop; "
                       & "if Runs = 0 then Y : Integer := 1 / 0; end if;"),
              "a null range ran its body");

      --  One turn, and the parameter is the bound on it.
      Assert (Reaches ("Runs : Integer := 0; "
                       & "for I in 2 .. 2 loop Runs := Runs + I; end loop; "
                       & "if Runs = 2 then Y : Integer := 1 / 0; end if;"),
              "a range of one value did not run exactly once");

      --  Nested loops each need a bound of their own; one shared slot would
      --  leave the outer loop testing against the inner one's.
      Assert (Reaches ("Runs : Integer := 0; "
                       & "for I in 1 .. 2 loop for J in 1 .. 3 loop "
                       & "Runs := Runs + 1; end loop; end loop; "
                       & "if Runs = 6 then Y : Integer := 1 / 0; end if;"),
              "nested for loops shared an upper bound");

      --  A loop that runs to the largest value the type holds. Incrementing
      --  past the bound and testing afterwards -- which is how this was
      --  written -- raises Constraint_Error here rather than finishing.
      Assert (Reaches ("Runs : Integer := 0; "
                       & "for I in 9223372036854775806 .. 9223372036854775807 "
                       & "loop Runs := Runs + 1; end loop; "
                       & "if Runs = 2 then Y : Integer := 1 / 0; end if;"),
              "a loop reaching the largest integer did not finish");

      --  Each activation gets its own bound, so a loop inside a subprogram
      --  called twice runs the same number of times both times.
      Assert (Reaches ("Runs : Integer := 0; "
                       & "procedure P is begin for I in 1 .. 2 loop "
                       & "Runs := Runs + 1; end loop; end P; P; P; "
                       & "if Runs = 4 then Y : Integer := 1 / 0; end if;"),
              "a for loop in a body did not repeat identically");
   end For_Loops_Follow_Adas_Range;

   ---------------------------------
   -- Nested_Subprograms_See_Out --
   ---------------------------------

   procedure Nested_Subprograms_See_Out
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      --  The point of nesting: the inner body reads the frame of the body it
      --  was declared in. A lowering that addressed everything at one level
      --  would read whatever the submission had at that offset.
      Assert (Reaches ("procedure O is X : Integer := 7; "
                       & "procedure I is begin "
                       & "if X = 7 then Y : Integer := 1 / 0; end if; end I; "
                       & "begin I; end O; O;"),
              "an inner body did not see the enclosing body's local");
      Assert (Reaches ("procedure O (N : Integer) is procedure I is begin "
                       & "if N = 5 then Y : Integer := 1 / 0; end if; end I; "
                       & "begin I; end O; O (5);"),
              "an inner body did not see the enclosing body's parameter");

      --  And writes to it, which has to reach the same cell the outer body
      --  goes on reading.
      Assert (Reaches ("procedure O is X : Integer := 1; "
                       & "procedure I is begin X := 9; end I; "
                       & "begin I; if X = 9 then Y : Integer := 1 / 0; end if; "
                       & "end O; O;"),
              "a write from an inner body did not reach the outer frame");

      --  Two levels out, which is where a static link that only ever went one
      --  step would stop working.
      Assert (Reaches ("procedure A is X : Integer := 1; "
                       & "procedure B is Y : Integer := 2; "
                       & "procedure C is begin "
                       & "if X + Y = 3 then Z : Integer := 1 / 0; end if; "
                       & "end C; begin C; end B; begin B; end A; A;"),
              "a body three levels deep did not reach both frames above it");

      --  Each call has its own frame, so the inner body sees the one it was
      --  called from rather than the first or the last.
      Assert (Reaches ("Seen : Integer := 0; "
                       & "procedure O (N : Integer) is X : Integer := N * 10; "
                       & "procedure I is begin Seen := Seen + X; end I; "
                       & "begin I; end O; O (1); O (2); "
                       & "if Seen = 30 then Y : Integer := 1 / 0; end if;"),
              "an inner body did not see the frame of the call it came from");

      --  An inner body recursing, and an inner body calling the one that
      --  encloses it -- both need the display put back after the call.
      Assert (Reaches ("procedure O is X : Integer := 0; "
                       & "procedure I (N : Integer) is begin "
                       & "if N > 0 then X := X + N; I (N - 1); end if; end I; "
                       & "begin I (3); "
                       & "if X = 6 then Y : Integer := 1 / 0; end if; end O; O;"),
              "an inner body could not recurse");

      --  A name declared inside two different bodies is two subprograms. The
      --  lowering matches a call to the declaration the scope chain resolved
      --  to, not to the spelling, which is what keeps these apart.
      Assert (Reaches ("Seen : Integer := 0; "
                       & "procedure P is procedure Step is begin "
                       & "Seen := Seen + 1; end Step; begin Step; end P; "
                       & "procedure Q is procedure Step is begin "
                       & "Seen := Seen + 10; end Step; begin Step; end Q; "
                       & "P; Q; if Seen = 11 then Y : Integer := 1 / 0; end if;"),
              "two inner subprograms of the same name were not kept apart");

      --  A nested function, whose result has to come back through a frame one
      --  level deeper than the caller's.
      Assert (Reaches ("procedure O is X : Integer := 3; "
                       & "function I return Integer is begin return X * 2; "
                       & "end I; begin "
                       & "if I = 6 then Y : Integer := 1 / 0; end if; end O; O;"),
              "a nested function did not return through its own frame");
   end Nested_Subprograms_See_Out;

   ---------------------------------------
   -- Overloads_Are_Chosen_By_Arguments --
   ---------------------------------------

   procedure Overloads_Are_Chosen_By_Arguments
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      --  One name, two subprograms, and the argument decides. Both directions
      --  are asserted: picking by type is only demonstrated if the *other*
      --  candidate would have given a different answer.
      Assert (Reaches ("Seen : Integer := 0; "
                       & "procedure P (A : Integer) is begin Seen := 1; end P; "
                       & "procedure P (A : String) is begin Seen := 2; end P; "
                       & "P (7); if Seen = 1 then Y : Integer := 1 / 0; end if;"),
              "an overload was not chosen by its argument's type");
      Assert (Reaches ("Seen : Integer := 0; "
                       & "procedure P (A : Integer) is begin Seen := 1; end P; "
                       & "procedure P (A : String) is begin Seen := 2; end P; "
                       & "P (""s""); if Seen = 2 then Y : Integer := 1 / 0; end if;"),
              "the other overload was not chosen by its argument's type");

      --  By how many arguments there are, not only by their types.
      Assert (Reaches ("Seen : Integer := 0; "
                       & "procedure P (A : Integer) is begin Seen := 1; end P; "
                       & "procedure P (A : Integer; B : Integer) is begin "
                       & "Seen := 2; end P; P (1, 2); "
                       & "if Seen = 2 then Y : Integer := 1 / 0; end if;"),
              "an overload was not chosen by its argument count");

      --  Functions overload too, and the chosen one's result type is what the
      --  call has -- so this only compiles if the String version was taken.
      Assert (Reaches ("function F (N : Integer) return Integer is begin "
                       & "return N; end F; function F (S : String) return String "
                       & "is begin return S; end F; "
                       & "if F (""ab"") = ""ab"" then Y : Integer := 1 / 0; end if;"),
              "an overloaded function did not yield the chosen result type");

      --  A name written without arguments means whichever takes none. The
      --  plain lookup answers with the last declared, which is the other one.
      Assert (Reaches ("function G return Integer is begin return 1; end G; "
                       & "function G (N : Integer) return Integer is begin "
                       & "return N; end G; "
                       & "if G = 1 then Y : Integer := 1 / 0; end if;"),
              "a bare name did not resolve to the subprogram taking nothing");

      --  An inner declaration of a different profile does not hide the outer
      --  one; both are candidates inside the inner body.
      Assert (Reaches ("Seen : Integer := 0; "
                       & "procedure P (A : Integer) is begin Seen := Seen + 1; "
                       & "end P; procedure Q is "
                       & "procedure P (A : String) is begin Seen := Seen + 10; "
                       & "end P; begin P (1); P (""s""); end Q; Q; "
                       & "if Seen = 11 then Y : Integer := 1 / 0; end if;"),
              "an inner overload hid an outer one of a different profile");
   end Overloads_Are_Chosen_By_Arguments;

   -----------------------------
   -- What_Overloading_Refuses --
   -----------------------------

   procedure What_Overloading_Refuses
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      --  Same name, same parameter types: no call could tell them apart, so
      --  this is a redeclaration however it is spelled.
      Assert (Execute ("procedure P (A : Integer) is begin null; end P; "
                       & "procedure P (B : Integer) is begin null; end P;")
                = Ev.Refused,
              "two subprograms with the same profile were not refused");

      --  Two differing only in result type are two subprograms now, but a
      --  call that nothing settles is still ambiguous -- which is Ada's answer
      --  as well.
      Assert (Execute ("function F return Integer is begin return 1; end F; "
                       & "function F return String is begin return ""s""; "
                       & "end F; put_line (F);") = Ev.Refused,
              "an unsettled result-type overload was not reported as ambiguous");

      --  Arguments that fit none of the declarations.
      Assert (Execute ("procedure P (A : Integer) is begin null; end P; "
                       & "procedure P (A : String) is begin null; end P; "
                       & "P (1.5);") = Ev.Refused,
              "a call fitting no overload was not refused");

      --  The shell's own names stay the shell's. Ada would overload them; here
      --  they accept any type, so a user's version would fit every call the
      --  original does and every one would be ambiguous.
      Assert (Execute ("procedure Put_Line (X : Integer) is begin null; "
                       & "end Put_Line;") = Ev.Refused,
              "a subprogram named after a predefined one was not refused");
      Assert (Execute ("procedure Set (X : Integer) is begin null; end Set;")
                = Ev.Refused,
              "a subprogram named after an internal command was not refused");
   end What_Overloading_Refuses;

   -------------------------------------
   -- Specifications_Precede_Bodies --
   -------------------------------------

   procedure Specifications_Precede_Bodies
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      --  What a specification is for. Neither body can be written first: each
      --  calls the other, and without a name that exists before its code does
      --  one of the two calls is to something undeclared.
      Assert (Reaches ("Seen : Integer := 0; "
                       & "procedure Odd (N : Integer); "
                       & "procedure Even (N : Integer) is begin "
                       & "if N = 0 then Seen := 1; else Odd (N - 1); end if; "
                       & "end Even; "
                       & "procedure Odd (N : Integer) is begin "
                       & "if N = 0 then Seen := 2; else Even (N - 1); end if; "
                       & "end Odd; Even (7); "
                       & "if Seen = 2 then Y : Integer := 1 / 0; end if;"),
              "two subprograms could not call each other through a spec");

      --  A call written between the specification and the body reaches the
      --  body, which is the case that proves the lowering found it: the call
      --  was emitted before the body had an address.
      Assert (Reaches ("Seen : Integer := 0; "
                       & "procedure P (N : Integer); P (5); "
                       & "procedure P (N : Integer) is begin Seen := N; end P; "
                       & "if Seen = 5 then Y : Integer := 1 / 0; end if;"),
              "a call written before the body did not reach it");

      --  Functions too.
      Assert (Reaches ("function F return Integer; "
                       & "function F return Integer is begin return 3; end F; "
                       & "if F = 3 then Y : Integer := 1 / 0; end if;"),
              "a function specification was not completed by its body");

      --  Inside a body, where the specification and its body share the
      --  declarative part they were written in.
      Assert (Reaches ("Seen : Integer := 0; "
                       & "procedure Outer is procedure Inner (N : Integer); "
                       & "procedure Inner (N : Integer) is begin Seen := N; "
                       & "end Inner; begin Inner (9); end Outer; Outer; "
                       & "if Seen = 9 then Y : Integer := 1 / 0; end if;"),
              "a nested specification was not completed by its body");
   end Specifications_Precede_Bodies;

   ------------------------------------
   -- What_Specifications_Refuse --
   ------------------------------------

   procedure What_Specifications_Refuse
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      --  A name with no code behind it. Calls to it would jump nowhere, and
      --  the program is refused rather than run up to the point it does.
      Assert (Execute ("procedure P (N : Integer); put_line (""after"");")
                = Ev.Refused,
              "a specification with no body was not refused");

      --  A body whose profile differs is a second subprogram, not this one's
      --  body, so the specification is still waiting.
      Assert (Execute ("procedure P (N : Integer); "
                       & "procedure P (S : String) is begin null; end P;")
                = Ev.Refused,
              "a body of a different profile was taken as the spec's");

      --  Inside a body, reported as that body closes rather than at the end of
      --  the submission.
      Assert (Execute ("procedure Outer is procedure Inner (N : Integer); "
                       & "begin null; end Outer; Outer;") = Ev.Refused,
              "a nested specification with no body was not refused");

      --  Two of the same profile: the second is a redeclaration whether or not
      --  either has a body.
      Assert (Execute ("procedure P (N : Integer); procedure P (N : Integer);")
                = Ev.Refused,
              "two identical specifications were not refused");
      Assert (Execute ("procedure P (N : Integer) is begin null; end P; "
                       & "procedure P (N : Integer);") = Ev.Refused,
              "a specification after its body was not refused");
   end What_Specifications_Refuse;

   ------------------------------------
   -- Commands_Take_Several_Arguments --
   ------------------------------------

   procedure Commands_Take_Several_Arguments
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      function Execute_With_Sink (Text : String) return Ev.Outcome is
         Buffer : Src.Buffer;
         Stream : Adash.Language.Tokens.Token_Stream;
         Tree   : S.Tree;
         Result : Sem.Analysis;
         Report : D.List;
         Error  : Adash.Errors.Error_Info;
         Origin : constant Src.Origin :=
           Src.Make_Origin (Src.Origin_Text, "<run>");
         Ran    : Ev.Outcome;
      begin
         Assert (Src.Load (Buffer, Origin, Text, Error),
                 "the source did not load");
         Adash.Language.Lexer.Scan (Buffer, Stream, Report);
         Adash.Language.Parser.Parse (Stream, Origin, Tree, Report);
         Sem.Analyse (Tree, Origin, Result, Report);
         Ev.Run (Tree, Result, Origin, Ran, Report,
                 On_Command => Probe'Access);
         return Ran;
      end Execute_With_Sink;
   begin
      --  A command call used to carry exactly one argument: the stub was built
      --  for one slot, and anything more was refused. Job control is what made
      --  that a real limit -- `start ("sleep", "1")` is a program and its
      --  argument, and neither half is optional.
      Probe.Halt_On_Call := False;

      --  Two arguments arrive, in order. The separator is the probe's, so a
      --  call that delivered them the other way round reads differently.
      Probe.Calls := 0;
      declare
         Ran : constant Ev.Outcome :=
           Execute_With_Sink ("start (""one"", ""two"");");
      begin
         Assert (Ran = Ev.Evaluated, "a two-argument command call did not run");
         Assert (Probe.Calls = 1, "a two-argument command call did not arrive");
         Assert (Ada.Strings.Unbounded.To_String (Probe.Argument) = "one|two",
                 "two arguments did not arrive in the order they were written");
      end;

      --  Five, which is what the stub is built for. A call answered by the
      --  shell spends the first slot on the name of what is being asked for; a
      --  command spends none, so a command gets all five.
      Probe.Calls := 0;
      declare
         Ran : constant Ev.Outcome :=
           Execute_With_Sink ("start (""a"", ""b"", ""c"", ""d"", ""e"");");
      begin
         Assert (Ran = Ev.Evaluated, "a five-argument command call did not run");
         Assert (Ada.Strings.Unbounded.To_String (Probe.Argument) = "a|b|c|d|e",
                 "five arguments did not all arrive");
      end;

      --  One more than the record holds. Refused rather than truncated, which
      --  would run a different command than the one that was written.
      Assert (Execute_With_Sink
                ("start (""a"", ""b"", ""c"", ""d"", ""e"", ""f"");")
                = Ev.Not_Lowerable,
              "a call with more arguments than the stub holds was not refused");

      --  And none at all still works, which is the shape every other command
      --  in this shell uses.
      Probe.Calls := 0;
      declare
         Ran : constant Ev.Outcome := Execute_With_Sink ("pwd;");
      begin
         Assert (Ran = Ev.Evaluated, "a command with no arguments did not run");
         Assert (Ada.Strings.Unbounded.To_String (Probe.Argument) = "",
                 "a command with no arguments was given one");
      end;
   end Commands_Take_Several_Arguments;

   --------------------------------------
   -- Result_Type_Settles_An_Overload --
   --------------------------------------

   procedure Result_Type_Settles_An_Overload
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      --  Two subprograms of one name differing only in what they return. The
      --  arguments cannot tell them apart -- there are none -- so every case
      --  below is settled by what the context requires and by nothing else.
      Pair : constant String :=
        "function F return Integer is begin return 1; end F; "
        & "function F return String is begin return ""s""; end F; ";
   begin
      --  A declaration states the type it wants.
      Assert (Reaches (Pair & "X : Integer := F; "
                       & "if X = 1 then Y : Integer := 1 / 0; end if;"),
              "a declared type did not settle a result-type overload");
      Assert (Reaches (Pair & "S : String := F; "
                       & "if S = ""s"" then Y : Integer := 1 / 0; end if;"),
              "the other declared type did not settle the same overload");

      --  So does an assignment's target.
      Assert (Reaches (Pair & "X : Integer := 0; X := F; "
                       & "if X = 1 then Y : Integer := 1 / 0; end if;"),
              "an assignment target did not settle a result-type overload");

      --  So does the result type of the function being returned from.
      Assert (Reaches (Pair
                       & "function G return String is begin return F; end G; "
                       & "if G = ""s"" then Y : Integer := 1 / 0; end if;"),
              "a return statement did not settle a result-type overload");

      --  Parentheses group and change nothing, so the requirement passes
      --  through them.
      Assert (Reaches (Pair & "X : Integer := (F); "
                       & "if X = 1 then Y : Integer := 1 / 0; end if;"),
              "parentheses lost the context's requirement");

      --  An operator whose result is its operands' type passes it down too.
      Assert (Reaches (Pair & "S : String := F & ""!""; "
                       & "if S = ""s!"" then Y : Integer := 1 / 0; end if;"),
              "concatenation did not pass the requirement to its operand");
      Assert (Reaches (Pair & "X : Integer := F + 1; "
                       & "if X = 2 then Y : Integer := 1 / 0; end if;"),
              "addition did not pass the requirement to its operand");

      --  And a parameter, when every candidate agrees what that position
      --  takes -- here there is only one subprogram to call.
      Assert (Reaches (Pair
                       & "procedure P (N : Integer) is begin "
                       & "if N = 1 then Y : Integer := 1 / 0; end if; end P; "
                       & "P (F);"),
              "a parameter type did not settle a result-type overload");

      --  A condition requires Boolean, which is a requirement like any other.
      Assert (Reaches ("function B return Boolean is begin return True; "
                       & "end B; function B return Integer is begin return 0; "
                       & "end B; if B then X : Integer := 1 / 0; end if;"),
              "a condition did not settle a result-type overload");
   end Result_Type_Settles_An_Overload;

   --------------------------------------
   -- What_Result_Overloading_Refuses --
   --------------------------------------

   procedure What_Result_Overloading_Refuses
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Pair : constant String :=
        "function F return Integer is begin return 1; end F; "
        & "function F return String is begin return ""s""; end F; ";
   begin
      --  Nothing requires anything of it. `put_line` takes any type, so both
      --  fit and the call is ambiguous -- which is what Ada says too. Silently
      --  taking whichever was declared last is what this used to do.
      Assert (Execute (Pair & "put_line (F);") = Ev.Refused,
              "a call with no requirement on it was not ambiguous");

      --  A comparison's operands have each other's type, so one settles the
      --  other -- but only when exactly one of them is open. Two ambiguous
      --  operands say nothing about each other and neither does the operator.
      Assert (Execute (Pair & "if F = F then null; end if;") = Ev.Refused,
              "a comparison of two ambiguous calls was not refused");
      --  And the other way round: a comparison against something with a type
      --  of its own settles the call, on either side and through parentheses.
      Assert (Reaches (Pair & "if F = 1 then X : Integer := 1 / 0; end if;"),
              "a comparison did not settle an overloaded left operand");
      Assert (Reaches (Pair & "if 1 = F then X : Integer := 1 / 0; end if;"),
              "a comparison did not settle an overloaded right operand");
      Assert (Reaches (Pair
                       & "if F = ""s"" then X : Integer := 1 / 0; end if;"),
              "a comparison settled the wrong overload for a String");
      Assert (Reaches (Pair & "N : Integer := 1; "
                       & "if F < 2 then X : Integer := 1 / 0; end if;"),
              "an ordering operator did not settle an overloaded operand");

      --  Identical in every part, including the result: no call could ever
      --  tell these apart, so the second is still a redeclaration.
      Assert (Execute ("function F return Integer is begin return 1; end F; "
                       & "function F return Integer is begin return 2; end F;")
                = Ev.Refused,
              "two functions identical in every part were not refused");
   end What_Result_Overloading_Refuses;

   ----------
   -- Name --
   ----------

   overriding function Name (T : Case_Type) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Adash.Language.Evaluation");
   end Name;

   --------------------
   -- Register_Tests --
   --------------------

   overriding procedure Register_Tests (T : in out Case_Type) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, A_Program_Runs_On_The_Virtual_Machine'Access,
         "evaluation : a program runs on the virtual machine");
      Register_Routine
        (T, Arithmetic_Is_Actually_Computed'Access,
         "evaluation : arithmetic is actually computed, with Ada's precedence");
      Register_Routine
        (T, Variables_Keep_Their_Values'Access,
         "evaluation : variables keep their values and do not share slots");
      Register_Routine
        (T, Conditionals_Take_The_Right_Branch'Access,
         "evaluation : conditionals take the right branch, both ways round");
      Register_Routine
        (T, Loops_Run_The_Right_Number_Of_Times'Access,
         "evaluation : loops run the right number of times");
      Register_Routine
        (T, Short_Circuits_Do_Not_Evaluate_The_Right_Side'Access,
         "evaluation : short circuits do not evaluate the right side");
      Register_Routine
        (T, What_Cannot_Be_Lowered_Is_Said_So'Access,
         "evaluation : what cannot be lowered is reported as such, not refused");
      Register_Routine
        (T, Strings_Are_Values'Access,
         "a String is a value: held, copied, assigned and compared");
      Register_Routine
        (T, Strings_Compare_As_Text'Access,
         "Strings compare as text, in both directions");
      Register_Routine
        (T, What_Strings_Cannot_Do_Yet'Access,
         "an uninitialized String is refused");
      Register_Routine
        (T, Commands_Reach_This_Process'Access,
         "a command call in a lowered program runs here, with its arguments");
      Register_Routine
        (T, Strings_Concatenate'Access,
         "strings concatenate, including with the empty string");
      Register_Routine
        (T, Numeric_Operations'Access,
         "abs, negation and Float arithmetic use the right instruction");
      Register_Routine
        (T, Loops_And_Early_Exit'Access,
         "bare loops, exit in every loop kind, and return");
      Register_Routine
        (T, A_Running_Program_Can_Be_Stopped'Access,
         "a program that never ends can be stopped from outside");
      Register_Routine
        (T, Subprograms_Are_Called_And_Return'Access,
         "declared subprograms are called, take arguments and return values");
      Register_Routine
        (T, What_Subprograms_Cannot_Do_Yet'Access,
         "what a declared subprogram cannot do yet is reported, not run");
      Register_Routine
        (T, Parameters_Can_Be_Written_Back'Access,
         "out and in out parameters reach the caller's own variable");
      Register_Routine
        (T, What_Parameter_Modes_Refuse'Access,
         "an in parameter cannot be assigned, and out needs a variable");
      Register_Routine
        (T, Images_Turn_Values_Into_Text'Access,
         "'Image gives Ada's own text, and joins to surrounding text");
      Register_Routine
        (T, What_Attributes_Refuse'Access,
         "'Image of a String, and every other attribute, is refused");
      Register_Routine
        (T, Interpolation_Builds_Strings'Access,
         "an interpolated string builds the text it names, nesting included");
      Register_Routine
        (T, What_Interpolation_Refuses'Access,
         "interpolation refuses a non-String, an unknown escape, a stray brace");
      Register_Routine
        (T, For_Loops_Follow_Adas_Range'Access,
         "a for loop evaluates its bound once and stops at the largest value");
      Register_Routine
        (T, Nested_Subprograms_See_Out'Access,
         "a nested subprogram reads and writes the frames enclosing it");
      Register_Routine
        (T, Overloads_Are_Chosen_By_Arguments'Access,
         "one name can denote several subprograms, chosen by the arguments");
      Register_Routine
        (T, What_Overloading_Refuses'Access,
         "identical profiles, result-only overloads and shell names are refused");
      Register_Routine
        (T, Commands_Take_Several_Arguments'Access,
         "a command call carries more than one argument, in order");
      Register_Routine
        (T, Result_Type_Settles_An_Overload'Access,
         "what the context requires settles an overload on result type");
      Register_Routine
        (T, What_Result_Overloading_Refuses'Access,
         "a result-type overload nothing settles is ambiguous, not guessed");
      Register_Routine
        (T, Specifications_Precede_Bodies'Access,
         "a specification names a subprogram before its body exists");
      Register_Routine
        (T, What_Specifications_Refuse'Access,
         "a specification without a body, or duplicated, is refused");
   end Register_Tests;

end Adash_Tests.Evaluation_Cases;
