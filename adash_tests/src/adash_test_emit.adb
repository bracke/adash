with Ada.Command_Line;
with Ada.Text_IO;

--  Writes each argument on its own line, then exits with the status named by
--  the first argument if that argument is a number.
--
--  Shipped rather than borrowed from the host, for the reason hostkit's own
--  companions are: /bin/echo is absent on Windows, and every stand-in behaves
--  differently enough to make a test prove something other than what it says.
procedure Adash_Test_Emit is
   Status : Integer := 0;
begin
   for Index in 1 .. Ada.Command_Line.Argument_Count loop
      declare
         Value : constant String := Ada.Command_Line.Argument (Index);
      begin
         if Index = 1 and then Value'Length > 6
           and then Value (Value'First .. Value'First + 5) = "--exit"
         then
            Status := Integer'Value (Value (Value'First + 7 .. Value'Last));
         else
            Ada.Text_IO.Put_Line (Value);
         end if;
      end;
   end loop;

   Ada.Text_IO.Flush;
   Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Exit_Status (Status));
exception
   when others =>
      Ada.Command_Line.Set_Exit_Status (9);
end Adash_Test_Emit;
