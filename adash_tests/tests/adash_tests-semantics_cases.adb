with AUnit.Assertions;

with Adash.Diagnostics;
with Adash.Errors;
with Adash.Language.Lexer;
with Adash.Language.Parser;
with Adash.Language.Semantics;
with Adash.Language.Syntax;
with Adash.Language.Tokens;
with Adash.Language.Types;
with Adash.Messages;
with Adash.Source;

package body Adash_Tests.Semantics_Cases is

   use AUnit.Assertions;

   package S renames Adash.Language.Syntax;
   package Sem renames Adash.Language.Semantics;
   package D renames Adash.Diagnostics;
   package Src renames Adash.Source;
   package Ty renames Adash.Language.Types;

   use type Ty.Type_Kind;
   use type Adash.Messages.Message_Id;

   --  Parse and analyse. Each call starts from empty, so counts are per case.
   procedure Check
     (Text     : String;
      Tree     : in out S.Tree;
      Result   : in out Sem.Analysis;
      Report   : in out D.List)
   is
      Buffer : Src.Buffer;
      Stream : Adash.Language.Tokens.Token_Stream;
      Error  : Adash.Errors.Error_Info;
      Origin : constant Src.Origin := Src.Make_Origin (Src.Origin_Text, "<check>");
   begin
      Report.Clear;
      Assert (Src.Load (Buffer, Origin, Text, Error), "the test source did not load");
      Adash.Language.Lexer.Scan (Buffer, Stream, Report);
      Adash.Language.Parser.Parse (Stream, Origin, Tree, Report);
      Assert (not S.Has_Errors (Tree),
              "the test source did not parse: " & Text);
      Sem.Analyse (Tree, Origin, Result, Report);
   end Check;

   --  Whether any diagnostic reports a particular failure.
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

   procedure Legal_Programs_Are_Accepted
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Tree   : S.Tree;
      Result : Sem.Analysis;
      Report : D.List;
   begin
      --  First, because a rule added carelessly rejects working code, and
      --  nothing else in this case would notice.
      Check ("Count : Integer := 0;"
             & "Count := Count + 1;"
             & "if Count > 0 then Count := Count - 1; end if;"
             & "while Count < 10 loop Count := Count + 1; end loop;"
             & "for I in 1 .. 10 loop null; end loop;",
             Tree, Result, Report);

      Assert (Sem.Is_Legal (Result),
              "a legal program was rejected; first diagnostic count is"
              & Natural'Image (Report.Count));
      Assert (Report.Count = 0, "a legal program produced diagnostics");
      Assert (Sem.Annotated_Count (Result) > 0,
              "analysis did not annotate anything");

      --  The predefined names exist before anything is declared.
      Check ("Flag : Boolean := True; Text : String := ""hi"";",
             Tree, Result, Report);
      Assert (Sem.Is_Legal (Result), "the predefined names were not visible");
   end Legal_Programs_Are_Accepted;

   procedure Undeclared_Names_Are_Reported
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Tree   : S.Tree;
      Result : Sem.Analysis;
      Report : D.List;
   begin
      Check ("X := 1;", Tree, Result, Report);
      Assert (not Sem.Is_Legal (Result), "an undeclared name was accepted");
      Assert (Reported (Report, Adash.Errors.Error_Name_Undeclared),
              "an undeclared name was reported as something else");

      --  A declaration's own name is not in scope for its initial value, so
      --  `X : Integer := X;` reports X rather than quietly reading itself.
      Check ("X : Integer := X;", Tree, Result, Report);
      Assert (Reported (Report, Adash.Errors.Error_Name_Undeclared),
              "a self-referencing declaration was accepted");

      --  A name declared twice in one scope.
      Check ("X : Integer; X : Integer;", Tree, Result, Report);
      Assert (Reported (Report, Adash.Errors.Error_Name_Already_Declared),
              "a duplicate declaration was accepted");
   end Undeclared_Names_Are_Reported;

   procedure There_Is_No_Implicit_Conversion
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Tree   : S.Tree;
      Result : Sem.Analysis;
      Report : D.List;
   begin
      --  The decision Phase 3 locked, now enforced on real programs. Ada
      --  itself would widen here; Adash does not, because a quiet widening has
      --  a rounding rule nobody wrote down.
      Check ("X : Float := 1;", Tree, Result, Report);
      Assert (not Sem.Is_Legal (Result), "an Integer initialised a Float");
      Assert (Reported (Report, Adash.Errors.Error_Type_Mismatch),
              "the mismatch was reported as something else");

      Check ("X : Integer := 0; Y : Float := 0.0; X := Y;", Tree, Result, Report);
      Assert (not Sem.Is_Legal (Result), "a Float was assigned to an Integer");

      --  Mixed arithmetic is refused for the same reason.
      Check ("X : Integer := 0; Y : Float := 0.0; Z : Float := X * Y;",
             Tree, Result, Report);
      Assert (Reported (Report, Adash.Errors.Error_Operator_Not_Defined),
              "mixed-type arithmetic was accepted");

      --  And a String is not a number.
      Check ("X : Integer := 0; T : String := ""a""; X := X + 1; T := T & ""b"";",
             Tree, Result, Report);
      Assert (Sem.Is_Legal (Result),
              "concatenation of two Strings was refused");

      Check ("T : String := ""a""; X : Integer := 1; T := T & X;",
             Tree, Result, Report);
      Assert (not Sem.Is_Legal (Result), "a String was concatenated with an Integer");
   end There_Is_No_Implicit_Conversion;

   procedure Conditions_Must_Be_Boolean
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Tree   : S.Tree;
      Result : Sem.Analysis;
      Report : D.List;
   begin
      --  There is no truthiness in Adash: an Integer is not a condition, and
      --  accepting one would make `if X` mean something the language does not
      --  say.
      Check ("X : Integer := 1; if X then null; end if;", Tree, Result, Report);
      Assert (not Sem.Is_Legal (Result), "an Integer was accepted as a condition");
      Assert (Reported (Report, Adash.Errors.Error_Condition_Not_Boolean),
              "a non-Boolean condition was reported as something else");

      Check ("X : Integer := 1; while X loop null; end loop;", Tree, Result, Report);
      Assert (not Sem.Is_Legal (Result), "an Integer was accepted as a while condition");

      Check ("X : Integer := 1; loop exit when X; end loop;", Tree, Result, Report);
      Assert (not Sem.Is_Legal (Result), "an Integer was accepted in exit when");

      --  A comparison is Boolean, so this is fine.
      Check ("X : Integer := 1; if X > 0 then null; end if;", Tree, Result, Report);
      Assert (Sem.Is_Legal (Result), "a comparison was refused as a condition");
   end Conditions_Must_Be_Boolean;

   procedure Constants_And_Loop_Parameters_Cannot_Be_Assigned
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Tree   : S.Tree;
      Result : Sem.Analysis;
      Report : D.List;
   begin
      Check ("Limit : constant Integer := 10; Limit := 11;", Tree, Result, Report);
      Assert (not Sem.Is_Legal (Result), "a constant was assigned to");
      Assert (Reported (Report, Adash.Errors.Error_Not_Assignable),
              "assigning to a constant was reported as something else");

      --  Ada makes the loop parameter a constant, and so does this.
      Check ("for I in 1 .. 3 loop I := 2; end loop;", Tree, Result, Report);
      Assert (not Sem.Is_Legal (Result), "a loop parameter was assigned to");
      Assert (Reported (Report, Adash.Errors.Error_Not_Assignable),
              "assigning to a loop parameter was reported as something else");

      --  And it is gone after the loop.
      Check ("for I in 1 .. 3 loop null; end loop; I := 1;", Tree, Result, Report);
      Assert (Reported (Report, Adash.Errors.Error_Name_Undeclared),
              "the loop parameter outlived its loop");
   end Constants_And_Loop_Parameters_Cannot_Be_Assigned;

   procedure Type_Names_Are_Not_Values
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Tree   : S.Tree;
      Result : Sem.Analysis;
      Report : D.List;
   begin
      --  `X := Integer` parses and is not legal. Telling a type name from a
      --  value is what Symbol_Type is for.
      --
      --  Reported as what it is rather than as its opposite. The two
      --  complaints are different: this one is that a name *is* a type where a
      --  value belongs, and the one below is that a name is not a type where
      --  one belongs. They shared a message, so a program that named a type
      --  where a value goes was told the type was not a type.
      Check ("X : Integer := 0; X := Integer;", Tree, Result, Report);
      Assert (not Sem.Is_Legal (Result), "a type name was used as a value");
      Assert (Reported (Report, Adash.Errors.Error_Is_A_Type),
              "using a type as a value was reported as something else");

      --  And a variable is not a type.
      Check ("X : Integer := 0; Y : X := 1;", Tree, Result, Report);
      Assert (Reported (Report, Adash.Errors.Error_Not_A_Type),
              "a variable was accepted as a type name");

      --  A name that is not callable cannot be called.
      Check ("X : Integer := 0; X (1);", Tree, Result, Report);
      Assert (Reported (Report, Adash.Errors.Error_Not_Callable),
              "a variable was called");
   end Type_Names_Are_Not_Values;

   procedure Expressions_Get_Their_Types
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Tree   : S.Tree;
      Result : Sem.Analysis;
      Report : D.List;
   begin
      Check ("X : Integer := 1 + 2;", Tree, Result, Report);
      Assert (Sem.Is_Legal (Result), "a simple declaration was refused");

      declare
         Declaration : constant S.Node_Id := S.Child (Tree, S.Root (Tree), 1);
         Value       : constant S.Node_Id := S.Third (Tree, Declaration);
      begin
         --  The conclusion is in the side table, keyed by node. The tree was
         --  not touched.
         Assert (Sem.Type_Of (Result, Value) = Ty.Type_Integer,
                 "1 + 2 was not typed as Integer");
      end;

      --  A comparison yields Boolean whatever it compares.
      Check ("F : Boolean := ""a"" < ""b"";", Tree, Result, Report);
      Assert (Sem.Is_Legal (Result), "comparing two Strings was refused");

      --  'Image is defined for every type and yields String.
      Check ("X : Integer := 1; T : String := X'Image;", Tree, Result, Report);
      Assert (Sem.Is_Legal (Result), "'Image was refused");

      --  An attribute that does not exist is refused rather than guessed at.
      Check ("X : Integer := 1; T : String := X'Nonsense;", Tree, Result, Report);
      Assert (not Sem.Is_Legal (Result), "an unknown attribute was accepted");
   end Expressions_Get_Their_Types;

   procedure Scopes_Hide_And_Restore
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Tree   : S.Tree;
      Result : Sem.Analysis;
      Report : D.List;
   begin
      --  A for loop's parameter may hide an outer name while it lasts. That is
      --  legal Ada, and a scope model that treated it as a duplicate would
      --  reject working programs.
      Check ("I : String := ""outer"";"
             & "for I in 1 .. 3 loop null; end loop;"
             & "I := ""outer again"";",
             Tree, Result, Report);
      Assert (Sem.Is_Legal (Result),
              "an inner loop parameter hiding an outer name was refused");
   end Scopes_Hide_And_Restore;

   procedure One_Unknown_Type_Does_Not_Cascade
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Tree   : S.Tree;
      Result : Sem.Analysis;
      Report : D.List;
   begin
      --  One undeclared name, used three times in one expression. A pass that
      --  complained at each operator would bury the one thing the user has to
      --  fix.
      Check ("Y : Integer := Nope + Nope * Nope;", Tree, Result, Report);
      Assert (not Sem.Is_Legal (Result), "an undeclared name was accepted");
      Assert (Report.Count <= 3,
              "one undeclared name produced a cascade of"
              & Natural'Image (Report.Count) & " diagnostics");
      Assert (not Reported (Report, Adash.Errors.Error_Operator_Not_Defined),
              "an operator was blamed for an operand that never resolved");
   end One_Unknown_Type_Does_Not_Cascade;

   procedure A_Tree_That_Did_Not_Parse_Is_Not_Analysed
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Buffer : Src.Buffer;
      Stream : Adash.Language.Tokens.Token_Stream;
      Tree   : S.Tree;
      Result : Sem.Analysis;
      Report : D.List;
      Error  : Adash.Errors.Error_Info;
      Origin : constant Src.Origin := Src.Make_Origin (Src.Origin_Text, "<broken>");
   begin
      Assert (Src.Load (Buffer, Origin, "X := ;", Error), "the source did not load");
      Adash.Language.Lexer.Scan (Buffer, Stream, Report);
      Adash.Language.Parser.Parse (Stream, Origin, Tree, Report);
      Assert (S.Has_Errors (Tree), "the broken source parsed cleanly");

      declare
         Before : constant Natural := Report.Count;
      begin
         Sem.Analyse (Tree, Origin, Result, Report);

         --  Analysing a tree that did not parse would report on the recovery
         --  rather than on the program, burying the diagnostics the user needs.
         Assert (Report.Count = Before,
                 "analysing a broken tree added diagnostics on top of the parse errors");
         Assert (not Sem.Is_Legal (Result),
                 "a tree that did not parse was declared legal");
      end;
   end A_Tree_That_Did_Not_Parse_Is_Not_Analysed;

   ----------
   -- Name --
   ----------

   procedure Commands_Are_Callable_Names
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Tree   : S.Tree;
      Result : Sem.Analysis;
      Report : D.List;

      procedure Legal (Text : String; Why : String);
      procedure Rejected (Text : String; Why : String);

      procedure Legal (Text : String; Why : String) is
      begin
         Check (Text, Tree, Result, Report);
         Assert (Sem.Is_Legal (Result), Why);
      end Legal;

      procedure Rejected (Text : String; Why : String) is
      begin
         Check (Text, Tree, Result, Report);
         Assert (not Sem.Is_Legal (Result), Why);
      end Rejected;

   begin
      --  What step 2 is for. A command used where the analyser can see it is a
      --  known name with a typed profile, not an undeclared one.
      --
      --  The difference matters more than it looks: "quit is not declared
      --  here" tells the user they made a typo, when what has actually
      --  happened is that Adash cannot lower the call yet. A name the shell
      --  obviously knows must never be reported as unknown.
      Legal ("N : Integer := 1; if N = 1 then quit; end if;",
             "a command inside an if was not accepted as a known name");
      Legal ("N : Integer := 1; if N = 1 then quit (0); end if;",
             "a command with an argument was not accepted");
      Legal ("P : String := ""/tmp""; if True then cd (P); end if;",
             "a command given a String variable was not accepted");

      --  And it is checked like anything else. Before this, a wrong argument
      --  was something the command discovered at run time by failing to
      --  convert text somebody had typed.
      Rejected ("if True then quit (""later""); end if;",
                "quit accepted a String status");
      Rejected ("if True then cd (1); end if;",
                "cd accepted an Integer directory");
      Rejected ("if True then pwd (1); end if;",
                "pwd accepted an argument");
      Rejected ("if True then set; end if;",
                "set accepted no argument when it requires one");

      --  A command that takes one argument optionally accepts both, which a
      --  single parameter count could not express.
      Legal ("if True then quit; end if;", "quit was rejected without a status");
      Legal ("if True then quit (2); end if;",
             "quit was rejected with a status");

      --  A name nothing owns is still undeclared, so making commands visible
      --  did not make everything visible.
      Rejected ("if True then no_such_command; end if;",
                "an unknown name was accepted as a command");
   end Commands_Are_Callable_Names;

   ------------------------------------------------------------------

   overriding function Name (T : Case_Type) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Adash.Language.Semantics");
   end Name;

   --------------------
   -- Register_Tests --
   --------------------

   procedure A_Case_Must_Account_For_Every_Value
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Tree   : S.Tree;
      Result : Sem.Analysis;
      Report : D.List;
   begin
      --  The four forms Ada writes, all accepted.
      Check ("X : Integer := 1; case X is when 1 => null; when 2 | 3 => null; "
             & "when 4 .. 6 => null; when others => null; end case;",
             Tree, Result, Report);
      Assert (Sem.Is_Legal (Result), "a well formed case was rejected");

      --  Completeness is what the rule asks for, not the word `others`: two
      --  alternatives account for a Boolean.
      Check ("B : Boolean := True; case B is when True => null; "
             & "when False => null; end case;", Tree, Result, Report);
      Assert (Sem.Is_Legal (Result), "a complete Boolean case was rejected");

      Check ("B : Boolean := True; case B is when True => null; end case;",
             Tree, Result, Report);
      Assert (not Sem.Is_Legal (Result), "a Boolean case missing a value was accepted");
      Assert (Reported (Report, Adash.Errors.Error_Case_Incomplete),
              "an incomplete case was reported as something else");

      --  An Integer has too many values for anything but others to finish.
      Check ("X : Integer := 1; case X is when 1 => null; end case;",
             Tree, Result, Report);
      Assert (not Sem.Is_Legal (Result), "an Integer case without others was accepted");

      Check ("X : Integer := 1; case X is when 1 .. 3 => null; "
             & "when 2 => null; when others => null; end case;",
             Tree, Result, Report);
      Assert (not Sem.Is_Legal (Result), "a value covered twice was accepted");
      Assert (Reported (Report, Adash.Errors.Error_Case_Choice_Covered_Twice),
              "an overlapping choice was reported as something else");

      --  Static is decided by what the name resolves to rather than by how it
      --  is spelled: a variable is not a choice however short its name.
      Check ("X : Integer := 1; Y : Integer := 2; case X is when Y => null; "
             & "when others => null; end case;", Tree, Result, Report);
      Assert (not Sem.Is_Legal (Result), "a variable was accepted as a choice");
      Assert (Reported (Report, Adash.Errors.Error_Case_Choice_Not_Static),
              "a non-static choice was reported as something else");

      Check ("X : Integer := 1; case X is when others => null; "
             & "when 1 => null; end case;", Tree, Result, Report);
      Assert (not Sem.Is_Legal (Result), "others was accepted before another alternative");

      Check ("X : Integer := 1; case X is when 5 .. 1 => null; "
             & "when others => null; end case;", Tree, Result, Report);
      Assert (not Sem.Is_Legal (Result), "a backwards range was accepted");

      --  A type without a successor cannot be covered.
      Check ("S : String := ""a""; case S is when ""a"" => null; "
             & "when others => null; end case;", Tree, Result, Report);
      Assert (not Sem.Is_Legal (Result), "a String was accepted as a case value");
      Assert (Reported (Report, Adash.Errors.Error_Case_Not_Discrete),
              "a String case was reported as something else");

      Check ("F : Float := 1.5; case F is when 1.5 => null; "
             & "when others => null; end case;", Tree, Result, Report);
      Assert (not Sem.Is_Legal (Result), "a Float was accepted as a case value");

      --  A choice of the wrong type is a type error, and says so.
      Check ("X : Integer := 1; case X is when 'a' => null; "
             & "when others => null; end case;", Tree, Result, Report);
      Assert (not Sem.Is_Legal (Result), "a Character choice was accepted for an Integer");
      Assert (Reported (Report, Adash.Errors.Error_Type_Mismatch),
              "a choice of the wrong type was reported as something else");

      --  What an alternative holds is analysed like anything else, so a
      --  mistake inside one is reported rather than hidden by the case.
      Check ("X : Integer := 1; case X is when 1 => zzz := 2; "
             & "when others => null; end case;", Tree, Result, Report);
      Assert (not Sem.Is_Legal (Result), "an undeclared name inside an alternative was accepted");
   end A_Case_Must_Account_For_Every_Value;

   procedure A_String_Is_Taken_Apart_By_Position
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Tree   : S.Tree;
      Result : Sem.Analysis;
      Report : D.List;
   begin
      --  Ada writes indexing and calling the same way, so which one this is
      --  depends on what the name denotes -- a question only this pass can
      --  answer.
      Check ("S : String := ""abc""; C : Character := S (1);",
             Tree, Result, Report);
      Assert (Sem.Is_Legal (Result), "indexing a String was rejected");

      Check ("S : String := ""abc""; T : String := S (1 .. 2);",
             Tree, Result, Report);
      Assert (Sem.Is_Legal (Result), "slicing a String was rejected");

      --  One position yields a Character and one range yields a String. The
      --  two are not interchangeable, and a build that confused them would put
      --  the wrong thing on the stack.
      Check ("S : String := ""abc""; T : String := S (1);",
             Tree, Result, Report);
      Assert (not Sem.Is_Legal (Result),
              "a Character was accepted where a String was wanted");

      Check ("S : String := ""abc""; C : Character := S (1 .. 2);",
             Tree, Result, Report);
      Assert (not Sem.Is_Legal (Result),
              "a String was accepted where a Character was wanted");

      Check ("S : String := ""abc""; C : Character := S (""x"");",
             Tree, Result, Report);
      Assert (not Sem.Is_Legal (Result), "a String position was accepted");
      Assert (Reported (Report, Adash.Errors.Error_Type_Mismatch),
              "a position of the wrong type was reported as something else");

      Check ("S : String := ""abc""; C : Character := S (1, 2);",
             Tree, Result, Report);
      Assert (not Sem.Is_Legal (Result), "two positions were accepted");
      Assert (Reported (Report, Adash.Errors.Error_String_Index_Malformed),
              "a malformed index was reported as something else");

      --  Nothing else is indexable, and the older complaint is still the right
      --  one for a name that cannot be called either.
      Check ("N : Integer := 1; M : Integer := N (1);", Tree, Result, Report);
      Assert (not Sem.Is_Legal (Result), "an Integer was indexed");
      Assert (Reported (Report, Adash.Errors.Error_Not_Callable),
              "indexing an Integer was reported as something else");

      --  The three attributes a String has, and only for a String.
      Check ("S : String := ""abc""; N : Integer := S'Length + S'First + S'Last;",
             Tree, Result, Report);
      Assert (Sem.Is_Legal (Result), "the String attributes were rejected");

      Check ("S : String := ""abc""; T : String := S'Length;",
             Tree, Result, Report);
      Assert (not Sem.Is_Legal (Result), "'Length was accepted as a String");

      Check ("N : Integer := 1; M : Integer := N'Length;", Tree, Result, Report);
      Assert (not Sem.Is_Legal (Result), "an Integer was asked its length");
      Assert (Reported (Report, Adash.Errors.Error_Attribute_Not_Defined),
              "an attribute that does not apply was reported as something else");

      --  A parameter is a name like any other, so a body can take its argument
      --  apart -- which is most of what taking a String apart is for.
      Check ("function F (Text : String) return Character is "
             & "begin return Text (1); end F;", Tree, Result, Report);
      Assert (Sem.Is_Legal (Result), "indexing a parameter was rejected");
   end A_String_Is_Taken_Apart_By_Position;

   procedure A_Block_Is_A_Scope_Of_Its_Own
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Tree   : S.Tree;
      Result : Sem.Analysis;
      Report : D.List;
   begin
      Check ("declare X : Integer := 1; begin put_line (X); end;",
             Tree, Result, Report);
      Assert (Sem.Is_Legal (Result), "a block was rejected");

      --  The declare is optional, as in Ada.
      Check ("begin put_line (1); end;", Tree, Result, Report);
      Assert (Sem.Is_Legal (Result), "a block with no declarations was rejected");

      --  What it declares lasts as long as it does.
      Check ("declare X : Integer := 1; begin null; end; put_line (X);",
             Tree, Result, Report);
      Assert (not Sem.Is_Legal (Result),
              "a name declared in a block was visible after it");
      Assert (Reported (Report, Adash.Errors.Error_Name_Undeclared),
              "a name gone out of scope was reported as something else");

      --  And may hide one from around it while it does, which is the other
      --  half of being a scope.
      Check ("X : String := ""a""; declare X : Integer := 1; "
             & "begin put_line (X); end;", Tree, Result, Report);
      Assert (Sem.Is_Legal (Result),
              "a block could not declare a name the scope around it had");

      --  Ada draws the line at begin and so does this.
      Check ("declare put_line (1); begin null; end;", Tree, Result, Report);
      Assert (not Sem.Is_Legal (Result), "a statement was accepted before begin");
      Assert (Reported (Report, Adash.Errors.Error_Statement_Among_Declarations),
              "a statement among declarations was reported as something else");

      --  A subprogram is a declaration, so it belongs there too.
      Check ("declare procedure P is begin null; end P; begin P; end;",
             Tree, Result, Report);
      Assert (Sem.Is_Legal (Result),
              "a subprogram declared in a block was rejected");

      --  A block does not make an exit legal, and does not make one illegal.
      Check ("declare X : Integer := 1; begin exit; end;", Tree, Result, Report);
      Assert (not Sem.Is_Legal (Result), "an exit outside a loop was accepted");

      Check ("for I in 1 .. 3 loop declare X : Integer := I; "
             & "begin exit; end; end loop;", Tree, Result, Report);
      Assert (Sem.Is_Legal (Result), "an exit inside a block in a loop was refused");
   end A_Block_Is_A_Scope_Of_Its_Own;

   procedure A_Type_Can_Be_Read_From_Text
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Tree   : S.Tree;
      Result : Sem.Analysis;
      Report : D.List;
   begin
      --  `Integer'Value ("42")` yields the type it names, and takes a String.
      Check ("N : Integer := Integer'Value (""42"");", Tree, Result, Report);
      Assert (Sem.Is_Legal (Result), "reading a number from text was rejected");

      Check ("F : Float := Float'Value (""1.5"");", Tree, Result, Report);
      Assert (Sem.Is_Legal (Result), "reading a Float from text was rejected");

      --  And `Integer'Image (N)` the other way, which is how Ada has always
      --  written it.
      Check ("S : String := Integer'Image (42);", Tree, Result, Report);
      Assert (Sem.Is_Legal (Result), "the image of a type was rejected");

      --  The types have to match in both directions.
      Check ("S : String := Integer'Value (""42"");", Tree, Result, Report);
      Assert (not Sem.Is_Legal (Result),
              "a number was accepted where a String was wanted");

      Check ("N : Integer := Integer'Value (42);", Tree, Result, Report);
      Assert (not Sem.Is_Legal (Result), "a number was accepted as the text");
      Assert (Reported (Report, Adash.Errors.Error_Type_Mismatch),
              "an argument of the wrong type was reported as something else");

      --  Neither direction is defined for a String.
      Check ("S : String := String'Value (""x"");", Tree, Result, Report);
      Assert (not Sem.Is_Legal (Result), "a String was read back from a String");
      Assert (Reported (Report, Adash.Errors.Error_Attribute_Not_Defined),
              "an attribute that does not apply was reported as something else");

      --  Written without its argument, and with an attribute no type has.
      Check ("N : Integer := Integer'Value;", Tree, Result, Report);
      Assert (not Sem.Is_Legal (Result),
              "a type attribute without its argument was accepted");
      Assert (Reported (Report, Adash.Errors.Error_Wrong_Argument_Count),
              "a missing argument was reported as something else");

      --  An attribute no type here has. `'Size` was this example until a
      --  program could ask it -- how many slots a value takes is a question
      --  this machine can answer -- so the example is one it still cannot.
      Check ("N : Integer := Integer'Alignment;", Tree, Result, Report);
      Assert (not Sem.Is_Legal (Result), "an attribute no type has was accepted");
      Assert (Reported (Report, Adash.Errors.Error_Attribute_Not_Defined),
              "an unknown type attribute was reported as something else");

      --  A name that is not a type at all is still not a type.
      Check ("X : Integer := 1; N : Integer := X'Value (""1"");",
             Tree, Result, Report);
      Assert (not Sem.Is_Legal (Result), "a variable was used as a type");
   end A_Type_Can_Be_Read_From_Text;

   overriding procedure Register_Tests (T : in out Case_Type) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, A_Type_Can_Be_Read_From_Text'Access,
         "semantics : a type can be read from text and written to it");
      Register_Routine
        (T, A_Block_Is_A_Scope_Of_Its_Own'Access,
         "semantics : a block is a scope of its own");
      Register_Routine
        (T, A_String_Is_Taken_Apart_By_Position'Access,
         "semantics : a String is taken apart by position");
      Register_Routine
        (T, A_Case_Must_Account_For_Every_Value'Access,
         "semantics : a case must account for every value");
      Register_Routine
        (T, Legal_Programs_Are_Accepted'Access,
         "semantics : legal programs are accepted");
      Register_Routine
        (T, Undeclared_Names_Are_Reported'Access,
         "semantics : undeclared and duplicated names are reported");
      Register_Routine
        (T, There_Is_No_Implicit_Conversion'Access,
         "semantics : there is no implicit conversion, on real programs");
      Register_Routine
        (T, Conditions_Must_Be_Boolean'Access,
         "semantics : conditions must be Boolean; there is no truthiness");
      Register_Routine
        (T, Constants_And_Loop_Parameters_Cannot_Be_Assigned'Access,
         "semantics : constants and loop parameters cannot be assigned to");
      Register_Routine
        (T, Type_Names_Are_Not_Values'Access,
         "semantics : type names are not values and variables are not types");
      Register_Routine
        (T, Expressions_Get_Their_Types'Access,
         "semantics : expressions get their types in the side table");
      Register_Routine
        (T, Scopes_Hide_And_Restore'Access,
         "semantics : an inner declaration hides an outer one and restores it");
      Register_Routine
        (T, One_Unknown_Type_Does_Not_Cascade'Access,
         "semantics : one unknown type does not cascade into operator errors");
      Register_Routine
        (T, A_Tree_That_Did_Not_Parse_Is_Not_Analysed'Access,
         "semantics : a tree that did not parse is not analysed");
      Register_Routine
        (T, Commands_Are_Callable_Names'Access,
         "commands are callable names with typed profiles");
   end Register_Tests;

end Adash_Tests.Semantics_Cases;
