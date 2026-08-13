with Ada.Characters.Handling;

package body Adash.Language.Tokens is

   use Ada.Strings.Unbounded;

   ----------
   -- Make --
   ----------

   function Make
     (Kind   : Token_Kind;
      Extent : Adash.Source.Span;
      Text   : String;
      Value  : String := "";
      Word   : Reserved_Word := Word_Abort;
      Symbol : Delimiter := Delim_Ampersand) return Token
   is
   begin
      return (Kind    => Kind,
              Extent  => Extent,
              Text    => To_Unbounded_String (Text),
              --  Which tokens carry a decoded value is a property of the kind,
              --  not of whether a caller remembered to pass one.
              --
              --  This used to read `if Value = "" then Text else Value`, using
              --  the empty string as a sentinel for "not supplied" -- and the
              --  empty string literal is a legal value, so `""` decoded to its
              --  own source text, quotes and all. Everything downstream then
              --  agreed with itself: `"" = ""` was True because both sides
              --  were the same two characters, and only concatenating one with
              --  something else made the extra characters visible.
              Value   =>
                To_Unbounded_String
                  (if Kind in Token_String_Literal | Token_Character_Literal
                            | Token_Interpolation_Start
                            | Token_Interpolation_Chunk
                   then Value else Text),
              Word    => Word,
              Symbol  => Symbol,
              Present => True);
   end Make;

   ----------
   -- Kind --
   ----------

   function Kind (Item : Token) return Token_Kind is
   begin
      return Item.Kind;
   end Kind;

   ------------
   -- Extent --
   ------------

   function Extent (Item : Token) return Adash.Source.Span is
   begin
      return Item.Extent;
   end Extent;

   ----------
   -- Text --
   ----------

   function Text (Item : Token) return String is
   begin
      return To_String (Item.Text);
   end Text;

   -----------
   -- Value --
   -----------

   function Value (Item : Token) return String is
   begin
      return To_String (Item.Value);
   end Value;

   ----------
   -- Word --
   ----------

   function Word (Item : Token) return Reserved_Word is
   begin
      return Item.Word;
   end Word;

   ------------
   -- Symbol --
   ------------

   function Symbol (Item : Token) return Delimiter is
   begin
      return Item.Symbol;
   end Symbol;

   ---------------------
   -- Is_Significant --
   ---------------------

   function Is_Significant (Item : Token) return Boolean is
   begin
      case Item.Kind is
         when Token_Comment | Token_Error =>
            --  Both are in the stream because a highlighter and a diagnostic
            --  need them. Neither is something the parser reads.
            return False;

         when Token_End_Of_Input | Token_Identifier | Token_Reserved_Word
            | Token_Integer_Literal | Token_Real_Literal
            | Token_Character_Literal | Token_String_Literal
            | Token_Delimiter
            | Token_Interpolation_Start | Token_Interpolation_Chunk
            | Token_Interpolation_End =>
            return True;
      end case;
   end Is_Significant;

   ---------------
   -- Spelling --
   ---------------

   function Spelling (Item : Reserved_Word) return String is
      Image : constant String := Reserved_Word'Image (Item);
      Bare  : constant String := Image (Image'First + 5 .. Image'Last);
      Result : String := Bare;
   begin
      --  The literals are Word_<NAME>; the spelling is the name in lower case.
      --  Derived rather than tabulated, so a word added to the type cannot be
      --  added without its spelling.
      for Index in Result'Range loop
         Result (Index) := Ada.Characters.Handling.To_Lower (Result (Index));
      end loop;

      return Result;
   end Spelling;

   ---------------
   -- Spelling --
   ---------------

   function Spelling (Item : Delimiter) return String is
   begin
      case Item is
         when Delim_Ampersand     => return "&";
         when Delim_Apostrophe    => return "'";
         when Delim_Left_Paren    => return "(";
         when Delim_Right_Paren   => return ")";
         when Delim_Star          => return "*";
         when Delim_Plus          => return "+";
         when Delim_Comma         => return ",";
         when Delim_Minus         => return "-";
         when Delim_Dot           => return ".";
         when Delim_Slash         => return "/";
         when Delim_Colon         => return ":";
         when Delim_Semicolon     => return ";";
         when Delim_Less          => return "<";
         when Delim_Equal         => return "=";
         when Delim_Greater       => return ">";
         when Delim_Bar           => return "|";
         when Delim_Arrow         => return "=>";
         when Delim_Double_Dot    => return "..";
         when Delim_Double_Star   => return "**";
         when Delim_Assign        => return ":=";
         when Delim_Not_Equal     => return "/=";
         when Delim_Greater_Equal => return ">=";
         when Delim_Less_Equal    => return "<=";
         when Delim_Left_Label    => return "<<";
         when Delim_Right_Label   => return ">>";
         when Delim_Box           => return "<>";
      end case;
   end Spelling;

   -------------------
   -- Is_Reserved --
   -------------------

   function Is_Reserved (Name : String; Into : out Reserved_Word) return Boolean is
      Folded : String := Name;
   begin
      Into := Word_Abort;

      for Index in Folded'Range loop
         Folded (Index) := Ada.Characters.Handling.To_Lower (Folded (Index));
      end loop;

      --  Linear over about seventy words, on a token that is usually not one.
      --  A perfect hash would be faster and would need a generator; at this
      --  size the scan is not what makes lexing slow.
      for Candidate in Reserved_Word loop
         if Spelling (Candidate) = Folded then
            Into := Candidate;
            return True;
         end if;
      end loop;

      return False;
   end Is_Reserved;

   ------------
   -- Length --
   ------------

   function Length (Item : Token_Stream) return Natural is
   begin
      return Natural (Item.Entries.Length);
   end Length;

   -------------
   -- Element --
   -------------

   function Element (Item : Token_Stream; Index : Positive) return Token is
   begin
      if Index > Natural (Item.Entries.Length) then
         return No_Token;
      end if;

      return Item.Entries.Element (Index);
   end Element;

   ---------------
   -- Token_At --
   ---------------

   function Token_At
     (Item   : Token_Stream;
      Offset : Adash.Source.Byte_Offset) return Token
   is
   begin
      for Current of Item.Entries loop
         if Current.Kind /= Token_End_Of_Input
           and then Offset >= Current.Extent.First
           and then Offset <= Current.Extent.Last
         then
            return Current;
         end if;
      end loop;

      --  Between two tokens, or past the end. No_Token is the honest answer:
      --  completion there is starting a token rather than continuing one, and
      --  returning the nearest would make it complete the wrong thing.
      return No_Token;
   end Token_At;

   -----------
   -- Clear --
   -----------

   procedure Clear (Item : in out Token_Stream) is
   begin
      Item.Entries.Clear;
   end Clear;

   ------------
   -- Append --
   ------------

   procedure Append (Item : in out Token_Stream; Entry_To_Add : Token) is
   begin
      Item.Entries.Append (Entry_To_Add);
   end Append;

end Adash.Language.Tokens;
