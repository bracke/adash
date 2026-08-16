with Ada.Directories;
with Ada.IO_Exceptions;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;

with Adash.Errors;
with Adash.Filesystem;
with Adash.Language.Values;
with Adash.Version;

with Hostkit;
with Hostkit.Fs;
with Adash.Configuration;
with Adash.Configuration.Files;
with Adash.Persistence;
with Adash.Platform;

with Adash.Execution.Commands;
with Adash.Execution.Jobs;
with Adash.Execution.Pipelines;
with Adash.Execution.Redirection;
with Adash.Execution.Signals;
with Adash.Execution.Streams;

package body Adash.Commands.Builtins is

   package M renames Adash.Messages;

   --  A number as a user reads it, without the space Integer'Image leads with.
   function Trim (Value : Integer) return String is
     (Ada.Strings.Fixed.Trim (Integer'Image (Value), Ada.Strings.Both));

   package Env renames Adash.Execution.Environment;

   use Ada.Strings.Unbounded;

   --  A command's argument as text.
   --
   --  Image rather than Text: Text answers only for a String and gives "" for
   --  everything else, which would turn `quit (3)` into `quit ("")` silently.
   --  Image is the canonical text of any value, and a String images as its own
   --  contents without quotes.
   function Argument
     (Arguments : Argument_Set; Index : Positive) return String
   is (if Index <= Arguments.Count
       then Adash.Language.Values.Image (Arguments.Given (Index)) else "");

   --  Whether a command's argument is a String.
   --
   --  Asked of the value rather than of the profile, because the parameter
   --  takes whatever it is given: `forget (3)` and `forget ("git push")` are
   --  the same command told which entry two different ways.
   function Text_Argument
     (Arguments : Argument_Set; Index : Positive) return Boolean
   is (Index <= Arguments.Count
       and then Adash.Language.Types."="
                  (Adash.Language.Values.Kind (Arguments.Given (Index)),
                   Adash.Language.Types.Type_String));

   --  A command's argument as a whole number.
   --
   --  @return False when there is no such argument or it is not an Integer.
   --          The analyser has already checked the type against the command's
   --          profile, so False here means a caller built the argument set by
   --          hand and got it wrong -- which is worth reporting rather than
   --          defaulting.
   function Whole_Argument
     (Arguments : Argument_Set; Index : Positive; Into : out Integer)
      return Boolean
   is (Index <= Arguments.Count
       and then Adash.Language.Values.Get (Arguments.Given (Index), Into));

   ---------
   -- Run --
   ---------

   function Run
     (Id        : Command_Id;
      Arguments : Argument_Set;
      Shell     : in out State;
      Produced  : in out Output;
      Report    : in out Adash.Diagnostics.List)
      return Adash.Execution.Exit_Status
   is
      Given : constant Natural := Arguments.Count;

      --  Report a message directly.
      --
      --  The configuration messages are addressed by identifier rather than
      --  through an error code -- Adash.Configuration.Files raises them the
      --  same way -- so a command that reports one says so in the same terms
      --  rather than inventing a code that means "one of those".
      function Refused
        (Message : M.Message_Id;
         Args    : M.Argument_List;
         Quoted  : M.Message_Id := M.Msg_Error_None;
         Given   : M.Argument_List := M.No_Arguments)
         return Adash.Execution.Exit_Status;

      function Refused
        (Message : M.Message_Id;
         Args    : M.Argument_List;
         Quoted  : M.Message_Id := M.Msg_Error_None;
         Given   : M.Argument_List := M.No_Arguments)
         return Adash.Execution.Exit_Status
      is
      begin
         Report.Emit
           (Adash.Diagnostics.Make
              (Message   => Message,
               Level     => Adash.Diagnostics.Severity_Error,
               Of_Kind   => Adash.Diagnostics.Category_Configuration,
               Raised_By => Adash.Diagnostics.Owner_Commands,
               Arguments => Args,
               Quoted    => Quoted,
               Fills     => "detail",
               Quoted_Arguments => Given));

         return (Kind => Adash.Execution.Exit_Internal_Failure, others => <>);
      end Refused;

      function Failed
        (Code   : Adash.Errors.Error_Code;
         Args   : M.Argument_List;
         Quoted : M.Message_Id := M.Msg_Error_None;
         Fills  : String := "") return Adash.Execution.Exit_Status
      is
      begin
         Report.Emit
           (Adash.Diagnostics.From_Error
              (Adash.Errors.Failure (Code, Args, Quoted, Fills),
               Level     => Adash.Diagnostics.Severity_Error,
               Of_Kind   => Adash.Diagnostics.Category_Execution,
               Raised_By => Adash.Diagnostics.Owner_Commands));

         return (Kind => Adash.Execution.Exit_Internal_Failure, others => <>);
      end Failed;

   begin
      case Id is

         when Command_Change_Directory =>
            declare
               --  With no argument, the home directory -- asked of hostkit,
               --  which knows where a host keeps one, rather than read from
               --  HOME, which a spawned process can set to anything.
               Target : constant String :=
                 (if Given = 0 then Hostkit.Fs.Home_Directory
                  else Argument (Arguments, 1));
            begin
               if Target = "" then
                  return Failed (Adash.Errors.Error_Directory_Not_Found,
                                 [1 => M.Named ("path", Target)]);
               end if;

               begin
                  --  The process's own directory, so there is one answer and a
                  --  child inherits the real one without being told.
                  Ada.Directories.Set_Directory (Target);
               exception
                  when Ada.IO_Exceptions.Name_Error =>
                     return Failed (Adash.Errors.Error_Directory_Not_Found,
                                    [1 => M.Named ("path", Target)]);
                  when Ada.IO_Exceptions.Use_Error =>
                     return Failed (Adash.Errors.Error_Directory_Denied,
                                    [1 => M.Named ("path", Target)]);
               end;

               return Adash.Execution.Success;
            end;

         when Command_Print_Directory =>
            Say (Produced, M.Msg_Line_Directory,
                 [1 => M.Named ("path", Ada.Directories.Current_Directory)]);
            return Adash.Execution.Success;

         when Command_Exit =>
            Shell.Exit_Requested := True;

            if Given = 1 then
               declare
                  Status : Integer;
               begin
                  --  No Integer'Value on something the user typed. The status
                  --  is an Integer by the time it reaches here, because the
                  --  analyser checked it against quit's profile before
                  --  anything ran -- which is the whole point of commands
                  --  having typed profiles.
                  if Whole_Argument (Arguments, 1, Status) then
                     Shell.Exit_Status :=
                       Adash.Execution.From_External_Code (Status);
                  else
                     --  Not an Integer. The analyser would have refused it, so
                     --  reaching here means a caller built the argument set by
                     --  hand and got it wrong. The session still ends, because
                     --  that is what was asked for.
                     Shell.Exit_Status :=
                       (Kind => Adash.Execution.Exit_Internal_Failure,
                        others => <>);
                     return Failed
                       (Adash.Errors.Error_Command_Wrong_Arguments,
                        [M.Named ("name", "quit"),
                         M.Named ("found", Argument (Arguments, 1))]);
                  end if;
               end;
            else
               Shell.Exit_Status := Adash.Execution.Success;
            end if;

            return Shell.Exit_Status;

         when Command_Set =>
            declare
               Text  : constant String := Argument (Arguments, 1);
               Split : Natural := 0;
            begin
               for Index in Text'Range loop
                  if Text (Index) = '=' then
                     Split := Index;
                     exit;
                  end if;
               end loop;

               --  NAME=VALUE and nothing else. A `set` that accepted a bare
               --  name would have to decide what it meant -- empty, or unset --
               --  and either choice surprises half its users.
               if Split <= Text'First then
                  return Failed (Adash.Errors.Error_Command_Bad_Assignment,
                                 [1 => M.Named ("text", Text)]);
               end if;

               Env.Set (Shell.Environment,
                        Text (Text'First .. Split - 1),
                        Text (Split + 1 .. Text'Last));
               return Adash.Execution.Success;
            end;

         when Command_Unset =>
            Env.Unset (Shell.Environment, Argument (Arguments, 1));
            return Adash.Execution.Success;

         when Command_Environment =>
            --  Sorted, because Adash.Execution.Environment keeps it that way.
            --  A listing that changed order between runs would be one nobody
            --  could diff.
            for Entry_Text of Env.To_Vector (Shell.Environment) loop
               declare
                  Text  : constant String := To_String (Entry_Text);
                  Split : Natural := Text'First - 1;
               begin
                  for Index in Text'Range loop
                     if Text (Index) = '=' then
                        Split := Index;
                        exit;
                     end if;
                  end loop;

                  if Split >= Text'First then
                     Say (Produced, M.Msg_Line_Variable,
                          [M.Named ("name", Text (Text'First .. Split - 1)),
                           M.Named ("value", Text (Split + 1 .. Text'Last))]);
                  end if;
               end;
            end loop;

            return Adash.Execution.Success;

         when Command_Jobs =>
            --  What has finished since anyone last looked is noticed here
            --  rather than in the background: nothing polls, so a job's state
            --  is only as fresh as the last question asked about it.
            Adash.Execution.Jobs.Refresh (Shell.Jobs);

            for Id of Adash.Execution.Jobs.Ids (Shell.Jobs) loop
               Say (Produced, M.Msg_Line_Job,
                    [M.Named ("job", Trim (Integer (Id))),
                     M.Named
                       ("description",
                        Adash.Execution.Jobs.Description (Shell.Jobs, Id))],
                    Quoted =>
                      Adash.Execution.Jobs.Message
                        (Adash.Execution.Jobs.State (Shell.Jobs, Id)),
                    Fills  => "state");
            end loop;

            return Adash.Execution.Success;

         when Command_Pipe =>
            declare
               Args : Hostkit.String_Vectors.Vector;
            begin
               for Position in 2 .. Given loop
                  Args.Append
                    (Ada.Strings.Unbounded.To_Unbounded_String
                       (Argument (Arguments, Position)));
               end loop;

               Adash.Execution.Pipelines.Add_Stage
                 (Shell.Pending,
                  Adash.Execution.Commands.Make
                    (Argument (Arguments, 1), Args));

               return Adash.Execution.Success;
            end;

         when Command_Pipe_Run =>
            declare
               Running : Adash.Execution.Pipelines.Running;
               Error   : Adash.Errors.Error_Info;
            begin
               if Adash.Execution.Pipelines.Length (Shell.Pending) = 0
               then
                  --  Nothing was added. Refused rather than treated as a
                  --  pipeline of nothing, which would succeed and look like it
                  --  had run something.
                  return Failed (Adash.Errors.Error_Empty_Pipeline,
                                 M.No_Arguments);
               end if;

               if not Adash.Execution.Pipelines.Start
                        (Shell.Pending, Running, Error)
               then
                  --  Cleared even when it would not start. Leaving the stages
                  --  behind would put them at the front of whatever the user
                  --  built next, which is the last thing somebody fixing a
                  --  mistyped program name wants.
                  Shell.Pending := Adash.Execution.Pipelines.Empty_Plan;

                  Report.Emit
                    (Adash.Diagnostics.From_Error
                       (Error, Adash.Diagnostics.Severity_Error,
                        Adash.Diagnostics.Category_Execution,
                        Adash.Diagnostics.Owner_Commands));

                  return Adash.Execution.From_Start_Error (Error.Code);
               end if;

               Shell.Pending := Adash.Execution.Pipelines.Empty_Plan;

               declare
                  Started : constant Adash.Execution.Jobs.Job_Id :=
                    Adash.Execution.Jobs.Add
                      (Shell.Jobs, Running, "pipeline",
                       Adash.Execution.Jobs.Placement_Foreground);

                  Wait_Error : Adash.Errors.Error_Info;

                  Finished : constant Boolean :=
                    Adash.Execution.Jobs.Wait
                      (Shell.Jobs, Started, Shell.Interrupt, Wait_Error);
               begin
                  if not Finished then
                     declare
                        Stop_Error : Adash.Errors.Error_Info;
                        Asked      : constant Boolean :=
                          Adash.Execution.Jobs.Terminate_Job
                            (Shell.Jobs, Started, Stop_Error);
                     begin
                        pragma Unreferenced (Asked);
                     end;

                     Adash.Execution.Jobs.Forget (Shell.Jobs, Started);
                     return (Kind => Adash.Execution.Exit_Cancelled,
                             others => <>);
                  end if;

                  declare
                     --  The last stage's status is the pipeline's, which is
                     --  what every shell reports and what a reader means by
                     --  "did it work".
                     Ended : constant Adash.Execution.Exit_Status :=
                       Adash.Execution.Jobs.Result (Shell.Jobs, Started).Status;
                  begin
                     Adash.Execution.Jobs.Forget (Shell.Jobs, Started);
                     return Ended;
                  end;
               end;
            end;

         when Command_Run | Command_Run_Into | Command_Run_From
            | Command_Run_Append | Command_Run_New | Command_Run_Errors_Into
            | Command_Start =>
            declare
               Waits : constant Boolean := Id /= Command_Start;

               --  The first argument names a file when one of the program's
               --  streams is going to it, so the program starts one later.
               Redirects : constant Boolean :=
                 Id in Command_Run_Into | Command_Run_From
                     | Command_Run_Append | Command_Run_New
                     | Command_Run_Errors_Into;

               First_Word : constant Positive := (if Redirects then 2 else 1);

               --  What the file is attached as, said in the terms the
               --  redirection subsystem uses rather than in open modes. That
               --  package owns opening: it knows that appending is a property
               --  of the open file rather than a seek, that refusing an
               --  existing file has to be the open itself and not a prior
               --  check, and that a command which will not run must not have
               --  half-created its output. Opening the file here would be a
               --  second, quietly different copy of all three.
               Attach : Adash.Execution.Redirection.Plan;

               Line : Adash.Execution.Pipelines.Plan :=
                 Adash.Execution.Pipelines.Empty_Plan;
               Args : Hostkit.String_Vectors.Vector;
               Running : Adash.Execution.Pipelines.Running;
               Error   : Adash.Errors.Error_Info;
               Told    : Ada.Strings.Unbounded.Unbounded_String :=
                 Ada.Strings.Unbounded.To_Unbounded_String
                   (Argument (Arguments, First_Word));
            begin
               if Redirects then
                  declare
                     Asked : constant Adash.Execution.Redirection.Redirection :=
                       (Role =>
                          (case Id is
                              when Command_Run_From =>
                                Adash.Execution.Streams.Role_Input,
                              when Command_Run_Errors_Into =>
                                Adash.Execution.Streams.Role_Error,
                              when others =>
                                Adash.Execution.Streams.Role_Output),
                        Kind =>
                          (case Id is
                              when Command_Run_From =>
                                Adash.Execution.Redirection.Redirect_From_File,
                              when Command_Run_Append =>
                                Adash.Execution.Redirection.Redirect_Append_File,
                              when Command_Run_New =>
                                Adash.Execution.Redirection.Redirect_To_New_File,
                              when others =>
                                Adash.Execution.Redirection.Redirect_To_File),
                        Path =>
                          Ada.Strings.Unbounded.To_Unbounded_String
                            (Argument (Arguments, 1)));

                     Refused : Adash.Errors.Error_Info;
                  begin
                     if not Adash.Execution.Redirection.Add
                              (Attach, Asked, Refused)
                     then
                        Report.Emit
                          (Adash.Diagnostics.From_Error
                             (Refused, Adash.Diagnostics.Severity_Error,
                              Adash.Diagnostics.Category_Execution,
                              Adash.Diagnostics.Owner_Commands));

                        return (Kind => Adash.Execution.Exit_Internal_Failure,
                                others => <>);
                     end if;
                  end;
               end if;

               for Position in First_Word + 1 .. Given loop
                  Args.Append
                    (Ada.Strings.Unbounded.To_Unbounded_String
                       (Argument (Arguments, Position)));
                  Ada.Strings.Unbounded.Append
                    (Told, " " & Argument (Arguments, Position));
               end loop;

               declare
                  Stage : Adash.Execution.Commands.Invocation :=
                    Adash.Execution.Commands.Make
                      (Argument (Arguments, First_Word), Args);

                  Attached : Adash.Errors.Error_Info;
               begin
                  --  Opened now, not when the redirection was named: the file
                  --  is created at the moment the program is about to run, so
                  --  a command refused for any other reason has not touched it.
                  if Adash.Execution.Redirection.Length (Attach) > 0
                    and then not Adash.Execution.Redirection.Apply
                                   (Attach, Stage, Attached)
                  then
                     Report.Emit
                       (Adash.Diagnostics.From_Error
                          (Attached, Adash.Diagnostics.Severity_Error,
                           Adash.Diagnostics.Category_Execution,
                           Adash.Diagnostics.Owner_Commands));

                     return (Kind => Adash.Execution.Exit_Internal_Failure,
                             others => <>);
                  end if;

                  --  A background job does not share the keyboard. What it
                  --  gets instead, and why, is Streams.Background_Input --
                  --  which is where the rule lives so that a test can ask it
                  --  rather than having to arrange a whole job to watch.
                  if not Waits then
                     Stage.Input :=
                       Adash.Execution.Streams.Background_Input (Stage.Input);
                  end if;

                  Adash.Execution.Pipelines.Add_Stage (Line, Stage);
               end;

               if not Adash.Execution.Pipelines.Start (Line, Running, Error) then
                  --  Reported as the pipeline described it: which program, and
                  --  what the host said about it.
                  Report.Emit
                    (Adash.Diagnostics.From_Error
                       (Error, Adash.Diagnostics.Severity_Error,
                        Adash.Diagnostics.Category_Execution,
                        Adash.Diagnostics.Owner_Commands));

                  return Adash.Execution.From_Start_Error (Error.Code);
               end if;

               declare
                  Started : constant Adash.Execution.Jobs.Job_Id :=
                    Adash.Execution.Jobs.Add
                      (Shell.Jobs, Running,
                       Ada.Strings.Unbounded.To_String (Told),
                       (if Waits then Adash.Execution.Jobs.Placement_Foreground
                        else Adash.Execution.Jobs.Placement_Background));
               begin
                  if not Waits then
                     Say (Produced, M.Msg_Line_Job_Started,
                          [M.Named ("id", Trim (Integer (Started))),
                           M.Named ("what",
                                    Ada.Strings.Unbounded.To_String (Told))]);

                     return Adash.Execution.Success;
                  end if;

                  --  Waited for, which is what makes this the foreground. The
                  --  session's interrupt goes with it: the child is in a
                  --  process group of its own, so Ctrl-C does not reach it by
                  --  itself, and a wait that ignored the interrupt would leave
                  --  a user with no way out of a program that will not end.
                  declare
                     Wait_Error : Adash.Errors.Error_Info;
                     Ended      : Adash.Execution.Exit_Status;

                     --  The terminal, for as long as this program runs.
                     --
                     --  Both halves, as in Pipelines.Run: the console mode
                     --  where the shell watches its terminal, and the
                     --  terminal's foreground group where the host has them.
                     --  This is the path a user types -- `run ("cat")` --
                     --  and it waits here rather than in Pipelines.Run, so it
                     --  needs its own handover rather than inheriting one.
                     Ours : Integer;

                     Finished : Boolean;
                  begin
                     Adash.Execution.Signals.Hand_Over_Terminal;
                     Adash.Execution.Pipelines.Hand_The_Terminal_To
                       (Adash.Execution.Pipelines.Group (Running), Ours);

                     Finished :=
                       Adash.Execution.Jobs.Wait
                         (Shell.Jobs, Started, Shell.Interrupt, Wait_Error);

                     Adash.Execution.Pipelines.Take_The_Terminal_Back (Ours);
                     Adash.Execution.Signals.Take_Terminal_Back;

                     if not Finished then
                        --  Interrupted, or stopped. Asked to end so that a
                        --  program the user walked away from does not outlive
                        --  the line that started it.
                        declare
                           Stop_Error : Adash.Errors.Error_Info;
                           Asked      : constant Boolean :=
                             Adash.Execution.Jobs.Terminate_Job
                               (Shell.Jobs, Started, Stop_Error);
                        begin
                           pragma Unreferenced (Asked);
                        end;

                        Adash.Execution.Jobs.Forget (Shell.Jobs, Started);

                        return (Kind => Adash.Execution.Exit_Cancelled,
                                others => <>);
                     end if;

                     Ended := Adash.Execution.Jobs.Result
                       (Shell.Jobs, Started).Status;

                     --  Forgotten once its status has been taken. A foreground
                     --  program is not a job a user tracks, and leaving it in
                     --  the table would make `jobs` a list of everything ever
                     --  run.
                     Adash.Execution.Jobs.Forget (Shell.Jobs, Started);

                     return Ended;
                  end;
               end;
            end;

         when Command_Wait =>
            declare
               Wanted : Integer;
            begin
               if not Whole_Argument (Arguments, 1, Wanted)
                 or else Wanted < 1
                 or else not Adash.Execution.Jobs.Contains
                               (Shell.Jobs, Adash.Execution.Jobs.Job_Id (Wanted))
               then
                  return Failed (Adash.Errors.Error_Job_Unknown,
                                 [1 => M.Named ("job", Trim (Wanted))]);
               end if;

               declare
                  Error : Adash.Errors.Error_Info;
                  Ended : Adash.Execution.Exit_Status;

                  --  Waiting for a job is putting it in the foreground, in the
                  --  only sense a user means by the word: nothing else runs
                  --  until it ends. So it gets the terminal for as long as
                  --  that takes, exactly as a program started by `run` does --
                  --  a job asked a question while the shell held the terminal
                  --  would be stopped where it asked.
                  Ours : Integer;

                  Done : Boolean;
               begin
                  Adash.Execution.Signals.Hand_Over_Terminal;
                  Adash.Execution.Pipelines.Hand_The_Terminal_To
                    (Adash.Execution.Jobs.Group
                       (Shell.Jobs, Adash.Execution.Jobs.Job_Id (Wanted)),
                     Ours);

                  Done :=
                    Adash.Execution.Jobs.Wait
                      (Shell.Jobs, Adash.Execution.Jobs.Job_Id (Wanted),
                       Cancel => null, Error => Error);

                  Adash.Execution.Pipelines.Take_The_Terminal_Back (Ours);
                  Adash.Execution.Signals.Take_Terminal_Back;

                  if not Done then
                     --  Suspended rather than finished. Said plainly: waiting
                     --  for it would wait for an ending it cannot reach while
                     --  it is stopped, and `no such job` sent the reader
                     --  looking for a job that is right there.
                     return Failed
                       ((if Adash.Execution.Jobs."="
                             (Adash.Execution.Jobs.State
                                (Shell.Jobs,
                                 Adash.Execution.Jobs.Job_Id (Wanted)),
                              Adash.Execution.Jobs.Job_Stopped)
                         then Adash.Errors.Error_Job_Is_Suspended
                         else Adash.Errors.Error_Job_Unknown),
                        [1 => M.Named ("job", Trim (Wanted))]);
                  end if;

                  --  The last stage's status is the pipeline's own, which is
                  --  the one a caller means by "how did the job end".
                  Ended := Adash.Execution.Jobs.Result
                    (Shell.Jobs, Adash.Execution.Jobs.Job_Id (Wanted)).Status;

                  --  A job the host killed has no exit code: Code is only
                  --  meaningful for a program that chose one, and reporting it
                  --  anyway said "status 0" for something that was terminated.
                  if Adash.Execution."=" (Ended.Kind,
                                          Adash.Execution.Exit_Signalled)
                    and then Ended.Signal_Known
                  then
                     Say (Produced, M.Msg_Line_Job_Signalled,
                          [1 => M.Named ("id", Trim (Wanted))],
                          Quoted =>
                            Adash.Execution.Message
                              (Ended.Terminating_Signal),
                          Fills  => "signal");
                  else
                     Say (Produced, M.Msg_Line_Job_Finished,
                          [M.Named ("id", Trim (Wanted)),
                           M.Named ("status", Trim (Ended.Code))]);
                  end if;

                  --  The job's own status, so `wait` on a failing job fails.
                  return Ended;
               end;
            end;

         when Command_Stop | Command_Suspend | Command_Resume =>
            declare
               Wanted : Integer;
            begin
               if not Whole_Argument (Arguments, 1, Wanted)
                 or else Wanted < 1
                 or else not Adash.Execution.Jobs.Contains
                               (Shell.Jobs, Adash.Execution.Jobs.Job_Id (Wanted))
               then
                  return Failed (Adash.Errors.Error_Job_Unknown,
                                 [1 => M.Named ("job", Trim (Wanted))]);
               end if;

               declare
                  Which : constant Adash.Execution.Jobs.Job_Id :=
                    Adash.Execution.Jobs.Job_Id (Wanted);

                  Error : Adash.Errors.Error_Info;

                  --  Three ways to signal one job, and one shape for all of
                  --  them: which job, what to ask of it, and what the table
                  --  said when it could not.
                  Asked : constant Boolean :=
                    (case Id is
                        when Command_Suspend =>
                          Adash.Execution.Jobs.Suspend
                            (Shell.Jobs, Which, Error),
                        when Command_Resume =>
                          Adash.Execution.Jobs.Resume_In_Background
                            (Shell.Jobs, Which, Error),
                        when others =>
                          Adash.Execution.Jobs.Terminate_Job
                            (Shell.Jobs, Which, Error));
               begin
                  if not Asked then
                     --  Reported as the job table described it. This used to
                     --  answer `no job control here` whatever went wrong,
                     --  which is a guess: a host that refused the signal and a
                     --  host that has no groups at all are different answers
                     --  and the reader is owed whichever applies.
                     if Adash.Errors.Is_Failure (Error) then
                        Report.Emit
                          (Adash.Diagnostics.From_Error
                             (Error, Adash.Diagnostics.Severity_Error,
                              Adash.Diagnostics.Category_Execution,
                              Adash.Diagnostics.Owner_Commands));

                        return (Kind => Adash.Execution.Exit_Internal_Failure,
                                others => <>);
                     end if;

                     return Failed (Adash.Errors.Error_Capability_Unavailable,
                                    M.No_Arguments,
                                    Quoted =>
                                      Adash.Platform.Message
                                        (Adash.Platform.Capability_Job_Control),
                                    Fills => "capability");
                  end if;

                  --  What became of it. `stop` ends a job and `wait` reports
                  --  that; suspending and resuming leave it in the table, so
                  --  the line naming its new state is the only word the user
                  --  would otherwise get.
                  if Id /= Command_Stop then
                     --  Not refreshed again here: the table has already waited
                     --  for the job to reach the state it was asked for, and
                     --  polling once more would read a moment later than the
                     --  one that was confirmed.
                     Say (Produced, M.Msg_Line_Job,
                          [M.Named ("job", Trim (Wanted)),
                           M.Named
                             ("description",
                              Adash.Execution.Jobs.Description
                                (Shell.Jobs, Which))],
                          Quoted =>
                            Adash.Execution.Jobs.Message
                              (Adash.Execution.Jobs.State (Shell.Jobs, Which)),
                          Fills  => "state");
                  end if;

                  return Adash.Execution.Success;
               end;
            end;

         when Command_Settings =>
            declare
               package Config renames Adash.Configuration;

               --  A setting's value, as the user would type it back.
               function Written (Which : Config.Setting_Id) return String;

               function Written (Which : Config.Setting_Id) return String is
               begin
                  case Config.Kind (Which) is
                     when Config.Boolean_Setting =>
                        --  Ada spells these True and False, and so does the
                        --  language this shell speaks. The configuration file
                        --  is TOML and spells them lower case; what is shown
                        --  is what the file holds, because that is what a user
                        --  who goes to edit it will see.
                        return (if Shell.Chosen.Boolean_Value (Which)
                                then "true" else "false");

                     when Config.Integer_Setting =>
                        return Trim
                          (Integer (Shell.Chosen.Integer_Value (Which)));

                     when Config.Choice_Setting =>
                        return Shell.Chosen.Choice_Value (Which);
                  end case;
               end Written;
            begin
               if Given = 0 then
                  for Which in Config.Setting_Id loop
                     Say (Produced, M.Msg_Line_Setting,
                          [M.Named ("key", Config.Key (Which)),
                           M.Named ("value", Written (Which))],
                          Quoted => Config.Description (Which),
                          Fills  => "summary");
                  end loop;

                  return Adash.Execution.Success;
               end if;

               if Given /= 2 then
                  --  A name with no value is a question this command cannot
                  --  answer differently from the listing, and a value with no
                  --  name is nothing at all.
                  return Failed (Adash.Errors.Error_Command_Wrong_Arguments,
                                 [M.Named ("name", "settings"),
                                  M.Named ("found", Trim (Given))]);
               end if;

               declare
                  Which : Config.Setting_Id;
                  Named_As : constant String := Argument (Arguments, 1);
                  Wanted   : constant String := Argument (Arguments, 2);
               begin
                  if not Config.Find (Named_As, Which) then
                     --  Its own message rather than the file reader's. That
                     --  one says the key `was ignored`, which is true of a
                     --  line in a file nobody is watching and wrong for
                     --  something a user has just typed.
                     return Refused
                       (M.Msg_Setting_Unknown,
                        [1 => M.Named ("key", Named_As)]);
                  end if;

                  case Config.Kind (Which) is
                     when Config.Boolean_Setting =>
                        --  Only the two words the file uses. Accepting `yes`
                        --  or `1` here would make the shell and the file
                        --  disagree about what a Boolean looks like.
                        if Wanted = "true" then
                           Shell.Chosen.Set_Boolean (Which, True);
                        elsif Wanted = "false" then
                           Shell.Chosen.Set_Boolean (Which, False);
                        else
                           return Refused
                             (M.Msg_Config_Wrong_Type,
                              [1 => M.Named ("key", Named_As)],
                              M.Msg_Config_Wants_Truth);
                        end if;

                     when Config.Integer_Setting =>
                        declare
                           Value : Long_Long_Integer;
                        begin
                           Value := Long_Long_Integer'Value (Wanted);

                           if not Shell.Chosen.Set_Integer (Which, Value) then
                              return Refused
                                (M.Msg_Config_Out_Of_Range,
                                 [1 => M.Named ("key", Named_As)],
                                 M.Msg_Config_Wants_Range,
                                 [M.Named
                                    ("low",
                                     Trim (Integer (Config.Minimum (Which)))),
                                  M.Named
                                    ("high",
                                     Trim
                                       (Integer
                                          (Config.Maximum (Which))))]);
                           end if;
                        exception
                           when Constraint_Error =>
                              return Refused
                                (M.Msg_Config_Wrong_Type,
                                 [1 => M.Named ("key", Named_As)],
                                 M.Msg_Config_Wants_Whole);
                        end;

                     when Config.Choice_Setting =>
                        if not Shell.Chosen.Set_Choice (Which, Wanted) then
                           --  What it would have accepted, so the reader does
                           --  not have to go and find the list.
                           declare
                              Allowed : Ada.Strings.Unbounded.Unbounded_String;
                           begin
                              for Index in 1 .. Config.Choice_Count (Which) loop
                                 if Index > 1 then
                                    Ada.Strings.Unbounded.Append
                                      (Allowed, ", ");
                                 end if;

                                 Ada.Strings.Unbounded.Append
                                   (Allowed, Config.Choice_At (Which, Index));
                              end loop;

                              return Refused
                                (M.Msg_Config_Bad_Choice,
                                 [M.Named ("key", Named_As),
                                  M.Named
                                    ("detail",
                                     Ada.Strings.Unbounded.To_String
                                       (Allowed))]);
                           end;
                        end if;
                  end case;

                  --  Said back, so a user sees what the shell now holds rather
                  --  than trusting that it took.
                  Say (Produced, M.Msg_Line_Setting,
                       [M.Named ("key", Config.Key (Which)),
                        M.Named ("value", Written (Which))],
                       Quoted => Config.Description (Which),
                       Fills  => "summary");

                  return Adash.Execution.Success;
               end;
            end;

         when Command_Write_File | Command_Append_File =>
            declare
               What : constant String := Argument (Arguments, 1);
               Path : constant String := Argument (Arguments, 2);
               Done : Adash.Filesystem.Written;
            begin
               if Id = Command_Write_File then
                  Adash.Filesystem.Write (Path, What, Done);
               else
                  Adash.Filesystem.Append (Path, What, Done);
               end if;

               case Done is
                  when Adash.Filesystem.Write_Refused =>
                     return Failed (Adash.Errors.Error_File_Not_Writable,
                                    [1 => M.Named ("path", Path)]);

                  when Adash.Filesystem.Write_Failed =>
                     return Failed (Adash.Errors.Error_File_Write_Failed,
                                    [1 => M.Named ("path", Path)]);

                  when Adash.Filesystem.Write_Ok =>
                     --  Silent. A command that announced each write would put
                     --  its own lines into the script's output, so a script
                     --  that saves a file and prints a result could not have
                     --  its output read by anything. `Status` says it worked;
                     --  a failure says so on standard error.
                     return Adash.Execution.Success;
               end case;
            end;

         when Command_Make_Directory =>
            declare
               Path : constant String := Argument (Arguments, 1);
               Done : Adash.Filesystem.Written;
            begin
               Adash.Filesystem.Make_Directory (Path, Done);

               case Done is
                  when Adash.Filesystem.Write_Refused =>
                     return Failed (Adash.Errors.Error_File_Not_Writable,
                                    [1 => M.Named ("path", Path)]);

                  when Adash.Filesystem.Write_Failed =>
                     return Failed (Adash.Errors.Error_File_Write_Failed,
                                    [1 => M.Named ("path", Path)]);

                  when Adash.Filesystem.Write_Ok =>
                     --  Silent, like writing: a command that announced itself
                     --  would put its own lines into a script's output.
                     return Adash.Execution.Success;
               end case;
            end;

         when Command_Save_Settings =>
            declare
               Result : Adash.Persistence.Outcome;
            begin
               Adash.Configuration.Files.Save (Shell.Chosen, Result);

               if not Adash.Persistence.Succeeded (Result) then
                  return Refused
                    (M.Msg_Config_Unreadable,
                     [1 => M.Named
                             ("path", Adash.Configuration.Files.Path)]);
               end if;

               Say (Produced, M.Msg_Line_Settings_Saved,
                    [1 => M.Named
                            ("path", Adash.Configuration.Files.Path)]);

               return Adash.Execution.Success;
            end;

         when Command_Help =>
            if Given = 1 then
               declare
                  Wanted : Command_Id;
               begin
                  if not Find (Argument (Arguments, 1), Wanted) then
                     return Failed (Adash.Errors.Error_Command_Unavailable,
                                    [1 => M.Named ("name",
                                                   Argument (Arguments, 1))]);
                  end if;

                  Say (Produced, Describe (Wanted).Documentation);
                  return Adash.Execution.Success;
               end;
            end if;

            for Index in 1 .. Count loop
               declare
                  About : constant Metadata := Entry_At (Index);
               begin
                  --  What the command is for, quoted rather than rendered:
                  --  this package has no catalog and must not have one. The
                  --  summary was an empty string here for as long as `help`
                  --  has existed, so the listing was a column of names beside
                  --  a column of nothing.
                  Say (Produced, M.Msg_Line_Command_Entry,
                       [1 => M.Named ("name", M.Value (About.Name))],
                       Quoted => About.Documentation,
                       Fills  => "summary");
               end;
            end loop;

            return Adash.Execution.Success;

         when Command_Version =>
            Say (Produced, M.Msg_Line_Version,
                 [M.Named ("name", Adash.Version.Crate_Name),
                  M.Named ("version", Adash.Version.Number)]);
            return Adash.Execution.Success;

         when Command_Source =>
            declare
               Path   : constant String := Argument (Arguments, 1);
               Status : Adash.Execution.Exit_Status;
               Failed_To_Run : Boolean;
            begin
               if Shell.Scripts = null then
                  --  Nothing here can run one. Refused rather than ignored:
                  --  a `source` that quietly did nothing would look like a
                  --  file that was empty.
                  return Failed
                    (Adash.Errors.Error_Command_Unavailable,
                     [1 => M.Named ("name", M.Value (Describe (Id).Name))]);
               end if;

               Shell.Scripts.Run_Script (Path, Status, Failed_To_Run);

               if Failed_To_Run then
                  --  The runner has already said what was wrong with the file.
                  return (Kind => Adash.Execution.Exit_Internal_Failure,
                          others => <>);
               end if;

               --  The script's own status, so `source failing.adash` is a
               --  failure here too.
               return Status;
            end;

         when Command_Forget =>
            declare
               Wanted    : Integer := 1;
               Forgotten : Natural;
               Failed_To : Boolean;
            begin
               if Shell.History = null then
                  --  Nothing is keeping track, so there is nothing to take
                  --  out. The same answer `history` gives, for the same
                  --  reason: this session has no log, and that is not a
                  --  missing feature.
                  return Failed (Adash.Errors.Error_No_History_Here,
                                 M.No_Arguments);
               end if;

               --  Two ways of saying which entry, told apart by what was
               --  given rather than by a second command: a number is how many
               --  of the most recent, and a line of text is that line wherever
               --  it is -- including in the file, beyond what this session
               --  ever read back.
               if Given >= 1 and then Text_Argument (Arguments, 1) then
                  Shell.History.Forget_Line
                    (Text => Argument (Arguments, 1),
                     Forgotten => Forgotten,
                     Failed => Failed_To);

               else
                  --  A count that is not a positive number is refused rather
                  --  than read as "all of it". `history (0)` listing
                  --  everything costs a screen; `forget (0)` taking everything
                  --  would cost the history, and a command that destroys more
                  --  than it was asked to must not be reachable by a typing
                  --  mistake.
                  if Given >= 1
                    and then (not Whole_Argument (Arguments, 1, Wanted)
                              or else Wanted < 1)
                  then
                     return Failed
                       (Adash.Errors.Error_Command_Wrong_Arguments,
                        [1 => M.Named ("name", M.Value (Describe (Id).Name))]);
                  end if;

                  Shell.History.Forget_Recent
                    (Count => Positive (Wanted),
                     Forgotten => Forgotten,
                     Failed => Failed_To);
               end if;

               if Failed_To then
                  --  The session has forgotten it and the file has not, which
                  --  is the half that matters. Reported rather than counted as
                  --  done: a user told "2 forgotten" would stop looking.
                  return Failed (Adash.Errors.Error_History_Not_Forgotten,
                                 M.No_Arguments);
               end if;

               Say (Produced, M.Msg_Line_Forgotten,
                    [1 => M.Named ("count", Trim (Forgotten))]);

               return Adash.Execution.Success;
            end;

         when Command_History =>
            declare
               Wanted : Integer;
               Held   : Natural;
               First  : Positive;
            begin
               if Shell.History = null then
                  --  Nothing is keeping track. Not the same as an empty
                  --  history, and reporting no lines would say the session had
                  --  typed nothing.
                  return Failed (Adash.Errors.Error_No_History_Here,
                                 M.No_Arguments);
               end if;

               Held := Shell.History.Recorded;

               if Held = 0 then
                  return Adash.Execution.Success;
               end if;

               --  With a count, the last that many. Without one, all of them.
               --  A count larger than the log is not an error: the user asked
               --  for the last twenty and there are nine, and nine is the
               --  answer to that.
               if Given = 1 and then Whole_Argument (Arguments, 1, Wanted)
                 and then Wanted > 0
                 and then Wanted < Held
               then
                  First := Held - Wanted + 1;
               else
                  First := 1;
               end if;

               for Index in First .. Held loop
                  Say (Produced, M.Msg_Line_History_Entry,
                       [M.Named ("number", Trim (Index)),
                        M.Named ("line", Shell.History.Recorded_Line (Index))]);
               end loop;

               return Adash.Execution.Success;
            end;

      end case;
   end Run;

end Adash.Commands.Builtins;
