with Ada.Strings.Unbounded;

with Hostkit;
with Hostkit.Fs;
with Hostkit.Process;

with Adash.Execution.Environment;
with Adash.Execution.Streams;
with Adash.Messages;

package body Adash.Execution.External is

   use Ada.Strings.Unbounded;
   use type Hostkit.Spawn.Spawn_Outcome;
   use type Hostkit.Spawn.Wait_State;

   package C renames Adash.Execution.Commands;
   package S renames Adash.Execution.Streams;

   function Names_A_Path (Program : String) return Boolean;
   --  Whether the program is a path rather than a name to look up.

   function Prepare (Item : in out C.Invocation) return Boolean;
   --  Make every endpoint inheritable. False when one could not be.

   function To_Options (Item : C.Invocation) return Hostkit.Spawn.Options;
   --  The host-level options for an invocation, minus the group placement.

   -------------------
   -- Names_A_Path --
   -------------------

   function Names_A_Path (Program : String) return Boolean is
   begin
      for Character_Index in Program'Range loop
         --  Both separators, on every host. A Windows path may use either, and
         --  a POSIX filename containing a backslash is legal but is not
         --  something a shell should quietly look up on PATH.
         if Program (Character_Index) = '/'
           or else Program (Character_Index) = '\'
         then
            return True;
         end if;
      end loop;

      return False;
   end Names_A_Path;

   -------------
   -- Resolve --
   -------------

   function Resolve (Item : C.Invocation) return Resolution is
      Program : constant String := C.Program (Item);
      Result  : Resolution;
   begin
      if Program = "" then
         return Result;
      end if;

      if Names_A_Path (Program) then
         Result.Was_Path := True;

         --  Real_Path answers "" for something that is not there, which is the
         --  question being asked. Executability is not checked here: the host
         --  decides that at the moment of running, and a check now would be a
         --  different answer from the one that matters.
         if Hostkit.Fs.Real_Path (Program) /= "" then
            Result.Found := True;
            Result.Path  := To_Unbounded_String (Program);
         end if;

         return Result;
      end if;

      declare
         Located : constant String := Hostkit.Process.Locate (Program);
      begin
         if Located /= "" then
            Result.Found := True;
            Result.Path  := To_Unbounded_String (Located);
         end if;
      end;

      return Result;
   end Resolve;

   -------------
   -- Prepare --
   -------------

   function Prepare (Item : in out C.Invocation) return Boolean is
   begin
      --  Every descriptor this crate makes is close-on-exec, so each endpoint
      --  the child needs has to be opened up one at a time. That is the whole
      --  reason a pipe end does not leak into the next child in a pipeline.
      return S.Prepare_For_Child (Item.Input)
        and then S.Prepare_For_Child (Item.Output)
        and then S.Prepare_For_Child (Item.Error_Output);
   end Prepare;

   ----------------
   -- To_Options --
   ----------------

   function To_Options (Item : C.Invocation) return Hostkit.Spawn.Options is
      Result : Hostkit.Spawn.Options;
   begin
      Result.Working_Directory := Item.Working_Directory;
      Result.Input             := S.Handle (Item.Input);
      Result.Output            := S.Handle (Item.Output);
      Result.Error_Output      := S.Handle (Item.Error_Output);

      --  Always replaced, never inherited. The invocation carries the
      --  environment the command is to run with, and letting the host fall
      --  back to this process's own would silently ignore a variable the user
      --  set for this one command.
      Result.Replace_Environment := True;
      Result.Environment := Adash.Execution.Environment.To_Vector (Item.Environment);

      --  A child gets the host's default signal dispositions back. The shell
      --  ignores SIGINT so Ctrl-C does not kill it; a child that inherited that
      --  would be a foreground program nothing can interrupt.
      Result.Reset_Signals := True;

      return Result;
   end To_Options;

   --------------------
   -- Failure_For --
   --------------------

   function Failure_For
     (Outcome : Hostkit.Spawn.Spawn_Outcome;
      Program : String) return Adash.Errors.Error_Info
   is
      Named : constant Adash.Messages.Argument_List :=
        [1 => Adash.Messages.Named ("command", Program)];
   begin
      case Outcome is
         when Hostkit.Spawn.Spawn_Ok =>
            return Adash.Errors.Success;
         when Hostkit.Spawn.Spawn_Not_Found =>
            return Adash.Errors.Failure (Adash.Errors.Error_Command_Not_Found, Named);
         when Hostkit.Spawn.Spawn_Not_Executable =>
            return Adash.Errors.Failure (Adash.Errors.Error_Command_Not_Executable, Named);
         when Hostkit.Spawn.Spawn_Denied =>
            return Adash.Errors.Failure (Adash.Errors.Error_Command_Denied, Named);
         when Hostkit.Spawn.Spawn_Failed =>
            return Adash.Errors.Failure
              (Adash.Errors.Error_Command_Start_Failed,
               [Adash.Messages.Named ("command", Program),
                Adash.Messages.Named ("reason", "")],
             Quoted => Adash.Messages.Msg_Start_Reason_Host_Refused,
             Fills  => "reason");
      end case;
   end Failure_For;

   ---------------------
   -- Start_In_Group --
   ---------------------

   function Start_In_Group
     (Item       : in out C.Invocation;
      Join_Group : Integer;
      Process    : out Hostkit.Spawn.Process_Handle;
      Error      : out Adash.Errors.Error_Info) return Boolean
   is
      Options : Hostkit.Spawn.Options := To_Options (Item);
      Outcome : Hostkit.Spawn.Spawn_Outcome;
   begin
      Process := Hostkit.Spawn.Invalid_Process;
      Error   := Adash.Errors.Success;

      if not Prepare (Item) then
         C.Release (Item);
         Error := Adash.Errors.Failure
           (Adash.Errors.Error_Command_Start_Failed,
            [Adash.Messages.Named ("command", C.Program (Item)),
             Adash.Messages.Named ("reason", "")],
          Quoted => Adash.Messages.Msg_Start_Reason_Stream_Setup,
          Fills  => "reason");
         return False;
      end if;

      if Join_Group = 0 then
         Options.Group := Hostkit.Spawn.Group_New;
      else
         Options.Group      := Hostkit.Spawn.Group_Join;
         Options.Join_Group := Join_Group;
      end if;

      Outcome := Hostkit.Spawn.Start
        (C.Program (Item), Item.Arguments, Options, Process);

      --  Released whether it worked or not, and before returning. The child has
      --  its copies; the shell holding on is what stops the far end of a pipe
      --  from ever seeing end-of-file.
      C.Release (Item);

      if Outcome /= Hostkit.Spawn.Spawn_Ok then
         Error := Failure_For (Outcome, C.Program (Item));
         return False;
      end if;

      return True;
   end Start_In_Group;

   -----------
   -- Start --
   -----------

   function Start
     (Item    : in out C.Invocation;
      Process : out Hostkit.Spawn.Process_Handle;
      Error   : out Adash.Errors.Error_Info) return Boolean
   is
      Options : Hostkit.Spawn.Options := To_Options (Item);
      Outcome : Hostkit.Spawn.Spawn_Outcome;
   begin
      Process := Hostkit.Spawn.Invalid_Process;
      Error   := Adash.Errors.Success;

      if not Prepare (Item) then
         C.Release (Item);
         Error := Adash.Errors.Failure
           (Adash.Errors.Error_Command_Start_Failed,
            [Adash.Messages.Named ("command", C.Program (Item)),
             Adash.Messages.Named ("reason", "")],
          Quoted => Adash.Messages.Msg_Start_Reason_Stream_Setup,
          Fills  => "reason");
         return False;
      end if;

      Options.Group := Hostkit.Spawn.Group_Inherit;

      Outcome := Hostkit.Spawn.Start
        (C.Program (Item), Item.Arguments, Options, Process);

      C.Release (Item);

      if Outcome /= Hostkit.Spawn.Spawn_Ok then
         Error := Failure_For (Outcome, C.Program (Item));
         return False;
      end if;

      return True;
   end Start;

   ----------
   -- Wait --
   ----------

   function Wait
     (Process  : Hostkit.Spawn.Process_Handle;
      Blocking : Boolean;
      Status   : out Adash.Execution.Exit_Status) return Observation
   is
      Result : Hostkit.Spawn.Status;
   begin
      Status := Adash.Execution.Success;

      if not Hostkit.Spawn.Wait
        (Process,
         (if Blocking then Hostkit.Spawn.Wait_Block else Hostkit.Spawn.Wait_Poll),
         Result)
      then
         Status := (Kind => Adash.Execution.Exit_Internal_Error, others => <>);
         return Observed_Ended;
      end if;

      case Result.State is
         when Hostkit.Spawn.Wait_Running =>
            return Observed_Running;

         when Hostkit.Spawn.Wait_Exited =>
            Status := Adash.Execution.From_External_Code (Result.Exit_Code);
            return Observed_Ended;

         when Hostkit.Spawn.Wait_Signalled =>
            Status := Adash.Execution.From_Signal
              (Result.Terminating_Signal, Result.Signal_Known);
            return Observed_Ended;

         when Hostkit.Spawn.Wait_Stopped =>
            --  Not an ending. A stopped job still exists and can be resumed;
            --  reporting it as finished is how a shell loses a suspended job,
            --  and reporting it as running is how a shell never notices one.
            return Observed_Suspended;

         when Hostkit.Spawn.Wait_Continued =>
            return Observed_Resumed;

         when Hostkit.Spawn.Wait_Lost =>
            Status := (Kind => Adash.Execution.Exit_Internal_Error, others => <>);
            return Observed_Ended;
      end case;
   end Wait;

end Adash.Execution.External;
