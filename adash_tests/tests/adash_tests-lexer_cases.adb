with AUnit.Assertions;

with Adash.Diagnostics;
with Adash.Errors;
with Adash.Language.Lexer;
with Adash.Language.Tokens;
with Adash.Messages;
with Adash.Source;

package body Adash_Tests.Lexer_Cases is

   use AUnit.Assertions;

   package T renames Adash.Language.Tokens;
   package L renames Adash.Language.Lexer;
   package D renames Adash.Diagnostics;
   package Src renames Adash.Source;

   use type T.Token_Kind;
   use type T.Reserved_Word;
   use type T.Delimiter;
   use type D.Category;
   use type Adash.Messages.Message_Id;

   --  Lex a string and hand back the significant tokens only, which is what a
   --  parser would see.
   procedure Lex
     (Text   : String;
      Stream : out T.Token_Stream;
      Report : in out D.List)
   is
      Buffer : Src.Buffer;
      Error  : Adash.Errors.Error_Info;
   begin
      Assert (Src.Load (Buffer, Src.Make_Origin (Src.Origin_Text, "<lex>"), Text, Error),
              "the test source did not load");

      --  Fresh per call. Scan accumulates into Report by design -- a caller
      --  lexing several buffers wants one list -- so a test that asserts on
      --  counts has to start each case from empty.
      Report.Clear;
      L.Scan (Buffer, Stream, Report);
   end Lex;

   --  The Index'th significant token, skipping comments and error tokens.
   function Significant (Stream : T.Token_Stream; Index : Positive) return T.Token is
      Seen : Natural := 0;
   begin
      for Position in 1 .. Stream.Length loop
         if T.Is_Significant (Stream.Element (Position)) then
            Seen := Seen + 1;

            if Seen = Index then
               return Stream.Element (Position);
            end if;
         end if;
      end loop;

      return T.No_Token;
   end Significant;

   function Significant_Count (Stream : T.Token_Stream) return Natural is
      Seen : Natural := 0;
   begin
      for Position in 1 .. Stream.Length loop
         if T.Is_Significant (Stream.Element (Position)) then
            Seen := Seen + 1;
         end if;
      end loop;

      return Seen;
   end Significant_Count;

   ------------------------------------------------------------------
   --  The basics
   ------------------------------------------------------------------

   procedure A_Stream_Always_Ends_With_End_Of_Input
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Stream : T.Token_Stream;
      Report : D.List;
   begin
      --  Even for empty input, so a parser can read the first token without
      --  first checking whether there is one.
      Lex ("", Stream, Report);
      Assert (Stream.Length = 1, "an empty input did not produce exactly one token");
      Assert (T.Kind (Stream.Element (1)) = T.Token_End_Of_Input,
              "an empty input did not end with end-of-input");
      Assert (Report.Count = 0, "an empty input produced diagnostics");

      --  And for input that is entirely whitespace.
      Lex ("   " & Character'Val (10) & Character'Val (9), Stream, Report);
      Assert (Significant_Count (Stream) = 1,
              "whitespace produced tokens of its own");
   end A_Stream_Always_Ends_With_End_Of_Input;

   procedure Identifiers_And_Reserved_Words_Are_Told_Apart
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Stream : T.Token_Stream;
      Report : D.List;
      Word   : T.Reserved_Word;
   begin
      Lex ("Count begin BEGIN Beginning", Stream, Report);

      Assert (T.Kind (Significant (Stream, 1)) = T.Token_Identifier,
              "Count was not an identifier");
      Assert (T.Text (Significant (Stream, 1)) = "Count",
              "an identifier lost the user's spelling");

      --  Reserved words are case-insensitive, as Ada's are.
      Assert (T.Kind (Significant (Stream, 2)) = T.Token_Reserved_Word,
              "begin was not a reserved word");
      Assert (T.Word (Significant (Stream, 2)) = T.Word_Begin,
              "begin was the wrong reserved word");
      Assert (T.Kind (Significant (Stream, 3)) = T.Token_Reserved_Word,
              "BEGIN was not a reserved word");

      --  But a word that merely starts with one is a name.
      Assert (T.Kind (Significant (Stream, 4)) = T.Token_Identifier,
              "Beginning was taken for a reserved word");

      --  Every reserved word is recognized, including ones Adash does not yet
      --  accept -- `begin` used as a name is a lexical fact, and diagnosing it
      --  as an unsupported construct would be the wrong complaint.
      declare
         Recognized : constant Boolean := T.Is_Reserved ("protected", Word);
         Detail     : constant String := T.Reserved_Word'Image (Word);
      begin
         Assert (Recognized and then Word = T.Word_Protected,
                 "a reserved word Adash does not support was not recognized; got "
                 & Detail);
      end;
      declare
         Recognized : constant Boolean := T.Is_Reserved ("Count", Word);
         Detail     : constant String := T.Reserved_Word'Image (Word);
      begin
         Assert (not Recognized,
                 "a name was taken for a reserved word: " & Detail);
      end;
   end Identifiers_And_Reserved_Words_Are_Told_Apart;

   ------------------------------------------------------------------
   --  The corners
   ------------------------------------------------------------------

   procedure An_Apostrophe_Is_A_Quote_Or_A_Tick_By_Context
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Stream : T.Token_Stream;
      Report : D.List;
   begin
      --  After a name, an apostrophe marks an attribute.
      Lex ("X'Image", Stream, Report);
      Assert (T.Kind (Significant (Stream, 2)) = T.Token_Delimiter
              and then T.Symbol (Significant (Stream, 2)) = T.Delim_Apostrophe,
              "X'Image did not lex its apostrophe as an attribute marker");
      Assert (T.Kind (Significant (Stream, 3)) = T.Token_Identifier,
              "the attribute name did not lex as an identifier");
      Assert (Report.Count = 0, "X'Image produced a diagnostic");

      --  Elsewhere it opens a character literal.
      Lex ("C := 'a';", Stream, Report);
      Assert (T.Kind (Significant (Stream, 3)) = T.Token_Character_Literal,
              "'a' after an assignment did not lex as a character literal");
      Assert (T.Value (Significant (Stream, 3)) = "a",
              "a character literal lost its value");
      Assert (Report.Count = 0, "a character literal produced a diagnostic");

      --  After a closing parenthesis, an attribute again -- X(1)'Image.
      Lex ("X(1)'Image", Stream, Report);
      Assert (T.Symbol (Significant (Stream, 5)) = T.Delim_Apostrophe,
              "X(1)'Image did not lex its apostrophe as an attribute marker");
      Assert (Report.Count = 0, "X(1)'Image produced a diagnostic");

      --  The apostrophe character itself is three apostrophes, and looking for
      --  a closing quote rather than counting would get this wrong.
      Lex ("C := ''';", Stream, Report);
      Assert (T.Kind (Significant (Stream, 3)) = T.Token_Character_Literal,
              "''' did not lex as a character literal");
      Assert (T.Value (Significant (Stream, 3)) = "'",
              "''' did not denote an apostrophe");
   end An_Apostrophe_Is_A_Quote_Or_A_Tick_By_Context;

   procedure A_Dot_Is_A_Point_Or_Half_A_Range
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Stream : T.Token_Stream;
      Report : D.List;
   begin
      --  The classic. `1..5` is three tokens, not a malformed real followed by
      --  something -- consuming the first dot would turn a loop bound into a
      --  lexical error nowhere near the cause.
      Lex ("1..5", Stream, Report);
      Assert (Significant_Count (Stream) = 4,
              "1..5 did not lex as three tokens plus end-of-input; got"
              & Natural'Image (Significant_Count (Stream) - 1));
      Assert (T.Kind (Significant (Stream, 1)) = T.Token_Integer_Literal,
              "1..5 did not start with an integer");
      Assert (T.Symbol (Significant (Stream, 2)) = T.Delim_Double_Dot,
              "1..5 did not lex a range delimiter");
      Assert (T.Kind (Significant (Stream, 3)) = T.Token_Integer_Literal,
              "1..5 did not end with an integer");
      Assert (Report.Count = 0, "1..5 produced a diagnostic");

      --  And a real literal still works.
      Lex ("3.14", Stream, Report);
      Assert (T.Kind (Significant (Stream, 1)) = T.Token_Real_Literal,
              "3.14 did not lex as a real literal");
      Assert (Significant_Count (Stream) = 2, "3.14 lexed as more than one token");
   end A_Dot_Is_A_Point_Or_Half_A_Range;

   procedure Compound_Delimiters_Take_The_Longest_Match
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Stream : T.Token_Stream;
      Report : D.List;
   begin
      --  A ":=" read as ":" then "=" would parse as something else and the
      --  error would surface nowhere near its cause.
      Lex (":= => .. ** /= >= <= << >> <> : = < >", Stream, Report);

      Assert (T.Symbol (Significant (Stream, 1)) = T.Delim_Assign, ":= is wrong");
      Assert (T.Symbol (Significant (Stream, 2)) = T.Delim_Arrow, "=> is wrong");
      Assert (T.Symbol (Significant (Stream, 3)) = T.Delim_Double_Dot, ".. is wrong");
      Assert (T.Symbol (Significant (Stream, 4)) = T.Delim_Double_Star, "** is wrong");
      Assert (T.Symbol (Significant (Stream, 5)) = T.Delim_Not_Equal, "/= is wrong");
      Assert (T.Symbol (Significant (Stream, 6)) = T.Delim_Greater_Equal, ">= is wrong");
      Assert (T.Symbol (Significant (Stream, 7)) = T.Delim_Less_Equal, "<= is wrong");
      Assert (T.Symbol (Significant (Stream, 8)) = T.Delim_Left_Label, "<< is wrong");
      Assert (T.Symbol (Significant (Stream, 9)) = T.Delim_Right_Label, ">> is wrong");
      Assert (T.Symbol (Significant (Stream, 10)) = T.Delim_Box, "<> is wrong");
      Assert (T.Symbol (Significant (Stream, 11)) = T.Delim_Colon, ": is wrong");
      Assert (T.Symbol (Significant (Stream, 12)) = T.Delim_Equal, "= is wrong");
      Assert (T.Symbol (Significant (Stream, 13)) = T.Delim_Less, "< is wrong");
      Assert (T.Symbol (Significant (Stream, 14)) = T.Delim_Greater, "> is wrong");
      Assert (Report.Count = 0, "the delimiters produced diagnostics");
   end Compound_Delimiters_Take_The_Longest_Match;

   procedure Numeric_Literals_Follow_Adas_Shapes
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Stream : T.Token_Stream;
      Report : D.List;
   begin
      Lex ("1_000_000 16#FF# 2#1010#  1.0E10 16#F.F#E2", Stream, Report);
      Assert (Report.Count = 0,
              "well formed numeric literals produced diagnostics");
      Assert (T.Kind (Significant (Stream, 1)) = T.Token_Integer_Literal,
              "an underscored integer did not lex");
      Assert (T.Text (Significant (Stream, 1)) = "1_000_000",
              "an underscored integer lost its text");
      Assert (T.Kind (Significant (Stream, 2)) = T.Token_Integer_Literal,
              "a based literal did not lex");
      Assert (T.Kind (Significant (Stream, 4)) = T.Token_Real_Literal,
              "an exponent literal did not lex as real");
      Assert (T.Kind (Significant (Stream, 5)) = T.Token_Real_Literal,
              "a based real did not lex as real");
   end Numeric_Literals_Follow_Adas_Shapes;

   procedure Strings_Undouble_Their_Quotes
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Stream : T.Token_Stream;
      Report : D.List;
   begin
      Lex ("""say """"hi"""""" ", Stream, Report);
      Assert (Report.Count = 0, "a well formed string produced a diagnostic");
      Assert (T.Kind (Significant (Stream, 1)) = T.Token_String_Literal,
              "the string did not lex");

      --  Text is the source form, Value is what it denotes. Keeping both is
      --  what lets a formatter reproduce the source and an evaluator read the
      --  meaning.
      Assert (T.Value (Significant (Stream, 1)) = "say ""hi""",
              "a doubled quote was not reduced; got: "
              & T.Value (Significant (Stream, 1)));
      Assert (T.Text (Significant (Stream, 1)) = """say """"hi""""""",
              "the source form was not preserved");

      --  Non-ASCII is data and belongs in a string, even though identifiers are
      --  ASCII only.
      Lex ("""s" & Character'Val (16#C3#) & Character'Val (16#A5#) & "r""",
           Stream, Report);
      Assert (Report.Count = 0, "a string with non-ASCII bytes was rejected");
   end Strings_Undouble_Their_Quotes;

   ------------------------------------------------------------------
   --  Recovery
   ------------------------------------------------------------------

   procedure Comments_Are_Tokens_The_Parser_Skips
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Stream : T.Token_Stream;
      Report : D.List;
      Found  : Boolean := False;
   begin
      Lex ("X -- a remark" & Character'Val (10) & "Y", Stream, Report);

      --  In the stream, because a highlighter colours them and a formatter has
      --  to put them back.
      for Index in 1 .. Stream.Length loop
         if T.Kind (Stream.Element (Index)) = T.Token_Comment then
            Found := True;
            Assert (T.Text (Stream.Element (Index)) = "-- a remark",
                    "a comment lost its text: " & T.Text (Stream.Element (Index)));
         end if;
      end loop;

      Assert (Found, "the comment is not in the stream");

      --  But not significant, so the parser does not see it.
      Assert (Significant_Count (Stream) = 3,
              "the comment was significant to the parser");
      Assert (T.Kind (Significant (Stream, 2)) = T.Token_Identifier,
              "the token after the comment was not reached");
   end Comments_Are_Tokens_The_Parser_Skips;

   procedure Lexing_Never_Stops_At_The_First_Problem
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Stream : T.Token_Stream;
      Report : D.List;
   begin
      --  A stray byte is reported and skipped; the tokens after it still lex.
      --  The interactive frontend depends on this: it lexes text a user is
      --  still typing, which is malformed most of the time, and still has to
      --  highlight the part that is finished.
      Lex ("A $ B", Stream, Report);
      Assert (Report.Count = 1, "a stray character did not produce one diagnostic");
      Assert (D.Message (Report.Element (1))
              = Adash.Errors.Message (Adash.Errors.Error_Lexical_Stray_Character),
              "a stray character was reported as something else");
      Assert (D.Of_Kind (Report.Element (1)) = D.Category_Lexical,
              "a lexical problem was not categorised as lexical");
      Assert (Significant_Count (Stream) = 3,
              "lexing stopped at the stray character");

      --  An unterminated string ends at its line, so one missing quote gives
      --  one complaint rather than a cascade about the rest of the file.
      Lex ("X := ""oops" & Character'Val (10) & "Y := 1;", Stream, Report);
      Assert (Report.Count = 1,
              "an unterminated string did not produce exactly one diagnostic; got"
              & Natural'Image (Report.Count));
      --  X, :=, then the next line's Y -- the error token between them is not
      --  significant, so the parser's view skips straight over it.
      Assert (T.Kind (Significant (Stream, 3)) = T.Token_Identifier
              and then T.Text (Significant (Stream, 3)) = "Y",
              "the line after an unterminated string did not lex; token 3 is "
              & T.Text (Significant (Stream, 3)));

      --  A number running into letters is one malformed thing, not a number
      --  and a name that were never written.
      Lex ("12abc", Stream, Report);
      Assert (Report.Count = 1, "12abc did not produce one diagnostic");
      Assert (Significant_Count (Stream) = 1,
              "12abc was split into tokens that were never written");

      --  Ada's underscore rules.
      Lex ("Bad_", Stream, Report);
      Assert (Report.Count = 1, "a trailing underscore was accepted");
      Lex ("Two__Underscores", Stream, Report);
      Assert (Report.Count = 1, "a doubled underscore was accepted");
      Lex ("Good_Name", Stream, Report);
      Assert (Report.Count = 0, "a legal underscore was rejected");
   end Lexing_Never_Stops_At_The_First_Problem;

   procedure Tokens_Carry_Their_Extents
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Stream : T.Token_Stream;
      Report : D.List;
   begin
      Lex ("alpha := 12;", Stream, Report);

      Assert (T.Extent (Significant (Stream, 1)).First = 1
              and then T.Extent (Significant (Stream, 1)).Last = 5,
              "the first token's extent is wrong");
      Assert (T.Extent (Significant (Stream, 2)).First = 7,
              "the assignment's extent is wrong");

      --  What completion asks: the cursor is here, which token is it in?
      Assert (T.Kind (Stream.Token_At (3)) = T.Token_Identifier,
              "an offset inside the identifier did not find it");
      Assert (T.Kind (Stream.Token_At (10)) = T.Token_Integer_Literal,
              "an offset inside the literal did not find it");

      --  An offset in the whitespace between tokens belongs to neither, and
      --  saying so is honest: completion there starts a token rather than
      --  continuing one, and answering with the nearest would complete the
      --  wrong thing.
      Assert (T.Kind (Stream.Token_At (6)) = T.Token_End_Of_Input,
              "an offset in whitespace was attributed to a token");
   end Tokens_Carry_Their_Extents;

   ----------
   -- Name --
   ----------

   procedure Interpolation_Escapes_Are_Adas
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);

      --  Every escape Ada 2022 defines, and the character each produces.
      --
      --  These are not remembered. Each was compiled with GNAT under
      --  `pragma Extensions_Allowed (All)` and the resulting character read
      --  back, because an escape guessed wrong is a program that means one
      --  thing here and another under a real compiler -- the single failure
      --  this whole subset exists to prevent.
      type Case_Pair is record
         Written  : Character;
         Produces : Character;
      end record;

      Defined : constant array (Positive range <>) of Case_Pair :=
        [('{', '{'), ('}', '}'), ('\', '\'), ('"', '"'),
         ('n', Character'Val (10)), ('t', Character'Val (9)),
         ('r', Character'Val (13)), ('a', Character'Val (7)),
         ('b', Character'Val (8)), ('f', Character'Val (12)),
         ('v', Character'Val (11)), ('0', Character'Val (0))];

      --  Escapes other languages define and Ada 2022 does not. GNAT rejects
      --  each of these, so this build must too.
      Undefined : constant String := "exqzs1";
   begin
      for Item of Defined loop
         declare
            Stream : T.Token_Stream;
            Report : D.List;
            Buffer : Src.Buffer;
            Error  : Adash.Errors.Error_Info;
            Origin : constant Src.Origin :=
              Src.Make_Origin (Src.Origin_Text, "<lex>");
            Text   : constant String := "f""a\" & Item.Written & "b""";
         begin
            Assert (Src.Load (Buffer, Origin, Text, Error),
                    "the source did not load");
            Adash.Language.Lexer.Scan (Buffer, Stream, Report);

            Assert (Report.Count = 0,
                    "a defined escape was reported: \" & Item.Written);

            --  The literal arrives as one interpolation piece carrying the
            --  decoded text, so the escape is visible as the character it
            --  stands for and nothing else.
            Assert (T.Value (Stream.Element (1)) = "a" & Item.Produces & "b",
                    "escape \" & Item.Written & " produced the wrong character");
         end;
      end loop;

      for Written of Undefined loop
         declare
            Stream : T.Token_Stream;
            Report : D.List;
            Buffer : Src.Buffer;
            Error  : Adash.Errors.Error_Info;
            Origin : constant Src.Origin :=
              Src.Make_Origin (Src.Origin_Text, "<lex>");
            Text   : constant String := "f""a\" & Written & "b""";
         begin
            Assert (Src.Load (Buffer, Origin, Text, Error),
                    "the source did not load");
            Adash.Language.Lexer.Scan (Buffer, Stream, Report);

            Assert (Report.Count > 0,
                    "an escape Ada does not define was accepted: \" & Written);
         end;
      end loop;
   end Interpolation_Escapes_Are_Adas;

   overriding function Name (T : Case_Type) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Adash.Language.Lexer");
   end Name;

   --------------------
   -- Register_Tests --
   --------------------

   overriding procedure Register_Tests (T : in out Case_Type) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Interpolation_Escapes_Are_Adas'Access,
         "every interpolation escape produces the character GNAT produces");
      Register_Routine
        (T, A_Stream_Always_Ends_With_End_Of_Input'Access,
         "lexer : a stream always ends with end-of-input");
      Register_Routine
        (T, Identifiers_And_Reserved_Words_Are_Told_Apart'Access,
         "lexer : identifiers and reserved words are told apart, case-insensitively");
      Register_Routine
        (T, An_Apostrophe_Is_A_Quote_Or_A_Tick_By_Context'Access,
         "lexer : an apostrophe is a quote or a tick, by the previous token");
      Register_Routine
        (T, A_Dot_Is_A_Point_Or_Half_A_Range'Access,
         "lexer : 1..5 is a range, not a malformed real");
      Register_Routine
        (T, Compound_Delimiters_Take_The_Longest_Match'Access,
         "lexer : compound delimiters take the longest match");
      Register_Routine
        (T, Numeric_Literals_Follow_Adas_Shapes'Access,
         "lexer : numeric literals follow Ada's shapes");
      Register_Routine
        (T, Strings_Undouble_Their_Quotes'Access,
         "lexer : strings keep their source form and undouble their quotes");
      Register_Routine
        (T, Comments_Are_Tokens_The_Parser_Skips'Access,
         "lexer : comments are tokens the parser skips");
      Register_Routine
        (T, Lexing_Never_Stops_At_The_First_Problem'Access,
         "lexer : lexing recovers and never stops at the first problem");
      Register_Routine
        (T, Tokens_Carry_Their_Extents'Access,
         "lexer : tokens carry extents, and whitespace belongs to none");
   end Register_Tests;

end Adash_Tests.Lexer_Cases;
