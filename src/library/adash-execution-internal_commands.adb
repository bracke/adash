package body Adash.Execution.Internal_Commands is

   ------------------
   -- Is_Internal --
   ------------------

   function Is_Internal
     (Name : String;
      Id   : out Adash.Commands.Command_Id) return Boolean
   is
   begin
      --  Asked of the registry rather than answered from a list here. A second
      --  list would be a second thing to keep in step, and the two would
      --  disagree about one command for a release.
      return Adash.Commands.Find (Name, Id);
   end Is_Internal;

   ------------------
   -- Is_Internal --
   ------------------

   function Is_Internal (Name : String) return Boolean is
      Ignored : Adash.Commands.Command_Id;
   begin
      return Is_Internal (Name, Ignored);
   end Is_Internal;

end Adash.Execution.Internal_Commands;
