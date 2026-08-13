with Adash.Diagnostics;
with Adash.Execution;

--  The internal commands themselves.
--
--  Split from Adash.Commands so that the registry -- what exists, what its
--  metadata is, how a name is looked up -- is separable from the dozen
--  implementations. A registry that also held the bodies would be one package
--  that changes every time any command does.
--
--  Argument counts are checked before anything here runs, so each body may
--  assume it has as many arguments as its metadata allows.
private package Adash.Commands.Builtins is

   --  Run one command.
   --
   --  @param Id Which command.
   --  @param Arguments Its arguments, already checked for count.
   --  @param Shell The state it may read and change.
   --  @param Produced Where its output lines go.
   --  @param Report Where diagnostics go.
   --  @return What became of it.
   function Run
     (Id        : Command_Id;
      Arguments : Argument_Set;
      Shell     : in out State;
      Produced  : in out Output;
      Report    : in out Adash.Diagnostics.List)
      return Adash.Execution.Exit_Status;

end Adash.Commands.Builtins;
