with Ada.Characters.Handling;
with Ada.Text_IO;

--  Reads standard input to end-of-file and writes it back uppercased.
--
--  The second stage of a pipeline has to actually read what the first wrote, or
--  a test proves only that two programs ran. This one blocks until it gets
--  end-of-file, so it also fails -- by hanging -- if the parent forgets to close
--  its copy of the pipe's write end, which is the bug most worth catching.
procedure Adash_Test_Upcase is
begin
   while not Ada.Text_IO.End_Of_File loop
      Ada.Text_IO.Put_Line
        (Ada.Characters.Handling.To_Upper (Ada.Text_IO.Get_Line));
   end loop;

   Ada.Text_IO.Flush;
end Adash_Test_Upcase;
