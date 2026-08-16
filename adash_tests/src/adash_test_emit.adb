with Ada.Command_Line;
with Ada.Text_IO;

with Hostkit.Host;

--  Writes each argument on its own line, then exits with the status it was
--  told to.
--
--  Shipped rather than borrowed from the host, for the reason hostkit's own
--  companions are: /bin/echo is absent on Windows, and every stand-in behaves
--  differently enough to make a test prove something other than what it says.
--
--  Four arguments are read rather than written:
--
--    --exit=N    exit with status N
--    --error=T   write T to standard error rather than to standard output
--    --part=T    write T to standard error without ending the line, which is
--                what a program killed mid-write leaves behind
--    --sleep=S   wait S seconds before finishing
--    --file=P    write the contents of the file P
--    --repeat=N  write the arguments that follow N times each
--    --crlf      end each line with a carriage return and a line feed, on
--                every host -- which on Windows means letting Text_IO do it
--
--  Between them a conformance case can have a program that says something, a
--  program that fails, a program that complains where nobody should be
--  collecting it, a program that is still running, a program that shows what a
--  file holds, and a program that writes more than a shell will hold in one
--  capture -- on every host, without naming a utility one of them does not
--  have.
procedure Adash_Test_Emit is
   use type Hostkit.Host.Kind;

   Status : Integer := 0;
   Waited : Duration := 0.0;

   --  How many times each of the arguments after it is written. One by
   --  default, which is what every case that does not ask wants.
   Times : Positive := 1;

   --  Whether lines end the way a Windows program ends them, on every host.
   --
   --  So that what a shell does about the host's line endings can be asserted
   --  everywhere rather than only where the host happens to write them: a rule
   --  that only one of three hosts exercises is a rule that breaks on the
   --  other two without anybody hearing about it.
   Windows_Endings : Boolean := False;

   procedure Say (Text : String);

   procedure Say (Text : String) is
   begin
      if Windows_Endings
        and then Hostkit.Host.Current /= Hostkit.Host.Windows
      then
         --  The carriage return by hand and the line feed through New_Line:
         --  writing both by hand leaves Text_IO thinking the line is still
         --  open, and it adds a terminator of its own at the end.
         --
         --  Only where the host does not do it already. On Windows every line
         --  Text_IO writes ends in a carriage return and a line feed, so
         --  adding one by hand wrote two of them -- and a shell that dropped
         --  the one in front of the line feed handed back the other, which is
         --  how this was found.
         Ada.Text_IO.Put (Text & Character'Val (13));
         Ada.Text_IO.New_Line;
      else
         Ada.Text_IO.Put_Line (Text);
      end if;
   end Say;

   --  Whether an argument is one of the three, and what it carries.
   function Introduced_By (Value : String; Flag : String) return Boolean
   is (Value'Length > Flag'Length
       and then Value (Value'First .. Value'First + Flag'Length - 1) = Flag);

   function After (Value : String; Flag : String) return String
   is (Value (Value'First + Flag'Length .. Value'Last));
begin
   for Index in 1 .. Ada.Command_Line.Argument_Count loop
      declare
         Value : constant String := Ada.Command_Line.Argument (Index);
      begin
         if Introduced_By (Value, "--exit=") then
            Status := Integer'Value (After (Value, "--exit="));

         elsif Introduced_By (Value, "--error=") then
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Standard_Error, After (Value, "--error="));

         elsif Introduced_By (Value, "--part=") then
            --  No terminator. A program that dies part-way through saying
            --  something leaves exactly this, and what happens to the next
            --  thing written to that stream is the question it raises.
            Ada.Text_IO.Put
              (Ada.Text_IO.Standard_Error, After (Value, "--part="));
            Ada.Text_IO.Flush (Ada.Text_IO.Standard_Error);

         elsif Value = "--crlf" then
            Windows_Endings := True;

         elsif Introduced_By (Value, "--repeat=") then
            Times := Positive'Value (After (Value, "--repeat="));

         elsif Introduced_By (Value, "--sleep=") then
            Waited := Duration'Value (After (Value, "--sleep="));

         elsif Introduced_By (Value, "--file=") then
            declare
               Source : Ada.Text_IO.File_Type;
            begin
               Ada.Text_IO.Open
                 (Source, Ada.Text_IO.In_File, After (Value, "--file="));
               while not Ada.Text_IO.End_Of_File (Source) loop
                  Say (Ada.Text_IO.Get_Line (Source));
               end loop;
               Ada.Text_IO.Close (Source);
            end;

         else
            for Turn in 1 .. Times loop
               Say (Value);
            end loop;
         end if;
      end;
   end loop;

   Ada.Text_IO.Flush;
   Ada.Text_IO.Flush (Ada.Text_IO.Standard_Error);

   if Waited > 0.0 then
      --  A delay rather than a busy wait: what a case wants from this is a job
      --  that is still there when it looks, and a spinning process on a shared
      --  runner is a poor way to provide one.
      delay Waited;
   end if;

   Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Exit_Status (Status));
exception
   when others =>
      Ada.Command_Line.Set_Exit_Status (9);
end Adash_Test_Emit;
