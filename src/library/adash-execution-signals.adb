with Hostkit.Signals;

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

   function Interrupt_Pending return Boolean is
   begin
      return Hostkit.Signals.Arrived (Hostkit.Signals.Signal_Interrupt);
   end Interrupt_Pending;

   -------------------------------
   -- Acknowledge_Interrupt --
   -------------------------------

   procedure Acknowledge_Interrupt is
   begin
      Hostkit.Signals.Clear (Hostkit.Signals.Signal_Interrupt);
   end Acknowledge_Interrupt;

end Adash.Execution.Signals;
