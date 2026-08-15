private with Ada.Containers.Vectors;

--  Visible rather than private: Entry_Text is part of the public contract.
with Ada.Strings.Unbounded;

--  What has been typed.
--
--  In memory here and durable through Adash.Persistence.History, which writes
--  one JSON string per line so that an entry holding a newline survives a
--  format that separates entries by newlines. The policies are here rather
--  than there because they are about what a session should remember, not about
--  how a file is written.
--
--  **A line is recorded whether or not it worked.** A user recalling the last
--  line usually wants the one they got wrong, to fix it. A history that kept
--  only successes would be a history of things nobody needs to type again.
--
--  **Consecutive duplicates are not recorded twice.** Pressing return on the
--  same line repeatedly is common and remembering each is noise; a
--  non-consecutive repeat *is* kept, because returning to something after
--  doing other work is a real place in the session.
--
--  **A line the user marked sensitive is never recorded.** History is one of
--  the more sensitive files on a system -- durable, plain, and rarely thought
--  about. A shell that could not be told to forget something would be one
--  users had to remember to clean up by hand. The mark is a leading space --
--  see Marked_Sensitive -- and it is the frontend that reads it, because what
--  a keystroke means is a frontend question and what a session remembers is
--  this one.
--
--  **Multi-line input is one entry.** A recalled entry has to be editable as
--  the thing that was typed, and half of a construct is not.
package Adash.Interactive.History is

   --  One remembered line.
   subtype Entry_Text is Ada.Strings.Unbounded.Unbounded_String;

   --  Bounded so that a long session does not grow without limit. Reaching the
   --  bound drops the oldest, which is the entry least likely to be wanted.
   Default_Limit : constant := 1_000;

   --  The history of one session.
   type Log is tagged limited private;

   --  Set how many entries are kept.
   --
   --  @param Item Log to configure.
   --  @param Limit How many entries to keep; at least one.
   procedure Set_Limit (Item : in out Log; Limit : Positive);

   --  Record a line.
   --
   --  @param Item Log to add to.
   --  @param Line The line exactly as typed, including its whitespace: a
   --         recalled line has to be what the user wrote, not a tidied form
   --         of it.
   --  @param Sensitive True to record nothing at all.
   procedure Record_Line
     (Item      : in out Log;
      Line      : String;
      Sensitive : Boolean := False);

   --  Whether a line carries the mark that says "do not remember this".
   --
   --  The mark is a leading space, as in other shells: it is the one thing a
   --  user can type before a command without changing what the command means,
   --  since the lexer skips it. A word would be a second command language, a
   --  key would have to be found and remembered, and a setting toggled around
   --  the line would still record it when the user forgot to toggle it back.
   --
   --  A tab does not count, only a space. At an editing prompt a tab is
   --  completion and cannot start a line at all, so accepting it would mean
   --  quietly forgetting pasted indented text and nothing else.
   --
   --  This says what the mark *is*; whether it is honoured is the frontend's
   --  to decide from the history.ignore-space setting.
   --
   --  @param Line The submission exactly as typed.
   --  @return True when it begins with a space.
   function Marked_Sensitive (Line : String) return Boolean;

   --  @param Item Log to measure.
   --  @return How many entries it holds.
   function Count (Item : Log) return Natural;

   --  One entry, oldest first.
   --
   --  @param Item Log to read.
   --  @param Index Which entry, from one.
   --  @return That line, or "" when Index is out of range.
   function Entry_At (Item : Log; Index : Positive) return String;

   --  The most recent entry.
   --
   --  @param Item Log to read.
   --  @return The last line, or "" when there is none.
   function Most_Recent (Item : Log) return String;

   --  The most recent entry starting with a prefix.
   --
   --  What a search backwards through history does. Searching from the newest
   --  end is what a user means by "the last time I did this".
   --
   --  @param Item Log to search.
   --  @param Prefix What the entry starts with.
   --  @param Found The entry, when this returns True.
   --  @return True when one was found.
   function Search_Backwards
     (Item   : Log;
      Prefix : String;
      Found  : out Entry_Text) return Boolean;

   --  Forget the most recent entries.
   --
   --  What `forget` does to the session's own log. The durable file is a
   --  separate act -- Adash.Persistence.History.Forget -- because a log with
   --  no file behind it is an ordinary thing here (a script, a test) and this
   --  package has never known where a file is.
   --
   --  @param Item Log to shorten.
   --  @param Count How many of the newest to drop. More than it holds drops
   --         what it holds: a user asking to forget twenty of nine meant the
   --         nine.
   --  @param Removed How many actually went.
   procedure Forget_Last
     (Item    : in out Log;
      Count   : Natural;
      Removed : out Natural);

   --  Forget everything.
   --
   --  @param Item Log to clear.
   procedure Clear (Item : in out Log);

private

   package Line_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Ada.Strings.Unbounded.Unbounded_String,
      "="          => Ada.Strings.Unbounded."=");

   type Log is tagged limited record
      Lines : Line_Vectors.Vector;
      Limit : Positive := Default_Limit;
   end record;

end Adash.Interactive.History;
