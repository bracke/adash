with Ada.Strings.Unbounded;

with AUnit.Assertions;

with Adash.Diagnostics;
with Adash.Errors;
with Adash.Language.Lexer;
with Adash.Language.Parser;
with Adash.Language.Syntax;
with Adash.Language.Tokens;
with Adash.Messages;
with Adash.Source;

package body Adash_Tests.Parser_Cases is

   use AUnit.Assertions;

   package S renames Adash.Language.Syntax;
   package P renames Adash.Language.Parser;
   package D renames Adash.Diagnostics;
   package Src renames Adash.Source;

   use type S.Node_Kind;
   use type S.Operation;
   use type Adash.Messages.Message_Id;

   --  Parse a statement sequence.
   procedure Parse
     (Text   : String;
      Tree   : in out S.Tree;
      Report : in out D.List;
      Expression : Boolean := False)
   is
      Buffer : Src.Buffer;
      Stream : Adash.Language.Tokens.Token_Stream;
      Error  : Adash.Errors.Error_Info;
      Origin : constant Src.Origin := Src.Make_Origin (Src.Origin_Text, "<parse>");
   begin
      Report.Clear;
      Assert (Src.Load (Buffer, Origin, Text, Error), "the test source did not load");
      Adash.Language.Lexer.Scan (Buffer, Stream, Report);

      if Expression then
         P.Parse_Expression (Stream, Origin, Tree, Report);
      else
         P.Parse (Stream, Origin, Tree, Report);
      end if;
   end Parse;

   --  The single expression a one-expression parse produced.
   function Expression_Root (Tree : S.Tree) return S.Node_Id
   is (S.Root (Tree));

   --  The Index'th statement of a parsed sequence.
   function Statement (Tree : S.Tree; Index : Positive) return S.Node_Id
   is (S.Child (Tree, S.Root (Tree), Index));

   ------------------------------------------------------------------
   --  Precedence and associativity
   ------------------------------------------------------------------

   procedure Precedence_Follows_Ada
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Tree   : S.Tree;
      Report : D.List;
   begin
      --  1 + 2 * 3 is 1 + (2 * 3). A parser that got this wrong would not
      --  fail; it would quietly compute 9.
      Parse ("1 + 2 * 3", Tree, Report, Expression => True);
      Assert (Report.Count = 0, "a well formed expression produced diagnostics");

      declare
         Root : constant S.Node_Id := Expression_Root (Tree);
      begin
         Assert (S.Kind (Tree, Root) = S.Node_Binary_Operation,
                 "the root is not an operation");
         Assert (S.Operator (Tree, Root) = S.Op_Add,
                 "addition did not end up at the root; got "
                 & S.Spelling (S.Operator (Tree, Root)));
         Assert (S.Operator (Tree, S.Second (Tree, Root)) = S.Op_Multiply,
                 "multiplication is not the right operand");
      end;

      --  2 * 3 + 1 is (2 * 3) + 1: the same rule, the other way round.
      Parse ("2 * 3 + 1", Tree, Report, Expression => True);
      Assert (S.Operator (Tree, Expression_Root (Tree)) = S.Op_Add,
              "addition did not end up at the root when written second");
      Assert (S.Operator (Tree, S.First (Tree, Expression_Root (Tree)))
              = S.Op_Multiply,
              "multiplication is not the left operand");

      --  Exponentiation binds tighter than multiplication.
      Parse ("2 * 3 ** 4", Tree, Report, Expression => True);
      Assert (S.Operator (Tree, S.Second (Tree, Expression_Root (Tree)))
              = S.Op_Power,
              "exponentiation did not bind tighter than multiplication");

      --  Relational binds looser than arithmetic.
      Parse ("1 + 1 = 2", Tree, Report, Expression => True);
      Assert (S.Operator (Tree, Expression_Root (Tree)) = S.Op_Equal,
              "the comparison is not at the root");
   end Precedence_Follows_Ada;

   procedure Arithmetic_Is_Left_Associative
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Tree   : S.Tree;
      Report : D.List;
   begin
      --  10 - 3 - 2 is (10 - 3) - 2, which is 5. Right associativity would
      --  give 9, and nothing would report a problem.
      Parse ("10 - 3 - 2", Tree, Report, Expression => True);

      declare
         Root : constant S.Node_Id := Expression_Root (Tree);
      begin
         Assert (S.Operator (Tree, Root) = S.Op_Subtract, "the root is not a subtraction");
         Assert (S.Kind (Tree, S.First (Tree, Root)) = S.Node_Binary_Operation,
                 "subtraction grouped to the right instead of the left");
         Assert (S.Text (Tree, S.Second (Tree, Root)) = "2",
                 "the last operand is not on the right");
      end;
   end Arithmetic_Is_Left_Associative;

   procedure Parentheses_Are_Kept
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Tree   : S.Tree;
      Report : D.List;
   begin
      Parse ("(1 + 2) * 3", Tree, Report, Expression => True);

      declare
         Root : constant S.Node_Id := Expression_Root (Tree);
      begin
         Assert (S.Operator (Tree, Root) = S.Op_Multiply,
                 "parentheses did not change the grouping");

         --  Kept rather than folded away: a formatter has to reproduce them.
         Assert (S.Kind (Tree, S.First (Tree, Root)) = S.Node_Parenthesized,
                 "the parenthesized expression was folded away");
         Assert (S.Operator (Tree, S.First (Tree, S.First (Tree, Root))) = S.Op_Add,
                 "the parenthesized expression lost its contents");
      end;
   end Parentheses_Are_Kept;

   procedure Mixing_And_With_Or_Is_Refused
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Tree   : S.Tree;
      Report : D.List;
   begin
      --  Ada's rule, and it exists because `and` and `or` have equal
      --  precedence there: `a or b and c` has no reading a user could rely on.
      --  Every language that answers it with a precedence rule has users who
      --  remember the rule wrongly.
      Parse ("A and B or C", Tree, Report, Expression => True);
      Assert (Report.Count > 0, "mixing and with or was accepted");
      Assert (D.Message (Report.Element (1))
              = Adash.Errors.Message
                  (Adash.Errors.Error_Syntax_Mixed_Logical_Operators),
              "mixing was reported as something else");

      --  Parenthesized, it is fine.
      Parse ("(A and B) or C", Tree, Report, Expression => True);
      Assert (Report.Count = 0,
              "parenthesized mixing was refused anyway");

      --  Repeating one operator is fine.
      Parse ("A and B and C", Tree, Report, Expression => True);
      Assert (Report.Count = 0, "repeating and was refused");

      --  And a short circuit belongs to the same family as its plain form.
      Parse ("A and then B and C", Tree, Report, Expression => True);
      Assert (Report.Count = 0,
              "and then was treated as a different operator from and");
   end Mixing_And_With_Or_Is_Refused;

   procedure Short_Circuits_Are_Their_Own_Operators
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Tree   : S.Tree;
      Report : D.List;
   begin
      --  `and then` short-circuits and `and` does not, which is a difference
      --  in meaning. Recording it as a flag on `and` would let a later pass
      --  forget to look.
      Parse ("A and then B", Tree, Report, Expression => True);
      Assert (Report.Count = 0, "and then was rejected");
      Assert (S.Operator (Tree, Expression_Root (Tree)) = S.Op_And_Then,
              "and then did not produce its own operator");

      Parse ("A or else B", Tree, Report, Expression => True);
      Assert (S.Operator (Tree, Expression_Root (Tree)) = S.Op_Or_Else,
              "or else did not produce its own operator");

      Parse ("A and B", Tree, Report, Expression => True);
      Assert (S.Operator (Tree, Expression_Root (Tree)) = S.Op_And,
              "plain and was confused with and then");
   end Short_Circuits_Are_Their_Own_Operators;

   ------------------------------------------------------------------
   --  Statements
   ------------------------------------------------------------------

   procedure Statements_Parse_To_Their_Shapes
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Tree   : S.Tree;
      Report : D.List;
   begin
      Parse ("X := 1; Y; null; return;", Tree, Report);
      Assert (Report.Count = 0, "well formed statements produced diagnostics");
      Assert (S.Child_Count (Tree, S.Root (Tree)) = 4,
              "the sequence did not hold four statements; got"
              & Natural'Image (S.Child_Count (Tree, S.Root (Tree))));

      Assert (S.Kind (Tree, Statement (Tree, 1)) = S.Node_Assignment,
              "an assignment did not parse as one");
      --  A name followed by a semicolon is a call, not an assignment. Which it
      --  is depends on what follows, never on what the name means -- the
      --  parser does not know that.
      Assert (S.Kind (Tree, Statement (Tree, 2)) = S.Node_Procedure_Call,
              "a bare name did not parse as a procedure call");
      Assert (S.Kind (Tree, Statement (Tree, 3)) = S.Node_Null_Statement,
              "null did not parse as a null statement");
      Assert (S.Kind (Tree, Statement (Tree, 4)) = S.Node_Return,
              "return did not parse as a return");
   end Statements_Parse_To_Their_Shapes;

   procedure Declarations_Record_Their_Parts
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Tree   : S.Tree;
      Report : D.List;
   begin
      Parse ("Count : Integer := 0; Limit : constant Integer := 10;", Tree, Report);
      Assert (Report.Count = 0, "declarations produced diagnostics");

      declare
         First : constant S.Node_Id := Statement (Tree, 1);
      begin
         Assert (S.Kind (Tree, First) = S.Node_Object_Declaration,
                 "a declaration did not parse as one");
         Assert (S.Text (Tree, S.First (Tree, First)) = "Count",
                 "the declared name was lost");
         Assert (S.Text (Tree, S.Second (Tree, First)) = "Integer",
                 "the type name was lost");
         Assert (S.Text (Tree, S.Third (Tree, First)) = "0",
                 "the initial value was lost");
         Assert (S.Text (Tree, First) = "", "a variable was marked constant");
      end;

      Assert (S.Text (Tree, Statement (Tree, 2)) = "constant",
              "a constant was not marked as one");
   end Declarations_Record_Their_Parts;

   procedure Control_Structures_Nest
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Tree   : S.Tree;
      Report : D.List;
   begin
      Parse ("if A then X := 1; else X := 2; end if;", Tree, Report);
      Assert (Report.Count = 0, "an if statement produced diagnostics");

      declare
         Node : constant S.Node_Id := Statement (Tree, 1);
      begin
         Assert (S.Kind (Tree, Node) = S.Node_If, "if did not parse as an if");
         Assert (S.Child_Count (Tree, Node) = 3,
                 "an if with an else did not keep three parts");
         Assert (S.Kind (Tree, S.Second (Tree, Node)) = S.Node_Sequence,
                 "the then part is not a sequence");
      end;

      --  An elsif is an if in the else part, so every later pass has one shape
      --  to handle rather than a chain with its own rules.
      Parse ("if A then null; elsif B then null; else null; end if;", Tree, Report);
      Assert (Report.Count = 0, "an elsif produced diagnostics");
      Assert (S.Kind (Tree, S.Third (Tree, Statement (Tree, 1))) = S.Node_If,
              "an elsif did not become a nested if");

      Parse ("while A loop X := X + 1; end loop;", Tree, Report);
      Assert (Report.Count = 0, "a while loop produced diagnostics");
      Assert (S.Kind (Tree, Statement (Tree, 1)) = S.Node_While_Loop,
              "while did not parse as a while loop");

      Parse ("for I in 1 .. 10 loop null; end loop;", Tree, Report);
      Assert (Report.Count = 0, "a for loop produced diagnostics");
      Assert (S.Kind (Tree, Statement (Tree, 1)) = S.Node_For_Loop,
              "for did not parse as a for loop");
      Assert (S.Child_Count (Tree, Statement (Tree, 1)) = 4,
              "a for loop did not keep variable, bounds and body");

      Parse ("loop exit when A; end loop;", Tree, Report);
      Assert (Report.Count = 0, "a bare loop produced diagnostics");
      Assert (S.Kind (Tree, Statement (Tree, 1)) = S.Node_Loop,
              "a bare loop did not parse as one");
   end Control_Structures_Nest;

   procedure Calls_And_Attributes_Chain
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Tree   : S.Tree;
      Report : D.List;
   begin
      Parse ("F (1, 2)", Tree, Report, Expression => True);
      Assert (Report.Count = 0, "a call produced diagnostics");

      declare
         Root : constant S.Node_Id := Expression_Root (Tree);
      begin
         --  Whether this denotes a function or an array is a semantic
         --  question: Ada spells both the same way, and a parser that guessed
         --  would be doing name resolution.
         Assert (S.Kind (Tree, Root) = S.Node_Call, "a call did not parse as one");
         Assert (S.Child_Count (Tree, S.Second (Tree, Root)) = 2,
                 "the argument list did not hold two arguments");
      end;

      Parse ("X'Image", Tree, Report, Expression => True);
      Assert (Report.Count = 0, "an attribute produced diagnostics");
      Assert (S.Kind (Tree, Expression_Root (Tree)) = S.Node_Attribute,
              "an attribute did not parse as one");

      --  Both, in either order: X'Image (1) and X (1)'Image are legal Ada.
      Parse ("X (1)'Image", Tree, Report, Expression => True);
      Assert (Report.Count = 0, "a call followed by an attribute was rejected");
      Assert (S.Kind (Tree, Expression_Root (Tree)) = S.Node_Attribute,
              "the attribute did not end up outermost");
   end Calls_And_Attributes_Chain;

   ------------------------------------------------------------------
   --  Recovery, spans, and the walkability contract
   ------------------------------------------------------------------

   procedure Parsing_Recovers_And_Marks_The_Tree
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Tree   : S.Tree;
      Report : D.List;
   begin
      --  One missing semicolon must not produce a diagnostic per token after
      --  it. Recovery skips to something that reliably starts a statement.
      Parse ("X := 1 Y := 2; Z := 3;", Tree, Report);
      Assert (Report.Count > 0, "a missing semicolon was not reported");
      Assert (Report.Count <= 3,
              "one missing semicolon produced a cascade of"
              & Natural'Image (Report.Count) & " diagnostics");

      --  The tree stays walkable -- a highlighter still wants it -- and says
      --  it must not be evaluated.
      --
      --  Both, not either. This asked for `Has_Errors or else Has_Blocking`,
      --  and a recovered parse satisfied it on the report alone while leaving
      --  the tree unmarked -- which is what let `put_line ("a") put_line ("b")`
      --  print both lines and report success. An error node is what the engine
      --  stops on, so an error node is what this asks for.
      Assert (S.Has_Errors (Tree),
              "a repaired parse left no error node in the tree");
      Assert (Report.Has_Blocking,
              "a repaired parse reported nothing that blocks");
      Assert (S.Node_Count (Tree) > 0, "a failed parse produced no tree at all");

      --  A call is the shape that exposed this. An assignment missing its
      --  semicolon already left an error node by another path, so the
      --  assertion above held whichever way `Complain` behaved and the hole
      --  survived under a test that looked like it covered it.
      Parse ("put_line (""a"") put_line (""b"");", Tree, Report);
      Assert (S.Has_Errors (Tree),
              "two calls with no semicolon between them parsed as clean");

      --  A clean parse says so.
      Parse ("X := 1;", Tree, Report);
      Assert (not S.Has_Errors (Tree), "a clean parse was marked as failed");
      Assert (not Report.Has_Blocking, "a clean parse reported a blocking problem");
   end Parsing_Recovers_And_Marks_The_Tree;

   procedure Nodes_Carry_Their_Extents
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Tree   : S.Tree;
      Report : D.List;
   begin
      Parse ("alpha + beta", Tree, Report, Expression => True);

      declare
         Root  : constant S.Node_Id := Expression_Root (Tree);
         Left  : constant S.Node_Id := S.First (Tree, Root);
         Right : constant S.Node_Id := S.Second (Tree, Root);
      begin
         Assert (S.Extent (Tree, Left).First = 1, "the left operand's extent is wrong");
         Assert (S.Extent (Tree, Right).First = 9,
                 "the right operand's extent is wrong; got"
                 & Natural'Image (S.Extent (Tree, Right).First));

         --  A parent covers its children, which is what lets a diagnostic
         --  point at a whole construct and a formatter reproduce one.
         Assert (S.Extent (Tree, Root).First <= S.Extent (Tree, Left).First
                 and then S.Extent (Tree, Root).Last >= S.Extent (Tree, Right).Last,
                 "a parent's extent does not cover its children");
      end;
   end Nodes_Carry_Their_Extents;

   procedure A_Graft_Copies_And_Renames
     (Test : in out AUnit.Test_Cases.Test_Case'Class);

   procedure A_Tree_Is_Reused_Not_Accumulated
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Tree   : S.Tree;
      Report : D.List;
      First_Size : Natural;
   begin
      --  One tree, many parses: what an interactive session does, a line at a
      --  time. A parser that appended would grow the tree without bound and
      --  leave the previous line's nodes reachable.
      Parse ("X := 1;", Tree, Report);
      First_Size := S.Node_Count (Tree);
      Assert (First_Size > 0, "the first parse produced nothing");

      Parse ("Y := 2;", Tree, Report);
      Assert (S.Node_Count (Tree) = First_Size,
              "parsing again grew the tree instead of replacing it:"
              & Natural'Image (First_Size) & " then"
              & Natural'Image (S.Node_Count (Tree)));
      Assert (S.Text (Tree, S.First (Tree, Statement (Tree, 1))) = "Y",
              "the second parse did not replace the first");
   end A_Tree_Is_Reused_Not_Accumulated;

   ----------
   -- Name --
   ----------

   procedure A_Statement_Spans_Only_Itself
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);

      --  One of every construct that ends in a terminator: a declaration, an
      --  assignment, a call, two compound statements and a subprogram body.
      Pieces : constant array (1 .. 7) of Ada.Strings.Unbounded.Unbounded_String
        := [Ada.Strings.Unbounded.To_Unbounded_String ("X : Integer := 1;"),
            Ada.Strings.Unbounded.To_Unbounded_String ("X := 2;"),
            Ada.Strings.Unbounded.To_Unbounded_String ("put_line (X);"),
            Ada.Strings.Unbounded.To_Unbounded_String
              ("if X = 2 then put_line (""y""); end if;"),
            Ada.Strings.Unbounded.To_Unbounded_String
              ("while X > 9 loop X := X + 1; end loop;"),
            Ada.Strings.Unbounded.To_Unbounded_String
              ("for I in 1 .. 2 loop null; end loop;"),
            Ada.Strings.Unbounded.To_Unbounded_String
              ("procedure P is begin null; end P;")];

      function Sample return String is
         Text : Ada.Strings.Unbounded.Unbounded_String;
      begin
         for Index in Pieces'Range loop
            if Index > Pieces'First then
               Ada.Strings.Unbounded.Append (Text, " ");
            end if;

            Ada.Strings.Unbounded.Append (Text, Pieces (Index));
         end loop;

         return Ada.Strings.Unbounded.To_String (Text);
      end Sample;

      Buffer : Src.Buffer;
      Stream : Adash.Language.Tokens.Token_Stream;
      Tree   : S.Tree;
      Report : D.List;
      Error  : Adash.Errors.Error_Info;
      Origin : constant Src.Origin :=
        Src.Make_Origin (Src.Origin_Text, "<extent>");
   begin
      Assert (Src.Load (Buffer, Origin, Sample, Error),
              "the source did not load");
      Adash.Language.Lexer.Scan (Buffer, Stream, Report);
      P.Parse (Stream, Origin, Tree, Report);

      Assert (Report.Count = 0, "the sample did not parse cleanly");
      Assert (S.Child_Count (Tree, S.Root (Tree)) = Pieces'Length,
              "the sample did not produce"
              & Natural'Image (Pieces'Length) & " statements");

      --  A statement's extent used to end at the token that comes *next*, so
      --  every slice below carried the beginning of the statement after it.
      --  Harmless while a span was only pointed at; not harmless the moment the
      --  source under one is read back, which is what carrying a declaration
      --  from one submission to the next does.
      for Index in Pieces'Range loop
         declare
            Node  : constant S.Node_Id := S.Child (Tree, S.Root (Tree), Index);
            Slice : constant String := Src.Slice (Buffer, S.Extent (Tree, Node));
         begin
            Assert (Slice = Ada.Strings.Unbounded.To_String (Pieces (Index)),
                    "statement" & Natural'Image (Index) & " spans [" & Slice
                    & "] rather than ["
                    & Ada.Strings.Unbounded.To_String (Pieces (Index)) & "]");
         end;
      end loop;
   end A_Statement_Spans_Only_Itself;

   overriding function Name (T : Case_Type) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Adash.Language.Parser");
   end Name;

   --------------------
   -- Register_Tests --
   --------------------

   --  What a generic instantiation is made of.
   procedure A_Graft_Copies_And_Renames
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);

      Tree   : S.Tree;
      Report : Adash.Diagnostics.List;

      use type S.Node_Id;
   begin
      Parse ("X + Y", Tree, Report, Expression => True);

      declare
         Before : constant Natural := S.Node_Count (Tree);

         Bindings : constant S.Renamings :=
           [1 => (From => Ada.Strings.Unbounded.To_Unbounded_String ("X"),
                  To   => Ada.Strings.Unbounded.To_Unbounded_String ("Z"))];

         Copy : constant S.Node_Id :=
           S.Graft (Tree, S.Root (Tree), Bindings);
      begin
         --  Fresh nodes, which is the whole point: conclusions are recorded
         --  per node, and two instantiations of one generic sharing nodes
         --  would overwrite each other's answers about every name in it.
         Assert (Copy /= S.Root (Tree), "a graft returned the original");
         Assert (S.Node_Count (Tree) > Before,
                 "a graft added no nodes to the tree");

         Assert (S.Kind (Tree, Copy) = S.Kind (Tree, S.Root (Tree)),
                 "a graft changed the shape of what it copied");
         Assert (S.Child_Count (Tree, Copy)
                 = S.Child_Count (Tree, S.Root (Tree)),
                 "a graft lost a child");

         --  The binding applies to names and to nothing else, and the
         --  original is untouched.
         Assert (S.Text (Tree, S.First (Tree, Copy)) = "Z",
                 "a graft did not bind the name it was given");
         Assert (S.Text (Tree, S.Second (Tree, Copy)) = "Y",
                 "a graft bound a name it was not given");
         Assert (S.Text (Tree, S.First (Tree, S.Root (Tree))) = "X",
                 "a graft changed the subtree it copied");

         --  The spans are the original's, so a diagnostic about an
         --  instantiation points at the generic's own source -- which is where
         --  the reader has to look.
         Assert (S.Extent (Tree, S.First (Tree, Copy)).First
                 = S.Extent (Tree, S.First (Tree, S.Root (Tree))).First,
                 "a graft moved the span of what it copied");
      end;
   end A_Graft_Copies_And_Renames;

   overriding procedure Register_Tests (T : in out Case_Type) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, A_Statement_Spans_Only_Itself'Access,
         "a statement's extent covers itself and not the token after it");
      Register_Routine
        (T, Precedence_Follows_Ada'Access,
         "parser : precedence follows Ada");
      Register_Routine
        (T, Arithmetic_Is_Left_Associative'Access,
         "parser : arithmetic is left-associative");
      Register_Routine
        (T, Parentheses_Are_Kept'Access,
         "parser : parentheses group and are kept in the tree");
      Register_Routine
        (T, Mixing_And_With_Or_Is_Refused'Access,
         "parser : mixing and with or without parentheses is refused");
      Register_Routine
        (T, Short_Circuits_Are_Their_Own_Operators'Access,
         "parser : short circuits are their own operators");
      Register_Routine
        (T, Statements_Parse_To_Their_Shapes'Access,
         "parser : statements parse to their shapes");
      Register_Routine
        (T, Declarations_Record_Their_Parts'Access,
         "parser : declarations record name, type, value and constancy");
      Register_Routine
        (T, Control_Structures_Nest'Access,
         "parser : control structures nest, and elsif becomes a nested if");
      Register_Routine
        (T, Calls_And_Attributes_Chain'Access,
         "parser : calls and attributes chain in either order");
      Register_Routine
        (T, Parsing_Recovers_And_Marks_The_Tree'Access,
         "parser : parsing recovers without a cascade and marks the tree");
      Register_Routine
        (T, Nodes_Carry_Their_Extents'Access,
         "parser : nodes carry extents and parents cover their children");
      Register_Routine
        (T, A_Tree_Is_Reused_Not_Accumulated'Access,
         "parser : a tree is replaced by a second parse, not appended to");
      Register_Routine
        (T, A_Graft_Copies_And_Renames'Access,
         "syntax : a graft copies a subtree and binds names in the copy");
   end Register_Tests;

end Adash_Tests.Parser_Cases;
