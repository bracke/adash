private with Ada.Containers.Vectors;
private with Ada.Strings.Unbounded;

with Adash.Errors;

--  Where a piece of source came from, and where in it something is.
--
--  Everything the language subsystem produces -- every token, every syntax
--  node, every semantic entity, every diagnostic -- carries a span into a
--  buffer. That is what lets an error point at the thing it is about rather
--  than describe it, what lets a highlighter colour a range, and what will let
--  a formatter put text back where it found it. A model that loses extents
--  cannot be given them back later.
--
--  Four properties this depends on, each of which is easy to lose:
--
--  Text is immutable once loaded. Nothing here can rewrite a buffer, so a span
--  taken at lexing time still means the same characters at diagnosis time. A
--  buffer that could be edited underneath its spans would produce errors that
--  point somewhere plausible and wrong.
--
--  Offsets are byte offsets into the original bytes. Not into a normalized
--  copy: normalizing first would make every span an offset into a text the user
--  never wrote, and a column number that does not match their editor.
--
--  Line endings are normalized by the line map, not by rewriting. CR LF, a lone
--  LF and a lone CR all end a line, and Line_Text hands back the line without
--  its terminator -- so a consumer sees uniform lines while the offsets still
--  index the bytes as they arrived.
--
--  Columns count characters, not bytes. A caret under the third character of a
--  line with an accented letter before it has to be under the third character.
--  Byte columns are the same thing only for ASCII, which is exactly the input
--  that never reveals the difference.
package Adash.Source is

   --  What kind of thing a buffer came from.
   type Origin_Kind is
     (
      --  A file named on the command line or loaded by a script.
      Origin_File,

      --  A line the user typed.
      Origin_Interactive,

      --  A startup file.
      Origin_Startup,

      --  A module or unit loaded by name.
      Origin_Module,

      --  Text supplied directly -- a test, or a prompt expression. It has no
      --  file behind it, which a diagnostic has to be able to say.
      Origin_Text);

   --  Where a buffer came from.
   --
   --  A value, deliberately: it is copied into every diagnostic that refers to
   --  the buffer, so a diagnostic remains meaningful after the buffer is gone.
   --  A registry of buffers with small integer identities would be less to
   --  copy and would be hidden global state, which this project does not have.
   type Origin is private;

   --  An origin naming nothing.
   Unknown_Origin : constant Origin;

   --  Build an origin.
   --
   --  @param Kind What sort of source it is.
   --  @param Name Its file path, module name, or a short label for text with
   --         no file behind it.
   --  @return The origin.
   function Make_Origin (Kind : Origin_Kind; Name : String) return Origin;

   --  @param Item Origin to inspect.
   --  @return Its kind.
   function Kind (Item : Origin) return Origin_Kind;

   --  @param Item Origin to inspect.
   --  @return Its name.
   function Name (Item : Origin) return String;

   --  A one-based byte offset into a buffer's text.
   subtype Byte_Offset is Positive;

   --  A range of bytes, in the Ada slice convention: First .. Last, and empty
   --  when Last is below First.
   --
   --  Empty spans are meaningful and common -- a token expected and missing has
   --  a position but no extent -- so they are representable rather than an
   --  error.
   type Span is record
      First : Byte_Offset := 1;
      Last  : Natural := 0;
   end record;

   --  A span covering nothing, for something with no position at all.
   Nowhere : constant Span := (First => 1, Last => 0);

   --  @param Item Span to test.
   --  @return True when the span covers no bytes.
   function Is_Empty (Item : Span) return Boolean;

   --  @param Item Span to measure.
   --  @return How many bytes it covers.
   function Length (Item : Span) return Natural;

   --  The smallest span covering both.
   --
   --  What a parser uses to give a node the extent of its children.
   --
   --  @param Left One span.
   --  @param Right The other.
   --  @return Their hull. An empty span contributes only its position.
   function Join (Left, Right : Span) return Span;

   --  A place in a buffer, as a person reads it.
   type Location is record
      Line   : Positive := 1;

      --  In characters from the start of the line, not bytes.
      Column : Positive := 1;
   end record;

   --  Loaded source text. Immutable once loaded.
   type Buffer is tagged limited private;

   --  Load text that is already in memory.
   --
   --  The text is validated as UTF-8 before anything else looks at it. Invalid
   --  input is rejected here, once, with the offset of the first bad byte --
   --  rather than by whichever consumer first trips over it, which would report
   --  a lexical error for what is really an encoding problem.
   --
   --  @param Item Buffer to load into.
   --  @param From Where the text came from.
   --  @param Text The bytes.
   --  @param Error Why it was rejected, when this returns False.
   --  @return True when the buffer is loaded and usable.
   function Load
     (Item  : in out Buffer;
      From  : Origin;
      Text  : String;
      Error : out Adash.Errors.Error_Info) return Boolean;

   --  Load a file.
   --
   --  @param Item Buffer to load into.
   --  @param Path File to read.
   --  @param Kind What sort of source this file is.
   --  @param Error Why it could not be loaded, when this returns False.
   --  @return True when the buffer is loaded and usable.
   function Load_File
     (Item  : in out Buffer;
      Path  : String;
      Kind  : Origin_Kind := Origin_File;
      Error : out Adash.Errors.Error_Info) return Boolean;

   --  @param Item Buffer to test.
   --  @return True when it holds loaded text.
   function Is_Loaded (Item : Buffer) return Boolean;

   --  @param Item Buffer to inspect.
   --  @return Where its text came from.
   function From (Item : Buffer) return Origin;

   --  @param Item Buffer to measure.
   --  @return How many bytes it holds.
   function Length (Item : Buffer) return Natural;

   --  The whole text, as it arrived.
   --
   --  @param Item Buffer to read.
   --  @return Its bytes.
   function Text (Item : Buffer) return String;

   --  The bytes a span covers.
   --
   --  @param Item Buffer to read.
   --  @param Extent The span. A span reaching past the end is clipped rather
   --         than raising: a diagnostic built from a slightly wrong span should
   --         still be reportable, and the caller has worse problems than this.
   --  @return The covered bytes, or "" for an empty or out-of-range span.
   function Slice (Item : Buffer; Extent : Span) return String;

   --  A span covering the whole buffer.
   --
   --  @param Item Buffer to span.
   --  @return Its full extent.
   function Whole (Item : Buffer) return Span;

   --  Where a byte offset falls, as a person reads it.
   --
   --  @param Item Buffer to consult.
   --  @param Offset The byte offset. Past the end reports the last position,
   --         which is where an "unexpected end of input" belongs.
   --  @return Its line and column.
   function Where_Is (Item : Buffer; Offset : Byte_Offset) return Location;

   --  How many lines the buffer has.
   --
   --  A buffer with no trailing terminator still ends a line, and an empty
   --  buffer has one empty line -- so a diagnostic at offset one always has a
   --  line to point at.
   --
   --  @param Item Buffer to count.
   --  @return Line count.
   function Line_Count (Item : Buffer) return Positive;

   --  One line's extent, not including its terminator.
   --
   --  @param Item Buffer to consult.
   --  @param Line Line number, from one.
   --  @return The line's span, or Nowhere when the line does not exist.
   function Line_Extent (Item : Buffer; Line : Positive) return Span;

   --  One line's text, not including its terminator.
   --
   --  This is where line endings are normalized: whatever ended the line -- CR
   --  LF, LF, or a lone CR -- is not in the result.
   --
   --  @param Item Buffer to read.
   --  @param Line Line number, from one.
   --  @return The line, or "" when it does not exist.
   function Line_Text (Item : Buffer; Line : Positive) return String;

private

   --  Natural, not Positive: a line's end is the offset of its last byte, and
   --  an empty first line ends at zero. Declaring these Positive made a file
   --  beginning with a newline raise instead of mapping.
   package Offset_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Natural);

   type Origin is record
      Kind : Origin_Kind := Origin_Text;
      Name : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   Unknown_Origin : constant Origin :=
     (Kind => Origin_Text, Name => Ada.Strings.Unbounded.Null_Unbounded_String);

   type Buffer is tagged limited record
      Loaded : Boolean := False;
      From   : Origin;
      Text   : Ada.Strings.Unbounded.Unbounded_String;

      --  The offset of the first byte of each line. Built once at load time:
      --  a diagnostic asking where an offset falls is on a path where something
      --  has already gone wrong, and should not also be scanning the file.
      Line_Starts : Offset_Vectors.Vector;

      --  The offset just past the last byte of each line, excluding whatever
      --  ended it. Kept alongside the starts so that normalizing a line ending
      --  costs nothing at the point a line is asked for.
      Line_Ends : Offset_Vectors.Vector;
   end record;

end Adash.Source;
