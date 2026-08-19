with Ada.Streams;

with Adash.Interactive.History;

--  Reading a line.
--
--  Three things live here, in order of how testable they are:
--
--    * a **buffer** -- the text being typed and where the cursor is in it,
--      with every operation an editor performs on it. Pure, and tested without
--      a terminal, which matters because this is the code a user's fingers
--      touch thousands of times a session;
--
--    * a **key decoder** -- bytes to intentions. Arrow keys arrive as escape
--      sequences that may be split across reads, so the decoder is explicit
--      about needing more input rather than guessing;
--
--    * a **reader** -- the part that actually talks to a terminal, and the
--      only part that cannot be tested without one.
--
--  **Positions are byte offsets, and movement is by character.** The buffer
--  holds UTF-8, so a cursor that moved a byte at a time would stop in the
--  middle of a letter and the next keystroke would corrupt it. Every movement
--  operation here steps over a whole encoded character.
--
--  **Display width is not character count.** An East Asian ideograph occupies
--  two cells and a combining accent occupies none, so a reader that counted
--  characters put its cursor in the wrong place on any line containing either.
--  Adash.Display_Width answers in cells and this package asks it: Cursor_Cells
--  and Cell_Count are what the reader draws with, and Cursor_Column and
--  Character_Count remain for callers that mean characters.
package Adash.Interactive.Editing is

   --  Longest line that can be typed. Bounded because an editor that grows
   --  without limit turns a stuck key into memory exhaustion, and because a
   --  fixed buffer keeps the redraw cost predictable.
   Max_Line : constant := 8_192;

   ---------------------------------------------------------------------
   --  The buffer.
   ---------------------------------------------------------------------

   --  The line being typed.
   type Buffer is tagged private;

   --  @param Item Buffer to measure.
   --  @return How many bytes it holds.
   function Length (Item : Buffer) return Natural;

   --  @param Item Buffer to read.
   --  @return The text, as typed.
   function Text (Item : Buffer) return String;

   --  Where the cursor is, as a byte offset from zero: zero is before the
   --  first byte, Length is after the last.
   --
   --  @param Item Buffer to read.
   --  @return The offset.
   function Cursor (Item : Buffer) return Natural;

   --  How many characters precede the cursor.
   --
   --  Characters, not cells. What the reader needs to place a cursor is
   --  Cursor_Cells; this is what a caller counting the text itself wants, and
   --  the two differ the moment an ideograph or a combining accent appears.
   --
   --  @param Item Buffer to read.
   --  @return The count.
   function Cursor_Column (Item : Buffer) return Natural;

   --  How many cells the text before the cursor occupies.
   --
   --  What the reader needs to place the cursor on screen.
   --
   --  @param Item Buffer to read.
   --  @return The width in cells.
   function Cursor_Cells (Item : Buffer) return Natural;

   --  How many characters the buffer holds.
   --
   --  @param Item Buffer to read.
   --  @return The count.
   function Character_Count (Item : Buffer) return Natural;

   --  How many cells the buffer's text occupies on screen.
   --
   --  @param Item Buffer to read.
   --  @return The width in cells.
   function Cell_Count (Item : Buffer) return Natural;

   --  Where something sits on a wrapped screen: rows down from the first row
   --  of the prompt, and cells across.
   type Screen_Position is record
      Row    : Natural := 0;
      Column : Natural := 0;
   end record;

   --  Where the cursor would be after the first Upto bytes of the line.
   --
   --  Walked, not divided. Rows are not all the same width: a break falls
   --  before a character that would overflow, so a row ending in a wide
   --  character stops a cell short, and dividing a cell count by the row width
   --  puts the cursor one cell out on every line of ideographs. It is also
   --  wrong at an exact boundary, where a full row has no break after it and
   --  the cursor has not moved down.
   --
   --  Exposed rather than left inside the reader because the reader cannot be
   --  tested without a terminal, and this is the part that was wrong twice.
   --
   --  @param Item Buffer to measure.
   --  @param Prompt_Width How many cells precede the line on its first row.
   --  @param Usable How many cells a row holds.
   --  @param Upto Count the bytes before this offset; Natural'Last for all.
   --  @return Its position.
   function Place
     (Item         : Buffer;
      Prompt_Width : Natural;
      Usable       : Positive;
      Upto         : Natural) return Screen_Position;

   --  Empty the buffer and put the cursor at the start.
   --
   --  @param Item Buffer to clear.
   procedure Clear (Item : in out Buffer);

   --  Replace the whole line, cursor to the end.
   --
   --  What recalling a history entry does.
   --
   --  @param Item Buffer to set.
   --  @param To The new text; truncated at Max_Line, because refusing a recall
   --         outright would lose the entry the user asked for.
   procedure Set (Item : in out Buffer; To : String);

   --  Insert text at the cursor and move past it.
   --
   --  @param Item Buffer to insert into.
   --  @param What The bytes to insert, which may be one character or a whole
   --         paste.
   --  @return True when all of it fit. False when the buffer is full and
   --          nothing was inserted -- a partial paste is worse than a refused
   --          one, because the user cannot see what went missing.
   function Insert (Item : in out Buffer; What : String) return Boolean;

   --  Delete the character before the cursor.
   --
   --  @param Item Buffer to edit.
   --  @return True when something was deleted.
   function Delete_Backward (Item : in out Buffer) return Boolean;

   --  Delete the character at the cursor.
   --
   --  @param Item Buffer to edit.
   --  @return True when something was deleted.
   function Delete_Forward (Item : in out Buffer) return Boolean;

   --  Delete from the cursor to the end of the line.
   --
   --  @param Item Buffer to edit.
   --  @return True when something was deleted.
   function Delete_To_End (Item : in out Buffer) return Boolean;

   --  Delete from the start of the line to the cursor.
   --
   --  @param Item Buffer to edit.
   --  @return True when something was deleted.
   function Delete_To_Start (Item : in out Buffer) return Boolean;

   --  Delete the word before the cursor.
   --
   --  A word here is a run of non-blanks, and the blanks before it go too:
   --  deleting a word and leaving its separator behind means pressing the key
   --  twice for one word, every time.
   --
   --  @param Item Buffer to edit.
   --  @return True when something was deleted.
   function Delete_Word_Backward (Item : in out Buffer) return Boolean;

   --  Where the cursor can go.
   type Movement is
     (To_Start, To_End, Left, Right, Word_Left, Word_Right);

   --  Move the cursor.
   --
   --  @param Item Buffer to move within.
   --  @param Where Which way.
   --  @return True when the cursor moved. False at the end it was already at,
   --          which a reader uses to decide whether a redraw is needed.
   function Move (Item : in out Buffer; Where : Movement) return Boolean;

   ---------------------------------------------------------------------
   --  Keys.
   ---------------------------------------------------------------------

   --  What a keystroke meant.
   type Key_Kind is
     (
      --  A printable character; see Key_Event.Text.
      Key_Character,

      --  Submit the line.
      Key_Enter,

      Key_Backspace,
      Key_Delete,
      Key_Left,
      Key_Right,
      Key_Up,
      Key_Down,
      Key_Home,
      Key_End,
      Key_Word_Left,
      Key_Word_Right,

      --  Ask for completion.
      Key_Complete,

      --  Abandon the line. Not the same as end of input: the session
      --  continues, and the abandoned line is still recorded, because a user
      --  who gave up on a line often wants it back to fix it.
      Key_Interrupt,

      --  End of input on an empty line. The session ends.
      Key_End_Of_Input,

      Key_Kill_To_End,
      Key_Kill_To_Start,
      Key_Kill_Word,

      --  Redraw everything.
      Key_Refresh,

      --  Search the history for a line holding what is typed next, newest
      --  first, and again for the one before it.
      Key_Search,

      --  Put back what the last kill took out.
      Key_Yank,

      --  Bytes that decoded to nothing this editor knows. Ignored rather than
      --  inserted: inserting the bytes of an unrecognised escape sequence puts
      --  visible rubbish in the line the user is typing.
      Key_Unknown,

      --  Not enough bytes yet. Read more and decode again.
      Key_Incomplete);

   --  Longest text one event can carry.
   Max_Key_Text : constant := 8;

   --  One decoded keystroke.
   type Key_Event is record
      Kind   : Key_Kind := Key_Unknown;

      --  The characters, for Key_Character.
      Text   : String (1 .. Max_Key_Text) := [others => ' '];
      Length : Natural range 0 .. Max_Key_Text := 0;
   end record;

   --  Decode the front of a byte stream.
   --
   --  @param Bytes The bytes read so far, oldest first.
   --  @param Event What they meant.
   --  @param Consumed How many bytes the event used. Zero when the event is
   --         Key_Incomplete, so the caller keeps what it has and reads more.
   procedure Decode
     (Bytes    : Ada.Streams.Stream_Element_Array;
      Event    : out Key_Event;
      Consumed : out Natural);

   ---------------------------------------------------------------------
   --  The reader.
   ---------------------------------------------------------------------

   --  How a line ended.
   type Read_Outcome is
     (
      --  The user pressed return; see the text.
      Line_Read,

      --  The user abandoned the line. Its text is still reported, so the
      --  caller can record it.
      Line_Abandoned,

      --  End of input. The session is over.
      Input_Ended,

      --  The terminal could not be read at all.
      Read_Failed);

   --  Whether a full-featured editor is possible on this terminal.
   --
   --  False on a pipe, on a host hostkit does not know, and on a terminal that
   --  refuses raw mode. Read_Line still works when this is False -- it falls
   --  back to whole lines with no editing -- and the caller is told so it can
   --  say what the user is getting rather than leaving them to discover that
   --  the arrow keys print letters.
   --
   --  @return True when Read_Line will edit in place.
   function Supports_Editing return Boolean;

   --  Read one line.
   --
   --  @param Prompt What to draw before the line, already rendered and styled.
   --         Passed in rather than built here: the prompt is a model this
   --         package has no business resolving.
   --  @param Prompt_Width How many cells the prompt occupies, which the caller
   --         knows and this package cannot work out from styled text.
   --  @param Recall History to move through with the up and down keys.
   --  @param Allow_Editing False to read whole lines with no editing even on a
   --         terminal that could do better. What the editing setting turns
   --         off, for a terminal that misbehaves or a reader that would rather
   --         see the line once.
   --  @param Into The line as typed, without its terminator.
   --  @param Last Index of the last byte written into Into.
   --  @return How the line ended.
   --  @param Search_Path Where Tab looks for programs, as the host writes a
   --         search path. The session's own rather than this process's: `set
   --         ("PATH=...")` changes what a child is started with, and a
   --         completion that read its own environment would offer the programs
   --         of a path the shell no longer uses. "" offers none.
   --  What a caller can add to what Tab offers.
   --
   --  Asked with the line and the cursor, and answering with one candidate per
   --  line. A line is the unit because that is what a user's own subprogram
   --  can produce with `put_line` -- and asking the caller rather than
   --  reaching for the engine here keeps the editor a thing that edits: it
   --  knows about keys and cells, not about how a language evaluates a call.
   --  An object rather than an access to a function, because what answers the
   --  question has to know which session was asked. A function on its own
   --  cannot carry one, so the session had to be left where the function could
   --  find it -- and a second shell in the same process would then have been
   --  answered by the first one's. The caller passes the thing that knows.
   type Candidate_Supplier is limited interface;

   --  @param Supplier Whatever the caller gave, which knows where to look.
   --  @param Line The line as typed.
   --  @param Cursor Where the cursor is in it, one-based.
   --  @return One candidate per line, empty for none.
   function Candidates
     (Supplier : Candidate_Supplier;
      Line     : String;
      Cursor   : Positive) return String is abstract;

   function Read_Line
     (Prompt       : String;
      Prompt_Width : Natural;
      Recall       : Adash.Interactive.History.Log;
      Allow_Editing : Boolean := True;
      Search_Path  : String := "";
      Ask_Caller   : access Candidate_Supplier'Class := null;

      --  What a search shows in place of the prompt while it runs, and what
      --  it shows when nothing matches. Text rather than a message, because
      --  this package renders no catalog: the caller has one and passes what
      --  it says.
      Search_Label : String := "";
      Search_Empty : String := "";
      Into         : out String;
      Last         : out Natural) return Read_Outcome;

private

   --  The components are not named Text, Length and Cursor, though those are
   --  what they hold. A tagged record's component selection beats a primitive
   --  operation of the same name, so Line.Text would silently return the whole
   --  fixed-size component -- padding and all -- rather than calling the
   --  function that trims it. Distinct names make the two impossible to
   --  confuse.
   type Buffer is tagged record
      Content : String (1 .. Max_Line) := [others => ' '];
      Used    : Natural range 0 .. Max_Line := 0;
      Point   : Natural range 0 .. Max_Line := 0;
   end record;

end Adash.Interactive.Editing;
