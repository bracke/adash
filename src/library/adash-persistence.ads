--  Where the shell keeps things, and how it puts them there.
--
--  This package owns the *mechanism* and knows nothing about the content. It
--  answers three questions and no others: where does a file of this sort live,
--  how is one read, and how is one written so that a crash cannot leave it half
--  written. What goes in the files belongs to whoever owns the data --
--  Adash.Configuration for settings, Adash.Persistence.History for history --
--  and a store that knew about settings would have to change every time a
--  setting was added.
--
--  **Every write is atomic.** A file is written beside its destination and then
--  replaced in one step, so a reader never sees a partial file and a crash
--  never destroys the previous one. A shell writes its history at the end of
--  every session, which is exactly when a machine is most likely to be going
--  down; the naive version of this loses the file.
--
--  **Every write is locked.** Two sessions ending at the same moment is the
--  normal case, not the rare one. Without a lock the second replaces the first
--  and the first session's work is gone with no sign that anything happened.
--
--  **Files are private.** A history file records what a person typed and a
--  configuration file may record where their systems are. Both are created
--  readable by their owner and nobody else, on hosts that have the concept.
--
--  **Nothing here raises.** Absence, permission, a full disk and a lock held by
--  somebody else are all facts about the machine rather than defects in the
--  program, and each comes back as a distinct outcome. A caller that cannot
--  tell "there is no file yet" from "I am not allowed to read it" will write
--  the wrong message for one of them.

--  Visible rather than private: Contents is part of the contract, and a caller
--  has to be able to declare one.
with Ada.Strings.Unbounded;

package Adash.Persistence is

   --  The bytes of a file. Unbounded because a history file has no useful
   --  bound: a caller that wanted one would have to guess, and guessing low
   --  silently truncates somebody's history.
   subtype Contents is Ada.Strings.Unbounded.Unbounded_String;

   --  What sort of thing is being stored. The three differ in where they live
   --  and in what it means to lose them.
   type Store_Kind is
     (
      --  Settings: written by a person, kept for as long as they want it, and
      --  the one sort a user is likely to edit by hand or put in version
      --  control.
      Configuration_Store,

      --  Data the shell accumulates and the user would miss: history, above
      --  all. Losing it is not fatal but it is a loss.
      Data_Store,

      --  Things that can be rebuilt. A cache directory is the one a system is
      --  entitled to empty without asking, so nothing that matters may live
      --  here.
      Cache_Store);

   --  What became of an attempt.
   type Outcome is
     (
      --  It worked.
      Store_Ok,

      --  There is no such file. Distinct from every failure, because for a
      --  shell starting for the first time this is the ordinary case and not a
      --  problem to report.
      Store_Absent,

      --  The host has no such directory. On a system with no home directory --
      --  a container, a daemon, a locked-down account -- there is nowhere for
      --  a user's files to go, and pretending otherwise would mean writing
      --  into whatever the current directory happens to be.
      Store_Unavailable,

      --  It exists and could not be read.
      Store_Not_Readable,

      --  It could not be written: no permission, no room, or a directory that
      --  could not be created.
      Store_Not_Writable,

      --  Another process holds the lock. Not an error in this process; the
      --  caller can wait and try again, or skip the write and say so.
      Store_Busy,

      --  It exists and holds bytes that are not text this shell can use --
      --  malformed UTF-8. Reported here rather than left to the parser,
      --  because it is a property of the file rather than of the format.
      Store_Not_Text);

   --  Whether an outcome means the work was done.
   --
   --  @param Item The outcome.
   --  @return True only for Store_Ok.
   function Succeeded (Item : Outcome) return Boolean is (Item = Store_Ok);

   --  Where a file of a given sort lives.
   --
   --  Asked of hostkit, which knows where each host keeps such things, and
   --  never assembled from environment variables here: a spawned process could
   --  then choose where the next shell reads its settings from, which is a way
   --  in rather than a feature.
   --
   --  @param Kind What sort of thing.
   --  @param Name The file's name within the store, with its extension.
   --  @return The full path, or "" when the host has no such directory.
   function Path_For (Kind : Store_Kind; Name : String) return String;

   --  Read a whole file.
   --
   --  @param Path The file.
   --  @param Into The contents, as UTF-8. Empty unless this returns Store_Ok.
   --  @param Result What became of it.
   procedure Read
     (Path   : String;
      Into   : out Contents;
      Result : out Outcome);

   --  Write a whole file, replacing whatever was there.
   --
   --  The file is written beside its destination and then replaced in one
   --  step, under a lock. A reader never sees it half written, and a crash
   --  leaves either the old file or the new one.
   --
   --  @param Path The file. Its directory is created if it does not exist.
   --  @param Text The contents, as UTF-8.
   --  @param Result What became of it.
   procedure Write
     (Path   : String;
      Text   : String;
      Result : out Outcome);

   --  Add one line to the end of a file.
   --
   --  Appending rather than rewriting, because a history that rewrote the
   --  whole file after every command would be quadratic in the length of a
   --  session and would lose everything on a crash rather than the last line.
   --  Held under the same lock, so two sessions appending at once interleave
   --  whole lines rather than fragments.
   --
   --  @param Path The file. Created if it does not exist.
   --  @param Text The line, without its terminator.
   --  @param Result What became of it.
   procedure Append_Line
     (Path   : String;
      Text   : String;
      Result : out Outcome);

   --  Whether a file exists and can be read.
   --
   --  @param Path The file.
   --  @return True when a read would succeed.
   function Exists (Path : String) return Boolean;

   --  Remove a file.
   --
   --  @param Path The file.
   --  @param Result Store_Ok when it is gone, including when it was already
   --         absent -- the caller wanted it not to be there, and it is not.
   procedure Remove (Path : String; Result : out Outcome);

   --  Make sure the directory a file would live in exists.
   --
   --  Reading and writing do this for themselves; taking a *lock* on a file in
   --  the store does not, because a lock is not a write and the file it names
   --  may never be written at all. A caller that locks before it writes -- a
   --  session claiming its own history file is the case -- has to ask first.
   --
   --  @param Path A file path, whose containing directory is created.
   --  @return True when the directory exists afterwards.
   function Ensure_Container (Path : String) return Boolean;

end Adash.Persistence;
