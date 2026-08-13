private with Ada.Containers.Vectors;
private with Ada.Strings.Unbounded;

with Adash.Source;

--  The lexical elements of the Adash language.
--
--  A token is immutable and carries its exact extent in the buffer it came
--  from. Everything downstream depends on that: a parse error points at a
--  token, a highlighter colours one, and completion asks which token the cursor
--  is in. A token model that recorded only what something *is* and not where it
--  was would make all three impossible.
--
--  Comments are tokens. They are not whitespace to be discarded: an editor
--  colours them, a formatter has to put them back, and a documentation tool
--  reads them. The parser skips them, which is a decision the parser makes
--  rather than one the lexer makes for it.
--
--  Whitespace is not a token. It is the gap between adjacent spans, derivable
--  from the stream without doubling its size, and nothing needs it as an
--  object.
--
--  Reserved words are recognized here in full, including the ones the Adash
--  language subset does not yet accept. That is deliberate: `begin` used as a
--  variable name is a *lexical* fact, and reporting it as an unsupported
--  construct rather than as a misuse of a reserved word would be the wrong
--  diagnostic. Which reserved words Adash actually accepts is a semantic
--  question, answered later.
package Adash.Language.Tokens is

   --  What a token is.
   type Token_Kind is
     (
      --  There is no more input. Always the last token of a stream, so a parser
      --  never has to test for the end separately from testing what is next.
      Token_End_Of_Input,

      --  A name.
      Token_Identifier,

      --  One of Ada's reserved words; see Word.
      Token_Reserved_Word,

      --  An integer literal, decimal or based.
      Token_Integer_Literal,

      --  A real literal.
      Token_Real_Literal,

      --  A character literal, in single quotes.
      Token_Character_Literal,

      --  A string literal, in double quotes.
      Token_String_Literal,

      --  A comment, from "--" to the end of its line, not including the line
      --  terminator.
      --  The three pieces of an interpolated string literal, `f"a{X}b"`.
      --
      --  Three tokens rather than one, because the expressions inside the
      --  braces are ordinary expressions and the parser has to see ordinary
      --  tokens for them. Lexing them in place is also what keeps their spans
      --  right: a diagnostic about `X` points at the `X` the user typed, which
      --  it could not if the literal arrived whole and were taken apart later.
      --
      --  The shape is Start, then for each expression its tokens followed by a
      --  Chunk, then End. Start and Chunk carry the literal text before and
      --  after an expression; End carries nothing and is what tells the parser
      --  no further expression follows.
      Token_Interpolation_Start,
      Token_Interpolation_Chunk,
      Token_Interpolation_End,

      Token_Comment,

      --  A delimiter or operator; see Symbol.
      Token_Delimiter,

      --  Something that is not a lexical element at all. Carries its extent so
      --  a diagnostic can point at it, and lets the lexer continue rather than
      --  stop at the first bad byte.
      Token_Error);

   --  Every reserved word of Ada 2022.
   --
   --  All of them, not only the ones Adash accepts. A reserved word used as a
   --  name is a lexical fact, and diagnosing it as an unsupported construct
   --  would be the wrong complaint.
   type Reserved_Word is
     (Word_Abort, Word_Abs, Word_Abstract, Word_Accept, Word_Access,
      Word_Aliased, Word_All, Word_And, Word_Array, Word_At,
      Word_Begin, Word_Body,
      Word_Case, Word_Constant,
      Word_Declare, Word_Delay, Word_Delta, Word_Digits, Word_Do,
      Word_Else, Word_Elsif, Word_End, Word_Entry, Word_Exception, Word_Exit,
      Word_For, Word_Function,
      Word_Generic, Word_Goto,
      Word_If, Word_In, Word_Interface, Word_Is,
      Word_Limited, Word_Loop,
      Word_Mod,
      Word_New, Word_Not, Word_Null,
      Word_Of, Word_Or, Word_Others, Word_Out, Word_Overriding,
      Word_Package, Word_Parallel, Word_Pragma, Word_Private, Word_Procedure,
      Word_Protected,
      Word_Raise, Word_Range, Word_Record, Word_Rem, Word_Renames, Word_Requeue,
      Word_Return, Word_Reverse,
      Word_Select, Word_Separate, Word_Some, Word_Subtype, Word_Synchronized,
      Word_Tagged, Word_Task, Word_Terminate, Word_Then, Word_Type,
      Word_Until, Word_Use,
      Word_When, Word_While, Word_With,
      Word_Xor);

   --  Every delimiter and compound delimiter of Ada.
   type Delimiter is
     (
      --  Single characters.
      Delim_Ampersand,        --  &
      Delim_Apostrophe,       --  '  as an attribute marker
      Delim_Left_Paren,       --  (
      Delim_Right_Paren,      --  )
      Delim_Star,             --  *
      Delim_Plus,             --  +
      Delim_Comma,            --  ,
      Delim_Minus,            --  -
      Delim_Dot,              --  .
      Delim_Slash,            --  /
      Delim_Colon,            --  :
      Delim_Semicolon,        --  ;
      Delim_Less,             --  <
      Delim_Equal,            --  =
      Delim_Greater,          --  >
      Delim_Bar,              --  |

      --  Compound delimiters. Matched longest-first, so ":=" is never a colon
      --  followed by an equals sign.
      Delim_Arrow,            --  =>
      Delim_Double_Dot,       --  ..
      Delim_Double_Star,      --  **
      Delim_Assign,           --  :=
      Delim_Not_Equal,        --  /=
      Delim_Greater_Equal,    --  >=
      Delim_Less_Equal,       --  <=
      Delim_Left_Label,       --  <<
      Delim_Right_Label,      --  >>
      Delim_Box);             --  <>

   --  One lexical element.
   type Token is private;

   --  A token denoting nothing, for a stream position that has none.
   No_Token : constant Token;

   --  @param Item Token to inspect.
   --  @return What it is.
   function Kind (Item : Token) return Token_Kind;

   --  @param Item Token to inspect.
   --  @return Where it is in its buffer.
   function Extent (Item : Token) return Adash.Source.Span;

   --  The token's text, exactly as it appeared.
   --
   --  For a string literal this is the literal *including* its quotes and with
   --  its doubled quotes undoubled nowhere -- the source form. Use Value for
   --  what the literal denotes. Keeping both is what lets a formatter reproduce
   --  the source and an evaluator read the meaning.
   --
   --  @param Item Token to inspect.
   --  @return Its source text.
   function Text (Item : Token) return String;

   --  What a literal denotes.
   --
   --  For a string literal, the text between the quotes with doubled quotes
   --  reduced to one. For a character literal, the single character. For
   --  anything else, the same as Text.
   --
   --  @param Item Token to inspect.
   --  @return Its value as text.
   function Value (Item : Token) return String;

   --  @param Item Token to inspect; must be a reserved word.
   --  @return Which reserved word, or Word_Abort when Item is not one. Callers
   --          test Kind first; the default exists so this is total.
   function Word (Item : Token) return Reserved_Word;

   --  @param Item Token to inspect; must be a delimiter.
   --  @return Which delimiter, or Delim_Ampersand when Item is not one.
   function Symbol (Item : Token) return Delimiter;

   --  Whether a token is one the parser reads.
   --
   --  False for comments and for the error token. The parser skips both; the
   --  highlighter and the diagnostics do not, which is why they are in the
   --  stream rather than dropped.
   --
   --  @param Item Token to test.
   --  @return True when the parser should consider it.
   function Is_Significant (Item : Token) return Boolean;

   --  The reserved word a name spells, if it spells one.
   --
   --  Case-insensitive, because Ada's reserved words are. Exposed so that a
   --  completion list and a highlighter can ask the same question the lexer
   --  asked, and get the same answer.
   --
   --  @param Name The name as written.
   --  @param Into Which reserved word, when this returns True.
   --  @return True when Name is a reserved word.
   function Is_Reserved (Name : String; Into : out Reserved_Word) return Boolean;

   --  A reserved word's spelling, in lower case as Ada writes them.
   --
   --  A language identifier, not text for a user.
   --
   --  @param Item Reserved word.
   --  @return Its spelling.
   function Spelling (Item : Reserved_Word) return String;

   --  A delimiter's spelling.
   --
   --  @param Item Delimiter.
   --  @return Its characters.
   function Spelling (Item : Delimiter) return String;

   --  An ordered, immutable sequence of tokens.
   type Token_Stream is tagged private;

   --  @param Item Stream to measure.
   --  @return How many tokens it holds, including the end-of-input token.
   function Length (Item : Token_Stream) return Natural;

   --  @param Item Stream to read.
   --  @param Index Which token, from one.
   --  @return That token, or No_Token when Index is past the end.
   function Element (Item : Token_Stream; Index : Positive) return Token;

   --  The token covering a byte offset.
   --
   --  What completion asks: the user's cursor is here, which token is it in?
   --  An offset in the whitespace between two tokens belongs to neither and
   --  returns No_Token, which is the honest answer -- completion there is
   --  starting a new token rather than continuing one.
   --
   --  @param Item Stream to search.
   --  @param Offset The byte offset.
   --  @return The token covering it, or No_Token.
   function Token_At
     (Item   : Token_Stream;
      Offset : Adash.Source.Byte_Offset) return Token;

   --  Forget every token. Used by the lexer before it fills a stream, so that
   --  one stream reused across many buffers holds only the last -- which is
   --  what an interactive session does, with one stream and a line at a time.
   --
   --  @param Item Stream to empty.
   procedure Clear (Item : in out Token_Stream);

   --  Add a token. Used by the lexer; a stream is immutable to everyone else.
   --
   --  @param Item Stream to extend.
   --  @param Entry_To_Add The token.
   procedure Append (Item : in out Token_Stream; Entry_To_Add : Token);

   --  Build a token. Used by the lexer.
   --
   --  @param Kind What it is.
   --  @param Extent Where it is.
   --  @param Text Its source text.
   --  @param Value What it denotes; the same as Text when that is the same.
   --  @param Word Which reserved word, when Kind is Token_Reserved_Word.
   --  @param Symbol Which delimiter, when Kind is Token_Delimiter.
   --  @return The token.
   function Make
     (Kind   : Token_Kind;
      Extent : Adash.Source.Span;
      Text   : String;
      Value  : String := "";
      Word   : Reserved_Word := Word_Abort;
      Symbol : Delimiter := Delim_Ampersand) return Token;

private

   type Token is record
      Kind    : Token_Kind := Token_End_Of_Input;
      Extent  : Adash.Source.Span := Adash.Source.Nowhere;
      Text    : Ada.Strings.Unbounded.Unbounded_String;
      Value   : Ada.Strings.Unbounded.Unbounded_String;
      Word    : Reserved_Word := Word_Abort;
      Symbol  : Delimiter := Delim_Ampersand;
      Present : Boolean := False;
   end record;

   No_Token : constant Token := (others => <>);

   package Token_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Token);

   type Token_Stream is tagged record
      Entries : Token_Vectors.Vector;
   end record;

end Adash.Language.Tokens;
