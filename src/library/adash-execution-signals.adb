with Ada.Calendar;
with Ada.Characters.Latin_1;
with Ada.Streams;

with Hostkit.Terminal_Control;

with Adash.Execution.Streams;
with Adash.Messages;
with Adash.Platform;

package body Adash.Execution.Signals is

   use type Hostkit.Signals.Signal;

   --  Set by a successful Install on a host that has signals. Process-wide
   --  because the dispositions are; a per-caller flag would let two callers
   --  disagree about the state of one process.
   Installed : Boolean := False;

   function Apply (To : Hostkit.Signals.Disposition) return Adash.Errors.Error_Info;
   --  Set every refused signal to one disposition.

   ---------------------------
   -- Is_Refused_By_Shell --
   ---------------------------

   function Is_Refused_By_Shell (Item : Adash.Execution.Signal) return Boolean is
   begin
      --  Enumerated rather than tested by exclusion, so that a signal added to
      --  hostkit does not silently join the list. Each entry's reason is in the
      --  package header.
      return Item = Hostkit.Signals.Signal_Pipe
        or else Item = Hostkit.Signals.Signal_Interrupt
        or else Item = Hostkit.Signals.Signal_Quit
        or else Item = Hostkit.Signals.Signal_Terminal_Stop
        or else Item = Hostkit.Signals.Signal_Background_Read
        or else Item = Hostkit.Signals.Signal_Background_Write;
   end Is_Refused_By_Shell;

   ------------------
   -- Wanted_For --
   ------------------

   function Wanted_For
     (Item : Hostkit.Signals.Signal;
      Base : Hostkit.Signals.Disposition) return Hostkit.Signals.Disposition
   is
      use type Hostkit.Signals.Disposition;
   begin
      --  Interrupt is refused like the others -- it must not kill the shell --
      --  but it is not discarded: a user pressing Ctrl-C while a program runs
      --  means "stop that", and a shell that threw the signal away could not
      --  tell. Recorded instead, and the interactive loop asks.
      --
      --  Only when the shell is taking its dispositions, not when restoring
      --  them: putting a handler back where the default belongs would leave it
      --  installed in something that is no longer a shell.
      if Item = Hostkit.Signals.Signal_Interrupt
        and then Base = Hostkit.Signals.Disposition_Ignore
      then
         return Hostkit.Signals.Disposition_Record;
      end if;

      return Base;
   end Wanted_For;

   -----------
   -- Apply --
   -----------

   function Apply (To : Hostkit.Signals.Disposition) return Adash.Errors.Error_Info is
   begin
      for Item in Hostkit.Signals.Signal loop
         if Is_Refused_By_Shell (Item) then
            --  Two questions rather than one, because a host may be able to
            --  report a signal it does not otherwise have. Windows is exactly
            --  that: no signals, and a console that can still say the user
            --  pressed Ctrl-C. Asking only Is_Supported would skip the one
            --  thing that host *can* do; asking only Can_Record would skip
            --  every signal that is merely ignored.
            --
            --  Both directions go through here, so a host reached by Can_Record
            --  on the way in is reached again on the way out and the recording
            --  is undone rather than left installed.
            if not (Hostkit.Signals.Is_Supported (Item)
                    or else Hostkit.Signals.Can_Record (Item))
            then
               --  A host that has no such signal and cannot report one either.
               --  Not a failure -- there is nothing to refuse. Skipped rather
               --  than reported, or every startup on Windows would look broken.
               null;

            elsif not Hostkit.Signals.Set_Disposition
                        (Item, Wanted_For (Item, To))
            then
               --  A signal the host has and would not change. This is a real
               --  failure: the shell asked for a disposition it needs and did
               --  not get it, and carrying on would mean dying to SIGPIPE
               --  later while believing it was safe.
               return Adash.Errors.Failure
                 (Adash.Errors.Error_Capability_Unavailable,
                  [1 => Adash.Messages.Named
                          ("capability", "")],
                     Quoted => Adash.Execution.Message (Item),
                     Fills  => "capability");
            end if;
         end if;
      end loop;

      return Adash.Errors.Success;
   end Apply;

   -------------
   -- Install --
   -------------

   function Install return Adash.Errors.Error_Info is
      Result : constant Adash.Errors.Error_Info :=
        Apply (Hostkit.Signals.Disposition_Ignore);
   begin
      if Adash.Errors.Is_Failure (Result) then
         return Result;
      end if;

      --  True only where the dispositions were actually changed. On a host
      --  without signals Install succeeds and this stays False, which is what
      --  lets a caller tell "in force" from "not needed here".
      Installed := Adash.Platform.Is_Available (Adash.Platform.Capability_Signals);

      return Adash.Errors.Success;
   end Install;

   -------------
   -- Restore --
   -------------

   function Restore return Adash.Errors.Error_Info is
      Result : constant Adash.Errors.Error_Info :=
        Apply (Hostkit.Signals.Disposition_Default);
   begin
      if Adash.Errors.Is_Failure (Result) then
         return Result;
      end if;

      Installed := False;
      return Adash.Errors.Success;
   end Restore;

   -------------------
   -- Is_Installed --
   -------------------

   function Is_Installed return Boolean is
   begin
      return Installed;
   end Is_Installed;

   ---------------------------
   -- Interrupt_Pending --
   ---------------------------

   --  Where the terminal is watched, and what the watching found.
   --
   --  A flag of this package's own rather than one of hostkit's: what arrived
   --  is a keystroke this shell read, not a signal the host delivered, and
   --  saying otherwise would make Hostkit.Signals.Arrived answer for something
   --  no signal did.
   Looking_At : Hostkit.Descriptors.Descriptor := Hostkit.Descriptors.Invalid;

   --  The terminal as the shell found it, and whether a program has it now.
   As_It_Was   : Hostkit.Terminal_Control.Mode;
   Handed_Over : Boolean := False;
   Seen_Typed : Boolean := False;
   pragma Atomic (Seen_Typed);

   --  What a terminal sends for the interrupt key, and for a return.
   Interrupt_Key : constant Ada.Streams.Stream_Element := 3;
   Return_Key    : constant Ada.Streams.Stream_Element := 13;

   function Record_Signal (Item : Hostkit.Signals.Signal) return Boolean is
   begin
      --  Asked of the host rather than assumed from the signal's name: Kill
      --  and Stop cannot be caught anywhere, and Windows can report an
      --  interrupt and nothing else.
      if not Hostkit.Signals.Can_Record (Item) then
         return False;
      end if;

      return Hostkit.Signals.Set_Disposition
               (Item, Hostkit.Signals.Disposition_Record);
   end Record_Signal;

   function Winding_Up return Boolean is
   begin
      return Hostkit.Signals.Arrived (Hostkit.Signals.Signal_Terminate)
        or else Hostkit.Signals.Arrived (Hostkit.Signals.Signal_Hangup)
        or else Hostkit.Signals.Arrived (Hostkit.Signals.Signal_Quit);
   end Winding_Up;

   function Signal_Pending (Item : Hostkit.Signals.Signal) return Boolean is
   begin
      return Hostkit.Signals.Arrived (Item);
   end Signal_Pending;

   procedure Acknowledge_Signal (Item : Hostkit.Signals.Signal) is
   begin
      Hostkit.Signals.Clear (Item);
   end Acknowledge_Signal;

   function Interrupt_Pending return Boolean is
   begin
      return Seen_Typed
        or else Hostkit.Signals.Arrived (Hostkit.Signals.Signal_Interrupt);
   end Interrupt_Pending;

   ---------------------
   -- Watch_Terminal --
   ---------------------

   procedure Watch_Terminal (Terminal : Hostkit.Descriptors.Descriptor) is
   begin
      Looking_At := Hostkit.Descriptors.Invalid;
      Handed_Over := False;

      if not Hostkit.Terminal_Control.Save_Mode (Terminal, As_It_Was) then
         return;
      end if;

      if not Hostkit.Terminal_Control.Set_Raw (Terminal) then
         return;
      end if;

      Looking_At := Terminal;
   end Watch_Terminal;

   --------------------
   -- Stop_Watching --
   --------------------

   procedure Stop_Watching is
   begin
      if not Hostkit.Descriptors.Is_Valid (Looking_At) then
         return;
      end if;

      declare
         Ignored : constant Boolean :=
           Hostkit.Terminal_Control.Restore_Mode (Looking_At, As_It_Was);
         pragma Unreferenced (Ignored);
      begin
         null;
      end;

      Looking_At := Hostkit.Descriptors.Invalid;
      Handed_Over := False;
   end Stop_Watching;

   ---------------------------
   -- Hand_Over_Terminal --
   ---------------------------

   procedure Hand_Over_Terminal is
   begin
      if not Hostkit.Descriptors.Is_Valid (Looking_At) or else Handed_Over then
         return;
      end if;

      Handed_Over := True;

      declare
         Ignored : constant Boolean :=
           Hostkit.Terminal_Control.Restore_Mode (Looking_At, As_It_Was);
         pragma Unreferenced (Ignored);
      begin
         null;
      end;
   end Hand_Over_Terminal;

   ----------------------------
   -- Take_Terminal_Back --
   ----------------------------

   procedure Take_Terminal_Back is
   begin
      if not Hostkit.Descriptors.Is_Valid (Looking_At)
        or else not Handed_Over
      then
         return;
      end if;

      Handed_Over := False;

      declare
         Ignored : constant Boolean :=
           Hostkit.Terminal_Control.Set_Raw (Looking_At);
         pragma Unreferenced (Ignored);
      begin
         null;
      end;
   end Take_Terminal_Back;

   ----------------
   -- Watching --
   ----------------

   function Watching return Boolean is
   begin
      return Hostkit.Descriptors.Is_Valid (Looking_At) and then not Handed_Over;
   end Watching;

   -------------------------------
   -- Look_For_An_Interrupt --
   -------------------------------

   --  How often the terminal is worth a look.
   --
   --  Not every instruction. Looking means three calls into the host, and a
   --  machine running millions of instructions a second would spend most of
   --  its time asking a keyboard whether anything had happened. A twentieth of
   --  a second is far below what a user can notice between pressing Ctrl-C and
   --  a loop stopping, and far above what this costs.
   Look_Interval : constant Duration := 0.05;

   --  The clock is not asked every instruction either: reading it is cheap,
   --  and cheap times ten million is not.
   Between_Clocks : constant := 1_024;

   Since_A_Look  : Natural := 0;
   Last_Look     : Ada.Calendar.Time := Ada.Calendar.Clock;

   procedure Look_For_An_Interrupt is
      Buffer : Ada.Streams.Stream_Element_Array (1 .. 64);
      Last   : Ada.Streams.Stream_Element_Offset;

      use type Ada.Calendar.Time;
      use type Ada.Streams.Stream_Element;
      use type Hostkit.Descriptors.Transfer_Outcome;
   begin
      if not Watching then
         return;
      end if;

      Since_A_Look := Since_A_Look + 1;

      if Since_A_Look < Between_Clocks then
         return;
      end if;

      Since_A_Look := 0;

      if Ada.Calendar.Clock - Last_Look < Look_Interval then
         return;
      end if;

      Last_Look := Ada.Calendar.Clock;

      if not Hostkit.Descriptors.Wait_Readable (Looking_At, 0)
        or else Hostkit.Descriptors.Read (Looking_At, Buffer, Last)
                /= Hostkit.Descriptors.Transfer_Ok
      then
         return;
      end if;

      declare
         Kept  : String (1 .. Natural (Last));
         Count : Natural := 0;
      begin
         for Index in Buffer'First .. Last loop
            if Buffer (Index) = Interrupt_Key then
               Seen_Typed := True;
            else
               --  Everything else is what the user typed while waiting, and it
               --  belongs to whoever reads next rather than to this look.
               --
               --  A return arrives as a carriage return here, because that is
               --  what a raw terminal sends and nothing is translating it. The
               --  reader that takes these bytes next may be the editor, which
               --  reads either, or a script's Read_Line, which looks for a
               --  line feed and would wait forever for one. So it is written
               --  down as the line feed it means.
               Count := Count + 1;
               Kept (Count) :=
                 (if Buffer (Index) = Return_Key
                  then Ada.Characters.Latin_1.LF
                  else Character'Val (Natural (Buffer (Index))));
            end if;
         end loop;

         if Count > 0 then
            Adash.Execution.Streams.Put_Back (Kept (1 .. Count));
         end if;
      end;
   end Look_For_An_Interrupt;

   -------------------------------
   -- Acknowledge_Interrupt --
   -------------------------------

   procedure Acknowledge_Interrupt is
   begin
      Seen_Typed := False;
      Hostkit.Signals.Clear (Hostkit.Signals.Signal_Interrupt);
   end Acknowledge_Interrupt;

end Adash.Execution.Signals;
