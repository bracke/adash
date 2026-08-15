private with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;

--  History that survives the session.
--
--  **One JSON string per line.** Not one raw line per entry, which is what most
--  shells do and what makes them all subtly wrong: a history entry may contain
--  a newline, because Adash accepts multi-line input, and a format that uses
--  newlines as its separator cannot hold one. The usual fixes -- a magic escape
--  before the newline, a marker character -- each invent a small format nobody
--  documents and every tool reading the file has to guess at.
--
--  A JSON string is already the answer to that question. It holds any byte
--  sequence exactly, it is one line so the file stays appendable and greppable,
--  every language has a reader for it, and jsonlib is already the crate that
--  owns it. A line looks like:
--
--      "put_line (\"hello\");"
--      "for I in 1 .. 3 loop\n   put_line (\"x\");\nend loop;"
--
--  **A line that will not parse is skipped, not fatal.** A history file is
--  appended to at the end of every session, which is when a machine is most
--  likely to be going down; a truncated last line is a normal thing to find. A
--  reader that refused the whole file over it would throw away everything the
--  user had done rather than the fragment.
--
--  What is *not* here: the policies about what is worth remembering --
--  duplicates, blank lines, sensitive input, the limit. Those belong to
--  Adash.Interactive.History, which is where a session decides what to record;
--  this package stores what it is given and reads back what is there.
package Adash.Persistence.History is

   --  What the file is called inside the data store.
   File_Name : constant String := "history.jsonl";

   --  Most session files one sweep will consider.
   --
   --  A bound rather than a vector because the answer is built on the stack and
   --  a data store holding more than this many abandoned sessions has a problem
   --  a sweep will not fix. The rest are left for the next one.
   Max_Session_Files : constant := 64;

   type Path_List is array (1 .. Max_Session_Files) of
     Ada.Strings.Unbounded.Unbounded_String;

   --  Where it lives.
   --
   --  @return The full path, or "" when this host has no data directory.
   function Path return String;

   --  Where *this session's* history lives.
   --
   --  A file of its own, named after the process, so two shells running at once
   --  do not write into one file line by line. They still share a history --
   --  the session file is merged into the common one when the session ends --
   --  but a common file written a line at a time by several sessions reads as
   --  their commands shuffled together, which is not what either user did.
   --
   --  A session that dies before merging leaves its file behind.
   --  Abandoned_Session_Files finds those, and Owner_Lock_Path is how a
   --  sweeper tells an abandoned one from a session still running.
   --
   --  @return The full path, or "" when this host has no data directory.
   function Session_Path return String;

   --  The file a session holds a lock on for as long as it is running.
   --
   --  Separate from the lock the store takes around each write, which is taken
   --  and released per line: a sweeper testing that one would find it free
   --  between two keystrokes and take a live session's history away. This one
   --  is held from start to finish, so whether it can be taken is exactly the
   --  question "is that session still there".
   --
   --  Asked rather than derived from the process id. A pid can be reused, and a
   --  sweeper that reasoned from the number would eventually decide a running
   --  shell was a dead one.
   --
   --  @param For_File A session history file.
   --  @return The path of its ownership lock.
   function Owner_Lock_Path (For_File : String) return String;

   --  Session history files other than this session's.
   --
   --  Every one of them, whether or not its session is still running: which is
   --  which is the caller's question, asked by trying Owner_Lock_Path.
   --
   --  @param Found Their full paths, in whatever order the directory gives.
   --  @param Count How many; zero when there are none or this host has no data
   --         directory.
   procedure Abandoned_Session_Files
     (Found : out Path_List; Count : out Natural);

   --  Entries read from a file.
   type Log is tagged private;

   --  @param Item Log to measure.
   --  @return How many entries it holds.
   function Count (Item : Log) return Natural;

   --  One entry, oldest first.
   --
   --  @param Item Log to read.
   --  @param Index Which entry, from one.
   --  @return That line, or "" when Index is out of range.
   function Entry_At (Item : Log; Index : Positive) return String;

   --  How many lines were skipped because they did not parse.
   --
   --  Reported rather than silently absorbed: one is a session that ended
   --  badly, and hundreds is a file that has been corrupted or overwritten by
   --  something else, which the user would want to know.
   --
   --  @param Item Log to ask.
   --  @return The count.
   function Skipped (Item : Log) return Natural;

   --  Read the history file.
   --
   --  @param Into The entries. Emptied first.
   --  @param Result Store_Absent when there is no file yet, which is the
   --         ordinary case for a first session and not a problem.
   --  @param Limit How many of the most recent entries to keep. Older ones are
   --         read and discarded, so a long file does not become a long start-up.
   --  @param From Which file to read; the shared one when empty.
   procedure Load
     (Into   : out Log;
      Result : out Adash.Persistence.Outcome;
      Limit  : Positive := 1_000;
      From   : String := "");

   --  Add one entry to the end of the file.
   --
   --  Appending rather than rewriting: a shell that rewrote its whole history
   --  after every command would be quadratic in the length of a session, and
   --  would lose the file rather than the last line if it were interrupted.
   --
   --  @param Line The entry, exactly as typed.
   --  @param Result What became of it.
   --  @param Into_File Which file to write to; the shared one when empty.
   procedure Append
     (Line      : String;
      Result    : out Adash.Persistence.Outcome;
      Into_File : String := "");

   --  Rewrite the file with the entries in a log.
   --
   --  What trimming a file to its limit does, and the only operation that
   --  rewrites. Atomic, like every other write here.
   --
   --  @param Item The entries to keep, oldest first.
   --  @param Result What became of it.
   --  @param Into_File Which file to write; the shared one when empty.
   procedure Save
     (Item      : Log;
      Result    : out Adash.Persistence.Outcome;
      Into_File : String := "");

   --  Take entries out of the file.
   --
   --  The **last occurrence** of each line in Lines, not a position: a shared
   --  history file holds what several sessions wrote, interleaved, so removing
   --  "the last three lines" of it could take another shell's. What a user
   --  forgetting a line means is that text, and the last time it was written
   --  is the time they just typed it.
   --
   --  Read and written under one lock, so a line another session appends while
   --  this runs is not lost.
   --
   --  @param Lines The entries to forget. Each one this removes is removed
   --         from here too, so what is left afterwards is what this file did
   --         not hold -- which is how a caller carries the rest to another
   --         file rather than guessing.
   --  @param Result What became of it. Store_Absent when there is no such
   --         file, which is a session that has written nothing yet.
   --  @param From_File Which file; the shared one when empty.
   procedure Forget
     (Lines     : in out Log;
      Result    : out Adash.Persistence.Outcome;
      From_File : String := "");

   --  Add an entry to a log in memory, without writing anything.
   --
   --  For building a log to Save.
   --
   --  @param Item Log to add to.
   --  @param Line The entry.
   procedure Add (Item : in out Log; Line : String);

   --  Forget everything in a log. Does not touch the file.
   --
   --  @param Item Log to clear.
   procedure Clear (Item : in out Log);

   --  Encode one entry as a line of the file.
   --
   --  Exposed because it is the whole of the format, and a test that asserts
   --  what a line looks like is the only thing standing between a change here
   --  and every existing history file becoming unreadable.
   --
   --  @param Line The entry.
   --  @return The line to write, without its terminator.
   function Encode (Line : String) return String;

   --  Decode one line of the file.
   --
   --  @param Text The line, without its terminator.
   --  @param Line The entry, when this returns True.
   --  @return False when the line is not a JSON string. A partial line at the
   --          end of a file left by an interrupted session is the usual cause.
   function Decode (Text : String; Line : out Adash.Persistence.Contents)
                    return Boolean;

private

   package Line_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Ada.Strings.Unbounded.Unbounded_String,
      "="          => Ada.Strings.Unbounded."=");

   type Log is tagged record
      Lines   : Line_Vectors.Vector;
      Damaged : Natural := 0;
   end record;

end Adash.Persistence.History;
