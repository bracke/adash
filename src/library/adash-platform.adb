with Hostkit.Pty;
with Hostkit.Signals;
with Hostkit.Terminal_Control;

package body Adash.Platform is

   ------------------
   -- Is_Available --
   ------------------

   -------------
   -- Message --
   -------------

   function Message (Item : Capability) return Adash.Messages.Message_Id is
   begin
      case Item is
         when Capability_Signals =>
            return Adash.Messages.Msg_Capability_Signals;
         when Capability_Job_Control =>
            return Adash.Messages.Msg_Capability_Job_Control;
         when Capability_Pseudo_Terminal =>
            return Adash.Messages.Msg_Capability_Pseudo_Terminal;
         when Capability_Advisory_Locks =>
            return Adash.Messages.Msg_Capability_Advisory_Locks;
      end case;
   end Message;

   function Is_Available (Item : Capability) return Boolean is
   begin
      case Item is
         when Capability_Signals =>
            --  Asked about one signal rather than all of them. A host either
            --  has the facility or does not; there is no host with some of it,
            --  and asking about each would invite a consumer to build on a
            --  partial answer.
            return Hostkit.Signals.Is_Supported (Hostkit.Signals.Signal_Terminate);

         when Capability_Job_Control =>
            --  Both halves are needed and neither is sufficient. Process groups
            --  without a way to hand over the terminal give a job that cannot
            --  read the keyboard; a terminal handover without signals gives a
            --  job that cannot be interrupted once it has it.
            return Hostkit.Terminal_Control.Supports_Foreground_Group
              and then Hostkit.Signals.Is_Supported (Hostkit.Signals.Signal_Terminal_Stop);

         when Capability_Pseudo_Terminal =>
            return Hostkit.Pty.Is_Supported;

         when Capability_Advisory_Locks =>
            --  There is no Is_Supported to ask here, because whether locks work
            --  is a property of the filesystem rather than of the host: the
            --  same binary gets them on a local disk and not on some network
            --  mounts. Reported optimistically, and Adash.Persistence has to
            --  handle Lock_Unsupported from an actual Acquire regardless --
            --  which it would have to do even if this answered False.
            return True;
      end case;
   end Is_Available;

   ----------
   -- Name --
   ----------

   function Name (Item : Capability) return String is
   begin
      case Item is
         when Capability_Signals         => return "SIGNALS";
         when Capability_Job_Control     => return "JOB_CONTROL";
         when Capability_Pseudo_Terminal => return "PSEUDO_TERMINAL";
         when Capability_Advisory_Locks  => return "ADVISORY_LOCKS";
      end case;
   end Name;

   -----------------
   -- Unavailable --
   -----------------

   function Unavailable (Item : Capability) return Adash.Errors.Error_Info is
   begin
      return Adash.Errors.Failure
        (Adash.Errors.Error_Capability_Unavailable,
         [1 => Adash.Messages.Named ("capability", Name (Item))]);
   end Unavailable;

end Adash.Platform;
