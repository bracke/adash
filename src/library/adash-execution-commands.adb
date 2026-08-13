package body Adash.Execution.Commands is

   use Ada.Strings.Unbounded;

   ----------
   -- Make --
   ----------

   function Make
     (Program   : String;
      Arguments : Hostkit.String_Vectors.Vector) return Invocation
   is
      Result : Invocation;
   begin
      Result.Program     := To_Unbounded_String (Program);
      Result.Arguments   := Arguments;
      Result.Environment := Adash.Execution.Environment.Inherited;
      return Result;
   end Make;

   ---------------------
   -- Append_Argument --
   ---------------------

   procedure Append_Argument (Item : in out Invocation; Value : String) is
   begin
      Item.Arguments.Append (To_Unbounded_String (Value));
   end Append_Argument;

   -------------
   -- Program --
   -------------

   function Program (Item : Invocation) return String is
   begin
      return To_String (Item.Program);
   end Program;

   -------------
   -- Release --
   -------------

   procedure Release (Item : in out Invocation) is
   begin
      Adash.Execution.Streams.Release (Item.Input);
      Adash.Execution.Streams.Release (Item.Output);
      Adash.Execution.Streams.Release (Item.Error_Output);
   end Release;

end Adash.Execution.Commands;
