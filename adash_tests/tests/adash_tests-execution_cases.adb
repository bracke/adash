with Ada.Characters.Latin_1;
with Ada.Command_Line;
with Ada.Directories;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with AUnit.Assertions;

with Adash.Filesystem;

with Hostkit;
with Ada.Streams;
with Ada.Strings.Fixed;
with Hostkit.Fs;
with Hostkit.Descriptors;
with Hostkit.Signals;
with Hostkit.Spawn;

with Adash.Errors;
with Adash.Execution;
with Hostkit.Host;
with Adash.Execution.Commands;
with Adash.Execution.Environment;
with Adash.Execution.Cancellation;
with Adash.Execution.External;
with Adash.Execution.Jobs;
with Adash.Execution.Pipelines;
with Adash.Execution.Redirection;
with Adash.Execution.Signals;
with Adash.Execution.Streams;
with Adash.Platform;

package body Adash_Tests.Execution_Cases is

   use AUnit.Assertions;
   use Ada.Strings.Unbounded;

   use type Adash.Execution.Exit_Kind;
   use type Adash.Errors.Error_Code;
   use type Adash.Errors.Error_Domain;
   use type Adash.Execution.Jobs.Job_State;
   use type Adash.Execution.Jobs.Job_Id;
   use type Adash.Execution.Jobs.Job_Placement;
   use type Hostkit.Signals.Disposition;

   package C renames Adash.Execution.Commands;
   package P renames Adash.Execution.Pipelines;
   package R renames Adash.Execution.Redirection;
   package S renames Adash.Execution.Streams;
   package X renames Adash.Execution.External;

   use type X.Observation;

   function Scratch (Name : String) return String
   is (Ada.Directories.Compose (Ada.Directories.Current_Directory, Name));

   function No_Args return Hostkit.String_Vectors.Vector is
      Empty : Hostkit.String_Vectors.Vector;
   begin
      return Empty;
   end No_Args;

   --  Read a whole file. Used to prove a redirection actually wrote what the
   --  command produced, which nothing else here can show.
   function Slurp (Path : String) return String is
      File   : Ada.Text_IO.File_Type;
      Result : Unbounded_String;
   begin
      Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Path);

      while not Ada.Text_IO.End_Of_File (File) loop
         Append (Result, Ada.Text_IO.Get_Line (File));
         Append (Result, Character'Val (10));
      end loop;

      Ada.Text_IO.Close (File);
      return To_String (Result);
   end Slurp;

   function Contains (Haystack, Needle : String) return Boolean is
   begin
      if Needle'Length = 0 or else Needle'Length > Haystack'Length then
         return Needle'Length = 0;
      end if;

      for Start in Haystack'First .. Haystack'Last - Needle'Length + 1 loop
         if Haystack (Start .. Start + Needle'Length - 1) = Needle then
            return True;
         end if;
      end loop;

      return False;
   end Contains;

   ------------------------------------------------------------------
   --  Exit status
   ------------------------------------------------------------------

   procedure Exit_Status_Model_Is_One_Table
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      use Adash.Execution;
   begin
      Assert (Numeric (Success) = 0, "success is not zero");
      Assert (Succeeded (Success), "success does not report success");

      Assert (Numeric (From_External_Code (7)) = 7,
              "an external status was not carried through");
      Assert (not Succeeded (From_External_Code (7)),
              "a non-zero external status reported success");
      Assert (Succeeded (From_External_Code (0)),
              "a zero external status did not report success");

      --  126 and 127 are the distinction a user acts on: a typo versus a
      --  permissions problem. Collapsing them is the bug this pins.
      Assert (Numeric (From_Start_Failure (Executable_Found => False)) = 127,
              "a missing program is not 127");
      Assert (Numeric (From_Start_Failure (Executable_Found => True)) = 126,
              "a non-executable program is not 126");

      --  128 + the host's number for the signal, on a host that has one.
      --  Windows does not, and hostkit refuses to invent a number rather than
      --  answering with a plausible POSIX one -- so there the honest reduction
      --  is a plain failure, and 127 (not found) is what the arithmetic would
      --  have produced instead.
      if Hostkit.Signals.Number (Hostkit.Signals.Signal_Interrupt) >= 0 then
         Assert (Numeric (From_Signal (Hostkit.Signals.Signal_Interrupt)) = 130,
                 "a program killed by an interrupt is not 130");
      else
         Assert (Numeric (From_Signal (Hostkit.Signals.Signal_Interrupt)) = 1,
                 "a signal this host cannot number did not reduce to a plain "
                 & "failure");
      end if;
      Assert (Numeric ((Kind => Exit_Cancelled, others => <>)) = 130,
              "a cancellation is not 130");

      --  A signal the host named but this crate does not must not become
      --  128 + a number nobody read.
      Assert (Numeric (From_Signal (Hostkit.Signals.Signal_Interrupt, Known => False)) = 1,
              "an unknown terminating signal produced a signal-derived status");
   end Exit_Status_Model_Is_One_Table;

   ------------------------------------------------------------------
   --  Environment
   ------------------------------------------------------------------

   procedure Environment_Is_A_Value_Not_The_Process
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      package Env renames Adash.Execution.Environment;
      Block : Env.Block := Env.Empty;
   begin
      Assert (Env.Length (Block) = 0, "an empty environment is not empty");

      Env.Set (Block, "ZEBRA", "1");
      Env.Set (Block, "ALPHA", "2");
      Env.Set (Block, "MIDDLE", "3");

      Assert (Env.Length (Block) = 3, "three variables did not survive");
      Assert (Env.Value (Block, "ALPHA") = "2", "a value did not round-trip");
      Assert (Env.Contains (Block, "MIDDLE"), "a variable went missing");

      --  Replacing, not appending. Two entries of one name is something no host
      --  resolves the same way.
      Env.Set (Block, "ALPHA", "changed");
      Assert (Env.Length (Block) = 3, "replacing a variable added one instead");
      Assert (Env.Value (Block, "ALPHA") = "changed", "a variable was not replaced");

      Env.Unset (Block, "MIDDLE");
      Assert (not Env.Contains (Block, "MIDDLE"), "a variable survived being unset");
      Assert (Env.Length (Block) = 2, "unset did not remove one");

      --  Deterministic order, whatever order they were set in. A test comparing
      --  two environments depends on it.
      declare
         Rendered : constant Hostkit.String_Vectors.Vector := Env.To_Vector (Block);
      begin
         Assert (To_String (Rendered.Element (1)) = "ALPHA=changed",
                 "the environment did not come out sorted: "
                 & To_String (Rendered.Element (1)));
         Assert (To_String (Rendered.Element (2)) = "ZEBRA=1",
                 "the environment did not come out sorted");
      end;

      --  A variable with no name has no representation a host can parse.
      Env.Set (Block, "", "orphan");
      Assert (Env.Length (Block) = 2, "a nameless variable was accepted");
   end Environment_Is_A_Value_Not_The_Process;

   ------------------------------------------------------------------
   --  Resolution and starting
   ------------------------------------------------------------------

   --  The companion programs, built beside the suite.
   function Companion (Name : String) return String is
      Self : constant String := Ada.Command_Line.Command_Name;
      Dir  : constant String := Ada.Directories.Containing_Directory (Self);
   begin
      if Ada.Directories.Exists (Ada.Directories.Compose (Dir, Name & ".exe")) then
         return Ada.Directories.Compose (Dir, Name & ".exe");
      end if;

      return Ada.Directories.Compose (Dir, Name);
   exception
      when others =>
         return Name;
   end Companion;

   procedure A_Missing_Command_Is_Reported_As_Missing
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Item    : C.Invocation := C.Make ("adash-no-such-command-anywhere", No_Args);
      Process : Hostkit.Spawn.Process_Handle;
      Error   : Adash.Errors.Error_Info;
   begin
      Assert (not X.Start (Item, Process, Error),
              "a command that does not exist reported that it started");

      --  The distinction the whole report-pipe in Hostkit.Spawn exists for. A
      --  shell that could not tell this from "it ran and returned 127" could
      --  not honestly say "command not found".
      Assert (Error.Code = Adash.Errors.Error_Command_Not_Found,
              "a missing command was not reported as missing: "
              & Adash.Errors.Error_Code'Image (Error.Code));
      Assert (Adash.Errors.Domain (Error.Code) = Adash.Errors.Domain_Execution,
              "a command failure was not attributed to execution");

      --  Resolve agrees, and says it was a name rather than a path.
      declare
         Found : constant X.Resolution := X.Resolve (Item);
      begin
         Assert (not Found.Found, "a missing command resolved anyway");
         Assert (not Found.Was_Path, "a bare name was treated as a path");
      end;
   end A_Missing_Command_Is_Reported_As_Missing;

   procedure A_Command_Runs_And_Reports_Its_Status
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Item    : C.Invocation := C.Make (Companion ("adash_test_emit"), No_Args);
      Process : Hostkit.Spawn.Process_Handle;
      Error   : Adash.Errors.Error_Info;
      Status  : Adash.Execution.Exit_Status;
   begin
      C.Append_Argument (Item, "--exit=7");

      Assert (X.Start (Item, Process, Error),
              "a real command did not start: "
              & Adash.Errors.Error_Code'Image (Error.Code));
      --  Four answers rather than two: a suspended program has neither ended
      --  nor is it running, and this is the one that says it ended.
      Assert (X.Wait (Process, True, Status) = X.Observed_Ended,
              "waiting for the command failed");

      Assert (Status.Kind = Adash.Execution.Exit_External,
              "a command that exited was not reported as having exited");
      Assert (Adash.Execution.Numeric (Status) = 7,
              "the command's exit status was lost; got"
              & Natural'Image (Adash.Execution.Numeric (Status)));
      Assert (not Adash.Execution.Succeeded (Status),
              "a non-zero exit reported success");
   end A_Command_Runs_And_Reports_Its_Status;

   procedure Output_Goes_Where_It_Is_Redirected
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Path    : constant String := Scratch ("adash-redirect-out.tmp");
      Item    : C.Invocation := C.Make (Companion ("adash_test_emit"), No_Args);
      Plan    : R.Plan := R.Nothing;
      Process : Hostkit.Spawn.Process_Handle;
      Error   : Adash.Errors.Error_Info;
      Status  : Adash.Execution.Exit_Status;
   begin
      C.Append_Argument (Item, "redirected-line");

      Assert (R.Add (Plan,
                     (Role => S.Role_Output,
                      Kind => R.Redirect_To_File,
                      Path => To_Unbounded_String (Path)),
                     Error),
              "a redirection was rejected");
      Assert (R.Apply (Plan, Item, Error),
              "a redirection could not be applied: "
              & Adash.Errors.Error_Code'Image (Error.Code));

      Assert (X.Start (Item, Process, Error), "the redirected command did not start");
      Assert (X.Wait (Process, True, Status) = X.Observed_Ended,
              "waiting failed");
      Assert (Adash.Execution.Succeeded (Status),
              "the redirected command failed:"
              & Natural'Image (Adash.Execution.Numeric (Status)));

      --  Reading the file back is the only thing that proves the descriptor
      --  reached the child as its standard output rather than being opened and
      --  dropped.
      Assert (Contains (Slurp (Path), "redirected-line"),
              "the command's output did not reach the file it was redirected to");

      Ada.Directories.Delete_File (Path);
   end Output_Goes_Where_It_Is_Redirected;

   procedure Two_Redirections_On_One_Stream_Are_Refused
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Plan  : R.Plan := R.Nothing;
      Error : Adash.Errors.Error_Info;
   begin
      Assert (R.Add (Plan,
                     (Role => S.Role_Output,
                      Kind => R.Redirect_To_File,
                      Path => To_Unbounded_String (Scratch ("first.tmp"))),
                     Error),
              "the first redirection was rejected");

      --  Refused rather than resolved. Picking one silently does not write the
      --  file that lost, and the user finds that out later, from its absence.
      Assert (not R.Add (Plan,
                         (Role => S.Role_Output,
                          Kind => R.Redirect_To_File,
                          Path => To_Unbounded_String (Scratch ("second.tmp"))),
                         Error),
              "two redirections on one stream were accepted");
      Assert (Error.Code = Adash.Errors.Error_Redirection_Conflict,
              "a redirection conflict was reported as something else");

      --  A different stream is not a conflict.
      Assert (R.Add (Plan,
                     (Role => S.Role_Error,
                      Kind => R.Redirect_To_File,
                      Path => To_Unbounded_String (Scratch ("err.tmp"))),
                     Error),
              "a redirection on a different stream was refused");
      Assert (R.Length (Plan) = 2, "the plan did not hold both redirections");

      --  Nothing was opened: planning is the phase where a mistake is free.
      Assert (not Ada.Directories.Exists (Scratch ("first.tmp")),
              "planning a redirection opened its file");
   end Two_Redirections_On_One_Stream_Are_Refused;

   procedure A_Pipeline_Carries_Output_Between_Stages
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Path   : constant String := Scratch ("adash-pipeline-out.tmp");
      Stage1 : C.Invocation := C.Make (Companion ("adash_test_emit"), No_Args);
      Stage2 : C.Invocation := C.Make (Companion ("adash_test_upcase"), No_Args);
      Plan   : P.Plan := P.Empty_Plan;
      Out_Plan : R.Plan := R.Nothing;
      Result : P.Outcome;
      Error  : Adash.Errors.Error_Info;
   begin
      C.Append_Argument (Stage1, "hello from stage one");

      --  The last stage's output goes to a file, so the test can read what
      --  came out the far end rather than trusting that it ran.
      Assert (R.Add (Out_Plan,
                     (Role => S.Role_Output,
                      Kind => R.Redirect_To_File,
                      Path => To_Unbounded_String (Path)),
                     Error),
              "the pipeline output redirection was rejected");
      Assert (R.Apply (Out_Plan, Stage2, Error), "could not redirect the last stage");

      P.Add_Stage (Plan, Stage1);
      P.Add_Stage (Plan, Stage2);
      Assert (P.Length (Plan) = 2, "the plan did not hold two stages");

      Assert (P.Run (Plan, Adash.Execution.Cancellation.Never'Access, Result, Error),
              "the pipeline did not run: "
              & Adash.Errors.Error_Code'Image (Error.Code));

      --  The second stage reads to end-of-file, so this returning at all proves
      --  the parent closed its copy of the pipe's write end. If it had not,
      --  this test would hang rather than fail -- which is exactly how the bug
      --  presents in a real shell.
      Assert (Natural (Result.Stages.Length) = 2,
              "the pipeline did not report a status per stage");
      Assert (Adash.Execution.Succeeded (Result.Status),
              "the pipeline reported failure");

      Assert (Contains (Slurp (Path), "HELLO FROM STAGE ONE"),
              "stage one's output did not reach stage two; the file holds: "
              & Slurp (Path));

      Ada.Directories.Delete_File (Path);
   end A_Pipeline_Carries_Output_Between_Stages;

   procedure A_Pipelines_Status_Is_Its_Last_Stage
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Stage1 : C.Invocation := C.Make (Companion ("adash_test_emit"), No_Args);
      Stage2 : C.Invocation := C.Make (Companion ("adash_test_emit"), No_Args);
      Plan   : P.Plan := P.Empty_Plan;
      Result : P.Outcome;
      Error  : Adash.Errors.Error_Info;
   begin
      --  The first stage fails, the last succeeds. The convention every script
      --  depends on is that the pipeline's status is the last stage's.
      C.Append_Argument (Stage1, "--exit=3");
      C.Append_Argument (Stage2, "done");

      P.Add_Stage (Plan, Stage1);
      P.Add_Stage (Plan, Stage2);

      Assert (P.Run (Plan, Adash.Execution.Cancellation.Never'Access, Result, Error), "the pipeline did not run");
      Assert (Adash.Execution.Succeeded (Result.Status),
              "the pipeline took its status from a stage other than the last");

      --  And the earlier stage's status is still available, so a shell can say
      --  which stage actually failed.
      Assert (Adash.Execution.Numeric (Result.Stages.First_Element) = 3,
              "the failing stage's own status was lost");
   end A_Pipelines_Status_Is_Its_Last_Stage;

   procedure A_Pipeline_Shares_One_Process_Group
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Stage1 : C.Invocation := C.Make (Companion ("adash_test_emit"), No_Args);
      Stage2 : constant C.Invocation :=
        C.Make (Companion ("adash_test_upcase"), No_Args);
      Plan   : P.Plan := P.Empty_Plan;
      Result : P.Outcome;
      Error  : Adash.Errors.Error_Info;
   begin
      C.Append_Argument (Stage1, "grouped");

      P.Add_Stage (Plan, Stage1);
      P.Add_Stage (Plan, Stage2);
      Assert (P.Run (Plan, Adash.Execution.Cancellation.Never'Access, Result, Error), "the pipeline did not run");

      if Adash.Platform.Is_Available (Adash.Platform.Capability_Job_Control) then
         --  One group for the whole pipeline is what makes a single Ctrl-C
         --  reach every stage instead of only the first.
         Assert (Result.Group > 0,
                 "a pipeline on a host with job control reported no process group");
      else
         Assert (Result.Group = -1,
                 "a host without job control reported a process group anyway");
      end if;
   end A_Pipeline_Shares_One_Process_Group;

   ------------------------------------------------------------------
   --  Signal policy
   ------------------------------------------------------------------

   procedure The_Shell_Refuses_The_Signals_That_Would_Kill_It
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      package Sig renames Adash.Execution.Signals;
      Outcome : Adash.Errors.Error_Info;
   begin
      Outcome := Sig.Install;
      Assert (not Adash.Errors.Is_Failure (Outcome),
              "installing the shell signal policy failed: "
              & Adash.Errors.Error_Code'Image (Outcome.Code));

      --  SIGPIPE above all. Without it the shell -- not its child -- dies the
      --  first time a user writes `something | head -1`.
      Assert (Sig.Is_Refused_By_Shell (Hostkit.Signals.Signal_Pipe),
              "the shell does not refuse SIGPIPE");
      Assert (Sig.Is_Refused_By_Shell (Hostkit.Signals.Signal_Interrupt),
              "the shell does not refuse SIGINT");
      Assert (Sig.Is_Refused_By_Shell (Hostkit.Signals.Signal_Terminal_Stop),
              "the shell does not refuse SIGTSTP");

      --  SIGTTOU is the one whose absence looks like something else entirely:
      --  reclaiming the terminal after a job would stop the shell.
      Assert (Sig.Is_Refused_By_Shell (Hostkit.Signals.Signal_Background_Write),
              "the shell does not refuse SIGTTOU");

      --  And it does not refuse what it has no business refusing.
      Assert (not Sig.Is_Refused_By_Shell (Hostkit.Signals.Signal_Terminate),
              "the shell refuses SIGTERM, which should still end it");
      Assert (not Sig.Is_Refused_By_Shell (Hostkit.Signals.Signal_Kill),
              "the shell claims to refuse SIGKILL, which cannot be refused");

      if Adash.Platform.Is_Available (Adash.Platform.Capability_Signals) then
         Assert (Sig.Is_Installed,
                 "the policy reported itself not installed on a host with signals");

         --  Read back from the host, not from this package's own flag: a policy
         --  that only remembers having been set is not a policy.
         declare
            Current : Hostkit.Signals.Disposition;
         begin
            Assert (Hostkit.Signals.Current_Disposition
                      (Hostkit.Signals.Signal_Pipe, Current),
                    "could not read back the SIGPIPE disposition");
            Assert (Current = Hostkit.Signals.Disposition_Ignore,
                    "SIGPIPE is not actually ignored after Install");
         end;
      else
         --  Nothing to refuse. Install still succeeds, or every startup on such
         --  a host would look broken.
         Assert (not Sig.Is_Installed,
                 "a host without signals reported the policy installed");
      end if;

      Outcome := Sig.Restore;
      Assert (not Adash.Errors.Is_Failure (Outcome), "restoring the defaults failed");
      Assert (not Sig.Is_Installed, "Restore left the policy installed");

      --  Put it back: the rest of the suite runs pipelines, and a suite that
      --  left SIGPIPE at its default would be one truncated read from dying.
      Outcome := Sig.Install;
      Assert (not Adash.Errors.Is_Failure (Outcome), "reinstalling the policy failed");
   end The_Shell_Refuses_The_Signals_That_Would_Kill_It;

   ------------------------------------------------------------------
   --  Cancellation
   ------------------------------------------------------------------

   procedure A_Cancellation_Request_Is_Sticky
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Token : Adash.Execution.Cancellation.Token;
   begin
      Assert (not Token.Is_Requested, "a fresh token was already requested");

      Token.Request;
      Assert (Token.Is_Requested, "a request did not take");

      --  Sticky: a second observer must see it too. A flag cleared by whoever
      --  reads it first loses the request, which is exactly the situation a
      --  pipeline with several stages is in.
      Assert (Token.Is_Requested, "the request was consumed by reading it");

      Token.Request;
      Assert (Token.Is_Requested, "requesting twice cleared the request");

      Token.Reset;
      Assert (not Token.Is_Requested, "Reset did not clear the request");
   end A_Cancellation_Request_Is_Sticky;

   procedure A_Cancelled_Pipeline_Stops_And_Says_So
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  upcase reads to end-of-file. Given a pipe whose write end the test
      --  keeps open, it blocks for ever -- so the only thing that can end this
      --  pipeline is the cancellation, which is what makes the test meaningful.
      Stage  : C.Invocation := C.Make (Companion ("adash_test_upcase"), No_Args);
      Plan   : P.Plan := P.Empty_Plan;
      Live   : P.Running;
      Final  : P.Outcome;
      Error  : Adash.Errors.Error_Info;
      Token  : aliased Adash.Execution.Cancellation.Token;
      Ends   : Hostkit.Descriptors.Pipe_Ends;
   begin
      if not Adash.Platform.Is_Available (Adash.Platform.Capability_Signals) then
         --  Cancellation is delivered as a signal. A host without them cannot
         --  do this, and says so rather than hanging.
         return;
      end if;

      Assert (Hostkit.Descriptors.Create_Pipe (Ends), "could not create a pipe");
      Stage.Input := S.Borrowed (Ends.Read_End);

      P.Add_Stage (Plan, Stage);
      Assert (P.Start (Plan, Live, Error), "the pipeline did not start");

      --  The child is now blocked on a read that will never complete.
      Token.Request;
      Assert (P.Wait (Live, Token'Access, Final),
              "a cancelled pipeline did not finish");

      --  Reported as cancelled, not as the signal that carried it out. A script
      --  branching on the result has to see that it was stopped rather than
      --  that the program failed on its own.
      Assert (Final.Status.Kind = Adash.Execution.Exit_Cancelled,
              "a cancelled pipeline was not reported as cancelled: "
              & Adash.Execution.Exit_Kind'Image (Final.Status.Kind));
      Assert (Adash.Execution.Numeric (Final.Status) = 130,
              "a cancelled pipeline did not reduce to 130");
      Assert (not Adash.Execution.Succeeded (Final.Status),
              "a cancelled pipeline reported success");

      Hostkit.Descriptors.Close (Ends.Read_End);
      Hostkit.Descriptors.Close (Ends.Write_End);
   end A_Cancelled_Pipeline_Stops_And_Says_So;

   ------------------------------------------------------------------
   --  Jobs
   ------------------------------------------------------------------

   procedure A_Job_Is_Tracked_From_Start_To_Reaping
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      package J renames Adash.Execution.Jobs;
      Stage : C.Invocation := C.Make (Companion ("adash_test_emit"), No_Args);
      Plan  : P.Plan := P.Empty_Plan;
      Live  : P.Running;
      Error : Adash.Errors.Error_Info;
      Table : J.Table;
      Id    : J.Job_Id;
   begin
      C.Append_Argument (Stage, "--exit=4");
      P.Add_Stage (Plan, Stage);
      Assert (P.Start (Plan, Live, Error), "the job's pipeline did not start");

      Id := J.Add (Table, Live, "adash_test_emit --exit=4", J.Placement_Background);
      Assert (J.Length (Table) = 1, "the job was not added");
      Assert (J.Contains (Table, Id), "the job number does not name the job");
      Assert (J.Description (Table, Id) = "adash_test_emit --exit=4",
              "the job did not keep what the user typed");
      Assert (J.Placement (Table, Id) = J.Placement_Background,
              "the job did not keep its placement");

      --  Wait for it, then let the table observe the ending.
      Assert (J.Wait (Table, Id, Adash.Execution.Cancellation.Never'Access, Error),
              "waiting for the job failed");
      Assert (J.State (Table, Id) = J.Job_Completed,
              "a finished job was not reported as completed");
      Assert (Adash.Execution.Numeric (J.Result (Table, Id).Status) = 4,
              "the job lost its exit status");

      --  A state change is unreported until somebody collects it, and is
      --  collected exactly once -- a prompt must not announce the same job
      --  twice.
      declare
         Changed : constant J.Id_Vectors.Vector := J.Take_Unreported (Table);
      begin
         Assert (Natural (Changed.Length) = 1,
                 "the finished job was not offered for reporting");
         Assert (Changed.First_Element = Id, "the wrong job was reported");
      end;

      Assert (Natural (J.Take_Unreported (Table).Length) = 0,
              "the same change was offered for reporting twice");

      --  Kept until reported, then reapable. A job that finished must stay
      --  namable long enough for the shell to say so.
      J.Reap (Table);
      Assert (J.Length (Table) = 0, "a reported, completed job was not reaped");
      Assert (not J.Contains (Table, Id), "a reaped job is still present");
   end A_Job_Is_Tracked_From_Start_To_Reaping;

   procedure Job_Numbers_Are_Not_Reused
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      package J renames Adash.Execution.Jobs;
      Table  : J.Table;
      First  : J.Job_Id;
      Second : J.Job_Id;

      function Started return P.Running is
         Stage : C.Invocation := C.Make (Companion ("adash_test_emit"), No_Args);
         Plan  : P.Plan := P.Empty_Plan;
         Live  : P.Running;
         Error : Adash.Errors.Error_Info;
      begin
         C.Append_Argument (Stage, "x");
         P.Add_Stage (Plan, Stage);
         Assert (P.Start (Plan, Live, Error), "a job's pipeline did not start");
         return Live;
      end Started;

   begin
      First := J.Add (Table, Started, "first", J.Placement_Background);

      declare
         Error : Adash.Errors.Error_Info;
      begin
         Assert (J.Wait (Table, First, Adash.Execution.Cancellation.Never'Access, Error),
                 "waiting for the first job failed");
      end;

      declare
         Ignored : constant J.Id_Vectors.Vector := J.Take_Unreported (Table);
         pragma Unreferenced (Ignored);
      begin
         J.Reap (Table);
      end;

      Assert (J.Length (Table) = 0, "the first job was not reaped");

      Second := J.Add (Table, Started, "second", J.Placement_Background);

      --  The point: a user who backgrounds a job, waits, and then names it by
      --  number must not reach a different job that has taken the number since.
      Assert (Second /= First,
              "a job number was reused after the first job was reaped");

      declare
         Error : Adash.Errors.Error_Info;
      begin
         Assert (J.Wait (Table, Second, Adash.Execution.Cancellation.Never'Access, Error),
                 "waiting for the second job failed");
      end;
   end Job_Numbers_Are_Not_Reused;

   procedure An_Unknown_Job_Number_Is_Refused
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      package J renames Adash.Execution.Jobs;
      Table : J.Table;
      Error : Adash.Errors.Error_Info;
   begin
      --  A stale job number is something a user types, not a defect, so it is a
      --  structured failure rather than an exception.
      Assert (not J.Wait (Table, 42, Adash.Execution.Cancellation.Never'Access, Error),
              "waiting for a job that does not exist reported success");
      Assert (Error.Code = Adash.Errors.Error_Job_Unknown,
              "an unknown job was reported as something else");
      Assert (not J.Terminate_Job (Table, 42, Error),
              "signalling a job that does not exist reported success");
      Assert (Error.Code = Adash.Errors.Error_Job_Unknown,
              "an unknown job was reported as something else");
      Assert (not J.Contains (Table, 42), "an empty table contains a job");
   end An_Unknown_Job_Number_Is_Refused;

   ----------
   -- Name --
   ----------

   procedure An_Interrupt_Is_Recorded_Not_Discarded
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Taken : constant Adash.Errors.Error_Info :=
        Adash.Execution.Signals.Install;
   begin
      if Adash.Errors.Is_Failure (Taken)
        or else not Hostkit.Signals.Is_Supported
                      (Hostkit.Signals.Signal_Interrupt)
      then
         --  A host that will not give the shell its dispositions. Nothing to
         --  test, and saying so beats asserting something that cannot hold.
         return;
      end if;

      Adash.Execution.Signals.Acknowledge_Interrupt;
      Assert (not Adash.Execution.Signals.Interrupt_Pending,
              "an interrupt was outstanding before one was sent");

      --  Safe to send to ourselves precisely because the shell records rather
      --  than dies: if the disposition had not taken, this test would kill the
      --  suite -- which is a blunt way to fail, and still a failure rather
      --  than a pass.
      Assert (Hostkit.Signals.Send_To_Process
                (Hostkit.Host.Own_Process_Id,
                 Hostkit.Signals.Signal_Interrupt),
              "the interrupt could not be sent to this process");

      Assert (Adash.Execution.Signals.Interrupt_Pending,
              "an interrupt was sent and not recorded; Ctrl-C would be lost");

      --  It stays outstanding until acknowledged. A program asks between
      --  instructions and may ask more than once, so an arrival consumed by
      --  the first ask would let it carry on.
      Assert (Adash.Execution.Signals.Interrupt_Pending,
              "asking twice consumed the interrupt");

      Adash.Execution.Signals.Acknowledge_Interrupt;
      Assert (not Adash.Execution.Signals.Interrupt_Pending,
              "acknowledging did not clear the interrupt");
   end An_Interrupt_Is_Recorded_Not_Discarded;

   ------------------------------------------------------------------

   --  The other host's half of the same question, asserted where the first one
   --  cannot run at all. On Windows hostkit reports every signal unsupported --
   --  deliberately, because SetConsoleCtrlHandler is a different mechanism and
   --  no process there asks another to stop in a way it may decline -- and what
   --  matters then is that the shell does not believe it armed anything.
   procedure An_Interrupt_Is_Declined_Where_The_Host_Has_None
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Taken : constant Adash.Errors.Error_Info :=
        Adash.Execution.Signals.Install;
   begin
      if Hostkit.Signals.Is_Supported (Hostkit.Signals.Signal_Interrupt) then
         --  A host that has them. The test above is the one that applies, and
         --  sending an interrupt to this process to prove the negative here
         --  would end the suite.
         return;
      end if;

      --  Installing is not a failure. There is nothing to install and nothing
      --  went wrong, and a start-up that refused to run on a host without
      --  signals would be a shell that does not run on Windows at all.
      Assert (not Adash.Errors.Is_Failure (Taken),
              "installing dispositions failed on a host that has none");

      --  But it is not in force either, and that is the distinction the flag
      --  exists for: "arranged" and "not needed here" must not read alike, or
      --  a caller will wait for a Ctrl-C that can never arrive.
      Assert (not Adash.Execution.Signals.Is_Installed,
              "the shell believed it had armed dispositions this host has not");

      Assert (not Adash.Platform.Is_Available (Adash.Platform.Capability_Signals),
              "the platform claimed signals on a host where hostkit has none");

      --  Nothing is ever pending, and sending refuses rather than reporting a
      --  success nobody can act on.
      Assert (not Adash.Execution.Signals.Interrupt_Pending,
              "an interrupt was pending on a host that cannot deliver one");

      Assert (not Hostkit.Signals.Send_To_Process
                    (Hostkit.Host.Own_Process_Id,
                     Hostkit.Signals.Signal_Interrupt),
              "sending a signal reported success on a host without signals");

      Assert (not Adash.Execution.Signals.Interrupt_Pending,
              "a refused send left an interrupt pending");
   end An_Interrupt_Is_Declined_Where_The_Host_Has_None;

   ------------------------------------------------------------------

   procedure The_Shell_Can_Read_Its_Own_Input
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      package S renames Adash.Execution.Streams;
   begin
      --  One buffer over standard input, so a frontend that reads it and a
      --  program that reads it are reading the same stream. Put_Back and
      --  Take_Held are how the two hand it over; without them an interactive
      --  editor holding a user's typed-ahead answer would leave a program
      --  reading nothing.
      S.Put_Back ("first" & Ada.Characters.Latin_1.LF
                  & "second" & Ada.Characters.Latin_1.LF);

      declare
         Ended : Boolean;
         Line  : constant String := S.Read_Line (Ended);
      begin
         Assert (Line = "first" and then not Ended,
                 "the first line did not come back: " & Line);
      end;

      --  What is left is still there for the next reader, whoever that is.
      Assert (S.Take_Held = "second" & Ada.Characters.Latin_1.LF,
              "the rest of the input was not held for the next reader");

      --  A terminator that came from another host is still a terminator, and
      --  a last line without one is still a line.
      S.Put_Back ("carriage" & Ada.Characters.Latin_1.CR
                  & Ada.Characters.Latin_1.LF & "last");

      declare
         Ended : Boolean;
         Line  : constant String := S.Read_Line (Ended);
      begin
         Assert (Line = "carriage" and then not Ended,
                 "a CRLF terminator was not removed: " & Line);
      end;

      --  What a last line without a terminator does is not asked here: knowing
      --  it is the last one means reading the input to its end, and this test
      --  runs with a terminal on the other side that will not end. A
      --  conformance case pipes input that stops without a newline and asserts
      --  the line survives.
      Assert (S.Take_Held = "last",
              "an unterminated remainder was not left for the next reader");
   end The_Shell_Can_Read_Its_Own_Input;

   overriding function Name (T : Case_Type) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Adash.Execution");
   end Name;

   --------------------
   -- Register_Tests --
   --------------------

   --  Input that never ends a line arrives in pieces rather than unbounded.
   --
   --  A shell holds what it reads until it finds a terminator, so a stream
   --  with none -- a program producing bytes, a file written without a final
   --  newline and rather too much before it -- would grow that buffer until
   --  the host ended the session.
   --
   --  Pieces rather than a refusal, and the difference from a file is the
   --  point: a file can be asked about again, and input that has been read and
   --  dropped is gone. So what has accumulated is handed over and reading goes
   --  on, which bounds what is held and loses nothing.
   --
   --  Standard input is pointed at a file for the length of this case and put
   --  back afterwards, because that is the only stream Read_Line reads and the
   --  suite is still using it.
   procedure A_Line_Longer_Than_The_Limit_Arrives_In_Pieces
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure A_Line_Longer_Than_The_Limit_Arrives_In_Pieces
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Limit : constant := 64 * 1_024;

      Path : constant String :=
        Ada.Directories.Compose
          (Ada.Directories.Current_Directory, "adash-test-no-newline");

      Block : constant String (1 .. Limit) := [others => 'a'];
      Tail  : constant String (1 .. 1_000) := [others => 'b'];

      Written : Adash.Filesystem.Written;

      Ours    : constant Hostkit.Descriptors.Descriptor :=
        Hostkit.Descriptors.Duplicate (Hostkit.Descriptors.Standard_Input);
      Feeding : Hostkit.Descriptors.Descriptor;

      --  Two of them, because a piece that is not the end of the input and a
      --  piece that is are different answers and both are asserted.
      After_First  : Boolean;
      After_Second : Boolean;

      use type Adash.Filesystem.Written;
   begin
      --  One piece and a little more, with no line feed anywhere in it.
      Adash.Filesystem.Write (Path, Block & Tail, Written);
      Assert (Written = Adash.Filesystem.Write_Ok,
              "the input file was not written");

      Assert (Hostkit.Descriptors.Open_File
                (Path, Hostkit.Descriptors.Open_Read, Feeding),
              "the input file would not open");

      Assert (Hostkit.Descriptors.Assign
                (Feeding, Hostkit.Descriptors.Stream_Input),
              "standard input could not be pointed at the file");

      declare
         First  : constant String :=
           Adash.Execution.Streams.Read_Line (After_First, Limit => Limit);
         Second : constant String :=
           Adash.Execution.Streams.Read_Line (After_Second, Limit => Limit);
      begin
         --  Put back before anything is asserted: a failure here would
         --  otherwise leave the rest of the suite reading a file.
         declare
            Restored : constant Boolean :=
              Hostkit.Descriptors.Assign
                (Ours, Hostkit.Descriptors.Stream_Input);
         begin
            Assert (Restored, "standard input could not be put back");
         end;

         Assert (First'Length = Limit,
                 "the first piece was not the limit:"
                 & Natural'Image (First'Length));
         Assert (Second'Length = Tail'Length,
                 "the rest did not follow the first piece:"
                 & Natural'Image (Second'Length));

         Assert (not After_First and then not After_Second,
                 "a piece was reported as the end of the input");
      end;

      Hostkit.Descriptors.Close (Feeding);
      Ada.Directories.Delete_File (Path);
   end A_Line_Longer_Than_The_Limit_Arrives_In_Pieces;

   --  What a shell's error stream holds after it stops a child mid-write.
   --
   --  A record rather than an assertion. One host puts a blank line ahead of
   --  the shell's own diagnostic there and nobody has identified what writes
   --  it: the shell emits the diagnostic -- that much is now known -- and
   --  something else reaches the stream first. A case cannot assert what
   --  differs between hosts, so this prints the bytes and lets the run say.
   --
   --  It said something else first, for a while: the child exited 1 with
   --  nothing on either stream on Windows, and five runs ruled out one thing
   --  at a time -- a shell running a shell, a child filling a pipe, pipes
   --  rather than files, the third stream left unset, paths written into the
   --  script as literals. What was left was the difference between this test
   --  spawning the shell and the conformance runner spawning it, and the
   --  difference was one line: the runner marks the ends it hands over as
   --  inheritable and this did not. The runner's comment describes the
   --  symptom exactly, having been written by somebody who had just spent a
   --  day on it.
   --
   --  The arrangement is the one that shows it: a shell reading a script that
   --  captures a second shell past `read.limit`, so the capture is refused and
   --  the child is stopped by the closing pipe. Its error stream is a pipe
   --  this test reads, which is the only way to get the bytes rather than a
   --  terminal's idea of them.
   procedure What_A_Stopped_Child_Leaves_On_A_Shells_Error_Stream
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure What_A_Stopped_Child_Leaves_On_A_Shells_Error_Stream
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      --  Three levels up and back down: this binary is in the test crate's
      --  bin, and the shell is in the bin beside the crate. In full, because a
      --  relative command name runs out of directories to climb.
      Shell : constant String :=
        Ada.Directories.Compose
          (Ada.Directories.Containing_Directory
             (Ada.Directories.Containing_Directory
                (Ada.Directories.Containing_Directory
                   (Ada.Directories.Full_Name
                      (Ada.Command_Line.Command_Name)))),
           "bin");

      Binary : constant String :=
        Ada.Directories.Compose
          (Shell, "adash" & Hostkit.Fs.Executable_Suffix);

      Fixture : constant String :=
        "../conformance/fixtures/says-too-much.adash";

      Script : constant String :=
        Ada.Directories.Compose
          (Ada.Directories.Current_Directory, "adash-test-refusal.adash");

      Told : Hostkit.String_Vectors.Vector;

      Options : Hostkit.Spawn.Options;
      Child   : Hostkit.Spawn.Process_Handle;
      Result  : Hostkit.Spawn.Status;

      Ends : Hostkit.Descriptors.Pipe_Ends;
      Outs : Hostkit.Descriptors.Pipe_Ends;

      Said : Ada.Strings.Unbounded.Unbounded_String;
      Wrote : Ada.Strings.Unbounded.Unbounded_String;

      Written : Adash.Filesystem.Written;

      use type Adash.Filesystem.Written;
      use type Hostkit.Spawn.Spawn_Outcome;
      use type Hostkit.Descriptors.Transfer_Outcome;
   begin
      if not Ada.Directories.Exists (Binary) then
         --  Run from somewhere the shell was not built into. Nothing to say.
         return;
      end if;

      --  The paths arrive as arguments rather than inside the text.
      --
      --  A Windows path is written with backslashes, and this script carried
      --  two of them in string literals. The same arrangement written as a
      --  fixture that reads its arguments works on that host, and this one
      --  exited 1 with nothing on either stream -- so what is being ruled in
      --  or out is whether a path in a literal is what breaks it.
      Adash.Filesystem.Write
        (Script,
         "settings (""read.limit"", ""1"");" & Ada.Characters.Latin_1.LF
         & "put_line (""["" & Output_Of (Argument (1), Argument (2)) & ""]"");"
         & Ada.Characters.Latin_1.LF
         & "quit (0);" & Ada.Characters.Latin_1.LF,
         Written);

      Assert (Written = Adash.Filesystem.Write_Ok,
              "the probe script was not written");

      Assert (Hostkit.Descriptors.Create_Pipe (Ends),
              "no pipe for the shell's error stream");
      Assert (Hostkit.Descriptors.Create_Pipe (Outs),
              "no pipe for the shell's output");

      --  The ends the child is given have to be marked as travelling.
      --
      --  This is what was wrong with the probe rather than with the shell:
      --  five runs narrowed a silent exit 1 on Windows to "the difference
      --  between how this test spawns the shell and how the conformance
      --  runner does", and the difference was this line, which the runner has
      --  and this did not. Its comment describes the symptom exactly -- a
      --  child handed an invalid handle for its standard streams cannot read
      --  its script, cannot write its answer, and exits 1 having said
      --  nothing. On POSIX a descriptor travels unless it is marked not to,
      --  which is why the probe worked there and only there.
      Assert (Hostkit.Descriptors.Set_Inheritable (Ends.Write_End, True)
              and then Hostkit.Descriptors.Set_Inheritable
                         (Outs.Write_End, True),
              "the child's streams would not travel to it");

      Told.Append (Ada.Strings.Unbounded.To_Unbounded_String (Script));
      Told.Append (Ada.Strings.Unbounded.To_Unbounded_String (Binary));
      Told.Append (Ada.Strings.Unbounded.To_Unbounded_String (Fixture));

      Options.Error_Output := Ends.Write_End;

      --  Its output as well as its complaints, because an empty error stream
      --  says nothing about which of the two things happened: a shell that
      --  wrote its diagnostic somewhere else, or one that never got that far.
      Options.Output := Outs.Write_End;

      --  And an input, which is the third stream and was the one left out.
      --
      --  On Windows the child exited 1 with nothing on either stream -- not
      --  even the line it prints before anything can go wrong -- while the
      --  same child on the other two hosts said everything. Two of three
      --  streams given and the third left to whatever a spawn does with it is
      --  the difference this rules in or out.
      declare
         Nothing : Hostkit.Descriptors.Descriptor;
      begin
         if Hostkit.Fs.Null_Device /= ""
           and then Hostkit.Descriptors.Open_File
                      (Hostkit.Fs.Null_Device,
                       Hostkit.Descriptors.Open_Read, Nothing)
           and then Hostkit.Descriptors.Set_Inheritable (Nothing, True)
         then
            Options.Input := Nothing;
         end if;
      end;

      Assert (Hostkit.Spawn.Start (Binary, Told, Options, Child)
              = Hostkit.Spawn.Spawn_Ok,
              "the shell would not start on the probe script");

      --  These ends of them, so that reading ends when the shell does.
      Hostkit.Descriptors.Close (Ends.Write_End);
      Hostkit.Descriptors.Close (Outs.Write_End);

      loop
         declare
            Chunk : Ada.Streams.Stream_Element_Array (1 .. 4_096);
            Last  : Ada.Streams.Stream_Element_Offset;
         begin
            exit when Hostkit.Descriptors.Read (Ends.Read_End, Chunk, Last)
                      /= Hostkit.Descriptors.Transfer_Ok;

            for Index in Chunk'First .. Last loop
               Ada.Strings.Unbounded.Append
                 (Said, Character'Val (Natural (Chunk (Index))));
            end loop;
         end;
      end loop;

      Hostkit.Descriptors.Close (Ends.Read_End);

      loop
         declare
            Chunk : Ada.Streams.Stream_Element_Array (1 .. 4_096);
            Last  : Ada.Streams.Stream_Element_Offset;
         begin
            exit when Hostkit.Descriptors.Read (Outs.Read_End, Chunk, Last)
                      /= Hostkit.Descriptors.Transfer_Ok;

            for Index in Chunk'First .. Last loop
               Ada.Strings.Unbounded.Append
                 (Wrote, Character'Val (Natural (Chunk (Index))));
            end loop;
         end;
      end loop;

      Hostkit.Descriptors.Close (Outs.Read_End);

      declare
         Ended : constant Boolean :=
           Hostkit.Spawn.Wait (Child, Hostkit.Spawn.Wait_Block, Result);
      begin
         Ada.Text_IO.Put_Line
           ("stopped-child-probe: ended=" & Boolean'Image (Ended)
            & " state=" & Hostkit.Spawn.Wait_State'Image (Result.State)
            & " code=" & Integer'Image (Result.Exit_Code));
      end;

      --  Byte by byte, because what is being looked for is a byte nobody has
      --  seen: printable characters as themselves, everything else as its
      --  number, so a line feed is visible where a rendering would hide it.
      declare
         Whole : constant String := Ada.Strings.Unbounded.To_String (Said);
         Shown : Ada.Strings.Unbounded.Unbounded_String;
      begin
         for Index in Whole'Range loop
            if Whole (Index) in ' ' .. '~' then
               Ada.Strings.Unbounded.Append (Shown, Whole (Index));
            else
               Ada.Strings.Unbounded.Append
                 (Shown,
                  "<" & Ada.Strings.Fixed.Trim
                          (Natural'Image (Character'Pos (Whole (Index))),
                           Ada.Strings.Both) & ">");
            end if;
         end loop;

         Ada.Text_IO.Put_Line
           ("stopped-child-probe: errors=["
            & Ada.Strings.Unbounded.To_String (Shown) & "]");
      end;

      Ada.Text_IO.Put_Line
        ("stopped-child-probe: output=["
         & Ada.Strings.Unbounded.To_String (Wrote) & "]");

      Ada.Directories.Delete_File (Script);
   end What_A_Stopped_Child_Leaves_On_A_Shells_Error_Stream;

   --  A shell whose reader goes away says nothing rather than a stack trace.
   --
   --  `adash script | head -1` is the ordinary way to meet this: the reader
   --  takes its line and closes the pipe, and every write after that fails.
   --  On POSIX the shell refuses the signal, so the write raises; on Windows
   --  there is no signal and it raises too. Unhandled it reaches the
   --  last-chance handler, which prints fifteen lines of addresses -- on the
   --  standard error, which is a stream somebody else may be reading, and in
   --  place of a shell saying one sentence or nothing at all.
   --
   --  What is asserted is the absence of that trace, which is true on every
   --  host: what the shell *says* instead differs -- a signal takes it on two
   --  of them before it can say anything -- and a case asserting the message
   --  would be asserting which host it was run on.
   --
   --  How it ends is asserted in both shapes: signalled, or exited with 74,
   --  which is the number for an input/output error and the one the shell
   --  chooses when it is left to choose.
   procedure A_Shell_Whose_Reader_Left_Says_No_Stack_Trace
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure A_Shell_Whose_Reader_Left_Says_No_Stack_Trace
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Shell : constant String :=
        Ada.Directories.Compose
          (Ada.Directories.Containing_Directory
             (Ada.Directories.Containing_Directory
                (Ada.Directories.Containing_Directory
                   (Ada.Directories.Full_Name
                      (Ada.Command_Line.Command_Name)))),
           "bin");

      Binary : constant String :=
        Ada.Directories.Compose
          (Shell, "adash" & Hostkit.Fs.Executable_Suffix);

      Script : constant String :=
        Ada.Directories.Compose
          (Ada.Directories.Current_Directory, "adash-test-spew.adash");

      Told : Hostkit.String_Vectors.Vector;

      Options : Hostkit.Spawn.Options;
      Child   : Hostkit.Spawn.Process_Handle;
      Result  : Hostkit.Spawn.Status;

      Ends : Hostkit.Descriptors.Pipe_Ends;
      Outs : Hostkit.Descriptors.Pipe_Ends;

      Said : Ada.Strings.Unbounded.Unbounded_String;

      Written : Adash.Filesystem.Written;

      use type Adash.Filesystem.Written;
      use type Hostkit.Spawn.Spawn_Outcome;
      use type Hostkit.Descriptors.Transfer_Outcome;
   begin
      if not Ada.Directories.Exists (Binary) then
         return;
      end if;

      --  More lines than any pipe holds, so the writing is still going on when
      --  the reading stops.
      Adash.Filesystem.Write
        (Script,
         "for Line in 1 .. 200_000 loop" & Ada.Characters.Latin_1.LF
         & "put_line (""x"");" & Ada.Characters.Latin_1.LF
         & "end loop;" & Ada.Characters.Latin_1.LF
         & "quit (0);" & Ada.Characters.Latin_1.LF,
         Written);

      Assert (Written = Adash.Filesystem.Write_Ok,
              "the spewing script was not written");

      Assert (Hostkit.Descriptors.Create_Pipe (Ends)
              and then Hostkit.Descriptors.Create_Pipe (Outs),
              "no pipes for the shell");

      Assert (Hostkit.Descriptors.Set_Inheritable (Ends.Write_End, True)
              and then Hostkit.Descriptors.Set_Inheritable
                         (Outs.Write_End, True),
              "the child's streams would not travel to it");

      Told.Append (Ada.Strings.Unbounded.To_Unbounded_String (Script));

      Options.Output := Outs.Write_End;
      Options.Error_Output := Ends.Write_End;

      Assert (Hostkit.Spawn.Start (Binary, Told, Options, Child)
              = Hostkit.Spawn.Spawn_Ok,
              "the shell would not start on the spewing script");

      Hostkit.Descriptors.Close (Ends.Write_End);
      Hostkit.Descriptors.Close (Outs.Write_End);

      --  One read, and then the reader leaves -- which is the whole of what
      --  `| head -1` does.
      declare
         Chunk : Ada.Streams.Stream_Element_Array (1 .. 64);
         Last  : Ada.Streams.Stream_Element_Offset;

         Ignored : constant Hostkit.Descriptors.Transfer_Outcome :=
           Hostkit.Descriptors.Read (Outs.Read_End, Chunk, Last);
         pragma Unreferenced (Ignored);
      begin
         Hostkit.Descriptors.Close (Outs.Read_End);
      end;

      loop
         declare
            Chunk : Ada.Streams.Stream_Element_Array (1 .. 4_096);
            Last  : Ada.Streams.Stream_Element_Offset;
         begin
            exit when Hostkit.Descriptors.Read (Ends.Read_End, Chunk, Last)
                      /= Hostkit.Descriptors.Transfer_Ok;

            for Index in Chunk'First .. Last loop
               Ada.Strings.Unbounded.Append
                 (Said, Character'Val (Natural (Chunk (Index))));
            end loop;
         end;
      end loop;

      Hostkit.Descriptors.Close (Ends.Read_End);

      declare
         Ended : constant Boolean :=
           Hostkit.Spawn.Wait (Child, Hostkit.Spawn.Wait_Block, Result);

         use type Hostkit.Spawn.Wait_State;
      begin
         --  Ended at all, which is the other half of not hanging: a shell that
         --  ignored the failure would go on writing into a pipe nobody holds
         --  for another hundred and ninety-nine thousand lines.
         Assert (Ended and then Result.State /= Hostkit.Spawn.Wait_Running,
                 "the shell did not end when its reader left");

         --  And how it ended, in the two shapes a host has for it. Where the
         --  terminal signals a writer whose reader has gone, that signal takes
         --  the shell before it can decide anything -- 74 is what it decides
         --  when it is left to decide, and asserting only one of the two would
         --  be asserting which host this ran on.
         if Result.State = Hostkit.Spawn.Wait_Exited then
            Assert (Result.Exit_Code = 74,
                    "a shell with nowhere to write exited with"
                    & Integer'Image (Result.Exit_Code)
                    & " rather than 74");
         else
            Assert (Result.State = Hostkit.Spawn.Wait_Signalled,
                    "a shell with nowhere to write neither exited nor was "
                    & "signalled: "
                    & Hostkit.Spawn.Wait_State'Image (Result.State));
         end if;
      end;

      --  The two lines a GNAT traceback always has. Either of them means the
      --  shell fell out of its own bottom rather than ending.
      Assert (Ada.Strings.Fixed.Index
                (Ada.Strings.Unbounded.To_String (Said), "Load address") = 0,
              "a shell whose reader left printed a stack trace: ["
              & Ada.Strings.Unbounded.To_String (Said) & "]");

      Assert (Ada.Strings.Fixed.Index
                (Ada.Strings.Unbounded.To_String (Said), "Call stack") = 0,
              "a shell whose reader left printed a call stack: ["
              & Ada.Strings.Unbounded.To_String (Said) & "]");

      Ada.Directories.Delete_File (Script);
   end A_Shell_Whose_Reader_Left_Says_No_Stack_Trace;

   overriding procedure Register_Tests (T : in out Case_Type) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, The_Shell_Can_Read_Its_Own_Input'Access,
         "execution : the shell reads its own input through one buffer");
      Register_Routine
        (T, Exit_Status_Model_Is_One_Table'Access,
         "execution : the exit status model is one table");
      Register_Routine
        (T, Environment_Is_A_Value_Not_The_Process'Access,
         "execution : the environment is a value, sorted and replacing");
      Register_Routine
        (T, A_Missing_Command_Is_Reported_As_Missing'Access,
         "execution : a missing command is told apart from one that failed");
      Register_Routine
        (T, A_Command_Runs_And_Reports_Its_Status'Access,
         "execution : a command runs and its exit status comes back");
      Register_Routine
        (T, Output_Goes_Where_It_Is_Redirected'Access,
         "execution : output reaches the file it was redirected to");
      Register_Routine
        (T, Two_Redirections_On_One_Stream_Are_Refused'Access,
         "execution : two redirections on one stream are refused, and open nothing");
      Register_Routine
        (T, A_Pipeline_Carries_Output_Between_Stages'Access,
         "execution : a pipeline carries output from one stage to the next");
      Register_Routine
        (T, A_Pipelines_Status_Is_Its_Last_Stage'Access,
         "execution : a pipeline takes its status from its last stage");
      Register_Routine
        (T, A_Pipeline_Shares_One_Process_Group'Access,
         "execution : a pipeline runs in one process group");
      Register_Routine
        (T, The_Shell_Refuses_The_Signals_That_Would_Kill_It'Access,
         "execution : the shell refuses the signals that would kill it");
      Register_Routine
        (T, A_Cancellation_Request_Is_Sticky'Access,
         "execution : a cancellation request is sticky until reset");
      Register_Routine
        (T, A_Cancelled_Pipeline_Stops_And_Says_So'Access,
         "execution : a cancelled pipeline stops and reports cancellation");
      Register_Routine
        (T, A_Job_Is_Tracked_From_Start_To_Reaping'Access,
         "execution : a job is tracked from start to reaping");
      Register_Routine
        (T, Job_Numbers_Are_Not_Reused'Access,
         "execution : job numbers are not reused within a session");
      Register_Routine
        (T, An_Unknown_Job_Number_Is_Refused'Access,
         "execution : an unknown job number is refused, not raised");
      Register_Routine
        (T, An_Interrupt_Is_Recorded_Not_Discarded'Access,
         "execution : an interrupt is recorded rather than discarded");
      Register_Routine
        (T, An_Interrupt_Is_Declined_Where_The_Host_Has_None'Access,
         "execution : a host without signals is not believed to have them");
      Register_Routine
        (T, A_Line_Longer_Than_The_Limit_Arrives_In_Pieces'Access,
         "execution : a line longer than the limit arrives in pieces");
      Register_Routine
        (T, A_Shell_Whose_Reader_Left_Says_No_Stack_Trace'Access,
         "execution : a shell whose reader left says no stack trace");
      Register_Routine
        (T, What_A_Stopped_Child_Leaves_On_A_Shells_Error_Stream'Access,
         "execution : what a stopped child leaves on a shell's error stream");
   end Register_Tests;

end Adash_Tests.Execution_Cases;
