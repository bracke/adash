with Ada.Characters.Handling;
with Ada.Strings.Unbounded;

with Adash.Errors;
with Adash.Messages;

package body Adash.Language.Lexer is

   package T renames Adash.Language.Tokens;
   package D renames Adash.Diagnostics;

   use type T.Token_Kind;
   use type T.Reserved_Word;
   use type T.Delimiter;

   LF : constant Character := Character'Val (10);
   CR : constant Character := Character'Val (13);

   ---------------------------
   -- Is_Identifier_Start --
   ---------------------------

   function Is_Identifier_Start (Item : Character) return Boolean is
   begin
      --  Ada.Characters.Handling, not the C library's isalpha: this answer must
      --  not depend on the process locale. See the note in the specification
      --  about why identifiers are ASCII.
      return Ada.Characters.Handling.Is_Letter (Item)
        and then Character'Pos (Item) < 128;
   end Is_Identifier_Start;

   --------------------------
   -- Is_Identifier_Part --
   --------------------------

   function Is_Identifier_Part (Item : Character) return Boolean is
   begin
      return Is_Identifier_Start (Item)
        or else (Item in '0' .. '9')
        or else Item = '_';
   end Is_Identifier_Part;

   ----------
   -- Scan --
   ----------

   procedure Scan
     (From   : Adash.Source.Buffer;
      Into   : out Adash.Language.Tokens.Token_Stream;
      Report : in out Adash.Diagnostics.List)
   is
      Text  : constant String := Adash.Source.Text (From);
      Last  : constant Natural := Text'Last;
      Index : Natural := Text'First;

      --  Whether an apostrophe here would be an attribute marker rather than
      --  the start of a character literal. True after anything a name can end
      --  with. This is the whole of the context the lexer keeps.
      After_Name : Boolean := False;

      --  How many interpolated string literals we are inside the *expression*
      --  part of. A counter rather than a flag because an interpolated literal
      --  can appear inside one: `f"a{f""b""}c"`. It is what tells a closing
      --  brace apart from a stray one -- outside an interpolation `}` is not
      --  an Ada delimiter at all.
      Interpolations : Natural := 0;

      function At_End return Boolean is (Index > Last);

      function Peek (Ahead : Natural := 0) return Character
      is (if Index + Ahead > Last then Character'Val (0) else Text (Index + Ahead));

      procedure Emit
        (Kind   : T.Token_Kind;
         First  : Positive;
         Stop   : Natural;
         Value  : String := "";
         Word   : T.Reserved_Word := T.Word_Abort;
         Symbol : T.Delimiter := T.Delim_Ampersand);

      procedure Complain
        (Code  : Adash.Errors.Error_Code;
         First : Positive;
         Stop  : Natural;
         Detail : String := "");

      procedure Scan_Identifier_Or_Word;
      procedure Scan_Number;
      procedure Scan_String;
      procedure Scan_Interpolation (Opening : Boolean);
      procedure Scan_Character_Literal;
      procedure Scan_Comment;
      procedure Scan_Delimiter;

      ----------
      -- Emit --
      ----------

      procedure Emit
        (Kind   : T.Token_Kind;
         First  : Positive;
         Stop   : Natural;
         Value  : String := "";
         Word   : T.Reserved_Word := T.Word_Abort;
         Symbol : T.Delimiter := T.Delim_Ampersand)
      is
         Extent : constant Adash.Source.Span := (First => First, Last => Stop);
      begin
         Into.Append
           (T.Make (Kind, Extent, Adash.Source.Slice (From, Extent),
                    Value, Word, Symbol));
      end Emit;

      --------------
      -- Complain --
      --------------

      procedure Complain
        (Code   : Adash.Errors.Error_Code;
         First  : Positive;
         Stop   : Natural;
         Detail : String := "")
      is
         Extent : constant Adash.Source.Span := (First => First, Last => Stop);

         --  The placeholder a lexical message expects differs by code, and the
         --  identifier knows which. Asking Adash.Messages rather than guessing
         --  keeps the two from drifting.
         Names : constant Adash.Messages.Placeholder_Names :=
           Adash.Messages.Placeholders (Adash.Errors.Message (Code));
      begin
         Report.Emit
           (D.Make
              (Message   => Adash.Errors.Message (Code),
               Level     => D.Severity_Error,
               Of_Kind   => D.Category_Lexical,
               Raised_By => D.Owner_Language,
               Origin    => Adash.Source.From (From),
               Extent    => Extent,
               Arguments =>
                 (if Names'Length = 0
                  then Adash.Messages.No_Arguments
                  else [1 => Adash.Messages.Named
                               (Ada.Strings.Unbounded.To_String (Names (Names'First)),
                                (if Detail = ""
                                 then Adash.Source.Slice (From, Extent)
                                 else Detail))])));

         Emit (T.Token_Error, First, Stop);
      end Complain;

      --------------------------------
      -- Scan_Identifier_Or_Word --
      --------------------------------

      procedure Scan_Identifier_Or_Word is
         First      : constant Positive := Index;
         Bad_Shape  : Boolean := False;
         Word       : T.Reserved_Word;
      begin
         while not At_End and then Is_Identifier_Part (Peek) loop
            --  Ada forbids a doubled underscore and a trailing one. Recorded
            --  and reported once at the end rather than stopping here, so the
            --  whole name is consumed and the next token starts where a reader
            --  expects it to.
            if Peek = '_'
              and then (Index = First
                        or else Text (Index - 1) = '_'
                        or else Index = Last
                        or else not Is_Identifier_Part (Peek (1)))
            then
               Bad_Shape := True;
            end if;

            Index := Index + 1;
         end loop;

         declare
            Stop : constant Natural := Index - 1;
            Name : constant String := Text (First .. Stop);
         begin
            if Bad_Shape then
               Complain (Adash.Errors.Error_Lexical_Malformed_Identifier,
                         First, Stop, Name);
               After_Name := False;
               return;
            end if;

            if T.Is_Reserved (Name, Word) then
               Emit (T.Token_Reserved_Word, First, Stop, Word => Word);

               --  `all` can end a name, as in `X.all'Address`. The other
               --  reserved words cannot, so an apostrophe after them opens a
               --  character literal.
               After_Name := Word = T.Word_All;
            else
               Emit (T.Token_Identifier, First, Stop);
               After_Name := True;
            end if;
         end;
      end Scan_Identifier_Or_Word;

      -----------------
      -- Scan_Number --
      -----------------

      procedure Scan_Number is
         First    : constant Positive := Index;
         Is_Real  : Boolean := False;
         Malformed : Boolean := False;

         procedure Take_Digits (Base_Digits : Boolean);

         --  Digits with underscores between them, never leading, trailing or
         --  doubled.
         procedure Take_Digits (Base_Digits : Boolean) is
            Seen : Boolean := False;
         begin
            loop
               exit when At_End;

               if Peek in '0' .. '9'
                 or else (Base_Digits
                          and then (Peek in 'a' .. 'f' or else Peek in 'A' .. 'F'))
               then
                  Seen  := True;
                  Index := Index + 1;

               elsif Peek = '_' then
                  if not Seen then
                     Malformed := True;
                  end if;

                  Index := Index + 1;

                  if At_End
                    or else not (Peek in '0' .. '9'
                                 or else (Base_Digits
                                          and then (Peek in 'a' .. 'f'
                                                    or else Peek in 'A' .. 'F')))
                  then
                     Malformed := True;
                  end if;

               else
                  exit;
               end if;
            end loop;

            if not Seen then
               Malformed := True;
            end if;
         end Take_Digits;

      begin
         Take_Digits (Base_Digits => False);

         if not At_End and then Peek = '#' then
            --  A based literal: 16#FF#, 2#1010#E4. The digits after the first
            --  '#' may be hexadecimal whatever the base says -- checking that
            --  they fit the base is a semantic question about the value, not a
            --  lexical one about the shape.
            Index := Index + 1;
            Take_Digits (Base_Digits => True);

            if not At_End and then Peek = '.' then
               Is_Real := True;
               Index := Index + 1;
               Take_Digits (Base_Digits => True);
            end if;

            if not At_End and then Peek = '#' then
               Index := Index + 1;
            else
               Malformed := True;
            end if;

         else
            --  A decimal literal. The dot only makes it real when a digit
            --  follows: in `1..5` the dots are a range, and consuming the first
            --  one would turn a loop bound into a malformed number.
            if not At_End
              and then Peek = '.'
              and then Peek (1) in '0' .. '9'
            then
               Is_Real := True;
               Index := Index + 1;
               Take_Digits (Base_Digits => False);
            end if;
         end if;

         --  An exponent, on either form.
         if not At_End and then (Peek = 'e' or else Peek = 'E') then
            Index := Index + 1;

            if not At_End and then (Peek = '+' or else Peek = '-') then
               Index := Index + 1;
            end if;

            Take_Digits (Base_Digits => False);
         end if;

         declare
            Stop : constant Natural := Index - 1;
         begin
            --  A literal running straight into a letter is a typo, not two
            --  tokens: `12abc` is one malformed thing, and splitting it would
            --  produce a number and an identifier that were never written.
            if not At_End and then Is_Identifier_Start (Peek) then
               while not At_End and then Is_Identifier_Part (Peek) loop
                  Index := Index + 1;
               end loop;

               Complain (Adash.Errors.Error_Lexical_Malformed_Number,
                         First, Index - 1, Text (First .. Index - 1));
               After_Name := False;
               return;
            end if;

            if Malformed then
               Complain (Adash.Errors.Error_Lexical_Malformed_Number,
                         First, Stop, Text (First .. Stop));
               After_Name := False;
               return;
            end if;

            Emit ((if Is_Real then T.Token_Real_Literal else T.Token_Integer_Literal),
                  First, Stop);

            --  A literal can be followed by an attribute: 1'Image is legal Ada.
            After_Name := True;
         end;
      end Scan_Number;

      -----------------
      -- Scan_String --
      -----------------

      procedure Scan_String is
         First : constant Positive := Index;
         Body_Text : Ada.Strings.Unbounded.Unbounded_String;
      begin
         Index := Index + 1;  --  the opening quote

         loop
            if At_End or else Peek = LF or else Peek = CR then
               --  Unterminated. It ends at the end of the line rather than
               --  swallowing the rest of the file: a user who forgot a quote
               --  gets one complaint about one line, not a cascade about
               --  everything after it.
               Complain (Adash.Errors.Error_Lexical_Unterminated_String,
                         First, Index - 1);
               After_Name := False;
               return;
            end if;

            if Peek = '"' then
               if Peek (1) = '"' then
                  --  A doubled quote is one quote in the value.
                  Ada.Strings.Unbounded.Append (Body_Text, '"');
                  Index := Index + 2;
               else
                  Index := Index + 1;
                  exit;
               end if;
            else
               Ada.Strings.Unbounded.Append (Body_Text, Peek);
               Index := Index + 1;
            end if;
         end loop;

         Emit (T.Token_String_Literal, First, Index - 1,
               Ada.Strings.Unbounded.To_String (Body_Text));

         --  A string literal can be an operator symbol, which a name can end
         --  with: "+"'Address is legal.
         After_Name := True;
      end Scan_String;

      -------------------------
      -- Scan_Interpolation --
      -------------------------

      --  Scan the literal text of an interpolated string.
      --
      --  Called with Opening True just after `f"`, and with it False just
      --  after the `}` that ended an expression. Either way it runs to the
      --  next `{` or to the closing quote, emits the piece it collected, and
      --  hands the expression tokens back to the main loop -- which lexes them
      --  exactly as it lexes anything else, so they carry their own spans.
      procedure Scan_Interpolation (Opening : Boolean) is
         First : constant Positive := Index;
         Piece : Ada.Strings.Unbounded.Unbounded_String;

         Kind : constant T.Token_Kind :=
           (if Opening then T.Token_Interpolation_Start
            else T.Token_Interpolation_Chunk);
      begin
         --  `f"` or `}`.
         Index := Index + (if Opening then 2 else 1);

         loop
            if At_End or else Peek = LF or else Peek = CR then
               --  Ends at the end of the line, as an ordinary literal does.
               Complain (Adash.Errors.Error_Lexical_Unterminated_String,
                         First, Index - 1);

               if not Opening then
                  Interpolations := Interpolations - 1;
               end if;

               After_Name := False;
               return;
            end if;

            if Peek = '"' then
               if Peek (1) = '"' then
                  --  Not one quote. Ada 2022 forbids a doubled quote inside an
                  --  interpolated literal outright -- the escape is what puts a
                  --  quote in one -- and accepting it here would take a program
                  --  a real compiler rejects.
                  --  Said, and then taken as the quote it was meant to be, so
                  --  that the literal still ends where its closing quote is.
                  --  Giving up here left the rest of the line to be scanned as
                  --  code, and the closing quote began a literal of its own.
                  Complain (Adash.Errors.Error_Lexical_Quote_In_Interpolation,
                            Index, Index + 1);
                  Ada.Strings.Unbounded.Append (Piece, '"');
                  Index := Index + 2;
               else
                  Index := Index + 1;
                  Emit (Kind, First, Index - 1,
                        Ada.Strings.Unbounded.To_String (Piece));
                  Emit (T.Token_Interpolation_End, Index - 1, Index - 1);

                  if not Opening then
                     Interpolations := Interpolations - 1;
                  end if;

                  After_Name := True;
                  return;
               end if;

            elsif Peek = '\' then
               --  Ada 2022's escape set, all twelve of it. The characters
               --  each produces were not taken from memory: every one was
               --  compiled with GNAT and its result read back, because an
               --  escape guessed wrong is a program that means one thing here
               --  and another under a real compiler.
               --
               --  Anything else is refused by name. `\e` and `\x41` are not
               --  escapes in Ada 2022, whatever other languages do with them.
               case Peek (1) is
                  when '{' | '}' | '\' | '"' =>
                     Ada.Strings.Unbounded.Append (Piece, Peek (1));
                     Index := Index + 2;

                  when 'n' | 't' | 'r' | 'a' | 'b' | 'f' | 'v' | '0' =>
                     Ada.Strings.Unbounded.Append
                       (Piece,
                        (case Peek (1) is
                            when 'n'    => Character'Val (10),   --  line feed
                            when 't'    => Character'Val (9),    --  tab
                            when 'r'    => Character'Val (13),   --  return
                            when 'a'    => Character'Val (7),    --  alert
                            when 'b'    => Character'Val (8),    --  backspace
                            when 'f'    => Character'Val (12),   --  form feed
                            when 'v'    => Character'Val (11),   --  vertical
                            when others => Character'Val (0)));  --  nul
                     Index := Index + 2;

                  when others =>
                     --  Said, and then taken as the character it follows, for
                     --  the same reason the other two are: what a reader needs
                     --  is the escape named once, not the rest of the line
                     --  read as something it is not.
                     Complain (Adash.Errors.Error_Lexical_Bad_Escape,
                               Index, Index + 1);
                     Ada.Strings.Unbounded.Append (Piece, Peek (1));
                     Index := Index + 2;
               end case;

            elsif Peek = '{' then
               Index := Index + 1;
               Emit (Kind, First, Index - 1,
                     Ada.Strings.Unbounded.To_String (Piece));

               if Opening then
                  Interpolations := Interpolations + 1;
               end if;

               After_Name := False;
               return;

            elsif Peek = '}' then
               --  A brace that closes nothing. Written as it is, it would read
               --  as the end of an expression that never began.
               --
               --  Said, and then taken as the character it looks like, because
               --  giving up on the literal here costs more than the mistake
               --  did: the closing quote was read as the *start* of a literal,
               --  so `put_line (f"closes } nothing");` -- one wrong byte on a
               --  finished line -- came back as an unterminated string, a
               --  missing bracket and a missing semicolon, and `Wants_More`
               --  told an interactive frontend to go on reading a line that
               --  was already whole.
               Complain (Adash.Errors.Error_Lexical_Brace_Unescaped,
                         Index, Index);
               Ada.Strings.Unbounded.Append (Piece, Peek);
               Index := Index + 1;

            else
               Ada.Strings.Unbounded.Append (Piece, Peek);
               Index := Index + 1;
            end if;
         end loop;
      end Scan_Interpolation;

      -------------------------------
      -- Scan_Character_Literal --
      -------------------------------

      procedure Scan_Character_Literal is
         First : constant Positive := Index;
      begin
         --  One character between two apostrophes. The character may be any
         --  byte including another apostrophe -- ''' is the apostrophe
         --  character -- which is why this looks two ahead rather than
         --  scanning for a closing quote.
         if Index + 2 <= Last and then Text (Index + 2) = ''' then
            Index := Index + 3;
            Emit (T.Token_Character_Literal, First, Index - 1,
                  Text (First + 1 .. First + 1));
            After_Name := True;
            return;
         end if;

         Complain (Adash.Errors.Error_Lexical_Unterminated_Character,
                   First, Natural'Min (First + 1, Last));
         Index := First + 1;
         After_Name := False;
      end Scan_Character_Literal;

      ------------------
      -- Scan_Comment --
      ------------------

      procedure Scan_Comment is
         First : constant Positive := Index;
      begin
         while not At_End and then Peek /= LF and then Peek /= CR loop
            Index := Index + 1;
         end loop;

         Emit (T.Token_Comment, First, Index - 1);

         --  A comment does not end a name. Whatever preceded it still governs
         --  what an apostrophe after it means, so After_Name is left alone.
      end Scan_Comment;

      --------------------
      -- Scan_Delimiter --
      --------------------

      procedure Scan_Delimiter is
         First : constant Positive := Index;

         procedure Take (Length : Positive; Symbol : T.Delimiter);

         procedure Take (Length : Positive; Symbol : T.Delimiter) is
         begin
            Index := Index + Length;
            Emit (T.Token_Delimiter, First, Index - 1, Symbol => Symbol);

            --  Only a closing parenthesis can end a name: X(1)'Image. After
            --  every other delimiter an apostrophe opens a character literal.
            After_Name := Symbol = T.Delim_Right_Paren;
         end Take;

         Here : constant Character := Peek;
         Next : constant Character := Peek (1);
      begin
         --  Longest match first, always. A ":=" read as ":" then "=" would
         --  parse as something else entirely and the error would be reported
         --  nowhere near the cause.
         case Here is
            when '=' =>
               if Next = '>' then
                  Take (2, T.Delim_Arrow);
               else
                  Take (1, T.Delim_Equal);
               end if;

            when '.' =>
               if Next = '.' then
                  Take (2, T.Delim_Double_Dot);
               else
                  Take (1, T.Delim_Dot);
               end if;

            when '*' =>
               if Next = '*' then
                  Take (2, T.Delim_Double_Star);
               else
                  Take (1, T.Delim_Star);
               end if;

            when ':' =>
               if Next = '=' then
                  Take (2, T.Delim_Assign);
               else
                  Take (1, T.Delim_Colon);
               end if;

            when '/' =>
               if Next = '=' then
                  Take (2, T.Delim_Not_Equal);
               else
                  Take (1, T.Delim_Slash);
               end if;

            when '>' =>
               if Next = '=' then
                  Take (2, T.Delim_Greater_Equal);
               elsif Next = '>' then
                  Take (2, T.Delim_Right_Label);
               else
                  Take (1, T.Delim_Greater);
               end if;

            when '<' =>
               if Next = '=' then
                  Take (2, T.Delim_Less_Equal);
               elsif Next = '<' then
                  Take (2, T.Delim_Left_Label);
               elsif Next = '>' then
                  Take (2, T.Delim_Box);
               else
                  Take (1, T.Delim_Less);
               end if;

            when '&' => Take (1, T.Delim_Ampersand);
            when '(' => Take (1, T.Delim_Left_Paren);
            when ')' => Take (1, T.Delim_Right_Paren);
            when '+' => Take (1, T.Delim_Plus);
            when ',' => Take (1, T.Delim_Comma);
            when '-' => Take (1, T.Delim_Minus);
            when ';' => Take (1, T.Delim_Semicolon);
            when '|' => Take (1, T.Delim_Bar);
            when ''' => Take (1, T.Delim_Apostrophe);

            when others =>
               Complain (Adash.Errors.Error_Lexical_Stray_Character,
                         First, First);
               Index := First + 1;
               After_Name := False;
         end case;
      end Scan_Delimiter;

   begin
      --  Replaced, as the specification says. An `out` parameter of a record
      --  type is not reliably emptied on entry, and a Scan that appended to
      --  whatever was already there would make a stream reused across two
      --  buffers hold both -- which is exactly what a REPL does with one
      --  stream and many lines.
      Into.Clear;

      while not At_End loop
         --  Whitespace is not a token: it is the gap between adjacent spans,
         --  and nothing needs it as an object.
         if Peek = ' ' or else Peek = Character'Val (9)
           or else Peek = LF or else Peek = CR
         then
            Index := Index + 1;

         elsif Peek = '-' and then Peek (1) = '-' then
            Scan_Comment;

         elsif (Peek = 'f' or else Peek = 'F') and then Peek (1) = '"' then
            --  Before the identifier rule, which would otherwise take the `f`
            --  and leave an ordinary string behind it.
            Scan_Interpolation (Opening => True);

         elsif Peek = '}' and then Interpolations > 0 then
            Scan_Interpolation (Opening => False);

         elsif Is_Identifier_Start (Peek) then
            Scan_Identifier_Or_Word;

         elsif Peek in '0' .. '9' then
            Scan_Number;

         elsif Peek = '"' then
            Scan_String;

         elsif Peek = ''' and then not After_Name then
            Scan_Character_Literal;

         else
            Scan_Delimiter;
         end if;
      end loop;

      --  Always, even for empty input and even when every byte was rejected, so
      --  a parser can read the first token without checking there is one.
      --  An empty span just past the last byte. For an empty buffer that is
      --  (1, 0), which is empty and in range; computing it as Last - 1 made it
      --  (1, -1) and raised, because a span's Last is a Natural.
      Into.Append
        (T.Make (T.Token_End_Of_Input, (First => Last + 1, Last => Last), ""));
   end Scan;

end Adash.Language.Lexer;
