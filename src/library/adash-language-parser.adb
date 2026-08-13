with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;

with Adash.Errors;
with Adash.Messages;

package body Adash.Language.Parser is

   package T renames Adash.Language.Tokens;
   package S renames Adash.Language.Syntax;
   package D renames Adash.Diagnostics;

   use type Adash.Messages.Message_Id;

   use type T.Token_Kind;
   use type T.Reserved_Word;
   use type T.Delimiter;
   use type S.Node_Id;
   use type S.Operation;

   package Token_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => T.Token,
      "="          => T."=");

   --  One parse. A record rather than package state, so two parses cannot
   --  interfere and a test can run them in any order.
   type Parse_State is limited record
      Items    : Token_Vectors.Vector;
      Position : Positive := 1;
      Origin   : Adash.Source.Origin;

      --  True when a rule wanted a token and the input had ended. What tells
      --  an unfinished submission from a wrong one: `if C then` ran out, and
      --  `if C than` met something it did not expect.
      Ran_Out  : Boolean := False;
   end record;

   ---------------------------------------------------------------------------

   procedure Run
     (From        : T.Token_Stream;
      Origin      : Adash.Source.Origin;
      Into        : out S.Tree;
      Report      : in out D.List;
      Expression  : Boolean;
      Unfinished  : out Boolean)
   is
      State : Parse_State;

      --  Forward declarations: the grammar is mutually recursive, so every
      --  level has to be visible to the others.
      function Parse_Expression_Rule return S.Node_Id;
      function Parse_Relation return S.Node_Id;
      function Parse_Simple_Expression return S.Node_Id;
      function Parse_Term return S.Node_Id;
      function Parse_Factor return S.Node_Id;
      function Parse_Primary return S.Node_Id;

      --  `X'Range` written where a range is expected, as the two ends it
      --  stands for. Declared here because the expression parser reads a
      --  membership's bounds before the body below is reached.
      function Expanded_Range (Node : S.Node_Id) return S.Node_Id;
      function Parse_Interpolation return S.Node_Id;
      function Parse_Statement return S.Node_Id;
      function Parse_Sequence (Stop_Words : T.Reserved_Word) return S.Node_Id;
      function Parse_Subprogram return S.Node_Id;
      function Parse_Instantiation return S.Node_Id;

      --  A formal parameter list, or No_Node when none is written.
      function Parse_Formals return S.Node_Id;

      --  A type name, which may be a package member and so may carry dots.
      --
      --  Returned as one Node_Name holding the whole spelling, because that is
      --  what a package member's name *is*: what a package holds is declared
      --  beside it under a dotted name, and `Config.Mode` resolves as one
      --  name rather than as a reach into something.
      --
      --  @param Ok False when what follows is not a type name at all.
      function Parse_Type_Mark (Ok : out Boolean) return S.Node_Id;
      function Parse_Choice return S.Node_Id;
      function Parse_Argument return S.Node_Id;
      function Parse_Handlers return S.Node_Id;

      ------------------------------------------------------------------
      --  Token access
      ------------------------------------------------------------------

      function Current return T.Token
      is (if State.Position <= Natural (State.Items.Length)
          then State.Items.Element (State.Position)
          else T.No_Token);

      function Ahead (Count : Positive := 1) return T.Token
      is (if State.Position + Count <= Natural (State.Items.Length)
          then State.Items.Element (State.Position + Count)
          else T.No_Token);

      function At_End return Boolean
      is (T.Kind (Current) = T.Token_End_Of_Input);

      procedure Advance is
      begin
         if State.Position <= Natural (State.Items.Length) then
            State.Position := State.Position + 1;
         end if;
      end Advance;

      function Here return Adash.Source.Span is (T.Extent (Current));

      --  The extent of the token just consumed.
      --
      --  `Here` is the token that comes *next*, so a construct whose span ends
      --  with Here reaches one token past itself. That is harmless where a span
      --  is only pointed at, and not harmless where the source under it is read
      --  back: a declaration kept for a later submission would carry the
      --  beginning of whatever followed it.
      function Just_Consumed return Adash.Source.Span
      is (if State.Position > 1
          then T.Extent (State.Items.Element (State.Position - 1))
          else Here);

      function Is_Word (Word : T.Reserved_Word) return Boolean
      is (T.Kind (Current) = T.Token_Reserved_Word and then T.Word (Current) = Word);

      function Is_Symbol (Symbol : T.Delimiter) return Boolean
      is (T.Kind (Current) = T.Token_Delimiter and then T.Symbol (Current) = Symbol);

      ------------------------------------------------------------------
      --  Diagnostics and recovery
      ------------------------------------------------------------------

      --  What was wanted, said one of the two ways it can be said.
      --
      --  A token has a spelling, which is Ada's own and goes in as an
      --  argument. A *kind* of thing -- an expression, a statement, a type
      --  name -- is prose a user reads, so it is a message and is quoted
      --  rather than written here.
      --
      --  Nothing where something was wanted is a different complaint from the
      --  wrong thing being there. `expected ; here` is what a user needs at
      --  the end of a line; `expected ;, found end of input` invents a token
      --  nobody typed and names it in English, in a file that may not hold
      --  one.
      procedure Complain
        (Expected : String;
         Named    : Adash.Messages.Message_Id := Adash.Messages.Msg_Error_None);

      procedure Complain (Named : Adash.Messages.Message_Id);

      procedure Complain
        (Expected : String;
         Named    : Adash.Messages.Message_Id := Adash.Messages.Msg_Error_None)
      is
         Ended : constant Boolean := At_End;
      begin
         if Ended then
            State.Ran_Out := True;
         end if;

         Report.Emit
           (D.Make
              (Message   =>
                 Adash.Errors.Message
                   (if Ended then Adash.Errors.Error_Syntax_Missing
                    else Adash.Errors.Error_Syntax_Unexpected),
               Level     => D.Severity_Error,
               Of_Kind   => D.Category_Syntax,
               Raised_By => D.Owner_Language,
               Origin    => State.Origin,
               Extent    => Here,
               --  The `expected` placeholder is filled once: from the quoted
               --  message when there is one, and from the token's spelling
               --  when there is not. Giving it both would pass two arguments
               --  of the same name and the renderer would take whichever came
               --  first.
               Arguments =>
                 (if Named /= Adash.Messages.Msg_Error_None
                  then (if Ended
                        then Adash.Messages.No_Arguments
                        else Adash.Messages.Argument_List'
                               (1 => Adash.Messages.Named
                                       ("found", T.Text (Current))))
                  elsif Ended
                  then Adash.Messages.Argument_List'
                         (1 => Adash.Messages.Named ("expected", Expected))
                  else [Adash.Messages.Named ("found", T.Text (Current)),
                        Adash.Messages.Named ("expected", Expected)]),
               Quoted    => Named,
               Fills     => "expected"));
      end Complain;

      procedure Complain (Named : Adash.Messages.Message_Id) is
      begin
         Complain ("", Named);
      end Complain;

      --  Skip to something that reliably starts a new construct. Reporting one
      --  problem per construct rather than one per token is what keeps a
      --  single missing semicolon from producing forty diagnostics.
      procedure Recover is
      begin
         while not At_End loop
            exit when Is_Symbol (T.Delim_Semicolon);
            exit when Is_Word (T.Word_End)
              or else Is_Word (T.Word_Then) or else Is_Word (T.Word_Loop)
              or else Is_Word (T.Word_Else) or else Is_Word (T.Word_Elsif)
              or else Is_Word (T.Word_Begin);
            Advance;
         end loop;

         if Is_Symbol (T.Delim_Semicolon) then
            Advance;
         end if;
      end Recover;

      function Error_Node (Extent : Adash.Source.Span) return S.Node_Id is
      begin
         return S.Add_Leaf (Into, S.Node_Error, Extent);
      end Error_Node;

      --  Consume an expected token, or report and carry on without it. Not
      --  consuming on failure is deliberate: the caller's recovery decides
      --  where to resume, and swallowing a token here would take away the
      --  evidence it needs.
      function Expect_Symbol (Symbol : T.Delimiter) return Boolean is
      begin
         if Is_Symbol (Symbol) then
            Advance;
            return True;
         end if;

         Complain (T.Spelling (Symbol));
         return False;
      end Expect_Symbol;

      function Expect_Word (Word : T.Reserved_Word) return Boolean is
      begin
         if Is_Word (Word) then
            Advance;
            return True;
         end if;

         Complain (T.Spelling (Word));
         return False;
      end Expect_Word;

      ------------------------------------------------------------------
      --  Expressions
      ------------------------------------------------------------------

      ---------------------------
      -- Parse_Interpolation --
      ---------------------------

      --  f"a{X}b" becomes ("a" & X) & "b".
      --
      --  Rewritten here rather than carried as a node of its own, because that
      --  is exactly what it means and every rule that would have to learn about
      --  a new node already knows about `&`. The type rule falls out too: `&`
      --  joins two Strings, which is what Ada 2022 requires of an interpolated
      --  expression, so `f"n{Count}"` is refused for the same reason and with
      --  the same message as `"n" & Count`.
      --
      --  Empty pieces are dropped. They arise constantly -- `f"{X}"` has two --
      --  and concatenating them would be work the program does not need and a
      --  tree a reader has to look past.
      function Parse_Interpolation return S.Node_Id is
         Start  : constant Adash.Source.Span := Here;
         Result : S.Node_Id := S.No_Node;

         procedure Join (Piece : S.Node_Id);

         procedure Join (Piece : S.Node_Id) is
         begin
            if not S.Is_Present (Piece) then
               return;
            end if;

            if S.Is_Present (Result) then
               Result := S.Add_Node
                 (Into, S.Node_Binary_Operation,
                  Adash.Source.Join (Start, Just_Consumed), [Result, Piece],
                  Operator => S.Op_Concat);
            else
               Result := Piece;
            end if;
         end Join;

         --  A literal piece, or nothing when it is empty.
         function Text_Piece return S.Node_Id is
         begin
            if T.Value (Current) = "" then
               return S.No_Node;
            end if;

            return S.Add_Leaf
              (Into, S.Node_String_Literal, Here, T.Value (Current));
         end Text_Piece;
      begin
         Join (Text_Piece);
         Advance;  --  the opening piece

         while not At_End
           and then T.Kind (Current) /= T.Token_Interpolation_End
         loop
            Join (Parse_Expression_Rule);

            if T.Kind (Current) /= T.Token_Interpolation_Chunk then
               --  The lexer emits a chunk after every expression, so this
               --  means the expression stopped early -- an unbalanced brace,
               --  or something that is not an expression at all.
               Complain (Adash.Messages.Msg_Expected_Interpolation_Rest);
               Recover;
               return Error_Node (Adash.Source.Join (Start, Just_Consumed));
            end if;

            Join (Text_Piece);
            Advance;
         end loop;

         if T.Kind (Current) = T.Token_Interpolation_End then
            Advance;
         end if;

         if not S.Is_Present (Result) then
            --  `f""`, and `f"{}"` once its empty pieces are gone. Still a
            --  String, and still the empty one.
            return S.Add_Leaf
              (Into, S.Node_String_Literal,
               Adash.Source.Join (Start, Just_Consumed), "");
         end if;

         return Result;
      end Parse_Interpolation;

      --  primary ::= literal | name | (expression) | name (arguments)
      --            | name'attribute
      function Parse_Primary return S.Node_Id is
         Start : constant Adash.Source.Span := Here;
      begin
         case T.Kind (Current) is
            when T.Token_Interpolation_Start =>
               return Parse_Interpolation;

            when T.Token_Integer_Literal =>
               declare
                  Node : constant S.Node_Id :=
                    S.Add_Leaf (Into, S.Node_Integer_Literal, Start, T.Value (Current));
               begin
                  Advance;
                  return Node;
               end;

            when T.Token_Real_Literal =>
               declare
                  Node : constant S.Node_Id :=
                    S.Add_Leaf (Into, S.Node_Real_Literal, Start, T.Value (Current));
               begin
                  Advance;
                  return Node;
               end;

            when T.Token_Character_Literal =>
               declare
                  Node : constant S.Node_Id :=
                    S.Add_Leaf (Into, S.Node_Character_Literal, Start, T.Value (Current));
               begin
                  Advance;
                  return Node;
               end;

            when T.Token_String_Literal =>
               declare
                  Node : constant S.Node_Id :=
                    S.Add_Leaf (Into, S.Node_String_Literal, Start, T.Value (Current));
               begin
                  Advance;
                  return Node;
               end;

            when T.Token_Identifier =>
               declare
                  Node : S.Node_Id :=
                    S.Add_Leaf (Into, S.Node_Name, Start, T.Text (Current));
               begin
                  Advance;

                  --  A name may be followed by arguments or by an attribute,
                  --  and either may be followed by the other: X'Image (1) and
                  --  X (1)'Image are both legal. The loop is what allows that.
                  loop
                     if Is_Symbol (T.Delim_Left_Paren) then
                        Advance;

                        declare
                           Arguments : S.Node_Id;
                           Collected : S.Node_List (1 .. 64);
                           Count     : Natural := 0;
                        begin
                           if not Is_Symbol (T.Delim_Right_Paren) then
                              loop
                                 exit when Count = Collected'Last;
                                 Count := Count + 1;

                                 --  A range, because `S (1 .. 3)` is written
                                 --  the way a call is and only the semantic
                                 --  pass can tell them apart. The parser
                                 --  records what was written; deciding that a
                                 --  name followed by a range is a slice would
                                 --  be name resolution.
                                 Collected (Count) := Parse_Argument;
                                 exit when not Is_Symbol (T.Delim_Comma);
                                 Advance;
                              end loop;
                           end if;

                           Arguments := S.Add_Node
                             (Into, S.Node_Sequence, Start, Collected (1 .. Count));

                           if not Expect_Symbol (T.Delim_Right_Paren) then
                              --  `Here` rather than Just_Consumed: nothing was
                              --  consumed, so the token this is stuck on is the
                              --  one that is wrong, and the span should reach
                              --  it rather than stop before it.
                              return Error_Node
                                (Adash.Source.Join (Start, Here));
                           end if;

                           Node := S.Add_Node
                             (Into, S.Node_Call,
                              Adash.Source.Join (Start, T.Extent (Current)),
                              [Node, Arguments]);
                        end;

                     elsif Is_Symbol (T.Delim_Dot) then
                        --  `R.Field`. The name on the right means nothing
                        --  outside the type on the left, so the parser records
                        --  it and the semantic pass decides what it denotes.
                        Advance;

                        if T.Kind (Current) /= T.Token_Identifier then
                           Complain (Adash.Messages.Msg_Expected_Component_Name);
                           return Error_Node (Adash.Source.Join (Start, Here));
                        end if;

                        declare
                           Field : constant S.Node_Id :=
                             S.Add_Leaf (Into, S.Node_Name, Here,
                                         T.Text (Current));
                        begin
                           Advance;
                           Node := S.Add_Node
                             (Into, S.Node_Selected,
                              Adash.Source.Join (Start, Just_Consumed),
                              [Node, Field]);
                        end;

                     elsif Is_Symbol (T.Delim_Apostrophe) then
                        Advance;

                        --  `X'Range` is the one attribute whose name is a
                        --  reserved word, so the token is a word where every
                        --  other is an identifier. Read as the name it is.
                        if T.Kind (Current) /= T.Token_Identifier
                          and then not Is_Word (T.Word_Range)
                        then
                           Complain (Adash.Messages.Msg_Expected_Attribute_Name);
                           return Error_Node (Adash.Source.Join (Start, Here));
                        end if;

                        declare
                           Attribute : constant S.Node_Id :=
                             S.Add_Leaf
                               (Into, S.Node_Name, Here,
                                (if Is_Word (T.Word_Range) then "Range"
                                 else T.Text (Current)));
                        begin
                           Node := S.Add_Node
                             (Into, S.Node_Attribute,
                              Adash.Source.Join (Start, Just_Consumed), [Node, Attribute]);
                           Advance;
                        end;

                     else
                        exit;
                     end if;
                  end loop;

                  return Node;
               end;

            when T.Token_Delimiter =>
               if T.Symbol (Current) = T.Delim_Left_Paren then
                  Advance;

                  declare
                     Collected : S.Node_List (1 .. 256);
                     Count     : Natural := 0;
                     Aggregate : Boolean := False;
                  begin
                     --  `(X)` groups; `(X, Y)` and `(A => X)` build a value.
                     --  One token of lookahead settles the named form and a
                     --  comma settles the positional one, so the two are told
                     --  apart by what is written rather than by what the
                     --  expression turns out to mean.
                     if T.Kind (Current) = T.Token_Identifier
                       and then T.Kind (Ahead) = T.Token_Delimiter
                       and then T.Symbol (Ahead) = T.Delim_Arrow
                     then
                        Aggregate := True;
                     end if;

                     --  `(others => 0)` is an aggregate from its first word,
                     --  and nothing else may begin with it.
                     if Is_Word (T.Word_Others) then
                        Aggregate := True;
                     end if;

                     loop
                        exit when Count = Collected'Last;
                        Count := Count + 1;

                        --  An array names its parts by index rather than by
                        --  name -- `(1 => 7)` -- and `others` names the rest
                        --  of them. Both are read as a choice and an arrow,
                        --  which is the shape a record's named part already
                        --  has, so what they build is the same node.
                        if Is_Word (T.Word_Others) then
                           declare
                              Where : constant Adash.Source.Span := Here;
                              Which : S.Node_Id;
                           begin
                              Advance;
                              Which := S.Add_Leaf (Into, S.Node_Others, Where);

                              if not Expect_Symbol (T.Delim_Arrow) then
                                 Recover;
                                 return Error_Node
                                   (Adash.Source.Join (Start, Here));
                              end if;

                              Aggregate := True;
                              Collected (Count) :=
                                S.Add_Node
                                  (Into, S.Node_Named_Argument,
                                   Adash.Source.Join (Where, Just_Consumed),
                                   [Which, Parse_Expression_Rule]);
                           end;

                        else
                           Collected (Count) := Parse_Argument;

                           --  A choice this parser read as an expression, and
                           --  an arrow after it: `1 => 7`. Rebuilt as the
                           --  named element it is.
                           if Is_Symbol (T.Delim_Arrow) then
                              Advance;
                              Aggregate := True;
                              Collected (Count) :=
                                S.Add_Node
                                  (Into, S.Node_Named_Argument,
                                   S.Extent (Into, Collected (Count)),
                                   [Collected (Count),
                                    Parse_Expression_Rule]);
                           end if;
                        end if;

                        exit when not Is_Symbol (T.Delim_Comma);
                        Advance;
                        Aggregate := True;
                     end loop;

                     if not Expect_Symbol (T.Delim_Right_Paren) then
                        return Error_Node (Adash.Source.Join (Start, Here));
                     end if;

                     if Aggregate then
                        return S.Add_Node
                          (Into, S.Node_Aggregate,
                           Adash.Source.Join (Start, Just_Consumed),
                           [1 => S.Add_Node
                                   (Into, S.Node_Sequence,
                                    Adash.Source.Join (Start, Just_Consumed),
                                    Collected (1 .. Count))]);
                     end if;

                     --  Kept rather than folded away: a formatter has to
                     --  reproduce it, and Ada's rule against mixing `and` with
                     --  `or` is stated in terms of parentheses.
                     return S.Add_Node
                       (Into, S.Node_Parenthesized,
                        Adash.Source.Join (Start, Just_Consumed),
                        [1 => Collected (1)]);
                  end;
               end if;

               Complain (Adash.Messages.Msg_Expected_Expression);
               return Error_Node (Start);

            when others =>
               Complain (Adash.Messages.Msg_Expected_Expression);
               return Error_Node (Start);
         end case;
      end Parse_Primary;

      --  factor ::= primary [** primary] | abs primary | not primary
      function Parse_Factor return S.Node_Id is
         Start : constant Adash.Source.Span := Here;
      begin
         if Is_Word (T.Word_Abs) or else Is_Word (T.Word_Not) then
            declare
               Op : constant S.Operation :=
                 (if Is_Word (T.Word_Abs) then S.Op_Abs else S.Op_Not);
            begin
               Advance;

               declare
                  Operand : constant S.Node_Id := Parse_Primary;
               begin
                  return S.Add_Node
                    (Into, S.Node_Unary_Operation,
                     Adash.Source.Join (Start, S.Extent (Into, Operand)),
                     [1 => Operand], Operator => Op);
               end;
            end;
         end if;

         declare
            Left : constant S.Node_Id := Parse_Primary;
         begin
            if Is_Symbol (T.Delim_Double_Star) then
               Advance;

               declare
                  Right : constant S.Node_Id := Parse_Primary;
               begin
                  return S.Add_Node
                    (Into, S.Node_Binary_Operation,
                     Adash.Source.Join (Start, S.Extent (Into, Right)),
                     [Left, Right], Operator => S.Op_Power);
               end;
            end if;

            return Left;
         end;
      end Parse_Factor;

      --  term ::= factor {multiplying_operator factor}
      function Parse_Term return S.Node_Id is
         Start : constant Adash.Source.Span := Here;
         Left  : S.Node_Id := Parse_Factor;
      begin
         loop
            declare
               Op : S.Operation := S.Op_None;
            begin
               if Is_Symbol (T.Delim_Star) then
                  Op := S.Op_Multiply;
               elsif Is_Symbol (T.Delim_Slash) then
                  Op := S.Op_Divide;
               elsif Is_Word (T.Word_Mod) then
                  Op := S.Op_Mod;
               elsif Is_Word (T.Word_Rem) then
                  Op := S.Op_Rem;
               end if;

               exit when Op = S.Op_None;
               Advance;

               declare
                  Right : constant S.Node_Id := Parse_Factor;
               begin
                  --  Left-associative, built as we go: a * b * c is
                  --  (a * b) * c, which is what Ada says and what matters the
                  --  moment division is involved.
                  Left := S.Add_Node
                    (Into, S.Node_Binary_Operation,
                     Adash.Source.Join (Start, S.Extent (Into, Right)),
                     [Left, Right], Operator => Op);
               end;
            end;
         end loop;

         return Left;
      end Parse_Term;

      --  simple_expression ::= [unary_adding] term {binary_adding term}
      function Parse_Simple_Expression return S.Node_Id is
         Start : constant Adash.Source.Span := Here;
         Left  : S.Node_Id;
      begin
         if Is_Symbol (T.Delim_Plus) or else Is_Symbol (T.Delim_Minus) then
            declare
               Op : constant S.Operation :=
                 (if Is_Symbol (T.Delim_Plus) then S.Op_Plus else S.Op_Minus);
            begin
               Advance;

               declare
                  Operand : constant S.Node_Id := Parse_Term;
               begin
                  Left := S.Add_Node
                    (Into, S.Node_Unary_Operation,
                     Adash.Source.Join (Start, S.Extent (Into, Operand)),
                     [1 => Operand], Operator => Op);
               end;
            end;
         else
            Left := Parse_Term;
         end if;

         loop
            declare
               Op : S.Operation := S.Op_None;
            begin
               if Is_Symbol (T.Delim_Plus) then
                  Op := S.Op_Add;
               elsif Is_Symbol (T.Delim_Minus) then
                  Op := S.Op_Subtract;
               elsif Is_Symbol (T.Delim_Ampersand) then
                  Op := S.Op_Concat;
               end if;

               exit when Op = S.Op_None;
               Advance;

               declare
                  Right : constant S.Node_Id := Parse_Term;
               begin
                  Left := S.Add_Node
                    (Into, S.Node_Binary_Operation,
                     Adash.Source.Join (Start, S.Extent (Into, Right)),
                     [Left, Right], Operator => Op);
               end;
            end;
         end loop;

         return Left;
      end Parse_Simple_Expression;

      --  relation ::= simple_expression [relational_operator simple_expression]
      --
      --  At most one: `a < b < c` is not Ada, and accepting it would give it a
      --  meaning C programmers expect and Ada does not have.
      function Parse_Relation return S.Node_Id is
         Start : constant Adash.Source.Span := Here;
         Left  : constant S.Node_Id := Parse_Simple_Expression;
         Op    : S.Operation := S.Op_None;
      begin
         if Is_Symbol (T.Delim_Equal) then
            Op := S.Op_Equal;
         elsif Is_Symbol (T.Delim_Not_Equal) then
            Op := S.Op_Not_Equal;
         elsif Is_Symbol (T.Delim_Less) then
            Op := S.Op_Less;
         elsif Is_Symbol (T.Delim_Less_Equal) then
            Op := S.Op_Less_Equal;
         elsif Is_Symbol (T.Delim_Greater) then
            Op := S.Op_Greater;
         elsif Is_Symbol (T.Delim_Greater_Equal) then
            Op := S.Op_Greater_Equal;
         end if;

         --  `V in L .. H` and `V not in L .. H`. Written like an operator and
         --  parsed here for that reason, but it takes three operands, so the
         --  node it builds is not a binary one.
         if Op = S.Op_None
           and then (Is_Word (T.Word_In)
                     or else (Is_Word (T.Word_Not)
                              and then T.Kind (Ahead) = T.Token_Reserved_Word
                              and then T.Word (Ahead) = T.Word_In))
         then
            declare
               Negated : constant Boolean := Is_Word (T.Word_Not);
               Low, High : S.Node_Id;
            begin
               if Negated then
                  Advance;
               end if;

               Advance;

               Low := Parse_Simple_Expression;

               --  `X in A'Range` says the two ends at once, so there is no
               --  `..` to find and the ends come out of what it stands for.
               declare
                  Spread : constant S.Node_Id := Expanded_Range (Low);
               begin
                  if S."=" (S.Kind (Into, Spread), S.Node_Range) then
                     return S.Add_Node
                       (Into, S.Node_Membership,
                        Adash.Source.Join (Start, Just_Consumed),
                        [Left, S.First (Into, Spread),
                         S.Second (Into, Spread)],
                        Operator =>
                          (if Negated then S.Op_Not_In else S.Op_In));
                  end if;
               end;

               if not Expect_Symbol (T.Delim_Double_Dot) then
                  return Error_Node
                    (Adash.Source.Join (Start, Just_Consumed));
               end if;

               High := Parse_Simple_Expression;

               return S.Add_Node
                 (Into, S.Node_Membership,
                  Adash.Source.Join (Start, S.Extent (Into, High)),
                  [Left, Low, High],
                  Operator => (if Negated then S.Op_Not_In else S.Op_In));
            end;
         end if;

         if Op = S.Op_None then
            return Left;
         end if;

         Advance;

         declare
            Right : constant S.Node_Id := Parse_Simple_Expression;
         begin
            return S.Add_Node
              (Into, S.Node_Binary_Operation,
               Adash.Source.Join (Start, S.Extent (Into, Right)),
               [Left, Right], Operator => Op);
         end;
      end Parse_Relation;

      --  expression ::= relation {logical_operator relation}
      --
      --  Ada forbids mixing `and` with `or` without parentheses, and this
      --  enforces it. The rule exists because the two have equal precedence in
      --  Ada, so `a or b and c` has no reading a user could rely on; every
      --  other language answers it with a precedence rule that half its users
      --  remember wrongly.
      function Parse_Expression_Rule return S.Node_Id is
         Start : constant Adash.Source.Span := Here;
         Left  : S.Node_Id := Parse_Relation;
         First_Op : S.Operation := S.Op_None;

         function Logical_Here return S.Operation is
         begin
            if Is_Word (T.Word_And) then
               return (if T.Kind (Ahead) = T.Token_Reserved_Word
                       and then T.Word (Ahead) = T.Word_Then
                       then S.Op_And_Then else S.Op_And);
            elsif Is_Word (T.Word_Or) then
               return (if T.Kind (Ahead) = T.Token_Reserved_Word
                       and then T.Word (Ahead) = T.Word_Else
                       then S.Op_Or_Else else S.Op_Or);
            elsif Is_Word (T.Word_Xor) then
               return S.Op_Xor;
            end if;

            return S.Op_None;
         end Logical_Here;

         --  `and` and `and then` are one family for the mixing rule, as are
         --  `or` and `or else`. Mixing those two *is* an error; mixing a short
         --  circuit with its plain form is not.
         function Family (Op : S.Operation) return Natural
         is (case Op is
                when S.Op_And | S.Op_And_Then => 1,
                when S.Op_Or | S.Op_Or_Else   => 2,
                when S.Op_Xor                 => 3,
                when others                   => 0);
      begin
         loop
            declare
               Op : constant S.Operation := Logical_Here;
            begin
               exit when Op = S.Op_None;

               if First_Op = S.Op_None then
                  First_Op := Op;
               elsif Family (Op) /= Family (First_Op) then
                  Report.Emit
                    (D.Make
                       (Message   => Adash.Errors.Message
                                       (Adash.Errors.Error_Syntax_Mixed_Logical_Operators),
                        Level     => D.Severity_Error,
                        Of_Kind   => D.Category_Syntax,
                        Raised_By => D.Owner_Language,
                        Origin    => State.Origin,
                        Extent    => Here,
                        Arguments =>
                          [Adash.Messages.Named ("first", S.Spelling (First_Op)),
                           Adash.Messages.Named ("second", S.Spelling (Op))]));

                  Advance;
                  return Error_Node (Adash.Source.Join (Start, Just_Consumed));
               end if;

               --  Consume the word, and the second word of a short circuit.
               Advance;

               if Op = S.Op_And_Then or else Op = S.Op_Or_Else then
                  Advance;
               end if;

               declare
                  Right : constant S.Node_Id := Parse_Relation;
               begin
                  Left := S.Add_Node
                    (Into, S.Node_Binary_Operation,
                     Adash.Source.Join (Start, S.Extent (Into, Right)),
                     [Left, Right], Operator => Op);
               end;
            end;
         end loop;

         return Left;
      end Parse_Expression_Rule;

      ------------------------------------------------------------------
      --  Statements
      ------------------------------------------------------------------

      --  `X'Range` written where a range is expected, as the two ends it
      --  stands for.
      --
      --  Ada defines it as `X'First .. X'Last` and this builds exactly that,
      --  so everything downstream -- a loop, a membership, a case choice, an
      --  aggregate's index -- sees the range it already knows how to read.
      --  Anything else is handed back untouched.
      --
      --  @param Node What was just parsed.
      --  @return The range it stands for, or Node itself.
      function Expanded_Range (Node : S.Node_Id) return S.Node_Id is
      begin
         if not S.Is_Present (Node)
           or else not S."=" (S.Kind (Into, Node), S.Node_Attribute)
           or else S.Text (Into, S.Second (Into, Node)) /= "Range"
         then
            return Node;
         end if;

         declare
            Where  : constant Adash.Source.Span := S.Extent (Into, Node);
            Prefix : constant S.Node_Id := S.First (Into, Node);
         begin
            return S.Add_Node
              (Into, S.Node_Range, Where,
               [S.Add_Node
                  (Into, S.Node_Attribute, Where,
                   [Prefix, S.Add_Leaf (Into, S.Node_Name, Where, "First")]),
                S.Add_Node
                  (Into, S.Node_Attribute, Where,
                   [Prefix, S.Add_Leaf (Into, S.Node_Name, Where, "Last")])]);
         end;
      end Expanded_Range;

      function Parse_Statement return S.Node_Id is
         Start : constant Adash.Source.Span := Here;
      begin
         --  null;
         if Is_Word (T.Word_Null) then
            Advance;

            declare
               Ignored : constant Boolean := Expect_Symbol (T.Delim_Semicolon);
               pragma Unreferenced (Ignored);
            begin
               return S.Add_Leaf (Into, S.Node_Null_Statement, Start);
            end;
         end if;

         --  raise [name];
         if Is_Word (T.Word_Raise) then
            Advance;

            declare
               What : S.Node_Id := S.No_Node;
            begin
               --  A name and nothing else: an exception is a name, so there is
               --  no expression to parse and nothing an expression would add.
               if T.Kind (Current) = T.Token_Identifier then
                  What := S.Add_Leaf (Into, S.Node_Name, Here, T.Text (Current));
                  Advance;
               end if;

               declare
                  Ignored : constant Boolean :=
                    Expect_Symbol (T.Delim_Semicolon);
                  pragma Unreferenced (Ignored);
               begin
                  return S.Add_Node
                    (Into, S.Node_Raise,
                     Adash.Source.Join (Start, Just_Consumed),
                     [1 => What]);
               end;
            end;
         end if;

         --  terminate;  -- only ever an alternative of a selective accept,
         --  which is where the analyser holds it to.
         if Is_Word (T.Word_Terminate) then
            Advance;

            declare
               Ignored : constant Boolean := Expect_Symbol (T.Delim_Semicolon);
               pragma Unreferenced (Ignored);
            begin
               return S.Add_Leaf (Into, S.Node_Terminate, Start);
            end;
         end if;

         --  return [expression];
         if Is_Word (T.Word_Return) then
            Advance;

            if Is_Symbol (T.Delim_Semicolon) then
               Advance;
               return S.Add_Leaf (Into, S.Node_Return, Start);
            end if;

            declare
               Value   : constant S.Node_Id := Parse_Expression_Rule;
               Ignored : constant Boolean := Expect_Symbol (T.Delim_Semicolon);
               pragma Unreferenced (Ignored);
            begin
               return S.Add_Node
                 (Into, S.Node_Return, Adash.Source.Join (Start, Just_Consumed), [1 => Value]);
            end;
         end if;

         --  exit [when condition];
         if Is_Word (T.Word_Exit) then
            Advance;

            if Is_Word (T.Word_When) then
               Advance;

               declare
                  Condition : constant S.Node_Id := Parse_Expression_Rule;
                  Ignored   : constant Boolean := Expect_Symbol (T.Delim_Semicolon);
                  pragma Unreferenced (Ignored);
               begin
                  return S.Add_Node
                    (Into, S.Node_Exit, Adash.Source.Join (Start, Just_Consumed),
                     [1 => Condition]);
               end;
            end if;

            declare
               Ignored : constant Boolean := Expect_Symbol (T.Delim_Semicolon);
               pragma Unreferenced (Ignored);
            begin
               return S.Add_Leaf (Into, S.Node_Exit, Start);
            end;
         end if;

         --  declare <declarations> begin <statements> end;
         --
         --  The `declare` is optional, as in Ada: a block that declares
         --  nothing is written `begin ... end;`.
         if Is_Word (T.Word_Declare) or else Is_Word (T.Word_Begin) then
            declare
               Declares : constant Boolean := Is_Word (T.Word_Declare);
               Declared : S.Node_Id := S.No_Node;
               Doing    : S.Node_Id;
               Handled  : S.Node_Id;
            begin
               Advance;

               if Declares then
                  Declared := Parse_Sequence (T.Word_Begin);

                  if not Expect_Word (T.Word_Begin) then
                     Recover;
                     return Error_Node
                       (Adash.Source.Join (Start, Just_Consumed));
                  end if;
               else
                  Declared := S.Add_Node
                    (Into, S.Node_Sequence, Just_Consumed, []);
               end if;

               Doing := Parse_Sequence (T.Word_End);

               --  What it does about what went wrong. Ada puts the handlers
               --  after the statements and before the `end`, and each answers
               --  for the exceptions it names.
               if Is_Word (T.Word_Exception) then
                  Advance;
                  Handled := Parse_Handlers;
               else
                  Handled := S.Add_Node
                    (Into, S.Node_Sequence, Just_Consumed, []);
               end if;

               if not Expect_Word (T.Word_End) then
                  Recover;
                  return Error_Node (Adash.Source.Join (Start, Just_Consumed));
               end if;

               --  Ada lets a block repeat its own label here. There are no
               --  labels in this build, so a name after `end` is consumed and
               --  ignored rather than reported: refusing it would be refusing
               --  something the language does not have an opinion about yet.
               if T.Kind (Current) = T.Token_Identifier then
                  Advance;
               end if;

               declare
                  Ignored : constant Boolean :=
                    Expect_Symbol (T.Delim_Semicolon);
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;

               return S.Add_Node
                 (Into, S.Node_Block,
                  Adash.Source.Join (Start, Just_Consumed),
                  [Declared, Doing, Handled]);
            end;
         end if;

         --  case Expression is when ... => ... end case;
         if Is_Word (T.Word_Case) then
            Advance;

            declare
               Subject      : constant S.Node_Id := Parse_Expression_Rule;
               Alternatives : S.Node_List (1 .. 256);
               Count        : Natural := 0;
            begin
               if not Expect_Word (T.Word_Is) then
                  Recover;
                  return Error_Node (Adash.Source.Join (Start, Just_Consumed));
               end if;

               while Is_Word (T.Word_When)
                 and then Count < Alternatives'Last
               loop
                  Advance;

                  declare
                     Opened  : constant Adash.Source.Span := Just_Consumed;
                     Choices : S.Node_List (1 .. 64);
                     Chosen  : Natural := 0;
                  begin
                     loop
                        exit when Chosen = Choices'Last;
                        Chosen := Chosen + 1;
                        Choices (Chosen) := Parse_Choice;
                        exit when not Is_Symbol (T.Delim_Bar);
                        Advance;
                     end loop;

                     if not Expect_Symbol (T.Delim_Arrow) then
                        Recover;
                        return Error_Node
                          (Adash.Source.Join (Start, Just_Consumed));
                     end if;

                     declare
                        Listed : constant S.Node_Id :=
                          S.Add_Node
                            (Into, S.Node_Sequence,
                             Adash.Source.Join (Opened, Just_Consumed),
                             Choices (1 .. Chosen));

                        Statements : constant S.Node_Id :=
                          Parse_Sequence (T.Word_End);
                     begin
                        Count := Count + 1;
                        Alternatives (Count) :=
                          S.Add_Node
                            (Into, S.Node_Case_Alternative,
                             Adash.Source.Join (Opened, Just_Consumed),
                             [Listed, Statements]);
                     end;
                  end;
               end loop;

               --  Required rather than accepted-if-present: without the
               --  `end`, `case X is` on its own parses as a case with no
               --  alternatives, and the reader is told it does not cover every
               --  value of Integer -- which is true, and is not what is wrong
               --  with it.
               if not Expect_Word (T.Word_End) then
                  Recover;
                  return Error_Node (Adash.Source.Join (Start, Just_Consumed));
               end if;

               if Is_Word (T.Word_Case) then
                  Advance;
               end if;

               declare
                  Ignored : constant Boolean :=
                    Expect_Symbol (T.Delim_Semicolon);
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;

               return S.Add_Node
                 (Into, S.Node_Case,
                  Adash.Source.Join (Start, Just_Consumed),
                  [Subject,
                   S.Add_Node
                     (Into, S.Node_Sequence,
                      Adash.Source.Join (Start, Just_Consumed),
                      Alternatives (1 .. Count))]);
            end;
         end if;

         --  if condition then ... {elsif ...} [else ...] end if;
         if Is_Word (T.Word_If) then
            Advance;

            declare
               Condition : constant S.Node_Id := Parse_Expression_Rule;
               Then_Part : S.Node_Id;
               Else_Part : S.Node_Id := S.No_Node;
            begin
               if not Expect_Word (T.Word_Then) then
                  Recover;
                  return Error_Node (Adash.Source.Join (Start, Just_Consumed));
               end if;

               Then_Part := Parse_Sequence (T.Word_End);

               if Is_Word (T.Word_Elsif) then
                  --  An elsif is an if in the else part. Representing it that
                  --  way means every later pass has one shape to handle rather
                  --  than a chain with its own rules; the extents still say
                  --  where the user wrote what.
                  Else_Part := Parse_Statement;

                  return S.Add_Node
                    (Into, S.Node_If, Adash.Source.Join (Start, Just_Consumed),
                     [Condition, Then_Part, Else_Part]);
               end if;

               if Is_Word (T.Word_Else) then
                  Advance;
                  Else_Part := Parse_Sequence (T.Word_End);
               end if;

               --  Required rather than accepted-if-present. Without the
               --  `end`, an unfinished construct parses as a finished one with
               --  an empty body: `if C then` at the end of the input ran and
               --  did nothing, a `loop` became one that never stops, and an
               --  interactive session had no way to tell a line that is wrong
               --  from a line that is not over.
               if not Expect_Word (T.Word_End) then
                  Recover;
                  return Error_Node (Adash.Source.Join (Start, Just_Consumed));
               end if;

               if Is_Word (T.Word_If) then
                  Advance;
               end if;

               declare
                  Ignored : constant Boolean := Expect_Symbol (T.Delim_Semicolon);
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;

               if Else_Part = S.No_Node then
                  return S.Add_Node
                    (Into, S.Node_If, Adash.Source.Join (Start, Just_Consumed),
                     [Condition, Then_Part]);
               end if;

               return S.Add_Node
                 (Into, S.Node_If, Adash.Source.Join (Start, Just_Consumed),
                  [Condition, Then_Part, Else_Part]);
            end;
         end if;

         --  An elsif reached directly is the tail of an if, handled above.
         if Is_Word (T.Word_Elsif) then
            Advance;

            declare
               Condition : constant S.Node_Id := Parse_Expression_Rule;
               Then_Part : S.Node_Id;
               Else_Part : S.Node_Id := S.No_Node;
            begin
               if not Expect_Word (T.Word_Then) then
                  Recover;
                  return Error_Node (Adash.Source.Join (Start, Just_Consumed));
               end if;

               Then_Part := Parse_Sequence (T.Word_End);

               if Is_Word (T.Word_Elsif) then
                  --  Return, exactly as the `if` above does. The `elsif` this
                  --  hands to parses the rest of the chain and consumes the
                  --  one `end if;` that closes all of it -- so consuming
                  --  another here asks for one `end if;` per `elsif`, which is
                  --  what a second `elsif` had been doing since the day the
                  --  chain was written. One `elsif` worked, because the outer
                  --  `if` returns here for the same reason, and two never did.
                  Else_Part := Parse_Statement;

                  return S.Add_Node
                    (Into, S.Node_If,
                     Adash.Source.Join (Start, Just_Consumed),
                     [Condition, Then_Part, Else_Part]);
               end if;

               if Is_Word (T.Word_Else) then
                  Advance;
                  Else_Part := Parse_Sequence (T.Word_End);
               end if;

               --  Required rather than accepted-if-present. Without the
               --  `end`, an unfinished construct parses as a finished one with
               --  an empty body: `if C then` at the end of the input ran and
               --  did nothing, a `loop` became one that never stops, and an
               --  interactive session had no way to tell a line that is wrong
               --  from a line that is not over.
               if not Expect_Word (T.Word_End) then
                  Recover;
                  return Error_Node (Adash.Source.Join (Start, Just_Consumed));
               end if;

               if Is_Word (T.Word_If) then
                  Advance;
               end if;

               declare
                  Ignored : constant Boolean := Expect_Symbol (T.Delim_Semicolon);
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;

               if Else_Part = S.No_Node then
                  return S.Add_Node
                    (Into, S.Node_If, Adash.Source.Join (Start, Just_Consumed),
                     [Condition, Then_Part]);
               end if;

               return S.Add_Node
                 (Into, S.Node_If, Adash.Source.Join (Start, Just_Consumed),
                  [Condition, Then_Part, Else_Part]);
            end;
         end if;

         --  while condition loop ... end loop;
         if Is_Word (T.Word_While) then
            Advance;

            declare
               Condition : constant S.Node_Id := Parse_Expression_Rule;
               Body_Part : S.Node_Id;
            begin
               if not Expect_Word (T.Word_Loop) then
                  Recover;
                  return Error_Node (Adash.Source.Join (Start, Just_Consumed));
               end if;

               Body_Part := Parse_Sequence (T.Word_End);

               --  Required rather than accepted-if-present. Without the
               --  `end`, an unfinished construct parses as a finished one with
               --  an empty body: `if C then` at the end of the input ran and
               --  did nothing, a `loop` became one that never stops, and an
               --  interactive session had no way to tell a line that is wrong
               --  from a line that is not over.
               if not Expect_Word (T.Word_End) then
                  Recover;
                  return Error_Node (Adash.Source.Join (Start, Just_Consumed));
               end if;

               if Is_Word (T.Word_Loop) then
                  Advance;
               end if;

               declare
                  Ignored : constant Boolean := Expect_Symbol (T.Delim_Semicolon);
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;

               return S.Add_Node
                 (Into, S.Node_While_Loop, Adash.Source.Join (Start, Just_Consumed),
                  [Condition, Body_Part]);
            end;
         end if;

         --  for name in [reverse] low .. high loop ... end loop;
         if Is_Word (T.Word_For) then
            Advance;

            declare
               Variable : S.Node_Id;
               Low, High, Body_Part : S.Node_Id;
               Backwards : Boolean := False;

               --  Whether the bounds are already both known, which is what
               --  `X'Range` gives without a `..` being written.
               Ranged : Boolean := False;
            begin
               if T.Kind (Current) /= T.Token_Identifier then
                  Complain (Adash.Messages.Msg_Expected_Loop_Variable);
                  Recover;
                  return Error_Node (Adash.Source.Join (Start, Just_Consumed));
               end if;

               Variable := S.Add_Leaf (Into, S.Node_Name, Here, T.Text (Current));
               Advance;

               if not Expect_Word (T.Word_In) then
                  Recover;
                  return Error_Node (Adash.Source.Join (Start, Just_Consumed));
               end if;

               --  Between `in` and the range, where Ada puts it.
               if Is_Word (T.Word_Reverse) then
                  Backwards := True;
                  Advance;
               end if;

               Low := Parse_Simple_Expression;

               --  `for I in F'Range loop` says both ends at once, so there is
               --  no `..` to find and the ends come out of what it stands
               --  for. Done here rather than left to the type-name path,
               --  which would look up a type named by an attribute.
               declare
                  Spread : constant S.Node_Id := Expanded_Range (Low);
               begin
                  if S."=" (S.Kind (Into, Spread), S.Node_Range) then
                     Low  := S.First (Into, Spread);
                     High := S.Second (Into, Spread);
                     Ranged := True;
                  end if;
               end;

               --  `for C in Colour loop`: a type name instead of a range. Ada
               --  writes it, and for an enumeration it is the only readable
               --  way to walk the whole type -- `Colour'First .. Colour'Last`
               --  says the same thing three times as long.
               --
               --  Which of the two was written is a question about what the
               --  name denotes, so the parser records the shape and semantics
               --  decides. A missing `..` after something that turns out not
               --  to be a type is reported there, against the name.
               if not Ranged and then not Is_Symbol (T.Delim_Double_Dot) then
                  if not Expect_Word (T.Word_Loop) then
                     Recover;
                     return Error_Node
                       (Adash.Source.Join (Start, Just_Consumed));
                  end if;

                  Body_Part := Parse_Sequence (T.Word_End);

                  if not Expect_Word (T.Word_End) then
                     Recover;
                     return Error_Node
                       (Adash.Source.Join (Start, Just_Consumed));
                  end if;

                  if Is_Word (T.Word_Loop) then
                     Advance;
                  end if;

                  declare
                     Ignored : constant Boolean :=
                       Expect_Symbol (T.Delim_Semicolon);
                     pragma Unreferenced (Ignored);
                  begin
                     null;
                  end;

                  return S.Add_Node
                    (Into,
                     (if Backwards then S.Node_For_Reverse_Loop
                      else S.Node_For_Loop),
                     Adash.Source.Join (Start, Just_Consumed),
                     [Variable, Low, Body_Part]);
               end if;

               if not Ranged then
                  Advance;
                  High := Parse_Simple_Expression;
               end if;

               if not Expect_Word (T.Word_Loop) then
                  Recover;
                  return Error_Node (Adash.Source.Join (Start, Just_Consumed));
               end if;

               Body_Part := Parse_Sequence (T.Word_End);

               --  Required rather than accepted-if-present. Without the
               --  `end`, an unfinished construct parses as a finished one with
               --  an empty body: `if C then` at the end of the input ran and
               --  did nothing, a `loop` became one that never stops, and an
               --  interactive session had no way to tell a line that is wrong
               --  from a line that is not over.
               if not Expect_Word (T.Word_End) then
                  Recover;
                  return Error_Node (Adash.Source.Join (Start, Just_Consumed));
               end if;

               if Is_Word (T.Word_Loop) then
                  Advance;
               end if;

               declare
                  Ignored : constant Boolean := Expect_Symbol (T.Delim_Semicolon);
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;

               return S.Add_Node
                 (Into,
                  (if Backwards then S.Node_For_Reverse_Loop
                   else S.Node_For_Loop),
                  Adash.Source.Join (Start, Just_Consumed),
                  [Variable, Low, High, Body_Part]);
            end;
         end if;

         --  loop ... end loop;
         if Is_Word (T.Word_Loop) then
            Advance;

            declare
               Body_Part : constant S.Node_Id := Parse_Sequence (T.Word_End);
            begin
               --  Required rather than accepted-if-present. Without the
               --  `end`, an unfinished construct parses as a finished one with
               --  an empty body: `if C then` at the end of the input ran and
               --  did nothing, a `loop` became one that never stops, and an
               --  interactive session had no way to tell a line that is wrong
               --  from a line that is not over.
               if not Expect_Word (T.Word_End) then
                  Recover;
                  return Error_Node (Adash.Source.Join (Start, Just_Consumed));
               end if;

               if Is_Word (T.Word_Loop) then
                  Advance;
               end if;

               declare
                  Ignored : constant Boolean := Expect_Symbol (T.Delim_Semicolon);
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;

               return S.Add_Node
                 (Into, S.Node_Loop, Adash.Source.Join (Start, Just_Consumed),
                  [1 => Body_Part]);
            end;
         end if;

         --  `use P;`
         if Is_Word (T.Word_Use) then
            Advance;

            if T.Kind (Current) /= T.Token_Identifier then
               Complain (Adash.Messages.Msg_Expected_Package_Name);
               Recover;
               return Error_Node (Adash.Source.Join (Start, Just_Consumed));
            end if;

            declare
               Named : constant S.Node_Id :=
                 S.Add_Leaf (Into, S.Node_Name, Here, T.Text (Current));
            begin
               Advance;

               declare
                  Ignored : constant Boolean :=
                    Expect_Symbol (T.Delim_Semicolon);
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;

               return S.Add_Node
                 (Into, S.Node_Use,
                  Adash.Source.Join (Start, Just_Consumed), [1 => Named]);
            end;
         end if;

         --  `accept N [(formals)] [do <statements> end N];`
         if Is_Word (T.Word_Accept) then
            Advance;

            declare
               Named   : S.Node_Id;
               Formals : S.Node_Id;
               Held    : S.Node_Id := S.No_Node;

               --  Which member of a family this serves, when it is one.
               Which_One : S.Node_Id := S.No_Node;
            begin
               if T.Kind (Current) /= T.Token_Identifier then
                  Complain (Adash.Messages.Msg_Expected_Subprogram_Name);
                  Recover;
                  return Error_Node
                    (Adash.Source.Join (Start, Just_Consumed));
               end if;

               Named := S.Add_Leaf (Into, S.Node_Name, Here, T.Text (Current));
               Advance;

               --  `accept Request (High) do ...` -- which member of a family.
               --  An expression rather than a name, because Ada indexes a
               --  family by a value and a task usually computes which one it
               --  is ready to serve. What tells this from a formal list is
               --  what stands after the parenthesis: a formal is a name and a
               --  colon, and anything else is an index.
               if Is_Symbol (T.Delim_Left_Paren)
                 and then not (T.Kind (Ahead) = T.Token_Identifier
                               and then T.Kind (Ahead (2)) = T.Token_Delimiter
                               and then T.Symbol (Ahead (2)) = T.Delim_Colon)
               then
                  Advance;
                  Which_One := Parse_Expression_Rule;

                  if not Expect_Symbol (T.Delim_Right_Paren) then
                     Recover;
                     return Error_Node
                       (Adash.Source.Join (Start, Just_Consumed));
                  end if;
               end if;

               Formals := Parse_Formals;

               if Is_Word (T.Word_Do) then
                  Advance;
                  Held := Parse_Sequence (T.Word_End);

                  if not Expect_Word (T.Word_End) then
                     Recover;
                     return Error_Node
                       (Adash.Source.Join (Start, Just_Consumed));
                  end if;

                  if T.Kind (Current) = T.Token_Identifier then
                     Advance;
                  end if;
               end if;

               declare
                  Ignored : constant Boolean :=
                    Expect_Symbol (T.Delim_Semicolon);
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;

               return S.Add_Node
                 (Into, S.Node_Accept,
                  Adash.Source.Join (Start, Just_Consumed),
                  [Named, Formals, Held, Which_One]);
            end;
         end if;

         --  `delay <expression>;` and `delay until <expression>;`
         if Is_Word (T.Word_Delay) then
            Advance;

            declare
               --  `until` makes it a time rather than a length. Read before
               --  the expression, because it stands where one would.
               Absolute : constant Boolean := Is_Word (T.Word_Until);
            begin
               if Absolute then
                  Advance;
               end if;

               declare
                  How_Long : constant S.Node_Id := Parse_Expression_Rule;
                  Ignored  : constant Boolean :=
                    Expect_Symbol (T.Delim_Semicolon);
                  pragma Unreferenced (Ignored);
               begin
                  return S.Add_Node
                    (Into, S.Node_Delay,
                     Adash.Source.Join (Start, Just_Consumed),
                     [1 => How_Long],
                     Text => (if Absolute then "until" else ""));
               end;
            end;
         end if;

         --  `abort <name>;`
         if Is_Word (T.Word_Abort) then
            Advance;

            if T.Kind (Current) /= T.Token_Identifier then
               Complain (Adash.Messages.Msg_Expected_Task_Name);
               Recover;
               return Error_Node (Adash.Source.Join (Start, Just_Consumed));
            end if;

            declare
               Names : S.Node_List (1 .. 16);
               Count : Natural := 0;
            begin
               loop
                  exit when Count = Names'Last;
                  Count := Count + 1;
                  Names (Count) :=
                    S.Add_Leaf (Into, S.Node_Name, Here, T.Text (Current));
                  Advance;

                  exit when not Is_Symbol (T.Delim_Comma);
                  Advance;

                  if T.Kind (Current) /= T.Token_Identifier then
                     Complain (Adash.Messages.Msg_Expected_Task_Name);
                     Recover;
                     return Error_Node
                       (Adash.Source.Join (Start, Just_Consumed));
                  end if;
               end loop;

               declare
                  Ignored : constant Boolean :=
                    Expect_Symbol (T.Delim_Semicolon);
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;

               return S.Add_Node
                 (Into, S.Node_Abort,
                  Adash.Source.Join (Start, Just_Consumed),
                  Names (1 .. Count));
            end;
         end if;

         --  `pragma Priority (5);`
         if Is_Word (T.Word_Pragma) then
            Advance;

            declare
               Named     : S.Node_Id;
               Collected : S.Node_List (1 .. 8);
               Count     : Natural := 0;
            begin
               if T.Kind (Current) /= T.Token_Identifier then
                  Complain (Adash.Messages.Msg_Expected_Subprogram_Name);
                  Recover;
                  return Error_Node
                    (Adash.Source.Join (Start, Just_Consumed));
               end if;

               Named :=
                 S.Add_Leaf (Into, S.Node_Name, Here, T.Text (Current));
               Advance;

               if Is_Symbol (T.Delim_Left_Paren) then
                  Advance;

                  --  `Max_Tasks => 2` as much as `No_Delay`: a restriction
                  --  may carry a number, and a named argument is how this
                  --  language already writes one.
                  loop
                     exit when Count = Collected'Last;
                     Count := Count + 1;
                     Collected (Count) := Parse_Argument;
                     exit when not Is_Symbol (T.Delim_Comma);
                     Advance;
                  end loop;

                  if not Expect_Symbol (T.Delim_Right_Paren) then
                     Recover;
                     return Error_Node
                       (Adash.Source.Join (Start, Just_Consumed));
                  end if;
               end if;

               declare
                  Ignored : constant Boolean :=
                    Expect_Symbol (T.Delim_Semicolon);
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;

               return S.Add_Node
                 (Into, S.Node_Pragma,
                  Adash.Source.Join (Start, Just_Consumed),
                  [Named,
                   S.Add_Node
                     (Into, S.Node_Sequence,
                      Adash.Source.Join (Start, Just_Consumed),
                      Collected (1 .. Count))]);
            end;
         end if;

         --  `requeue E;` and `requeue E with abort;`
         if Is_Word (T.Word_Requeue) then
            Advance;

            declare
               Named    : S.Node_Id;
               Abortive : Boolean := False;

               --  Which member of a family it moves the caller to, when the
               --  target is one.
               Which_One : S.Node_Id := S.No_Node;
            begin
               if T.Kind (Current) /= T.Token_Identifier then
                  Complain (Adash.Messages.Msg_Expected_Subprogram_Name);
                  Recover;
                  return Error_Node
                    (Adash.Source.Join (Start, Just_Consumed));
               end if;

               Named :=
                 S.Add_Leaf (Into, S.Node_Name, Here, T.Text (Current));
               Advance;

               --  `requeue Later (Which);` -- which member of a family the
               --  caller is moved to. An expression, because which member is
               --  something the body works out.
               if Is_Symbol (T.Delim_Left_Paren) then
                  Advance;
                  Which_One := Parse_Expression_Rule;

                  if not Expect_Symbol (T.Delim_Right_Paren) then
                     Recover;
                     return Error_Node
                       (Adash.Source.Join (Start, Just_Consumed));
                  end if;
               end if;

               if Is_Word (T.Word_With) then
                  Advance;

                  if not Expect_Word (T.Word_Abort) then
                     Recover;
                     return Error_Node
                       (Adash.Source.Join (Start, Just_Consumed));
                  end if;

                  Abortive := True;
               end if;

               declare
                  Ignored : constant Boolean :=
                    Expect_Symbol (T.Delim_Semicolon);
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;

               return S.Add_Node
                 (Into, S.Node_Requeue,
                  Adash.Source.Join (Start, Just_Consumed),
                  [Named, Which_One],
                  --  One word, because it is a marker rather than a phrase:
                  --  what the node records is that `abort` was written after
                  --  `with`, the way a parameter's node records its mode.
                  Text => (if Abortive then "abort" else ""));
            end;
         end if;

         --  `select <entry call>; <taken> [or delay D; | else] <otherwise>
         --   end select;`
         if Is_Word (T.Word_Select) then
            Advance;

            --  Two constructs share the word. One is a *task* choosing what to
            --  serve, whose alternatives are accepts; the other is a *caller*
            --  deciding how long to wait, which begins with an entry call.
            --  Which one this is settled by the first word after `select`,
            --  which is where Ada settles it too.
            if Is_Word (T.Word_Accept) or else Is_Word (T.Word_When) then
               declare
                  Alternatives : S.Node_List (1 .. 32);
                  Count        : Natural := 0;
                  Otherwise    : S.Node_Id := S.No_Node;
               begin
                  loop
                     declare
                        Began : constant Adash.Source.Span := Here;
                        Guard : S.Node_Id := S.No_Node;
                        Taken : S.Node_Id;
                        Rest  : S.Node_Id;
                     begin
                        if Is_Word (T.Word_When) then
                           Advance;
                           Guard := Parse_Expression_Rule;

                           if not Expect_Symbol (T.Delim_Arrow) then
                              Recover;
                              return Error_Node
                                (Adash.Source.Join (Start, Just_Consumed));
                           end if;
                        end if;

                        --  What the alternative *is*: an accept, or a delay
                        --  bounding how long the others are waited for.
                        --  Parsed as a statement, because both are statements
                        --  and a second reading of either is a second place
                        --  for them to be read differently.
                        Taken := Parse_Statement;
                        Rest  := Parse_Sequence (T.Word_End);

                        exit when Count = Alternatives'Last;
                        Count := Count + 1;
                        Alternatives (Count) :=
                          S.Add_Node
                            (Into, S.Node_Select_Alternative,
                             Adash.Source.Join (Began, Just_Consumed),
                             [Guard, Taken, Rest]);
                     end;

                     exit when not Is_Word (T.Word_Or);
                     Advance;
                  end loop;

                  if Is_Word (T.Word_Else) then
                     Advance;
                     Otherwise := Parse_Sequence (T.Word_End);
                  end if;

                  if not Expect_Word (T.Word_End)
                    or else not Expect_Word (T.Word_Select)
                  then
                     Recover;
                     return Error_Node
                       (Adash.Source.Join (Start, Just_Consumed));
                  end if;

                  declare
                     Ignored : constant Boolean :=
                       Expect_Symbol (T.Delim_Semicolon);
                     pragma Unreferenced (Ignored);
                  begin
                     null;
                  end;

                  return S.Add_Node
                    (Into, S.Node_Selective_Accept,
                     Adash.Source.Join (Start, Just_Consumed),
                     [S.Add_Node
                        (Into, S.Node_Sequence,
                         Adash.Source.Join (Start, Just_Consumed),
                         Alternatives (1 .. Count)),
                      Otherwise]);
               end;
            end if;

            declare
               Call      : constant S.Node_Id := Parse_Statement;
               Taken     : constant S.Node_Id := Parse_Sequence (T.Word_Or);
               How_Long  : S.Node_Id := S.No_Node;
               Otherwise : S.Node_Id := S.No_Node;
            begin
               --  `then abort` turns the same beginning into a different
               --  construct: what stood before it is a trigger rather than a
               --  call to wait on, and what follows is what the trigger
               --  abandons.
               if Is_Word (T.Word_Then) then
                  Advance;

                  if not Expect_Word (T.Word_Abort) then
                     Recover;
                     return Error_Node
                       (Adash.Source.Join (Start, Just_Consumed));
                  end if;

                  declare
                     Part : constant S.Node_Id := Parse_Sequence (T.Word_End);
                  begin
                     if not Expect_Word (T.Word_End)
                       or else not Expect_Word (T.Word_Select)
                     then
                        Recover;
                        return Error_Node
                          (Adash.Source.Join (Start, Just_Consumed));
                     end if;

                     declare
                        Ignored : constant Boolean :=
                          Expect_Symbol (T.Delim_Semicolon);
                        pragma Unreferenced (Ignored);
                     begin
                        null;
                     end;

                     return S.Add_Node
                       (Into, S.Node_Then_Abort,
                        Adash.Source.Join (Start, Just_Consumed),
                        [Call, Taken, Part]);
                  end;
               end if;

               if Is_Word (T.Word_Or) then
                  Advance;

                  if not Expect_Word (T.Word_Delay) then
                     Recover;
                     return Error_Node
                       (Adash.Source.Join (Start, Just_Consumed));
                  end if;

                  How_Long := Parse_Expression_Rule;

                  declare
                     Ignored : constant Boolean :=
                       Expect_Symbol (T.Delim_Semicolon);
                     pragma Unreferenced (Ignored);
                  begin
                     null;
                  end;

                  Otherwise := Parse_Sequence (T.Word_End);

               elsif Is_Word (T.Word_Else) then
                  Advance;
                  Otherwise := Parse_Sequence (T.Word_End);

               else
                  Otherwise :=
                    S.Add_Node (Into, S.Node_Sequence, Just_Consumed, []);
               end if;

               if not Expect_Word (T.Word_End) then
                  Recover;
                  return Error_Node
                    (Adash.Source.Join (Start, Just_Consumed));
               end if;

               if not Expect_Word (T.Word_Select) then
                  Recover;
                  return Error_Node
                    (Adash.Source.Join (Start, Just_Consumed));
               end if;

               declare
                  Ignored : constant Boolean :=
                    Expect_Symbol (T.Delim_Semicolon);
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;

               return S.Add_Node
                 (Into, S.Node_Select,
                  Adash.Source.Join (Start, Just_Consumed),
                  [Call, Taken, How_Long, Otherwise]);
            end;
         end if;

         --  `task T is ... end T;` and `task body T is ... end T;`
         --  `protected P is ... end P;` and `protected body P is ... end P;`
         if Is_Word (T.Word_Task) or else Is_Word (T.Word_Protected) then
            declare
               Is_Task : constant Boolean := Is_Word (T.Word_Task);
               Named   : S.Node_Id;

               --  `task type W is ... end W;` declares a type whose objects
               --  are tasks, and `task T is ... end T;` declares one task.
               --  Which it is rides on the node's text, as a parameter's mode
               --  does: a node kind of its own would double every branch that
               --  walks a task for a difference that is one bit.
               Is_Type : Boolean := False;

               --  What the task takes at elaboration, when it takes anything.
               Discriminants : S.Node_Id := S.No_Node;
            begin
               Advance;

               declare
                  Is_Body : constant Boolean := Is_Word (T.Word_Body);
               begin
                  if Is_Body then
                     Advance;
                  elsif Is_Word (T.Word_Type) then
                     Is_Type := True;
                     Advance;
                  end if;

                  if T.Kind (Current) /= T.Token_Identifier then
                     Complain (Adash.Messages.Msg_Expected_Package_Name);
                     Recover;
                     return Error_Node
                       (Adash.Source.Join (Start, Just_Consumed));
                  end if;

                  Named :=
                    S.Add_Leaf (Into, S.Node_Name, Here, T.Text (Current));
                  Advance;

                  --  `task type Worker (Id : Integer) is ...` and
                  --  `protected type Counter (Limit : Integer) is ...` -- a
                  --  discriminant part, which is what one of these takes at
                  --  elaboration where a subprogram takes parameters at a
                  --  call. Written on the declaration only, as Ada writes it:
                  --  the body has them in scope without repeating them.
                  if not Is_Body then
                     Discriminants := Parse_Formals;
                  end if;

                  --  `task T;` -- a task with no entries, which Ada writes
                  --  without an `is` at all. The commonest shape a script
                  --  wants: something that runs beside it and says nothing.
                  if Is_Symbol (T.Delim_Semicolon) then
                     Advance;

                     return S.Add_Node
                       (Into,
                        (if Is_Task then S.Node_Task_Declaration
                         else S.Node_Protected_Declaration),
                        Adash.Source.Join (Start, Just_Consumed),
                        [Named,
                         S.Add_Node
                           (Into, S.Node_Sequence,
                            Adash.Source.Join (Start, Just_Consumed),
                            S.No_Children),
                         S.No_Node,
                         Discriminants],
                        Text => (if Is_Type then "type" else ""));
                  end if;

                  if not Expect_Word (T.Word_Is) then
                     Recover;
                     return Error_Node
                       (Adash.Source.Join (Start, Just_Consumed));
                  end if;

                  declare
                     Collected : S.Node_List (1 .. 512);
                     Count     : Natural := 0;

                     --  A body may declare before it does: `is <declarations>
                     --  begin <statements> end`. Both are collected into one
                     --  sequence, because a body here is a scope of its own
                     --  and this language already accepts a declaration
                     --  wherever a statement may stand.
                     Before_Begin : constant S.Node_Id :=
                       Parse_Sequence (T.Word_Begin);
                  begin
                     for Index in 1 .. S.Child_Count (Into, Before_Begin) loop
                        exit when Count = Collected'Last;
                        Count := Count + 1;
                        Collected (Count) :=
                          S.Child (Into, Before_Begin, Index);
                     end loop;

                     if Is_Word (T.Word_Begin) then
                        Advance;

                        declare
                           After : constant S.Node_Id :=
                             Parse_Sequence (T.Word_End);
                        begin
                           for Index in 1 .. S.Child_Count (Into, After) loop
                              exit when Count = Collected'Last;
                              Count := Count + 1;
                              Collected (Count) := S.Child (Into, After, Index);
                           end loop;
                        end;
                     end if;

                     --  A body answers for what went wrong, the same way
                     --  every other body does. Ada lets a task body carry
                     --  handlers and it is where most of a task's belong: a
                     --  task that failed silently is a task nobody notices.
                     declare
                        Handlers : S.Node_Id := S.No_Node;
                     begin
                        if Is_Word (T.Word_Exception) then
                           Advance;
                           Handlers := Parse_Handlers;
                        end if;

                        if not Expect_Word (T.Word_End) then
                           Recover;
                           return Error_Node
                             (Adash.Source.Join (Start, Just_Consumed));
                        end if;

                        if T.Kind (Current) = T.Token_Identifier then
                           Advance;
                        end if;

                        declare
                           Ignored : constant Boolean :=
                             Expect_Symbol (T.Delim_Semicolon);
                           pragma Unreferenced (Ignored);
                        begin
                           null;
                        end;

                        return S.Add_Node
                          (Into,
                           (if Is_Task then
                               (if Is_Body then S.Node_Task_Body
                                else S.Node_Task_Declaration)
                            else
                               (if Is_Body then S.Node_Protected_Body
                                else S.Node_Protected_Declaration)),
                           Adash.Source.Join (Start, Just_Consumed),
                           [Named,
                            S.Add_Node
                              (Into, S.Node_Sequence,
                               Adash.Source.Join (Start, Just_Consumed),
                               Collected (1 .. Count)),
                            Handlers,
                            Discriminants],
                           Text => (if Is_Type then "type" else ""));
                     end;
                  end;
               end;
            end;
         end if;

         --  `entry Wait when Ready is ... end Wait;`
         if Is_Word (T.Word_Entry) then
            Advance;

            declare
               Named   : S.Node_Id;
               Formals : S.Node_Id := S.No_Node;
               Barrier : S.Node_Id := S.No_Node;
               Held    : S.Node_Id;

               --  What a family's members are indexed by, when this is one,
               --  and what its body calls the member it is running for.
               Indexed_By  : S.Node_Id := S.No_Node;
               Index_Named : S.Node_Id := S.No_Node;
            begin
               if T.Kind (Current) /= T.Token_Identifier then
                  Complain (Adash.Messages.Msg_Expected_Subprogram_Name);
                  Recover;
                  return Error_Node
                    (Adash.Source.Join (Start, Just_Consumed));
               end if;

               Named := S.Add_Leaf (Into, S.Node_Name, Here, T.Text (Current));
               Advance;

               --  `entry Request (Priority);` -- a family, whose parentheses
               --  hold the type its members are indexed by rather than
               --  parameters. Told apart by what is inside: a formal is a name
               --  followed by a colon, and a subtype mark is a name followed
               --  by the closing parenthesis. The parser reads what was
               --  written; deciding what the name denotes is not its business.
               if Is_Symbol (T.Delim_Left_Paren)
                 and then T.Kind (Ahead) = T.Token_Identifier
                 and then T.Kind (Ahead (2)) = T.Token_Delimiter
                 and then T.Symbol (Ahead (2)) = T.Delim_Right_Paren
               then
                  Advance;
                  Indexed_By :=
                    S.Add_Leaf (Into, S.Node_Name, Here, T.Text (Current));
                  Advance;
                  Advance;

               --  `entry Request (for Which in Priority) when ... is` -- the
               --  *body* of a family, which is one body for all its members
               --  and says what to call the member it is running for. Ada
               --  writes it this way and so does this: a barrier that could
               --  not ask which member it was would make a family of them no
               --  different from one entry.
               elsif Is_Symbol (T.Delim_Left_Paren)
                 and then T.Kind (Ahead) = T.Token_Reserved_Word
                 and then T.Word (Ahead) = T.Word_For
               then
                  Advance;
                  Advance;

                  if T.Kind (Current) /= T.Token_Identifier then
                     Complain (Adash.Messages.Msg_Expected_Loop_Variable);
                     Recover;
                     return Error_Node
                       (Adash.Source.Join (Start, Just_Consumed));
                  end if;

                  Index_Named :=
                    S.Add_Leaf (Into, S.Node_Name, Here, T.Text (Current));
                  Advance;

                  if not Expect_Word (T.Word_In) then
                     Recover;
                     return Error_Node
                       (Adash.Source.Join (Start, Just_Consumed));
                  end if;

                  if T.Kind (Current) /= T.Token_Identifier then
                     Complain (Adash.Messages.Msg_Expected_Type_Name);
                     Recover;
                     return Error_Node
                       (Adash.Source.Join (Start, Just_Consumed));
                  end if;

                  Indexed_By :=
                    S.Add_Leaf (Into, S.Node_Name, Here, T.Text (Current));
                  Advance;

                  if not Expect_Symbol (T.Delim_Right_Paren) then
                     Recover;
                     return Error_Node
                       (Adash.Source.Join (Start, Just_Consumed));
                  end if;
               end if;

               --  Parameters, which a task's entry takes and a protected
               --  object's does not: what carries them is the rendezvous, and
               --  a protected entry has no second side to copy them to. Both
               --  are parsed here and the analyser is what refuses the one
               --  that has no meaning -- a parser that refused it would be
               --  deciding by shape what only a declaration can say.
               Formals := Parse_Formals;

               if Is_Word (T.Word_When) then
                  Advance;
                  Barrier := Parse_Expression_Rule;
               end if;

               if not Is_Word (T.Word_Is) then
                  --  A declaration rather than a body: `entry Wait;` in the
                  --  visible part, whose body stands in the protected body.
                  declare
                     Ignored : constant Boolean :=
                       Expect_Symbol (T.Delim_Semicolon);
                     pragma Unreferenced (Ignored);
                  begin
                     null;
                  end;

                  return S.Add_Node
                    (Into, S.Node_Entry,
                     Adash.Source.Join (Start, Just_Consumed),
                     [Named, Barrier, S.No_Node, Formals, Indexed_By, Index_Named]);
               end if;

               Advance;

               --  `is [declarations] begin <statements> end`, the same shape
               --  every body has. The `begin` is consumed here rather than
               --  left to be read as a block, which would take the `end` that
               --  closes this entry and leave the object it stands in
               --  unterminated.
               declare
                  Collected : S.Node_List (1 .. 512);
                  Count     : Natural := 0;

                  Before_Begin : constant S.Node_Id :=
                    Parse_Sequence (T.Word_Begin);
               begin
                  for Index in 1 .. S.Child_Count (Into, Before_Begin) loop
                     exit when Count = Collected'Last;
                     Count := Count + 1;
                     Collected (Count) := S.Child (Into, Before_Begin, Index);
                  end loop;

                  if Is_Word (T.Word_Begin) then
                     Advance;

                     declare
                        After : constant S.Node_Id :=
                          Parse_Sequence (T.Word_End);
                     begin
                        for Index in 1 .. S.Child_Count (Into, After) loop
                           exit when Count = Collected'Last;
                           Count := Count + 1;
                           Collected (Count) := S.Child (Into, After, Index);
                        end loop;
                     end;
                  end if;

                  Held :=
                    S.Add_Node
                      (Into, S.Node_Sequence,
                       Adash.Source.Join (Start, Just_Consumed),
                       Collected (1 .. Count));
               end;

               if not Expect_Word (T.Word_End) then
                  Recover;
                  return Error_Node
                    (Adash.Source.Join (Start, Just_Consumed));
               end if;

               if T.Kind (Current) = T.Token_Identifier then
                  Advance;
               end if;

               declare
                  Ignored : constant Boolean :=
                    Expect_Symbol (T.Delim_Semicolon);
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;

               return S.Add_Node
                 (Into, S.Node_Entry,
                  Adash.Source.Join (Start, Just_Consumed),
                  [Named, Barrier, Held, Formals, Indexed_By, Index_Named]);
            end;
         end if;

         --  `package P is ... end P;` and `package body P is ... end P;`
         if Is_Word (T.Word_Package) then
            Advance;

            declare
               Is_Body : constant Boolean := Is_Word (T.Word_Body);
               Named   : S.Node_Id;
            begin
               if Is_Body then
                  Advance;
               end if;

               if T.Kind (Current) /= T.Token_Identifier then
                  Complain (Adash.Messages.Msg_Expected_Package_Name);
                  Recover;
                  return Error_Node
                    (Adash.Source.Join (Start, Just_Consumed));
               end if;

               Named := S.Add_Leaf (Into, S.Node_Name, Here, T.Text (Current));
               Advance;

               if not Expect_Word (T.Word_Is) then
                  Recover;
                  return Error_Node
                    (Adash.Source.Join (Start, Just_Consumed));
               end if;

               declare
                  Held : constant S.Node_Id := Parse_Sequence (T.Word_End);
               begin
                  if not Expect_Word (T.Word_End) then
                     Recover;
                     return Error_Node
                       (Adash.Source.Join (Start, Just_Consumed));
                  end if;

                  --  `end P;` names the package again, as Ada writes it. The
                  --  name is optional here for the same reason it is optional
                  --  after `end loop`: what closes the construct is `end`, and
                  --  the name is a reader's reassurance.
                  if T.Kind (Current) = T.Token_Identifier then
                     Advance;
                  end if;

                  declare
                     Ignored : constant Boolean :=
                       Expect_Symbol (T.Delim_Semicolon);
                     pragma Unreferenced (Ignored);
                  begin
                     null;
                  end;

                  return S.Add_Node
                    (Into,
                     (if Is_Body then S.Node_Package_Body
                      else S.Node_Package_Declaration),
                     Adash.Source.Join (Start, Just_Consumed),
                     [Named, Held]);
               end;
            end;
         end if;

         --  `generic <formals> procedure P ... end P;`
         if Is_Word (T.Word_Generic) then
            Advance;

            declare
               Formals : S.Node_List (1 .. 16);
               Count   : Natural := 0;
            begin
               --  `type T is private;` and nothing else. A formal value or a
               --  formal subprogram would each need a rule of its own about
               --  what an instantiation may supply, and a type is what the
               --  useful generics here take.
               while Is_Word (T.Word_Type) loop
                  Advance;

                  if T.Kind (Current) /= T.Token_Identifier then
                     Complain (Adash.Messages.Msg_Expected_Type_Name);
                     Recover;
                     return Error_Node
                       (Adash.Source.Join (Start, Just_Consumed));
                  end if;

                  declare
                     Formal : constant S.Node_Id :=
                       S.Add_Leaf (Into, S.Node_Name, Here, T.Text (Current));
                  begin
                     Advance;

                     if not Expect_Word (T.Word_Is) then
                        Recover;
                        return Error_Node
                          (Adash.Source.Join (Start, Just_Consumed));
                     end if;

                     if not Expect_Word (T.Word_Private) then
                        Recover;
                        return Error_Node
                          (Adash.Source.Join (Start, Just_Consumed));
                     end if;

                     if not Expect_Symbol (T.Delim_Semicolon) then
                        Recover;
                        return Error_Node
                          (Adash.Source.Join (Start, Just_Consumed));
                     end if;

                     exit when Count = Formals'Last;
                     Count := Count + 1;
                     Formals (Count) :=
                       S.Add_Node
                         (Into, S.Node_Generic_Formal,
                          Adash.Source.Join (Start, Just_Consumed),
                          [1 => Formal]);
                  end;
               end loop;

               if not Is_Word (T.Word_Procedure)
                 and then not Is_Word (T.Word_Function)
               then
                  Complain (Adash.Messages.Msg_Expected_Subprogram_Name);
                  Recover;
                  return Error_Node
                    (Adash.Source.Join (Start, Just_Consumed));
               end if;

               return S.Add_Node
                 (Into, S.Node_Generic_Declaration,
                  Adash.Source.Join (Start, Just_Consumed),
                  [S.Add_Node
                     (Into, S.Node_Sequence,
                      Adash.Source.Join (Start, Just_Consumed),
                      Formals (1 .. Count)),
                   Parse_Subprogram]);
            end;
         end if;

         if Is_Word (T.Word_Procedure) or else Is_Word (T.Word_Function) then
            --  `procedure Q is new P (Integer);` -- an instantiation rather
            --  than a body. Told apart by `is new`, which is three tokens in
            --  and is why this looks ahead rather than committing.
            declare
               Ahead_By : Natural := 1;
            begin
               while T.Kind (Ahead (Ahead_By)) /= T.Token_End_Of_Input
                 and then not (T.Kind (Ahead (Ahead_By)) = T.Token_Delimiter
                               and then T.Symbol (Ahead (Ahead_By))
                                        = T.Delim_Semicolon)
               loop
                  if T.Kind (Ahead (Ahead_By)) = T.Token_Reserved_Word
                    and then T.Word (Ahead (Ahead_By)) = T.Word_Is
                    and then T.Kind (Ahead (Ahead_By + 1))
                             = T.Token_Reserved_Word
                    and then T.Word (Ahead (Ahead_By + 1)) = T.Word_New
                  then
                     return Parse_Instantiation;
                  end if;

                  Ahead_By := Ahead_By + 1;
               end loop;
            end;

            return Parse_Subprogram;
         end if;

         --  subtype Name is Type [range Low .. High];
         if Is_Word (T.Word_Subtype) then
            Advance;

            declare
               Name  : S.Node_Id;
               Named : S.Node_Id;
               Low, High : S.Node_Id := S.No_Node;
            begin
               if T.Kind (Current) /= T.Token_Identifier then
                  Complain (Adash.Messages.Msg_Expected_Type_Name);
                  Recover;
                  return Error_Node
                    (Adash.Source.Join (Start, Just_Consumed));
               end if;

               Name := S.Add_Leaf (Into, S.Node_Name, Here, T.Text (Current));
               Advance;

               if not Expect_Word (T.Word_Is) then
                  Recover;
                  return Error_Node
                    (Adash.Source.Join (Start, Just_Consumed));
               end if;

               declare
                  Spelt : Boolean;
               begin
                  Named := Parse_Type_Mark (Spelt);

                  if not Spelt then
                     Complain (Adash.Messages.Msg_Expected_Type_Name);
                     Recover;
                     return Error_Node
                       (Adash.Source.Join (Start, Just_Consumed));
                  end if;
               end;

               if Is_Word (T.Word_Range) then
                  Advance;
                  Low := Parse_Simple_Expression;

                  if not Expect_Symbol (T.Delim_Double_Dot) then
                     Recover;
                     return Error_Node
                       (Adash.Source.Join (Start, Just_Consumed));
                  end if;

                  High := Parse_Simple_Expression;
               end if;

               declare
                  Ignored : constant Boolean :=
                    Expect_Symbol (T.Delim_Semicolon);
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;

               if S.Is_Present (Low) then
                  return S.Add_Node
                    (Into, S.Node_Subtype_Declaration,
                     Adash.Source.Join (Start, Just_Consumed),
                     [Name, Named,
                      S.Add_Node
                        (Into, S.Node_Range,
                         Adash.Source.Join (Start, Just_Consumed),
                         [Low, High])]);
               end if;

               return S.Add_Node
                 (Into, S.Node_Subtype_Declaration,
                  Adash.Source.Join (Start, Just_Consumed), [Name, Named]);
            end;
         end if;

         --  type Name is (Literal, Literal, ...);
         --
         --  An enumeration and nothing else. Ada writes records, arrays and
         --  derived types with the same first three tokens, and each of those
         --  is refused where its own definition would begin rather than here
         --  -- so the diagnostic names what was written instead of the word
         --  `type`, which is not the part that is wrong.
         if Is_Word (T.Word_Type) then
            Advance;

            declare
               Name     : S.Node_Id;
               Literals : S.Node_List (1 .. 256);
               Count    : Natural := 0;
            begin
               if T.Kind (Current) /= T.Token_Identifier then
                  Complain (Adash.Messages.Msg_Expected_Type_Name);
                  Recover;
                  return Error_Node
                    (Adash.Source.Join (Start, Just_Consumed));
               end if;

               Name := S.Add_Leaf (Into, S.Node_Name, Here, T.Text (Current));
               Advance;

               if not Expect_Word (T.Word_Is) then
                  Recover;
                  return Error_Node
                    (Adash.Source.Join (Start, Just_Consumed));
               end if;

               --  `record ... end record;`
               if Is_Word (T.Word_Record) then
                  Advance;

                  declare
                     Fields : S.Node_List (1 .. 64);
                     Count  : Natural := 0;
                  begin
                     while not Is_Word (T.Word_End) and then not At_End loop
                        exit when Count = Fields'Last;

                        if T.Kind (Current) /= T.Token_Identifier then
                           Complain
                             (Adash.Messages.Msg_Expected_Component_Name);
                           Recover;
                           return Error_Node
                             (Adash.Source.Join (Start, Just_Consumed));
                        end if;

                        declare
                           Field : constant S.Node_Id :=
                             S.Add_Leaf (Into, S.Node_Name, Here,
                                         T.Text (Current));
                           Of_Type : S.Node_Id;
                        begin
                           Advance;

                           if not Expect_Symbol (T.Delim_Colon) then
                              Recover;
                              return Error_Node
                                (Adash.Source.Join (Start, Just_Consumed));
                           end if;

                           declare
                              Named : Boolean;
                           begin
                              Of_Type := Parse_Type_Mark (Named);

                              if not Named then
                                 Complain
                                   (Adash.Messages.Msg_Expected_Type_Name);
                                 Recover;
                                 return Error_Node
                                   (Adash.Source.Join (Start, Just_Consumed));
                              end if;
                           end;

                           if not Expect_Symbol (T.Delim_Semicolon) then
                              Recover;
                              return Error_Node
                                (Adash.Source.Join (Start, Just_Consumed));
                           end if;

                           Count := Count + 1;
                           --  The same shape a formal parameter has, and it
                           --  means the same thing: a name and a type. The
                           --  mode goes in the text, and a component has none.
                           Fields (Count) :=
                             S.Add_Node
                               (Into, S.Node_Parameter, Here,
                                [Field, Of_Type], Text => "in");
                        end;
                     end loop;

                     if not Expect_Word (T.Word_End) then
                        Recover;
                        return Error_Node
                          (Adash.Source.Join (Start, Just_Consumed));
                     end if;

                     if not Expect_Word (T.Word_Record) then
                        Recover;
                        return Error_Node
                          (Adash.Source.Join (Start, Just_Consumed));
                     end if;

                     declare
                        Ignored : constant Boolean :=
                          Expect_Symbol (T.Delim_Semicolon);
                        pragma Unreferenced (Ignored);
                     begin
                        null;
                     end;

                     return S.Add_Node
                       (Into, S.Node_Record_Declaration,
                        Adash.Source.Join (Start, Just_Consumed),
                        [Name,
                         S.Add_Node
                           (Into, S.Node_Sequence,
                            Adash.Source.Join (Start, Just_Consumed),
                            Fields (1 .. Count))]);
                  end;
               end if;

               --  `array (Low .. High) of Element;`
               if Is_Word (T.Word_Array) then
                  Advance;

                  declare
                     Low, High, Element : S.Node_Id;
                  begin
                     if not Expect_Symbol (T.Delim_Left_Paren) then
                        Recover;
                        return Error_Node
                          (Adash.Source.Join (Start, Just_Consumed));
                     end if;

                     Low := Parse_Simple_Expression;

                     if not Expect_Symbol (T.Delim_Double_Dot) then
                        Recover;
                        return Error_Node
                          (Adash.Source.Join (Start, Just_Consumed));
                     end if;

                     High := Parse_Simple_Expression;

                     if not Expect_Symbol (T.Delim_Right_Paren) then
                        Recover;
                        return Error_Node
                          (Adash.Source.Join (Start, Just_Consumed));
                     end if;

                     if not Expect_Word (T.Word_Of) then
                        Recover;
                        return Error_Node
                          (Adash.Source.Join (Start, Just_Consumed));
                     end if;

                     declare
                        Named : Boolean;
                     begin
                        Element := Parse_Type_Mark (Named);

                        if not Named then
                           Complain (Adash.Messages.Msg_Expected_Type_Name);
                           Recover;
                           return Error_Node
                             (Adash.Source.Join (Start, Just_Consumed));
                        end if;
                     end;

                     declare
                        Ignored : constant Boolean :=
                          Expect_Symbol (T.Delim_Semicolon);
                        pragma Unreferenced (Ignored);
                     begin
                        null;
                     end;

                     return S.Add_Node
                       (Into, S.Node_Array_Declaration,
                        Adash.Source.Join (Start, Just_Consumed),
                        [Name,
                         S.Add_Node
                           (Into, S.Node_Range,
                            Adash.Source.Join (Start, Just_Consumed),
                            [Low, High]),
                         Element]);
                  end;
               end if;

               if not Expect_Symbol (T.Delim_Left_Paren) then
                  Recover;
                  return Error_Node
                    (Adash.Source.Join (Start, Just_Consumed));
               end if;

               loop
                  if T.Kind (Current) /= T.Token_Identifier then
                     Complain (Adash.Messages.Msg_Expected_Literal_Name);
                     Recover;
                     return Error_Node
                       (Adash.Source.Join (Start, Just_Consumed));
                  end if;

                  exit when Count = Literals'Last;

                  Count := Count + 1;
                  Literals (Count) :=
                    S.Add_Leaf (Into, S.Node_Name, Here, T.Text (Current));
                  Advance;

                  exit when not Is_Symbol (T.Delim_Comma);
                  Advance;
               end loop;

               if not Expect_Symbol (T.Delim_Right_Paren) then
                  Recover;
                  return Error_Node
                    (Adash.Source.Join (Start, Just_Consumed));
               end if;

               declare
                  Ignored : constant Boolean :=
                    Expect_Symbol (T.Delim_Semicolon);
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;

               return S.Add_Node
                 (Into, S.Node_Type_Declaration,
                  Adash.Source.Join (Start, Just_Consumed),
                  [Name,
                   S.Add_Node
                     (Into, S.Node_Sequence,
                      Adash.Source.Join (Start, Just_Consumed),
                      Literals (1 .. Count))]);
            end;
         end if;

         --  A declaration: name : [constant] type [:= value];
         if T.Kind (Current) = T.Token_Identifier
           and then T.Kind (Ahead) = T.Token_Delimiter
           and then T.Symbol (Ahead) = T.Delim_Colon
         then
            declare
               Name     : constant S.Node_Id :=
                 S.Add_Leaf (Into, S.Node_Name, Here, T.Text (Current));
               Type_Ref : S.Node_Id;
               Value    : S.Node_Id := S.No_Node;
               Actuals  : S.Node_Id := S.No_Node;
               Is_Const : Boolean := False;
            begin
               Advance;  --  the name
               Advance;  --  the colon

               --  `Wrong_Kind : exception;` -- a declaration with the shape of
               --  an object's and nothing else in common: no type, no value,
               --  no storage. Told apart by the one word that can stand where
               --  a type mark would.
               if Is_Word (T.Word_Exception) then
                  Advance;

                  declare
                     Ignored : constant Boolean :=
                       Expect_Symbol (T.Delim_Semicolon);
                     pragma Unreferenced (Ignored);
                  begin
                     return S.Add_Node
                       (Into, S.Node_Exception_Declaration,
                        Adash.Source.Join (Start, Just_Consumed),
                        [1 => Name]);
                  end;
               end if;

               if Is_Word (T.Word_Constant) then
                  Is_Const := True;
                  Advance;
               end if;

               declare
                  Named : Boolean;
               begin
                  Type_Ref := Parse_Type_Mark (Named);

                  if not Named then
                     Complain (Adash.Messages.Msg_Expected_Type_Name);
                     Recover;
                     return Error_Node
                       (Adash.Source.Join (Start, Just_Consumed));
                  end if;
               end;

               --  `A : Worker (1);` -- what the object gives its type. A
               --  constraint in Ada's terms, and here the values a task is
               --  elaborated with. Kept beside the type mark rather than
               --  inside it, because a type mark is read in a dozen places and
               --  only a declaration can constrain one.
               if Is_Symbol (T.Delim_Left_Paren) then
                  Advance;

                  declare
                     Collected : S.Node_List (1 .. 64);
                     Count     : Natural := 0;
                  begin
                     if not Is_Symbol (T.Delim_Right_Paren) then
                        loop
                           exit when Count = Collected'Last;
                           Count := Count + 1;
                           Collected (Count) := Parse_Argument;
                           exit when not Is_Symbol (T.Delim_Comma);
                           Advance;
                        end loop;
                     end if;

                     Actuals := S.Add_Node
                       (Into, S.Node_Sequence,
                        Adash.Source.Join (Start, Just_Consumed),
                        Collected (1 .. Count));

                     if not Expect_Symbol (T.Delim_Right_Paren) then
                        Recover;
                        return Error_Node
                          (Adash.Source.Join (Start, Here));
                     end if;
                  end;
               end if;

               if Is_Symbol (T.Delim_Assign) then
                  Advance;
                  Value := Parse_Expression_Rule;
               end if;

               declare
                  Ignored : constant Boolean := Expect_Symbol (T.Delim_Semicolon);
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;

               --  `constant` is recorded as the node's text rather than as a
               --  separate kind: it is a property of one declaration, and two
               --  kinds would double every place that handles declarations.
               return S.Add_Node
                 (Into, S.Node_Object_Declaration,
                  Adash.Source.Join (Start, Just_Consumed),
                  [Name, Type_Ref, Value, Actuals],
                  Text => (if Is_Const then "constant" else ""));
            end;
         end if;

         --  An assignment or a procedure call. Both start with a name, and
         --  which it is depends on what follows -- not on what the name means,
         --  which the parser does not know.
         if T.Kind (Current) = T.Token_Identifier then
            declare
               Target : constant S.Node_Id := Parse_Primary;
            begin
               if Is_Symbol (T.Delim_Assign) then
                  Advance;

                  declare
                     Value   : constant S.Node_Id := Parse_Expression_Rule;
                     Ignored : constant Boolean := Expect_Symbol (T.Delim_Semicolon);
                     pragma Unreferenced (Ignored);
                  begin
                     return S.Add_Node
                       (Into, S.Node_Assignment, Adash.Source.Join (Start, Just_Consumed),
                        [Target, Value]);
                  end;
               end if;

               declare
                  Ignored : constant Boolean := Expect_Symbol (T.Delim_Semicolon);
                  pragma Unreferenced (Ignored);
               begin
                  return S.Add_Node
                    (Into, S.Node_Procedure_Call, Adash.Source.Join (Start, Just_Consumed),
                     [1 => Target]);
               end;
            end;
         end if;

         Complain (Adash.Messages.Msg_Expected_Statement);
         Recover;
         return Error_Node (Start);
      end Parse_Statement;

      -----------------------
      -- Parse_Subprogram --
      -----------------------

      --  subprogram ::= ("procedure" | "function") name [formals]
      --                 ["return" name] "is" declarations
      --                 "begin" statements "end" [name] ";"
      --
      --  Parsed as one construct rather than a specification and a body,
      --  because a submission is a single unit: there is nowhere to put a
      --  specification that a later body could complete, and accepting one
      --  would promise a separation the language does not have.
      function Parse_Subprogram return S.Node_Id is
         Start      : constant Adash.Source.Span := Here;
         Is_Func    : constant Boolean := Is_Word (T.Word_Function);
         Name       : S.Node_Id;
         Result     : S.Node_Id := S.No_Node;
         Formals    : S.Node_List (1 .. 64);
         Count      : Natural := 0;
         Declared   : S.Node_Id;
         Statements : S.Node_Id;
         Handled    : S.Node_Id;
      begin
         Advance;  --  procedure or function

         if T.Kind (Current) /= T.Token_Identifier then
            Complain (Adash.Messages.Msg_Expected_Subprogram_Name);
            Recover;
            return Error_Node (Adash.Source.Join (Start, Just_Consumed));
         end if;

         Name := S.Add_Leaf (Into, S.Node_Name, Here, T.Text (Current));
         Advance;

         declare
            Given : constant S.Node_Id := Parse_Formals;
         begin
            for Index in 1 .. S.Child_Count (Into, Given) loop
               exit when Count = Formals'Last;
               Count := Count + 1;
               Formals (Count) := S.Child (Into, Given, Index);
            end loop;
         end;

         if Is_Word (T.Word_Return) then
            Advance;

            if T.Kind (Current) /= T.Token_Identifier then
               Complain (Adash.Messages.Msg_Expected_Type_Name);
               Recover;
               return Error_Node (Adash.Source.Join (Start, Just_Consumed));
            end if;

            declare
               Named : Boolean;
            begin
               Result := Parse_Type_Mark (Named);

               if not Named then
                  Complain (Adash.Messages.Msg_Expected_Type_Name);
                  Recover;
                  return Error_Node
                    (Adash.Source.Join (Start, Just_Consumed));
               end if;
            end;

         elsif Is_Func then
            --  Caught here rather than left to the semantic pass: a function
            --  without a result type has no `is` to reach yet, and every later
            --  diagnostic would be about the wreckage.
            Complain (T.Spelling (T.Word_Return));
            Recover;
            return Error_Node (Adash.Source.Join (Start, Just_Consumed));
         end if;

         --  A specification rather than a body: the profile, then a
         --  semicolon where `is` would have been. What it buys is a name that
         --  exists before its body does, which is the only way two subprograms
         --  can call each other.
         if Is_Symbol (T.Delim_Semicolon) then
            Advance;

            return S.Add_Node
              (Into, S.Node_Subprogram_Declaration,
               Adash.Source.Join (Start, Just_Consumed),
               [Name,
                S.Add_Node (Into, S.Node_Sequence, Here, Formals (1 .. Count)),
                Result,

                --  No declarative part, no statements, no handlers. Their
                --  absence is what says this is a specification; a body always
                --  has all three sequences, empty or not.
                S.No_Node,
                S.No_Node,
                S.No_Node]);
         end if;

         if not Expect_Word (T.Word_Is) then
            Recover;
            return Error_Node (Adash.Source.Join (Start, Just_Consumed));
         end if;

         Declared   := Parse_Sequence (T.Word_Begin);
         Statements :=
           (if Expect_Word (T.Word_Begin)
            then Parse_Sequence (T.Word_End)
            else S.Add_Node (Into, S.Node_Sequence, Here, S.No_Children));

         --  A body answers for what went wrong the same way a block does, and
         --  is the same three parts: what it declares, what it does, and what
         --  it does about it.
         if Is_Word (T.Word_Exception) then
            Advance;
            Handled := Parse_Handlers;
         else
            Handled := S.Add_Node (Into, S.Node_Sequence, Just_Consumed, []);
         end if;

         if Is_Word (T.Word_End) then
            Advance;

            --  `end Name;` -- the name is optional in this grammar and is not
            --  checked against the one above. Ada requires them to match; that
            --  is a semantic rule, and reporting it here would mean the parser
            --  knowing what it just parsed.
            if T.Kind (Current) = T.Token_Identifier then
               Advance;
            end if;
         else
            Complain (T.Spelling (T.Word_End));
         end if;

         declare
            Ignored : constant Boolean := Expect_Symbol (T.Delim_Semicolon);
            pragma Unreferenced (Ignored);
         begin
            null;
         end;

         return S.Add_Node
           (Into, S.Node_Subprogram_Declaration,
            Adash.Source.Join (Start, Just_Consumed),
            [Name,
             S.Add_Node (Into, S.Node_Sequence, Here, Formals (1 .. Count)),
             Result,
             Declared,
             Statements,
             Handled]);
      end Parse_Subprogram;

      --------------------
      -- Parse_Sequence --
      --------------------

      --  The handlers of a block, in the order they were written.
      --
      --  Each answers for the exceptions it names, and `others` answers for
      --  what is left. Written as `when` alternatives, which is how a case
      --  writes its choices -- and means the same thing.
      function Parse_Handlers return S.Node_Id is
         Start     : constant Adash.Source.Span := Here;
         Collected : S.Node_List (1 .. 64);
         Count     : Natural := 0;
      begin
         while Is_Word (T.Word_When) and then Count < Collected'Last loop
            Advance;

            declare
               Opened  : constant Adash.Source.Span := Just_Consumed;
               Named   : S.Node_List (1 .. 32);
               Chosen  : Natural := 0;
            begin
               loop
                  exit when Chosen = Named'Last;
                  Chosen := Chosen + 1;

                  if Is_Word (T.Word_Others) then
                     Named (Chosen) :=
                       S.Add_Leaf (Into, S.Node_Others, Here);
                     Advance;
                  else
                     Named (Chosen) :=
                       S.Add_Leaf (Into, S.Node_Name, Here, T.Text (Current));

                     if T.Kind (Current) /= T.Token_Identifier then
                        Complain (Adash.Messages.Msg_Expected_Exception_Name);
                        Recover;
                        exit;
                     end if;

                     Advance;
                  end if;

                  exit when not Is_Symbol (T.Delim_Bar);
                  Advance;
               end loop;

               if not Expect_Symbol (T.Delim_Arrow) then
                  Recover;
                  exit;
               end if;

               declare
                  Listed : constant S.Node_Id :=
                    S.Add_Node
                      (Into, S.Node_Sequence,
                       Adash.Source.Join (Opened, Just_Consumed),
                       Named (1 .. Chosen));

                  Doing : constant S.Node_Id := Parse_Sequence (T.Word_End);
               begin
                  Count := Count + 1;
                  Collected (Count) :=
                    S.Add_Node
                      (Into, S.Node_Handler,
                       Adash.Source.Join (Opened, Just_Consumed),
                       [Listed, Doing]);
               end;
            end;
         end loop;

         return S.Add_Node
           (Into, S.Node_Sequence,
            Adash.Source.Join (Start, Just_Consumed), Collected (1 .. Count));
      end Parse_Handlers;

      --  One argument of a call: an expression, or a range.
      --
      --  A range is only meaningful where the call turns out to be a slice,
      --  and that is a question about what the name denotes -- so it is parsed
      --  here and refused, if it is nonsense, by the pass that knows.
      function Parse_Argument return S.Node_Id is
         Start : constant Adash.Source.Span := Here;
      begin
         --  `Name => Value`. Two tokens of lookahead settle it, and nothing
         --  else in an argument position begins with an identifier followed by
         --  an arrow -- `=>` appears in a case alternative and a handler, and
         --  neither is an argument.
         if T.Kind (Current) = T.Token_Identifier
           and then T.Kind (Ahead) = T.Token_Delimiter
           and then T.Symbol (Ahead) = T.Delim_Arrow
         then
            declare
               Name : constant S.Node_Id :=
                 S.Add_Leaf (Into, S.Node_Name, Here, T.Text (Current));
            begin
               Advance;
               Advance;

               declare
                  Given : constant S.Node_Id := Parse_Expression_Rule;
               begin
                  return S.Add_Node
                    (Into, S.Node_Named_Argument,
                     Adash.Source.Join (Start, S.Extent (Into, Given)),
                     [Name, Given]);
               end;
            end;
         end if;

         declare
            Low : constant S.Node_Id := Parse_Expression_Rule;
         begin
            if not Is_Symbol (T.Delim_Double_Dot) then
               return Expanded_Range (Low);
            end if;

            Advance;

            declare
               High : constant S.Node_Id := Parse_Expression_Rule;
            begin
               return S.Add_Node
                 (Into, S.Node_Range,
                  Adash.Source.Join (Start, Just_Consumed), [Low, High]);
            end;
         end;
      end Parse_Argument;

      --  A formal parameter list, or an empty one when none is written.
      --
      --  Written once because three things take one: a subprogram, a task
      --  entry, and the `accept` that meets a call to that entry. A second
      --  copy of this is a second place for `A, B : out Integer` to be read
      --  differently.
      function Parse_Formals return S.Node_Id is
         Start   : constant Adash.Source.Span := Here;
         Formals : S.Node_List (1 .. 64);
         Count   : Natural := 0;

         --  Recovery inside a formal list gives back an empty one and leaves
         --  the complaint that was already made: the caller's own recovery
         --  decides where to resume.
         Gave_Up : Boolean := False;
      begin
         if Is_Symbol (T.Delim_Left_Paren) then
            Advance;

            loop
               declare
                  --  `A, B : Integer` declares two parameters of one type, so
                  --  the names are collected before the type is known and the
                  --  nodes are built afterwards.
                  Names  : S.Node_List (1 .. 16);
                  Named  : Natural := 0;
                  Of_Type : S.Node_Id;

                  --  What the parameters default to, when one was written.
                  --  Shared by every name in the specification, exactly as the
                  --  type and the mode are: `A, B : Integer := 1` gives both
                  --  the same default.
                  Default : S.Node_Id := S.No_Node;

                  --  The mode belongs to the specification, not to each name:
                  --  `A, B : out Integer` gives both the same one.
                  Reads  : Boolean := False;
                  Writes : Boolean := False;
               begin
                  loop
                     if T.Kind (Current) /= T.Token_Identifier then
                        Complain (Adash.Messages.Msg_Expected_Parameter_Name);
                        Recover;
                        return Error_Node (Adash.Source.Join (Start, Just_Consumed));
                     end if;

                     exit when Named = Names'Last;
                     Named := Named + 1;
                     Names (Named) :=
                       S.Add_Leaf (Into, S.Node_Name, Here, T.Text (Current));
                     Advance;

                     exit when not Is_Symbol (T.Delim_Comma);
                     Advance;
                  end loop;

                  if not Expect_Symbol (T.Delim_Colon) then
                     Recover;
                     return Error_Node (Adash.Source.Join (Start, Just_Consumed));
                  end if;

                  --  `in`, `out` or `in out`. `in` is the default and may be
                  --  written; the order is fixed, so `out in` is not a mode
                  --  and falls through to be reported as a missing type name.
                  if Is_Word (T.Word_In) then
                     Reads := True;
                     Advance;
                  end if;

                  if Is_Word (T.Word_Out) then
                     Writes := True;
                     Advance;
                  end if;

                  declare
                     Named_It : Boolean;
                  begin
                     Of_Type := Parse_Type_Mark (Named_It);

                     if not Named_It then
                        Complain (Adash.Messages.Msg_Expected_Type_Name);
                        Recover;
                        return Error_Node
                          (Adash.Source.Join (Start, Just_Consumed));
                     end if;
                  end;

                  --  `:= <literal>`, a default. Parsed as a full expression so
                  --  that a wrong one is reported as what it is rather than as
                  --  a missing `;`; semantics is where it is held to being a
                  --  literal, because that is a rule about meaning.
                  if Is_Symbol (T.Delim_Assign) then
                     Advance;
                     Default := Parse_Expression_Rule;
                  end if;

                  for Index in 1 .. Named loop
                     exit when Count = Formals'Last;
                     Count := Count + 1;
                     --  The mode is the node's text, as `constant` is on an
                     --  object declaration: it is a property of one parameter,
                     --  and three node kinds would triple every place that
                     --  walks a parameter list.
                     Formals (Count) :=
                       (if Default = S.No_Node
                        then S.Add_Node
                               (Into, S.Node_Parameter, Here,
                                [Names (Index), Of_Type],
                                Text =>
                                  (if Writes and then Reads then "in out"
                                   elsif Writes then "out"
                                   else "in"))
                        else S.Add_Node
                               (Into, S.Node_Parameter, Here,
                                [Names (Index), Of_Type, Default],
                                Text =>
                                  (if Writes and then Reads then "in out"
                                   elsif Writes then "out"
                                   else "in")));
                  end loop;
               end;

               exit when not Is_Symbol (T.Delim_Semicolon);
               Advance;
            end loop;

            if not Expect_Symbol (T.Delim_Right_Paren) then
               Recover;
               Gave_Up := True;
            end if;
         end if;

         if Gave_Up then
            Count := 0;
         end if;

         return S.Add_Node
           (Into, S.Node_Sequence, Adash.Source.Join (Start, Just_Consumed),
            Formals (1 .. Count));
      end Parse_Formals;

      function Parse_Type_Mark (Ok : out Boolean) return S.Node_Id is
         Start  : constant Adash.Source.Span := Here;
         Spelt  : Ada.Strings.Unbounded.Unbounded_String;
      begin
         Ok := False;

         if T.Kind (Current) /= T.Token_Identifier then
            return S.No_Node;
         end if;

         Ada.Strings.Unbounded.Append (Spelt, T.Text (Current));
         Advance;

         while Is_Symbol (T.Delim_Dot)
           and then T.Kind (Ahead) = T.Token_Identifier
         loop
            Advance;
            Ada.Strings.Unbounded.Append (Spelt, ".");
            Ada.Strings.Unbounded.Append (Spelt, T.Text (Current));
            Advance;
         end loop;

         Ok := True;
         return S.Add_Leaf
           (Into, S.Node_Name, Adash.Source.Join (Start, Just_Consumed),
            Ada.Strings.Unbounded.To_String (Spelt));
      end Parse_Type_Mark;

      --  `procedure Q is new P (Integer);`
      function Parse_Instantiation return S.Node_Id is
         Start : constant Adash.Source.Span := Here;
         Named : S.Node_Id;
         From  : S.Node_Id;
         Given : S.Node_List (1 .. 16);
         Count : Natural := 0;
      begin
         Advance;  --  procedure or function

         if T.Kind (Current) /= T.Token_Identifier then
            Complain (Adash.Messages.Msg_Expected_Subprogram_Name);
            Recover;
            return Error_Node (Adash.Source.Join (Start, Just_Consumed));
         end if;

         Named := S.Add_Leaf (Into, S.Node_Name, Here, T.Text (Current));
         Advance;

         if not Expect_Word (T.Word_Is) or else not Expect_Word (T.Word_New)
         then
            Recover;
            return Error_Node (Adash.Source.Join (Start, Just_Consumed));
         end if;

         declare
            Named : Boolean;
         begin
            --  The generic may be a package member, so its name may carry
            --  dots -- `procedure Show_Int is new Tools.Show (Integer);`.
            From := Parse_Type_Mark (Named);

            if not Named then
               Complain (Adash.Messages.Msg_Expected_Subprogram_Name);
               Recover;
               return Error_Node (Adash.Source.Join (Start, Just_Consumed));
            end if;
         end;

         if Is_Symbol (T.Delim_Left_Paren) then
            Advance;

            loop
               exit when Count = Given'Last;
               Count := Count + 1;

               declare
                  Named : Boolean;
               begin
                  Given (Count) := Parse_Type_Mark (Named);

                  if not Named then
                     Complain (Adash.Messages.Msg_Expected_Type_Name);
                     Recover;
                     return Error_Node
                       (Adash.Source.Join (Start, Just_Consumed));
                  end if;
               end;

               exit when not Is_Symbol (T.Delim_Comma);
               Advance;
            end loop;

            if not Expect_Symbol (T.Delim_Right_Paren) then
               Recover;
               return Error_Node (Adash.Source.Join (Start, Just_Consumed));
            end if;
         end if;

         declare
            Ignored : constant Boolean := Expect_Symbol (T.Delim_Semicolon);
            pragma Unreferenced (Ignored);
         begin
            null;
         end;

         return S.Add_Node
           (Into, S.Node_Instantiation,
            Adash.Source.Join (Start, Just_Consumed),
            [Named, From,
             S.Add_Node
               (Into, S.Node_Sequence,
                Adash.Source.Join (Start, Just_Consumed),
                Given (1 .. Count))]);
      end Parse_Instantiation;

      --  One discrete choice: a value, a range of them, or `others`.
      function Parse_Choice return S.Node_Id is
         Start : constant Adash.Source.Span := Here;
      begin
         if Is_Word (T.Word_Others) then
            Advance;
            return S.Add_Leaf (Into, S.Node_Others, Start);
         end if;

         declare
            Low : constant S.Node_Id := Parse_Expression_Rule;
         begin
            --  `..` is not an operator of the expression grammar, so the
            --  expression above stops at it and this is where a range is
            --  recognised -- the same shape a for loop's bounds have.
            if not Is_Symbol (T.Delim_Double_Dot) then
               return Expanded_Range (Low);
            end if;

            Advance;

            declare
               High : constant S.Node_Id := Parse_Expression_Rule;
            begin
               return S.Add_Node
                 (Into, S.Node_Range,
                  Adash.Source.Join (Start, Just_Consumed), [Low, High]);
            end;
         end;
      end Parse_Choice;

      function Parse_Sequence (Stop_Words : T.Reserved_Word) return S.Node_Id is
         Start     : constant Adash.Source.Span := Here;
         Collected : S.Node_List (1 .. 512);
         Count     : Natural := 0;
      begin
         while not At_End loop
            exit when Is_Word (Stop_Words)
              or else Is_Word (T.Word_Else) or else Is_Word (T.Word_Elsif)

              --  `or` separates a select's alternatives and begins nothing.
              or else Is_Word (T.Word_Or)

              --  Nor does anything begin with `then`: it follows a condition,
              --  and `then abort` follows the statements a trigger runs.
              or else Is_Word (T.Word_Then)

              --  `end` always. Nothing in this language begins with it, and a
              --  declarative part asked to stop at `begin` has to stop at the
              --  `end` of a construct that had no `begin` -- which is what a
              --  package, a task declaration and a protected declaration are.
              or else Is_Word (T.Word_End)

              --  Nothing begins with `when` -- `exit when` is consumed by the
              --  exit statement itself -- so one here ends the alternative
              --  whose statements these are. Nor does anything begin with
              --  `exception`, which ends what a block does and begins what it
              --  does about what went wrong.
              or else Is_Word (T.Word_When)
              or else Is_Word (T.Word_Exception);
            exit when Count = Collected'Last;

            declare
               Before : constant Positive := State.Position;
               Item   : constant S.Node_Id := Parse_Statement;
            begin
               Count := Count + 1;
               Collected (Count) := Item;

               --  A statement that consumed nothing would loop for ever. This
               --  cannot happen while every path either advances or recovers,
               --  and the check is here because "cannot happen" in a parser is
               --  a claim that outlives the reasoning behind it.
               if State.Position = Before then
                  Advance;
               end if;
            end;
         end loop;

         return S.Add_Node
           (Into, S.Node_Sequence, Adash.Source.Join (Start, Just_Consumed),
            Collected (1 .. Count));
      end Parse_Sequence;

   begin
      Into.Clear;
      State.Origin := Origin;

      --  Only what the parser reads. Comments and error tokens are in the
      --  stream for the highlighter; filtering once here means no rule below
      --  has to remember to skip them.
      for Index in 1 .. From.Length loop
         if T.Is_Significant (From.Element (Index)) then
            State.Items.Append (From.Element (Index));
         end if;
      end loop;

      if Expression then
         declare
            Node : constant S.Node_Id := Parse_Expression_Rule;
         begin
            if not At_End then
               Complain (Adash.Messages.Msg_Expected_End_Of_Input);
            end if;

            Into.Set_Root (Node);
         end;
      else
         declare
            Node : constant S.Node_Id := Parse_Sequence (T.Word_End);
         begin
            Into.Set_Root (Node);
         end;
      end if;

      Unfinished := State.Ran_Out;
   end Run;

   -----------
   -- Parse --
   -----------

   procedure Parse
     (From   : T.Token_Stream;
      Origin : Adash.Source.Origin;
      Into   : out S.Tree;
      Report : in out D.List)
   is
      Unfinished : Boolean;
   begin
      Run (From, Origin, Into, Report, Expression => False, Unfinished => Unfinished);
   end Parse;

   ----------------------
   -- Parse_Expression --
   ----------------------

   procedure Parse_Expression
     (From   : T.Token_Stream;
      Origin : Adash.Source.Origin;
      Into   : out S.Tree;
      Report : in out D.List)
   is
      Unfinished : Boolean;
   begin
      Run (From, Origin, Into, Report, Expression => True, Unfinished => Unfinished);
   end Parse_Expression;

   ------------------
   -- Wants_More --
   ------------------

   function Wants_More
     (From   : T.Token_Stream;
      Origin : Adash.Source.Origin) return Boolean
   is
      Tree       : S.Tree;
      Aside      : D.List;
      Unfinished : Boolean;
   begin
      Run (From, Origin, Tree, Aside, Expression => False,
           Unfinished => Unfinished);

      --  Aside rather than reported: the caller is asking about text the user
      --  may still be typing, and a diagnostic about that is noise. Whatever
      --  is really wrong with it is reported when it is submitted.
      return Unfinished;
   end Wants_More;

end Adash.Language.Parser;
