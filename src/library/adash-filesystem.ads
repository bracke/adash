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
