with Adash.Commands;

--  Deciding whether something is the shell's own.
--
--  The execution subsystem has one question to ask before it does anything:
--  does this name a command the shell runs itself, or a program to start? The
--  answer changes everything that follows -- an internal command must not be
--  forked, because forking is precisely what would make `cd` and `exit`
--  useless.
--
--  That question lives here rather than in Adash.Commands because it is
--  execution's question. Adash.Commands owns what the commands *are*; this owns
--  the one decision the execution subsystem makes about them, and keeps
--  Adash.Execution from having to know the registry's shape.
--
--  Resolution order is fixed and documented, because a user needs to be able to
--  predict it: **an internal command wins over an external program of the same
--  name.** A `cd` on PATH does not shadow the shell's own, and a shell where it
--  could would be one where installing a program changes what a script means.
package Adash.Execution.Internal_Commands is

   --  Whether a name is one the shell runs itself.
   --
   --  Case-insensitive, as every Adash name is.
   --
   --  @param Name The command name as written.
   --  @param Id Which internal command, when this returns True.
   --  @return True when the shell runs it rather than starting a program.
   function Is_Internal
     (Name : String;
      Id   : out Adash.Commands.Command_Id) return Boolean;

   --  Whether a name is internal, without asking which.
   --
   --  For a completer deciding how to describe a candidate, and for a
   --  diagnostic that has to say why a program was not searched for.
   --
   --  @param Name The command name as written.
   --  @return True when the shell runs it.
   function Is_Internal (Name : String) return Boolean;

end Adash.Execution.Internal_Commands;
