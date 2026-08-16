with Ada.Command_Line;
with Ada.Streams;
with Ada.Text_IO;

with Hostkit.Descriptors;
with Hostkit.Terminal_Control;

with Adash.Execution.Signals;
with Adash.Errors;

--  Sit on a terminal and write down what arrives.
--
--  A companion for one question that reading documentation has not answered:
--  what reaches a program on this host's terminal while it is busy, and in what
--  shape. The shell cannot report it -- it is the thing under test, and on the
--  host in question it goes on running as though nothing had been typed.
--
--  It writes to a file it is told to open, for the same reason
--  hostkit's terminal reporter does: a program asked what it sees on its own
--  terminal cannot answer *on* that terminal if the answer is that it sees
--  nothing.
--
--  What it records, in order:
--
--    * `raw=` whether it could put the terminal into raw mode, since what
--      arrives depends on that,
--    * `armed=` whether the interrupt disposition took,
--    * `byte=N` for each byte it reads, as a number, because the interesting
--      ones are not printable,
--    * `interrupt` where the recorded-signal flag turned out to be set, which
--      is the other way a Ctrl-C can arrive,
--    * `end`.
procedure Adash_Test_Watch is
   Where : constant String :=
     (if Ada.Command_Line.Argument_Count >= 1
      then Ada.Command_Line.Argument (1) else "");

   Seconds : constant Duration :=
     (if Ada.Command_Line.Argument_Count >= 2
      then Duration'Value (Ada.Command_Line.Argument (2)) else 5.0);

   Report : Ada.Text_IO.File_Type;

begin
   if Where = "" then
      Ada.Command_Line.Set_Exit_Status (2);
      return;
   end if;

   Ada.Text_IO.Create (Report, Ada.Text_IO.Out_File, Where);

   declare
      Armed : constant Adash.Errors.Error_Info :=
        Adash.Execution.Signals.Install;
   begin
      Ada.Text_IO.Put_Line
        (Report,
         "armed=" & Boolean'Image (not Adash.Errors.Is_Failure (Armed)));
   end;

   Ada.Text_IO.Put_Line
     (Report,
      "raw="
      & Boolean'Image
          (Hostkit.Terminal_Control.Set_Raw
             (Hostkit.Descriptors.Standard_Input)));

   Ada.Text_IO.Flush (Report);

   --  A fixed number of turns rather than a clock: this is a companion, and a
   --  companion that outlived its test would be a process nobody reaps.
   for Turn in 1 .. Integer (Seconds * 20) loop
      if Hostkit.Descriptors.Wait_Readable
           (Hostkit.Descriptors.Standard_Input, 50)
      then
         declare
            Buffer : Ada.Streams.Stream_Element_Array (1 .. 64);
            Last   : Ada.Streams.Stream_Element_Offset;

            use type Hostkit.Descriptors.Transfer_Outcome;
         begin
            if Hostkit.Descriptors.Read
                 (Hostkit.Descriptors.Standard_Input, Buffer, Last)
               = Hostkit.Descriptors.Transfer_Ok
            then
               for Index in Buffer'First .. Last loop
                  Ada.Text_IO.Put_Line
                    (Report,
                     "byte=" & Natural'Image (Natural (Buffer (Index))));
               end loop;

               Ada.Text_IO.Flush (Report);
            end if;
         end;
      end if;

      if Adash.Execution.Signals.Interrupt_Pending then
         Ada.Text_IO.Put_Line (Report, "interrupt");
         Ada.Text_IO.Flush (Report);
         Adash.Execution.Signals.Acknowledge_Interrupt;
      end if;
   end loop;

   Ada.Text_IO.Put_Line (Report, "end");
   Ada.Text_IO.Close (Report);
end Adash_Test_Watch;
