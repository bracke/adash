with Ada.Strings.Unbounded;

with AUnit.Assertions;

with Adash.Machine;

package body Adash_Tests.Machine_Cases is

   use AUnit.Assertions;
   use Ada.Strings.Unbounded;

   package M renames Adash.Machine;

   use type M.Cell_Kind;
   use type M.Outcome;
   use type M.Whole_Number;

   --  A shell that records what it was asked and answers with what it was told
   --  to answer.
   type Recorder is limited new M.Host with record
      Calls  : Natural := 0;
      Asked  : Unbounded_String;
      Given  : Unbounded_String;
      Reply  : Unbounded_String;
      Stop   : Boolean := False;
   end record;

   overriding procedure Call
     (Item      : in out Recorder;
      Name      : String;
      Arguments : M.Cell_Array;
      Count     : Natural;
      Result    : out M.Answer);

   overriding function Stop_Requested (Item : in out Recorder) return Boolean;

   overriding function Stop_Requested (Item : in out Recorder) return Boolean is
      pragma Unreferenced (Item);
   begin
      return False;
   end Stop_Requested;

   overriding procedure Call
     (Item      : in out Recorder;
      Name      : String;
      Arguments : M.Cell_Array;
      Count     : Natural;
      Result    : out M.Answer) is
   begin
      Item.Calls := Item.Calls + 1;
      Item.Asked := To_Unbounded_String (Name);
      Item.Given := Null_Unbounded_String;

      for Index in 1 .. Count loop
         if Index > 1 then
            Append (Item.Given, "|");
         end if;

         case Arguments (Index).Kind is
            when M.Cell_Text =>
               Append (Item.Given, Arguments (Index).Text);
            when M.Cell_Whole =>
               Append (Item.Given, M.Whole_Number'Image (Arguments (Index).Whole));
            when others =>
               Append (Item.Given, "?");
         end case;
      end loop;

      Result := (Value => (Kind => M.Cell_Text, Text => Item.Reply),
                 Halt  => Item.Stop);
   end Call;

   procedure Arithmetic_And_Comparison
     (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Frames_Carry_Their_Own_Variables
     (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure A_Call_Finds_The_Frame_It_Was_Declared_In
     (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Text_Is_Taken_Apart_And_Bounds_Raise
     (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Text_Is_Written_Into_And_Lengths_Must_Match
     (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure The_Shell_Is_Called_And_Can_Stop_It
     (Test : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------
   -- Arithmetic_And_Comparison --
   ---------------------------------

   procedure Arithmetic_And_Comparison
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Program : M.Program;
      Answer  : M.Result;
   begin
      --  (6 * 7) - 2, into slot 0.
      Program.Set_Frame (1);
      Program.Add (M.Address, 0, M.Whole_Number (0));
      Program.Add (M.Push_Whole, 0, M.Whole_Number (6));
      Program.Add (M.Push_Whole, 0, M.Whole_Number (7));
      Program.Add (M.Multiply_Whole);
      Program.Add (M.Push_Whole, 0, M.Whole_Number (2));
      Program.Add (M.Subtract_Whole);
      Program.Add (M.Store);
      Program.Add (M.Halt);

      Program.Run (null, Answer);

      Assert (Answer.What = M.Ran, "the program did not run");
      Assert (Program.Slot_Value (0).Kind = M.Cell_Whole
                and then Program.Slot_Value (0).Whole = 40,
              "the arithmetic came out wrong");

      --  Division by zero is Ada's own failure, and is raised rather than
      --  answered: a machine that returned a number here would be inventing
      --  one.
      Program.Reset;
      Program.Set_Frame (0);
      Program.Add (M.Push_Whole, 0, M.Whole_Number (1));
      Program.Add (M.Push_Whole, 0, M.Whole_Number (0));
      Program.Add (M.Divide_Whole);
      Program.Add (M.Halt);

      Program.Run (null, Answer);

      Assert (Answer.What = M.Raised, "dividing by zero did not raise");
      Assert (To_String (Answer.Raised_Name) = "Constraint_Error",
              "it raised the wrong thing: " & To_String (Answer.Raised_Name));
   end Arithmetic_And_Comparison;

   ----------------------------------------
   -- Frames_Carry_Their_Own_Variables --
   ----------------------------------------

   procedure Frames_Carry_Their_Own_Variables
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Program : M.Program;
      Answer  : M.Result;
      Routine : Positive;
      Top     : Natural;
   begin
      --  A routine that doubles its parameter, called twice with different
      --  arguments. Each activation has its own frame, which is the whole
      --  point of having frames.
      Program.Set_Frame (2);
      Routine := Program.Declare_Routine;

      --  slot 0 := Double (5); slot 1 := Double (9)
      Program.Add (M.Address, 0, M.Whole_Number (0));
      Program.Add (M.Push_Whole, 0, M.Whole_Number (5));
      Program.Add (M.Call, 0, M.Whole_Number (Routine));
      Program.Add (M.Store);

      Program.Add (M.Address, 0, M.Whole_Number (1));
      Program.Add (M.Push_Whole, 0, M.Whole_Number (9));
      Program.Add (M.Call, 0, M.Whole_Number (Routine));
      Program.Add (M.Store);
      Program.Add (M.Halt);

      Top := Program.Next;
      Program.Add (M.Load, 0, M.Whole_Number (0));
      Program.Add (M.Push_Whole, 0, M.Whole_Number (2));
      Program.Add (M.Multiply_Whole);
      Program.Add (M.Return_Value);

      Program.Define_Routine
        (Routine, Entry_At => Top, Frame => 1, Parameters => 1, Level => 1);

      Program.Run (null, Answer);

      Assert (Answer.What = M.Ran, "the program did not run");
      Assert (Program.Slot_Value (0).Whole = 10,
              "the first call came out wrong");
      Assert (Program.Slot_Value (1).Whole = 18,
              "the second call came out wrong; the frames were shared");
   end Frames_Carry_Their_Own_Variables;

   -------------------------------------------------
   -- A_Call_Finds_The_Frame_It_Was_Declared_In --
   -------------------------------------------------

   procedure A_Call_Finds_The_Frame_It_Was_Declared_In
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Program : M.Program;
      Answer  : M.Result;
      Outer   : Positive;
      Inner   : Positive;
      At_Outer, At_Inner : Natural;
   begin
      --  Outer declares a local and calls Inner, which reads it. That read
      --  goes out one static link, and getting it wrong is a read from
      --  whatever frame happened to be there -- which answers confidently.
      Program.Set_Frame (1);
      Outer := Program.Declare_Routine;
      Inner := Program.Declare_Routine;

      Program.Add (M.Address, 0, M.Whole_Number (0));
      Program.Add (M.Call, 0, M.Whole_Number (Outer));
      Program.Add (M.Store);
      Program.Add (M.Halt);

      At_Outer := Program.Next;
      --  Outer: local slot 0 := 7; return Inner
      Program.Add (M.Address, 0, M.Whole_Number (0));
      Program.Add (M.Push_Whole, 0, M.Whole_Number (7));
      Program.Add (M.Store);
      Program.Add (M.Call, 0, M.Whole_Number (Inner));
      Program.Add (M.Return_Value);

      At_Inner := Program.Next;
      --  Inner: return the enclosing frame's slot 0, plus one
      Program.Add (M.Load, 1, 0);
      Program.Add (M.Push_Whole, 0, M.Whole_Number (1));
      Program.Add (M.Add_Whole);
      Program.Add (M.Return_Value);

      Program.Define_Routine
        (Outer, Entry_At => At_Outer, Frame => 1, Parameters => 0, Level => 1);
      Program.Define_Routine
        (Inner, Entry_At => At_Inner, Frame => 0, Parameters => 0, Level => 2);

      Program.Run (null, Answer);

      Assert (Answer.What = M.Ran, "the program did not run");
      Assert (Program.Slot_Value (0).Whole = 8,
              "the inner routine did not read the frame it was declared in");
   end A_Call_Finds_The_Frame_It_Was_Declared_In;

   -----------------------------------------------
   -- Text_Is_Taken_Apart_And_Bounds_Raise --
   -----------------------------------------------

   procedure Text_Is_Taken_Apart_And_Bounds_Raise
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Program : M.Program;
      Answer  : M.Result;
      Hello   : Natural;
   begin
      Program.Set_Frame (1);
      Hello := Program.Text_Literal ("hello");

      Program.Add (M.Address, 0, M.Whole_Number (0));
      Program.Add (M.Push_Text, 0, M.Whole_Number (Hello));
      Program.Add (M.Push_Whole, 0, M.Whole_Number (2));
      Program.Add (M.Push_Whole, 0, M.Whole_Number (4));
      Program.Add (M.Text_Slice);
      Program.Add (M.Store);
      Program.Add (M.Halt);

      Program.Run (null, Answer);

      Assert (Answer.What = M.Ran, "the program did not run");
      Assert (To_String (Program.Slot_Value (0).Text) = "ell",
              "the slice came out wrong: "
              & To_String (Program.Slot_Value (0).Text));

      --  Past the end raises rather than reading whatever was next, which is
      --  the whole reason the bound is checked here rather than trusted.
      Program.Reset;
      Program.Set_Frame (0);
      Hello := Program.Text_Literal ("abc");
      Program.Add (M.Push_Text, 0, M.Whole_Number (Hello));
      Program.Add (M.Push_Whole, 0, M.Whole_Number (9));
      Program.Add (M.Text_Element);
      Program.Add (M.Halt);

      Program.Run (null, Answer);

      Assert (Answer.What = M.Raised, "an index past the end did not raise");
      Assert (To_String (Answer.Raised_Name) = "Index_Error",
              "it raised the wrong thing: " & To_String (Answer.Raised_Name));
   end Text_Is_Taken_Apart_And_Bounds_Raise;

   ---------------------------------------------------
   -- Text_Is_Written_Into_And_Lengths_Must_Match --
   ---------------------------------------------------

   procedure Text_Is_Written_Into_And_Lengths_Must_Match
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Program : M.Program;
      Answer  : M.Result;
      Line    : Natural;
      Given   : Natural;
   begin
      --  A slice replaced in place: the instruction takes the whole text and
      --  yields the whole text changed, because a String is one cell and there
      --  is no place inside it to store to.
      Program.Set_Frame (1);
      Line  := Program.Text_Literal ("abcdef");
      Given := Program.Text_Literal ("XYZ");

      Program.Add (M.Address, 0, M.Whole_Number (0));
      Program.Add (M.Push_Text, 0, M.Whole_Number (Line));
      Program.Add (M.Push_Whole, 0, M.Whole_Number (2));
      Program.Add (M.Push_Whole, 0, M.Whole_Number (4));
      Program.Add (M.Push_Text, 0, M.Whole_Number (Given));
      Program.Add (M.Text_Set_Slice);
      Program.Add (M.Store);
      Program.Add (M.Halt);

      Program.Run (null, Answer);

      Assert (Answer.What = M.Ran, "the program did not run");
      Assert (To_String (Program.Slot_Value (0).Text) = "aXYZef",
              "the slice was written wrong: "
              & To_String (Program.Slot_Value (0).Text));

      --  One position, which is the same statement with a Character in it.
      Program.Reset;
      Program.Set_Frame (1);
      Line := Program.Text_Literal ("abc");

      Program.Add (M.Address, 0, M.Whole_Number (0));
      Program.Add (M.Push_Text, 0, M.Whole_Number (Line));
      Program.Add (M.Push_Whole, 0, M.Whole_Number (2));
      Program.Add (M.Push_Letter, 0, M.Whole_Number (Character'Pos ('x')));
      Program.Add (M.Text_Set_Element);
      Program.Add (M.Store);
      Program.Add (M.Halt);

      Program.Run (null, Answer);

      Assert (Answer.What = M.Ran, "the program did not run");
      Assert (To_String (Program.Slot_Value (0).Text) = "axc",
              "the position was written wrong: "
              & To_String (Program.Slot_Value (0).Text));

      --  Ada's rule: what goes into a slice has to be as long as the slice.
      --  A shorter one would leave the rest of the target holding what it
      --  held, so this raises rather than writing a String of another length.
      Program.Reset;
      Program.Set_Frame (0);
      Line  := Program.Text_Literal ("abcdef");
      Given := Program.Text_Literal ("XY");

      Program.Add (M.Push_Text, 0, M.Whole_Number (Line));
      Program.Add (M.Push_Whole, 0, M.Whole_Number (2));
      Program.Add (M.Push_Whole, 0, M.Whole_Number (4));
      Program.Add (M.Push_Text, 0, M.Whole_Number (Given));
      Program.Add (M.Text_Set_Slice);
      Program.Add (M.Halt);

      Program.Run (null, Answer);

      Assert (Answer.What = M.Raised, "a length that did not match ran");
      Assert (To_String (Answer.Raised_Name) = "Constraint_Error",
              "it raised the wrong thing: " & To_String (Answer.Raised_Name));

      --  And a bound past the end raises where the read of one does.
      Program.Reset;
      Program.Set_Frame (0);
      Line  := Program.Text_Literal ("abc");
      Given := Program.Text_Literal ("XY");

      Program.Add (M.Push_Text, 0, M.Whole_Number (Line));
      Program.Add (M.Push_Whole, 0, M.Whole_Number (3));
      Program.Add (M.Push_Whole, 0, M.Whole_Number (4));
      Program.Add (M.Push_Text, 0, M.Whole_Number (Given));
      Program.Add (M.Text_Set_Slice);
      Program.Add (M.Halt);

      Program.Run (null, Answer);

      Assert (Answer.What = M.Raised, "a bound past the end ran");
      Assert (To_String (Answer.Raised_Name) = "Index_Error",
              "it raised the wrong thing: " & To_String (Answer.Raised_Name));
   end Text_Is_Written_Into_And_Lengths_Must_Match;

   -------------------------------------------
   -- The_Shell_Is_Called_And_Can_Stop_It --
   -------------------------------------------

   procedure The_Shell_Is_Called_And_Can_Stop_It
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Program : M.Program;
      Answer  : M.Result;
      Shell   : aliased Recorder;
      Named   : Natural;
      Arg     : Natural;
   begin
      Shell.Reply := To_Unbounded_String ("answered");

      Program.Set_Frame (1);
      Named := Program.Text_Literal ("pwd");
      Arg := Program.Text_Literal ("here");

      Program.Add (M.Address, 0, M.Whole_Number (0));
      Program.Add (M.Push_Text, 0, M.Whole_Number (Named));
      Program.Add (M.Push_Text, 0, M.Whole_Number (Arg));
      Program.Add (M.Call_Host, 0, M.Whole_Number (1));
      Program.Add (M.Store);
      Program.Add (M.Halt);

      Program.Run (Shell'Unchecked_Access, Answer);

      Assert (Answer.What = M.Ran, "the program did not run");
      Assert (Shell.Calls = 1, "the shell was not called once");
      Assert (To_String (Shell.Asked) = "pwd",
              "the shell was asked for the wrong thing: "
              & To_String (Shell.Asked));
      Assert (To_String (Shell.Given) = "here",
              "the argument did not arrive: " & To_String (Shell.Given));
      Assert (To_String (Program.Slot_Value (0).Text) = "answered",
              "what the shell answered was not what the program got");

      --  `quit` is the shell deciding the program is over, and the rest of it
      --  does not run.
      Shell.Calls := 0;
      Shell.Stop := True;

      Program.Reset;
      Program.Set_Frame (1);
      Named := Program.Text_Literal ("quit");

      Program.Add (M.Push_Text, 0, M.Whole_Number (Named));
      Program.Add (M.Call_Host, 0, M.Whole_Number (0));
      Program.Add (M.Discard);
      Program.Add (M.Address, 0, M.Whole_Number (0));
      Program.Add (M.Push_Whole, 0, M.Whole_Number (99));
      Program.Add (M.Store);
      Program.Add (M.Halt);

      Program.Run (Shell'Unchecked_Access, Answer);

      Assert (Program.Slot_Value (0).Kind = M.Cell_None,
              "the program went on after the shell stopped it");
   end The_Shell_Is_Called_And_Can_Stop_It;

   ----------
   -- Name --
   ----------

   procedure A_Handler_Catches_And_Unwinds
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Program : M.Program;
      Answer  : M.Result;
      Guard   : Natural;
      Routine : Positive;
      At_Body : Natural;
   begin
      --  A handler set in the outermost frame, a call that raises two frames
      --  down, and the handler catching it. What the frames in between held is
      --  gone by the time it runs, which is the whole of what unwinding is
      --  for -- and what a machine that only remembered where to jump would
      --  get wrong.
      Program.Set_Frame (1);
      Routine := Program.Declare_Routine;

      Guard := Program.Add (M.Push_Handler, 0, 0);
      Program.Add (M.Push_Whole, 0, 1);
      Program.Add (M.Call, 0, M.Whole_Number (Routine));
      Program.Add (M.Discard);
      Program.Add (M.Pop_Handler);
      Program.Add (M.Halt);

      Program.Patch (Guard, Program.Next);

      --  The machine arrives with the name and the detail on the stack.
      Program.Add (M.Discard);
      Program.Add (M.Address, 0, 0);
      Program.Add (M.Swap);
      Program.Add (M.Store);
      Program.Add (M.Halt);

      At_Body := Program.Next;
      Program.Add (M.Push_Whole, 0, 1);
      Program.Add (M.Push_Whole, 0, 0);
      Program.Add (M.Divide_Whole);
      Program.Add (M.Return_Value);

      Program.Define_Routine
        (Routine, Entry_At => At_Body, Frame => 1, Parameters => 1, Level => 1);

      Program.Run (null, Answer);

      Assert (Answer.What = M.Ran,
              "a caught exception still ended the run");
      Assert (Program.Slot_Value (0).Kind = M.Cell_Text
                and then To_String (Program.Slot_Value (0).Text)
                         = "Constraint_Error",
              "the handler was not told what was raised");

      --  Nothing waiting: the same raise ends the run and says what it was.
      Program.Reset;
      Program.Set_Frame (0);
      Program.Add (M.Push_Whole, 0, 1);
      Program.Add (M.Push_Whole, 0, 0);
      Program.Add (M.Divide_Whole);
      Program.Add (M.Halt);

      Program.Run (null, Answer);

      Assert (Answer.What = M.Raised,
              "an exception with no handler did not end the run");
   end A_Handler_Catches_And_Unwinds;

   overriding function Name (T : Case_Type) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Adash.Machine");
   end Name;

   --------------------
   -- Register_Tests --
   --------------------

   overriding procedure Register_Tests (T : in out Case_Type) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Arithmetic_And_Comparison'Access,
         "machine : arithmetic answers, and Ada's failures raise");
      Register_Routine
        (T, Frames_Carry_Their_Own_Variables'Access,
         "machine : each call has a frame of its own");
      Register_Routine
        (T, A_Call_Finds_The_Frame_It_Was_Declared_In'Access,
         "machine : a nested call reads the frame it was declared in");
      Register_Routine
        (T, Text_Is_Taken_Apart_And_Bounds_Raise'Access,
         "machine : text is taken apart, and a bound past the end raises");
      Register_Routine
        (T, Text_Is_Written_Into_And_Lengths_Must_Match'Access,
         "machine : text is written into, and a length that does not match "
         & "raises");
      Register_Routine
        (T, A_Handler_Catches_And_Unwinds'Access,
         "machine : a handler catches what a call raised, and unwinds to it");
      Register_Routine
        (T, The_Shell_Is_Called_And_Can_Stop_It'Access,
         "machine : the shell is called, answers, and can end the program");
   end Register_Tests;

end Adash_Tests.Machine_Cases;
