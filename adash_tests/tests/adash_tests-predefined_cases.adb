with AUnit.Assertions;

with Adash.Diagnostics;
with Adash.Errors;
with Adash.Language.Evaluation;
with Adash.Language.Lexer;
with Adash.Language.Parser;
with Adash.Commands;
with Adash.Language.Scopes;
with Adash.Language.Semantics;
with Adash.Language.Symbols;
with Adash.Language.Syntax;
with Adash.Language.Tokens;
with Adash.Language.Types;
with Adash.Messages;
with Adash.Predefined;
with Adash.Source;

package body Adash_Tests.Predefined_Cases is

   use AUnit.Assertions;

   package S renames Adash.Language.Syntax;
   package Sem renames Adash.Language.Semantics;
   package Ev renames Adash.Language.Evaluation;
   package D renames Adash.Diagnostics;
   package Src renames Adash.Source;
   package P renames Adash.Predefined;

   use type Ev.Outcome;
   use type P.Entity_Id;
   use type P.Entity_Sort;
   use type Adash.Messages.Message_Id;
   use type Adash.Language.Types.Type_Kind;
   use type Adash.Language.Symbols.Symbol_Kind;

   --  Analyse a program and report its diagnostics.
   procedure Check
     (Text   : String;
      Report : in out D.List;
      Legal  : out Boolean)
   is
      Buffer : Src.Buffer;
      Stream : Adash.Language.Tokens.Token_Stream;
      Tree   : S.Tree;
      Result : Sem.Analysis;
      Error  : Adash.Errors.Error_Info;
      Origin : constant Src.Origin := Src.Make_Origin (Src.Origin_Text, "<pre>");
   begin
      Report.Clear;
      Assert (Src.Load (Buffer, Origin, Text, Error), "the source did not load");
      Adash.Language.Lexer.Scan (Buffer, Stream, Report);
      Adash.Language.Parser.Parse (Stream, Origin, Tree, Report);
      Sem.Analyse (Tree, Origin, Result, Report);
      Legal := Sem.Is_Legal (Result);
   end Check;

   --  Analyse and run.
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

   procedure Every_Entity_Carries_Complete_Metadata
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
   begin
      Assert (P.Count > 0, "the registry is empty");

      for Index in 1 .. P.Count loop
         declare
            About : constant P.Metadata := P.Entry_At (Index);
            Name  : constant String := Adash.Messages.Value (About.Name);
         begin
            Assert (Name'Length > 0, "an entity has no name");

            --  Metadata is not decoration: without a documentation key an
            --  entity cannot be written about, and without a description key
            --  it appears in completion as a bare name.
            Assert (About.Documentation /= Adash.Messages.Msg_Error_None,
                    Name & " has no documentation key");
            Assert (About.Description /= Adash.Messages.Msg_Error_None,
                    Name & " has no description key");

            --  A procedure yields nothing; everything else denotes or yields
            --  a type.
            if About.Sort = P.Sort_Procedure then
               Assert (About.Of_Type = Adash.Language.Types.Type_None,
                       Name & " is a procedure with a result type");
            end if;

            --  Every registered entity is reachable by both routes, and they
            --  agree.
            declare
               Found     : P.Entity_Id;
               Findable  : constant Boolean := P.Find (Name, Found);
               Reported  : constant String := P.Entity_Id'Image (Found);
            begin
               Assert (Findable and then Found = About.Id,
                       Name & " is not findable by its own name; got " & Reported);
               Assert (Adash.Messages.Value (P.Describe (About.Id).Name) = Name,
                       Name & " does not describe back to itself");
            end;
         end;
      end loop;
   end Every_Entity_Carries_Complete_Metadata;

   procedure Lookup_Is_Case_Insensitive_And_Order_Free
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Found : P.Entity_Id;
   begin
      --  Ada names fold, and so do these.
      declare
         Lower : constant Boolean := P.Find ("put_line", Found);
         Lower_Id : constant P.Entity_Id := Found;
         Upper : constant Boolean := P.Find ("PUT_LINE", Found);
         Upper_Id : constant P.Entity_Id := Found;
         Near  : constant Boolean := P.Find ("Put_Lin", Found);
      begin
         Assert (Lower and then Lower_Id = P.Entity_Put_Line,
                 "a lower-case predefined name did not fold on lookup");
         Assert (Upper and then Upper_Id = P.Entity_Put_Line,
                 "an upper-case predefined name did not fold on lookup");
         Assert (not Near, "a near miss was matched");
      end;

      --  Nothing depends on the table's order: every entity is reachable
      --  whatever position it holds, and no two share a name -- which Install
      --  would otherwise fail on.
      for Left in 1 .. P.Count loop
         for Right in 1 .. P.Count loop
            if Left /= Right then
               Assert (Adash.Messages.Value (P.Entry_At (Left).Name)
                       /= Adash.Messages.Value (P.Entry_At (Right).Name),
                       "two predefined entities share a name");
            end if;
         end loop;
      end loop;
   end Lookup_Is_Case_Insensitive_And_Order_Free;

   procedure Installing_Declares_Everything_Once
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Chain : Adash.Language.Scopes.Chain;
   begin
      Assert (P.Install (Chain), "installing the predefined entities failed");

      --  Both tables, not one. Installing declares the language's own entities
      --  and the shell's internal commands, because a program has to be able
      --  to see both -- before this, `quit` inside an `if` was reported as an
      --  undeclared name, which told the user they had made a typo when Adash
      --  simply could not lower the call.
      Assert (Chain.Local_Count = P.Count + Adash.Commands.Count,
              "installing declared a different number of names than the two "
              & "tables hold between them");

      --  A command is callable, and its profile is the one Adash.Commands
      --  holds. The unified lookup is what semantics asks, so if these two
      --  disagree a call would be checked against the wrong profile.
      Assert (Adash.Language.Symbols.Is_Callable (Chain.Lookup ("quit")),
              "quit was not installed as callable");

      declare
         About : constant P.Profile := P.Profile_Of ("quit");
      begin
         Assert (About.Known, "quit has no profile");
         Assert (About.Minimum = 0 and then About.Maximum = 1,
                 "quit does not accept a status optionally");
         Assert (About.Types_Of (1).Of_Type = Adash.Language.Types.Type_Integer,
                 "quit's status is not an Integer");
      end;

      declare
         About : constant P.Profile := P.Profile_Of ("Put_Line");
      begin
         Assert (About.Known, "Put_Line has no profile");
         Assert (About.Minimum = 1 and then About.Maximum = 1,
                 "Put_Line does not take exactly one argument");
      end;

      Assert (not P.Profile_Of ("no_such_name_anywhere").Known,
              "a name nothing owns reported a profile");

      --  No command may take a name the language already uses. Either table
      --  alone is consistent; the collision only exists between them, and
      --  Install would fail rather than shadow -- but failing at start-up is a
      --  poor way to find out, so it is asserted here.
      for Index in 1 .. Adash.Commands.Count loop
         declare
            Ignored : P.Entity_Id;
         begin
            Assert (not P.Find
                      (Adash.Messages.Value (Adash.Commands.Entry_At (Index).Name),
                       Ignored),
                    "a command shares a name with a predefined subprogram: "
                    & Adash.Messages.Value (Adash.Commands.Entry_At (Index).Name));
         end;
      end loop;

      --  And each is visible under its own name, with the right kind.
      Assert (Adash.Language.Symbols.Kind (Chain.Lookup ("Integer"))
              = Adash.Language.Symbols.Symbol_Type,
              "Integer was not installed as a type");
      Assert (Adash.Language.Symbols.Is_Callable (Chain.Lookup ("Put_Line")),
              "Put_Line was not installed as callable");
      Assert (not Adash.Language.Symbols.Is_Assignable (Chain.Lookup ("True")),
              "True was installed as assignable");
   end Installing_Declares_Everything_Once;

   procedure Calls_Are_Checked_Against_Signatures
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Report : D.List;
      Legal  : Boolean;
   begin
      --  What Phase 6 deferred for want of anything with a profile.
      Check ("N : Integer := 1; Put_Line (N);", Report, Legal);
      Assert (Legal, "a correct call was rejected");

      Check ("N : Integer := 1; Put_Line (N, N);", Report, Legal);
      Assert (not Legal, "a call with too many arguments was accepted");
      Assert (Reported (Report, Adash.Errors.Error_Wrong_Argument_Count),
              "the wrong argument count was reported as something else");

      Check ("New_Line (1);", Report, Legal);
      Assert (not Legal, "an argument to New_Line was accepted");

      Check ("New_Line;", Report, Legal);
      Assert (Legal, "New_Line with no arguments was rejected");

      --  The first entity that yields a value, so the first whose result type
      --  has to be checked rather than only its parameters.
      Check ("S : String := Env_Value (""HOME"");", Report, Legal);
      Assert (Legal, "reading a variable into a String was rejected");

      Check ("N : Integer := Env_Value (""HOME"");", Report, Legal);
      Assert (not Legal, "a String result was accepted where an Integer was wanted");

      Check ("S : String := Env_Value (1);", Report, Legal);
      Assert (not Legal, "an Integer argument to Env_Value was accepted");

      Check ("S : String := Env_Value;", Report, Legal);
      Assert (not Legal, "Env_Value with no argument was accepted");

      Check ("Env_Value (""HOME"");", Report, Legal);
      Assert (not Legal, "a function was accepted as a statement");

      --  A function of no parameters, which Ada writes without parentheses
      --  and which therefore reaches the analyser as a plain name.
      Check ("N : Integer := Status;", Report, Legal);
      Assert (Legal, "reading the last status into an Integer was rejected");

      Check ("N : Integer := Status + 1;", Report, Legal);
      Assert (Legal, "the last status was not usable in arithmetic");

      Check ("S : String := Status;", Report, Legal);
      Assert (not Legal, "an Integer result was accepted where a String was wanted");

      Check ("N : Integer := Status (1);", Report, Legal);
      Assert (not Legal, "an argument to Status was accepted");

      Check ("N : Integer := Argument_Count;", Report, Legal);
      Assert (Legal, "reading the argument count was rejected");

      Check ("S : String := Argument (1);", Report, Legal);
      Assert (Legal, "reading an argument into a String was rejected");

      Check ("S : String := Argument (""1"");", Report, Legal);
      Assert (not Legal, "a String position was accepted");

      Check ("S : String := Argument;", Report, Legal);
      Assert (not Legal, "Argument without a position was accepted");
   end Calls_Are_Checked_Against_Signatures;

   procedure A_Program_Can_Write_Its_Output
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
   begin
      --  The milestone: a program that produces output rather than one whose
      --  behaviour has to be inferred from whether it raised. The numbers
      --  appear in this suite's own output above the result line.
      Assert (Execute ("N : Integer := 6 * 7; Put_Line (N);") = Ev.Evaluated,
              "a program that writes a line did not run");

      Assert (Execute ("Put_Line (1); Put (2); New_Line;") = Ev.Evaluated,
              "Put and New_Line did not run");

      --  Every type the language has except Float. Each carries its own count
      --  of format parameters and the machine takes exactly that many off the
      --  stack, so a count that is wrong does not fail -- it produces the
      --  wrong thing later, somewhere else. That is why each is asserted
      --  rather than trusted to the one that came first.
      Assert (Execute ("B : Boolean := True; Put_Line (B);") = Ev.Evaluated,
              "writing a Boolean did not run");
      Assert (Execute ("C : Character := 'q'; Put_Line (C);") = Ev.Evaluated,
              "writing a Character did not run");
      Assert (Execute ("S : String := ""text""; Put_Line (S);") = Ev.Evaluated,
              "writing a String did not run");

      Assert (Execute ("F : Float := 1.5; Put_Line (F);") = Ev.Evaluated,
              "writing a Float did not run");

      --  Every type the language has, now. A Float carries three format
      --  parameters where an Integer carries two and a String none, and the
      --  machine takes exactly as many as the type says -- so this is the
      --  assertion that would catch a count copied from the wrong branch.
      Assert (Execute ("Put_Line (1.5 + 2.25);") = Ev.Evaluated,
              "writing a computed Float did not run");
   end A_Program_Can_Write_Its_Output;

   ----------
   -- Name --
   ----------

   overriding function Name (T : Case_Type) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Adash.Predefined");
   end Name;

   --------------------
   -- Register_Tests --
   --------------------

   overriding procedure Register_Tests (T : in out Case_Type) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Every_Entity_Carries_Complete_Metadata'Access,
         "predefined : every entity carries complete metadata");
      Register_Routine
        (T, Lookup_Is_Case_Insensitive_And_Order_Free'Access,
         "predefined : lookup folds case and does not depend on table order");
      Register_Routine
        (T, Installing_Declares_Everything_Once'Access,
         "predefined : installing declares everything once, with the right kinds");
      Register_Routine
        (T, Calls_Are_Checked_Against_Signatures'Access,
         "predefined : calls are checked against real signatures");
      Register_Routine
        (T, A_Program_Can_Write_Its_Output'Access,
         "predefined : a program can write its output");
   end Register_Tests;

end Adash_Tests.Predefined_Cases;
