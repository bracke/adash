with Ada.Text_IO;

--  Reads one line and writes it back.
--
--  A program that wants the terminal, which is the only kind that can show
--  whether the shell gave it one worth having. A shell starts a job in a
--  process group of its own, and a POSIX terminal stops any program in another
--  group that reads it -- so this hangs where the shell has not handed the
--  terminal over, and answers where it has.
--
--  On a host where the shell watches its terminal for Ctrl-C the same program
--  answers the other question: watching means holding the terminal raw, and a
--  raw terminal echoes nothing and ends a line with a carriage return where a
--  reader waits for a line feed.
--
--  Either way it either answers or waits, and both are answers.
procedure Adash_Test_Reader is
begin
   --  Marked, so that what this program wrote is told apart from what a
   --  terminal echoed. Some terminals echo what is typed and some do not, and
   --  a test that could not tell the two apart would pass on the echo alone.
   Ada.Text_IO.Put_Line ("read=" & Ada.Text_IO.Get_Line);
end Adash_Test_Reader;
