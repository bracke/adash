private with Ada.Finalization;
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
   --  directory: a loop from 1 to File_Count walks the listing the count came
   --  from, so a file made while the loop runs does not shift the ones after
   --  it. Asking File_Count again reads the directory again -- a script that
   --  lists a place, removes something and lists it again sees what it did.
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

   --  Take a file away.
   --
   --  The other half of writing one, and it was missing for a reason that
   --  stopped being true: unmaking things was left to programs, and this shell
   --  now runs where the program that does it is not there. A script that can
   --  make a file and cannot remove it is a script that leaks.
   --
   --  A file only. A directory is refused here and removed by the call below,
   --  because the two mistakes they protect against are different sizes.
   --
   --  @param Path The file.
   --  @param Result Write_Ok when it is gone -- including when it was not
   --         there to start with, because what the caller asked for is that it
   --         not be there. Write_Refused for a directory, or a file the host
   --         will not part with.
   procedure Remove_File (Path : String; Result : out Written);

   --  Take an empty directory away.
   --
   --  **Empty only, and deliberately.** A recursive removal is one typo away
   --  from a catastrophe -- the single most destructive thing a shell can be
   --  asked to do -- and a script that means it can say it: list the directory,
   --  remove what is in it, then remove the directory. That is three lines
   --  which say what they will destroy, rather than one that says it in a way
   --  a slip of the finger can widen.
   --
   --  @param Path The directory.
   --  @param Result Write_Ok when it is gone, including when it was not there.
   --         Write_Refused for something that is not a directory, one that
   --         still holds something, or one the host will not part with.
   procedure Remove_Directory (Path : String; Result : out Written);

   --  Give something another name, or another place.
   --
   --  What `mv` does, and the same call for both because they are one act to a
   --  filesystem: a rename within a place and a move between two.
   --
   --  @param From What to rename. Refused when there is nothing there.
   --  @param To The new name. Refused when something is already there -- a
   --         move that silently replaced what it landed on would be the
   --         destructive case wearing the name of the safe one.
   --  @param Result What became of it.
   procedure Rename (From : String; To : String; Result : out Written);

   --  Copy a file.
   --
   --  @param From The file to copy. Refused when it is not there or is a
   --         directory: copying a tree is the recursive case again, and the
   --         loop that does it is the caller's to write.
   --  @param To Where to put it. Refused when something is already there.
   --  @param Result What became of it.
   procedure Copy_File (From : String; To : String; Result : out Written);

   --  Add text to the end of a file, making it when it is not there.
   --
   --  @param Path Where to write.
   --  @param Text What to add.
   --  @param Result What became of it.
   procedure Append
     (Path   : String;
      Text   : String;
      Result : out Written);

   --  A file holding text, for as long as a command needs one.
   --
   --  What `run_from_text` is made of. A program reads its input from a
   --  descriptor, so text a script computed has to become one somehow, and
   --  there are two ways: a pipe the shell writes into, or a file the shell
   --  makes first.
   --
   --  **A file, because a pipe would deadlock.** A pipe holds a bufferful --
   --  64k on one host, 8k on another, and a caller cannot know which -- and a
   --  shell writing more than that into a pipe waits for the program to read
   --  it, while a program that reads its whole input before answering waits
   --  for the shell. Both wait for ever, and the size at which that starts
   --  differs per host, so the failure would arrive on somebody else's
   --  machine. A file has no such point.
   --
   --  **In a private temporary directory**, so text a script did not choose to
   --  publish -- a token, a password being piped into a program that wants it
   --  on standard input -- is not readable by other users while it is there.
   --
   --  **Removed when the holder goes out of scope**, including where the
   --  command was refused, raised, or was interrupted half way. That is why
   --  this is a controlled type rather than a path and a matching call: the
   --  command that uses it has a dozen ways out, and eleven of them would have
   --  been the one nobody wrote the deletion on.
   type Held_Text is limited private;

   --  Put text in a file of its own.
   --
   --  @param Item The holder. Anything it held before is removed first.
   --  @param Text What the file is to contain.
   --  @param Result Write_Ok when the file is there and holds the text.
   procedure Hold (Item : in out Held_Text; Text : String;
                   Result : out Written);

   --  Where the text is.
   --
   --  @param Item The holder.
   --  @return The full path, or "" when it holds nothing.
   function Path (Item : Held_Text) return String;

private

   type Held_Text is new Ada.Finalization.Limited_Controlled with record
      --  The directory this made, which is what has to be removed: the file
      --  inside it is ours and so is the directory, and removing only the file
      --  would leave one empty directory per command in the host's temporary
      --  space.
      Room : Ada.Strings.Unbounded.Unbounded_String;
      File : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   overriding procedure Finalize (Item : in out Held_Text);

end Adash.Filesystem;
