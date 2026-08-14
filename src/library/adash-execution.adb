package body Adash.Execution is

   use type Hostkit.Signals.Signal;

   --  The numbers of the documented model. Named so that the case statement
   --  below reads as the table in the specification rather than as arithmetic.
   Status_Success          : constant := 0;
   Status_Internal_Failure : constant := 1;
   Status_Usage            : constant := 2;
   Status_Not_Executable   : constant := 126;
   Status_Not_Found        : constant := 127;
   Status_Signal_Base      : constant := 128;
   Status_Internal_Error   : constant := 70;

   --  What an interruption reduces to, said here rather than worked out.
   --
   --  128 + SIGINT is where the number comes from and is what a user who
   --  pressed Ctrl-C recognises, but it is *this shell's* answer rather than
   --  the host's: Windows has no signal numbers, `Hostkit.Signals.Number`
   --  refuses to invent one, and computing 128 + (-1) made an interruption
   --  report 127 -- the number this table gives a command that was not found.
   --  A convention of ours belongs in a constant of ours.
   Status_Interrupted      : constant := 130;

   ---------------
   -- Succeeded --
   ---------------

   function Succeeded (Item : Exit_Status) return Boolean is
   begin
      case Item.Kind is
         when Exit_Internal_Success =>
            return True;

         when Exit_External =>
            return Item.Code = 0;

         when Exit_Internal_Failure
            | Exit_Signalled
            | Exit_Start_Failure
            | Exit_Parse_Failure
            | Exit_Semantic_Failure
            | Exit_Cancelled
            | Exit_Internal_Error =>
            --  Cancellation counts as failure on purpose. A script whose
            --  command was interrupted must not go on to the next step as
            --  though it had worked.
            return False;
      end case;
   end Succeeded;

   -------------
   -- Numeric --
   -------------

   function Numeric (Item : Exit_Status) return Natural is
   begin
      case Item.Kind is
         when Exit_Internal_Success =>
            return Status_Success;

         when Exit_Internal_Failure =>
            return Status_Internal_Failure;

         when Exit_External =>
            --  A program's own status, clamped into the range a process status
            --  can carry. A program that returned 256 did not return 0, and
            --  letting the host's truncation decide would say it did.
            if Item.Code < 0 then
               return Status_Internal_Failure;
            elsif Item.Code > 255 then
               return Item.Code mod 256;
            else
               return Item.Code;
            end if;

         when Exit_Signalled =>
            if not Item.Signal_Known then
               --  Killed by something this crate does not name. Reported as a
               --  plain failure rather than as 128 + a number that was never
               --  read, which would name the wrong signal.
               return Status_Internal_Failure;
            end if;

            --  A host that has no number for the signal cannot be asked for
            --  one: 128 + (-1) is 127, which this table already means "not
            --  found". Reported as a plain failure, which is what an unknown
            --  signal above already gets and for the same reason.
            if Hostkit.Signals.Number (Item.Terminating_Signal) < 0 then
               return Status_Internal_Failure;
            end if;

            return Status_Signal_Base
              + Hostkit.Signals.Number (Item.Terminating_Signal);

         when Exit_Start_Failure =>
            --  Which of the two it is was decided by From_Start_Failure and
            --  carried in Code, because the distinction is the point.
            return (if Item.Code = Status_Not_Executable
                    then Status_Not_Executable
                    else Status_Not_Found);

         when Exit_Parse_Failure | Exit_Semantic_Failure =>
            return Status_Usage;

         when Exit_Cancelled =>
            --  The shell's own answer, the same on every host: a script that
            --  checks for 130 is checking what Adash did, not what the host
            --  calls an interrupt.
            return Status_Interrupted;

         when Exit_Internal_Error =>
            return Status_Internal_Error;
      end case;
   end Numeric;

   ------------------------
   -- From_External_Code --
   ------------------------

   function From_External_Code (Code : Integer) return Exit_Status is
   begin
      return (Kind               => Exit_External,
              Code               => Code,
              Terminating_Signal => Hostkit.Signals.Signal_Terminate,
              Signal_Known       => False);
   end From_External_Code;

   -----------------
   -- From_Signal --
   -----------------

   function From_Signal
     (Terminating_Signal : Signal;
      Known              : Boolean := True) return Exit_Status
   is
   begin
      return (Kind               => Exit_Signalled,
              Code               => 0,
              Terminating_Signal => Terminating_Signal,
              Signal_Known       => Known);
   end From_Signal;

   ------------------------
   -- From_Start_Failure --
   ------------------------

   -------------
   -- Message --
   -------------

   function Message (Item : Signal) return Adash.Messages.Message_Id is
   begin
      --  No `others`: a signal hostkit adds must be given words here rather
      --  than falling back to its identifier, which is the failure this
      --  function exists to end.
      case Item is
         when Hostkit.Signals.Signal_Interrupt =>
            return Adash.Messages.Msg_Signal_Interrupt;
         when Hostkit.Signals.Signal_Quit =>
            return Adash.Messages.Msg_Signal_Quit;
         when Hostkit.Signals.Signal_Terminate =>
            return Adash.Messages.Msg_Signal_Terminate;
         when Hostkit.Signals.Signal_Kill =>
            return Adash.Messages.Msg_Signal_Kill;
         when Hostkit.Signals.Signal_Hangup =>
            return Adash.Messages.Msg_Signal_Hangup;
         when Hostkit.Signals.Signal_Stop =>
            return Adash.Messages.Msg_Signal_Stop;
         when Hostkit.Signals.Signal_Terminal_Stop =>
            return Adash.Messages.Msg_Signal_Terminal_Stop;
         when Hostkit.Signals.Signal_Continue =>
            return Adash.Messages.Msg_Signal_Continue;
         when Hostkit.Signals.Signal_Pipe =>
            return Adash.Messages.Msg_Signal_Pipe;
         when Hostkit.Signals.Signal_Background_Read =>
            return Adash.Messages.Msg_Signal_Background_Read;
         when Hostkit.Signals.Signal_Background_Write =>
            return Adash.Messages.Msg_Signal_Background_Write;
         when Hostkit.Signals.Signal_Window_Change =>
            return Adash.Messages.Msg_Signal_Window_Change;
         when Hostkit.Signals.Signal_Child =>
            return Adash.Messages.Msg_Signal_Child;
      end case;
   end Message;

   ------------------------
   -- From_Start_Error --
   ------------------------

   function From_Start_Error
     (Reason : Adash.Errors.Error_Code) return Exit_Status is
   begin
      case Reason is
         when Adash.Errors.Error_Command_Not_Found =>
            return From_Start_Failure (Executable_Found => False);

         when Adash.Errors.Error_Command_Not_Executable
            | Adash.Errors.Error_Command_Denied =>
            --  Found, and refused. Denied is the same answer: something is
            --  there and this shell may not run it, which is what 126 says.
            return From_Start_Failure (Executable_Found => True);

         when others =>
            --  The host refused for a reason of its own, or the failure was
            --  ours. Neither is a statement about the program.
            return (Kind => Exit_Internal_Failure, others => <>);
      end case;
   end From_Start_Error;

   ------------------------
   -- From_Start_Failure --
   ------------------------

   function From_Start_Failure (Executable_Found : Boolean) return Exit_Status is
   begin
      return (Kind               => Exit_Start_Failure,
              Code               =>
                (if Executable_Found then Status_Not_Executable else Status_Not_Found),
              Terminating_Signal => Hostkit.Signals.Signal_Terminate,
              Signal_Known       => False);
   end From_Start_Failure;

end Adash.Execution;
