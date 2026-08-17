with Ada.Strings.Unbounded;

--  What the shell can ask about a path.
--
--  A shell script asks whether a file is there before it acts on it: that is
--  the commonest conditional anybody writes, and until this package existed the
--  language could not ask it at all. Every other way a program touched the
--  filesystem went through running something -- a redirection, a captured
--  program -- and none of those answers a question.
--
--  The questions are answered for expressions; the writing is not.
--
--  `Exists`, `Is_Directory` and `Is_Executable` are predefined functions, so
--  they may be written inside a condition. Writing is a *command* -- a
--  statement, where a reader sees it happen -- because a shell that could
--  change a file from inside an expression would make `if Exists (P) and then
--  Write (P, "") then` a line somebody could write by accident.
--
--  Nothing here removes anything. Unmaking files is what programs are for, and
--  this shell runs programs.
--
--  Answers rather than failures. A path that cannot be reached -- no such
--  directory, no permission to look -- is not a file, so the answer is False.
--  A predicate that could fail would need a second question beside every use,
--  and the useful answer is the same either way.
package Adash.Filesystem is

   --  Whether anything at all is at this path.
   --
   --  @param Path The path, as the user wrote it.
   --  @return True when something is there, of whatever kind.
   function Exists (Path : String) return Boolean;

   --  Whether a directory is at this path.
   --
   --  @param Path The path, as the user wrote it.
   --  @return True when it is a directory.
   function Is_Directory (Path : String) return Boolean;

   --  Whether a program at this path could be run.
   --
   --  The host's own answer, from hostkit: what "executable" means is a
   --  property of the host and not of the name.
   --
   --  @param Path The path, as the user wrote it.
   --  @return True when it is something this shell could run.
   function Is_Executable (Path : String) return Boolean;

   --  What became of a write.
   --  What became of a read.
   type Reading is
     (
      --  It was read; see the text.
      Read_Ok,

      --  There is no such file. Distinct from every failure, because a script
      --  reading what it may not yet have written is not a script with a fault
      --  in it.
      Read_Missing,

      --  It is there and could not be read: a directory, a permission, a
      --  device that answered no.
      Read_Refused,

      --  It is there and is not text this shell can carry: a file that is not
      --  UTF-8 has no String to become.
      Read_Not_Text,

      --  It is there and is larger than this shell will hold in a String.
      Read_Too_Large);

   --  What a limit of nothing in particular means.
   --
   --  A caller with no setting to hand -- a test, a tool reading one file --
   --  passes this and gets the shell's own default rather than no limit at
   --  all: unbounded has to be asked for by name, because the failure it
   --  causes is a session that dies rather than a read that is refused.
   Default_Limit : constant := 16 * 1_024 * 1_024;

   type Written is
     (
      --  It is there and holds what was given.
      Write_Ok,

      --  The path names nothing that can be written: a directory in the way, a
      --  directory that does not exist, a name the host will not form.
      Write_Refused,

      --  The host said no: permission, a full disk, a read-only mount.
      Write_Failed);

   --  Put text in a file, replacing whatever was there.
   --
   --  Ordinary permissions, not the private ones a store gets: this is the
   --  user's file, written where they asked for it, and a shell that quietly
   --  made it unreadable by anyone else would be deciding something that is
   --  not its to decide.
   --
   --  @param Path Where to write.
   --  @param Text What to write.
   --  @param Result What became of it.
   procedure Write
     (Path   : String;
      Text   : String;
      Result : out Written);

   --  Read a whole file.
   --
   --  The other half of Write, and the reason it exists: a shell that can put
   --  text in a file and cannot get it back is one whose scripts run `cat` to
   --  read what they just wrote -- a program start for something the shell can
   --  do itself, and one of the things that will not start on every host.
   --
   --  What comes back is **text**: a carriage return in front of a line feed
   --  is part of the line ending a Windows file has, and goes with it. The
   --  shell's other two readers already answer that way, and three readers of
   --  one language disagreeing about what a line ends with is worse than any
   --  of the three answers. A lone carriage return is left alone.
   --
   --  @param Path The file.
   --  @param Text What it held; empty unless this returns Read_Ok.
   --  @param Result What became of it. Read_Too_Large where the file is bigger
   --         than Limit, which is refused rather than half-read: half
   --         a file is not a shorter file, and a script cannot tell which half
   --         it got.
   --  @param Limit The most this will hold, in bytes. `read.limit` is where a
   --         user says, in mebibytes; a caller with no settings to consult
   --         passes Default_Limit.
   procedure Read
     (Path   : String;
      Text   : out Ada.Strings.Unbounded.Unbounded_String;
      Result : out Reading;
      Limit  : Natural := Default_Limit);

   --  How many things a directory holds.
   --
   --  The gap this closes is larger than it looks: nothing in this language
   --  could see what was in a directory, so the commonest loop anybody writes
   --  in a shell -- over the files in a place -- had no equivalent at all, and
   --  a script had to run a program to find out what existed. There is no
   --  pattern expansion here and there will not be, so a listing plus `Index`
   --  or `Ends_With` is how a script picks the ones it wants.
   --
   --  Everything in the directory, in one order: files, directories, and
   --  whatever else the host keeps there, sorted by name so that two runs of
   --  the same script do the same thing. `.` and `..` are left out -- every
   --  directory has them, and a loop that has to skip them every time is a
   --  loop with a wart in it.
   --
   --  Zero for a path that is not a directory, or one that cannot be read. A
   --  question has no consequences, and `Is_Directory` is how a script tells
   --  "no such place" from "nothing in it".
   --
   --  @param Path The directory.
   --  @return How many names are in it.
   function File_Count (Path : String) return Natural;

   --  One of the names in a directory, counting from one.
   --
   --  In the same order File_Count counted, and from the same reading of the
   --  directory: the two are answered from one snapshot, so a loop from 1 to
   --  File_Count sees a directory that is not changing underneath it. A file
   --  made while the loop runs turns up the next time something asks.
   --
   --  The name alone, not the path -- `Compose` is not this package's job and
   --  a script joining them with the separator it chose is a script that knows
   --  which one it wants.
   --
   --  @param Path The directory.
   --  @param Position Which one, from one.
   --  @return The name, or "" where there is no such position.
   function File_At (Path : String; Position : Positive) return String;

   --  Make a directory, and any directory above it that is missing.
   --
   --  The other half of Write in a different sense than Read is: `write_file`
   --  into a directory that is not there is refused, and until this existed a
   --  script had no way to make one -- so a shell that could save a file could
   --  not decide where to put it, and reached for a program to make the place.
   --
   --  Every missing directory in the path, rather than only the last: a script
   --  that has just worked out `logs/2026/august` means all of it, and a
   --  command that made one level would have the script call it three times
   --  and check between each. Nothing that is already there is disturbed.
   --
   --  A directory that already exists is Write_Ok rather than a failure. What
   --  the caller asked for is that it be there, and it is; a script that ran
   --  twice would otherwise fail on its second turn for having succeeded on
   --  its first.
   --
   --  @param Path The directory.
   --  @param Result Write_Ok, or Write_Refused where something that is not a
   --         directory is in the way, the host will not form the name, or it
   --         would not make it. Never Write_Failed: a write can stop in the
   --         middle and leave a file that is neither what was there nor what
   --         was meant, and a directory is made or it is not -- so there is
   --         never anything half done here for a caller to be told about.
   procedure Make_Directory (Path : String; Result : out Written);

   --  Add text to the end of a file, making it when it is not there.
   --
   --  @param Path Where to write.
   --  @param Text What to add.
   --  @param Result What became of it.
   procedure Append
     (Path   : String;
      Text   : String;
      Result : out Written);

end Adash.Filesystem;
