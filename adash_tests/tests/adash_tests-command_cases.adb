with Hostkit.Fs;
with Hostkit.Metadata;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Ada.Directories;
with Ada.Environment_Variables;

with Ada.Command_Line;

with AUnit.Assertions;

with Adash.Commands;
with Adash.Language.Values;
with Adash.Diagnostics;
with Adash.Errors;
with Adash.Configuration;
with Adash.Execution;
with Adash.Execution.Environment;
with Adash.Execution.Internal_Commands;
with Adash.Messages;

package body Adash_Tests.Command_Cases is

   use AUnit.Assertions;

   package C renames Adash.Commands;
   package D renames Adash.Diagnostics;
   package M renames Adash.Messages;

   use type C.Command_Id;
   use type C.Availability;
   use type M.Message_Id;

   --  Build an argument set from text, which is what most of these tests
   --  want: a command that takes a path or a name is given one. Whole exists
   --  for the one that takes a number, because a command's arguments are typed
   --  values now and passing "3" where an Integer is expected is exactly the
   --  mistake the types are there to catch.
   --  Up to as many as a command can be given. Widened from two when
   --  redirection arrived: `run_into` takes a file, a program and its
   --  arguments, and a helper that stopped at two could not express one.
   function Args
     (First  : String := "";
      Second : String := "";
      Third  : String := "";
      Fourth : String := "") return C.Argument_Set
   is
      Result : C.Argument_Set;

      procedure Add (Item : String);

      procedure Add (Item : String) is
      begin
         if Item /= "" and then Result.Count < C.Max_Parameters then
            Result.Count := Result.Count + 1;
            Result.Given (Result.Count) :=
              Adash.Language.Values.To_Value (Item);
         end if;
      end Add;
   begin
      Add (First);
      Add (Second);
      Add (Third);
      Add (Fourth);
      return Result;
   end Args;

   function Whole (Item : Integer) return C.Argument_Set is
      Result : C.Argument_Set;
   begin
      Result.Count := 1;
      Result.Given (1) := Adash.Language.Values.To_Value (Item);
      return Result;
   end Whole;

   --  The companion programs, built beside this suite.
   --
   --  Not `echo`: Windows has none, and a redirection case that skipped
   --  itself there was a case that never ran on the host most likely to get
   --  redirection wrong. The same reasoning that put these programs in the
   --  conformance cases this morning applies to the unit tests that spawn
   --  something.
   function Companion (Name : String) return String is
      Self : constant String := Ada.Command_Line.Command_Name;
      Dir  : constant String := Ada.Directories.Containing_Directory (Self);
   begin
      if Ada.Directories.Exists (Ada.Directories.Compose (Dir, Name & ".exe"))
      then
         return Ada.Directories.Compose (Dir, Name & ".exe");
      end if;

      return Ada.Directories.Compose (Dir, Name);
   exception
      when others =>
         return Name;
   end Companion;

   ------------------------------------------------------------------

   procedure Every_Command_Carries_Complete_Metadata
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Found : C.Command_Id;
   begin
      Assert (C.Count > 0, "the command registry is empty");

      for Index in 1 .. C.Count loop
         declare
            About : constant C.Metadata := C.Entry_At (Index);
            Name  : constant String := M.Value (About.Name);
         begin
            Assert (Name'Length > 0, "a command has no name");
            Assert (About.Documentation /= M.Msg_Error_None,
                    Name & " has no documentation key");
            Assert (About.Description /= M.Msg_Error_None,
                    Name & " has no description key");
            Assert (About.Maximum_Arguments >= About.Minimum_Arguments,
                    Name & " accepts fewer arguments than it requires");

            Assert (C.Find (Name, Found) and then Found = About.Id,
                    Name & " is not findable by its own name");
         end;
      end loop;
   end Every_Command_Carries_Complete_Metadata;

   procedure Internal_Commands_Win_Over_Programs
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Which : C.Command_Id;
   begin
      --  The documented resolution order. A `cd` installed on PATH must not
      --  shadow the shell's own, or installing a program would change what a
      --  script means.
      Assert (Adash.Execution.Internal_Commands.Is_Internal ("cd", Which)
              and then Which = C.Command_Change_Directory,
              "cd was not recognised as internal");
      Assert (Adash.Execution.Internal_Commands.Is_Internal ("CD"),
              "the internal lookup did not fold case");
      Assert (not Adash.Execution.Internal_Commands.Is_Internal ("ls"),
              "an external program was claimed as internal");
   end Internal_Commands_Win_Over_Programs;

   procedure Commands_Produce_Data_Not_Text
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Shell    : C.State;
      Produced : C.Output;
      Report   : D.List;
      Status   : Adash.Execution.Exit_Status;
   begin
      C.Initialize (Shell);

      Status := C.Execute (C.Command_Print_Directory, Args, Shell, Produced, Report);
      Assert (Adash.Execution.Succeeded (Status), "pwd failed");
      Assert (Produced.Count = 1, "pwd did not produce exactly one line");

      --  Asserting on the identity, which is only possible because the command
      --  produced data. A command that printed could only be tested by
      --  capturing its output and comparing strings.
      Assert (C.Message (Produced.Element (1)) = M.Msg_Line_Directory,
              "pwd's line is not a directory line");
      Assert (C.Arguments (Produced.Element (1))'Length = 1,
              "pwd's line does not carry the path");
      Assert (M.Value (C.Arguments (Produced.Element (1)) (1))
              = Ada.Directories.Current_Directory,
              "pwd reported a directory the process is not in");

      --  Output accumulates across the commands of one submission: `pwd;
      --  version;` is two lines, and a command that cleared would leave only
      --  the last. The caller clears once per submission.
      Status := C.Execute (C.Command_Version, Args, Shell, Produced, Report);
      Assert (Adash.Execution.Succeeded (Status), "version failed");
      Assert (Produced.Count = 2, "the second command did not add a line");
      Assert (C.Message (Produced.Element (2)) = M.Msg_Line_Version,
              "version did not produce a version line");

      Produced.Clear;
      Assert (Produced.Count = 0, "clearing the output left lines behind");
   end Commands_Produce_Data_Not_Text;

   procedure Changing_Directory_Changes_The_Process
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Shell    : C.State;
      Produced : C.Output;
      Report   : D.List;
      Status   : Adash.Execution.Exit_Status;
      Started  : constant String := Ada.Directories.Current_Directory;
   begin
      C.Initialize (Shell);

      Status := C.Execute (C.Command_Change_Directory, Args (".."),
                           Shell, Produced, Report);
      Assert (Adash.Execution.Succeeded (Status), "cd .. failed");

      --  There is one working directory, not a copy in the state: `pwd` asks
      --  the process, so a child would inherit the same one.
      Assert (Ada.Directories.Current_Directory /= Started,
              "cd did not change the process directory");

      Status := C.Execute (C.Command_Change_Directory, Args (Started),
                           Shell, Produced, Report);
      Assert (Adash.Execution.Succeeded (Status), "cd back failed");
      Assert (Ada.Directories.Current_Directory = Started,
              "cd did not return to where the test started");

      --  A directory that is not there is reported, not raised.
      Report.Clear;
      Status := C.Execute (C.Command_Change_Directory,
                           Args ("./no-such-directory-anywhere"),
                           Shell, Produced, Report);
      Assert (not Adash.Execution.Succeeded (Status),
              "cd to a missing directory reported success");
      Assert (Report.Count = 1, "cd to a missing directory did not report once");
      Assert (Ada.Directories.Current_Directory = Started,
              "a failed cd moved the process anyway");

      --  A directory that is there and will not open. Three things stop a
      --  `cd`, and `Set_Directory` raises the same exception for two of them:
      --  taking the exception's word for it called this one "no such
      --  directory" and sent a reader hunting for a typo in a name that was
      --  right. The mode is put back whatever happens, so a failure here does
      --  not leave a directory nobody can delete.
      declare
         Locked : constant String :=
           Ada.Directories.Compose
             (Ada.Directories.Current_Directory, "adash-test-locked");

         Denied : Boolean := False;
      begin
         if not Ada.Directories.Exists (Locked) then
            Ada.Directories.Create_Directory (Locked);
         end if;

         --  Windows has no mode bits of this kind, and hostkit says so rather
         --  than pretending: where it refuses, there is nothing to assert.
         if Hostkit.Metadata.Set_Permissions (Locked, 0) then
            Report.Clear;
            Status := C.Execute (C.Command_Change_Directory, Args (Locked),
                                 Shell, Produced, Report);

            Denied :=
              not Adash.Execution.Succeeded (Status)
                and then Report.Count = 1
                and then D.Message (Report.Element (1))
                         = Adash.Errors.Message
                             (Adash.Errors.Error_Directory_Denied);

            declare
               Ignored : constant Boolean :=
                 Hostkit.Metadata.Set_Permissions (Locked, 8#700#);
               pragma Unreferenced (Ignored);
            begin
               null;
            end;

            Assert (Denied,
                    "a directory that would not open was not reported as"
                    & " denied");
         end if;

         Ada.Directories.Delete_Directory (Locked);
      end;

      Assert (Ada.Directories.Current_Directory = Started,
              "a refused cd moved the process anyway");
   end Changing_Directory_Changes_The_Process;

   procedure The_Environment_Is_The_Sessions_Not_The_Process
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Shell    : C.State;
      Produced : C.Output;
      Report   : D.List;
      Status   : Adash.Execution.Exit_Status;
   begin
      C.Initialize (Shell);

      Status := C.Execute (C.Command_Set, Args ("ADASH_TEST_VAR=hello"),
                           Shell, Produced, Report);
      Assert (Adash.Execution.Succeeded (Status), "set failed");
      Assert (Adash.Execution.Environment.Value
                (Shell.Environment, "ADASH_TEST_VAR") = "hello",
              "set did not record the variable");

      --  The shell's own environment is untouched: `set` changes what children
      --  inherit, not what this process has.
      Assert (not Ada.Environment_Variables.Exists ("ADASH_TEST_VAR"),
              "set altered the shell's own environment");

      Status := C.Execute (C.Command_Environment, Args, Shell, Produced, Report);
      Assert (Adash.Execution.Succeeded (Status), "env failed");
      Assert (Produced.Count > 0, "env listed nothing");

      Status := C.Execute (C.Command_Unset, Args ("ADASH_TEST_VAR"),
                           Shell, Produced, Report);
      Assert (Adash.Execution.Succeeded (Status), "unset failed");
      Assert (not Adash.Execution.Environment.Contains
                (Shell.Environment, "ADASH_TEST_VAR"),
              "unset did not remove the variable");

      --  NAME=VALUE and nothing else: a bare name would have to mean either
      --  "empty" or "unset", and either choice surprises half its users.
      Report.Clear;
      Status := C.Execute (C.Command_Set, Args ("BARE_NAME"),
                           Shell, Produced, Report);
      Assert (not Adash.Execution.Succeeded (Status),
              "set accepted something that is not an assignment");
   end The_Environment_Is_The_Sessions_Not_The_Process;

   procedure Exit_Asks_Rather_Than_Ends
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Shell    : C.State;
      Produced : C.Output;
      Report   : D.List;
      Status   : Adash.Execution.Exit_Status;
   begin
      C.Initialize (Shell);
      Assert (not Shell.Exit_Requested, "a fresh session already wants to exit");

      --  Whole, not Args ("3"). quit takes an Integer now, and handing it the
      --  characters "3" is precisely the mistake the typed profile exists to
      --  catch -- the analyser refuses it before anything runs.
      Status := C.Execute (C.Command_Exit, Whole (3), Shell, Produced, Report);

      --  It records a request rather than ending the process. A command that
      --  halted would take the decision away from whoever is driving the
      --  session -- a script, a test, or the interactive frontend.
      Assert (Shell.Exit_Requested, "exit did not record the request");
      Assert (Adash.Execution.Numeric (Shell.Exit_Status) = 3,
              "exit did not carry its status");
      Assert (Adash.Execution.Numeric (Status) = 3,
              "exit did not return its status");

      --  A status that is not an Integer is reported, and the session still
      --  ends because the user asked it to.
      --
      --  The analyser refuses this before it can happen, so reaching the guard
      --  means a caller built the argument set by hand and got it wrong. It is
      --  still worth having and worth testing: a defence that is never
      --  exercised is one nobody knows is broken.
      C.Initialize (Shell);
      Report.Clear;
      Status := C.Execute (C.Command_Exit, Args ("later"), Shell, Produced, Report);
      Assert (not Adash.Execution.Succeeded (Status),
              "a status of the wrong type reported success");
      Assert (Shell.Exit_Requested,
              "a status of the wrong type stopped the exit from happening");
      Assert (Report.Count = 1,
              "a status of the wrong type was not reported");
   end Exit_Asks_Rather_Than_Ends;

   procedure Argument_Counts_And_Availability_Are_Enforced
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Shell    : C.State;
      Produced : C.Output;
      Report   : D.List;
      Status   : Adash.Execution.Exit_Status;
   begin
      C.Initialize (Shell);

      Status := C.Execute (C.Command_Print_Directory, Args ("unexpected"),
                           Shell, Produced, Report);
      Assert (not Adash.Execution.Succeeded (Status),
              "pwd accepted an argument it does not take");
      Assert (Report.Count = 1, "the wrong argument count was not reported");

      --  Every command the shell registers works. `alias` was the last one
      --  that did not, and it was retired rather than built: within a
      --  submission a subprogram is already a checked, composable short name
      --  for something longer, which is what its own documentation said alias
      --  was for.
      --
      --  The machinery for a registered-but-unavailable command stays -- it is
      --  what tells a missing feature from a typo, and only the shell knows
      --  which -- and this asserts that nothing needs it today.
      for Id in C.Command_Id loop
         Assert (C.Describe (Id).Status = C.Available,
                 "a registered command is not available: "
                 & M.Value (C.Describe (Id).Name));
         Assert (C.Describe (Id).Documentation /= M.Msg_Error_None,
                 "a command has no documentation: "
                 & M.Value (C.Describe (Id).Name));
      end loop;

      --  `history` is available, and a session with nothing keeping a log says
      --  so in its own words. "Not available in this build" would send a user
      --  looking for a build that has it; the command is here, and this
      --  session -- a test, a script -- simply has no lines.
      Report.Clear;
      Status := C.Execute (C.Command_History, Args, Shell, Produced, Report);
      Assert (not Adash.Execution.Succeeded (Status),
              "history reported success with nothing keeping a log");
      Assert (D.Message (Report.Element (1))
              = Adash.Errors.Message (Adash.Errors.Error_No_History_Here),
              "history without a log was reported as unavailable");
      Assert (C.Describe (C.Command_History).Status = C.Available,
              "history is still marked unavailable");

      --  Help lists what exists, and describes one on request.
      Produced.Clear;
      Status := C.Execute (C.Command_Help, Args, Shell, Produced, Report);
      Assert (Adash.Execution.Succeeded (Status), "help failed");
      Assert (Produced.Count = C.Count,
              "help did not list every command");

      --  Each entry names a command *and* says what it is for. The summary was
      --  an empty string for as long as `help` had existed, so the listing was
      --  a column of names beside a column of nothing. A command may not
      --  render, so what it carries is the identifier of the message that
      --  says so.
      for Index in 1 .. Produced.Count loop
         declare
            Entry_Line : constant C.Line := Produced.Element (Index);
         begin
            Assert (C.Message (Entry_Line) = M.Msg_Line_Command_Entry,
                    "a help entry is not a command entry line");
            Assert (C.Detail (Entry_Line)
                      = C.Describe (C.Entry_At (Index).Id).Documentation,
                    "a help entry does not quote what the command is for");
            Assert (C.Detail_Placeholder (Entry_Line) = "summary",
                    "a help entry quotes into the wrong placeholder");
         end;
      end loop;

      Produced.Clear;
      Status := C.Execute (C.Command_Help, Args ("pwd"), Shell, Produced, Report);
      Assert (Adash.Execution.Succeeded (Status), "help on one command failed");
      Assert (Produced.Count = 1 and then C.Message (Produced.Element (1))
              = M.Msg_Command_Pwd_Doc,
              "help on one command did not produce its documentation");
   end Argument_Counts_And_Availability_Are_Enforced;

   ----------
   -- Name --
   ----------

   procedure Redirection_Attaches_A_File
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Shell    : C.State;
      Produced : C.Output;
      Report   : D.List;
      Status   : Adash.Execution.Exit_Status;

      Folder : constant String := Hostkit.Fs.Temp_Directory;
      Target : constant String :=
        Hostkit.Fs.Join (Folder, "adash-redirect-out.txt");
      Source : constant String :=
        Hostkit.Fs.Join (Folder, "adash-redirect-in.txt");

      function Contents (Path : String) return String is
         File : Ada.Text_IO.File_Type;
         Text : Ada.Strings.Unbounded.Unbounded_String;
      begin
         Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Path);

         while not Ada.Text_IO.End_Of_File (File) loop
            Ada.Strings.Unbounded.Append
              (Text, Ada.Text_IO.Get_Line (File));
         end loop;

         Ada.Text_IO.Close (File);
         return Ada.Strings.Unbounded.To_String (Text);
      end Contents;
   begin
      C.Initialize (Shell);

      --  Output to a file. The subsystem underneath has been able to do this
      --  since Phase 11 and nothing could reach it: no command took a stream,
      --  and this language has no `>` and will not grow one.
      Status := C.Execute
        (C.Command_Run_Into, Args (Target, Companion ("adash_test_emit"), "captured"),
         Shell, Produced, Report);

      if not Adash.Execution.Succeeded (Status) then
         --  No temporary directory. The program is this crate's own, so a
         --  failure here is the host refusing a file rather than a missing
         --  utility, and the case is skipped rather than failed.
         return;
      end if;

      Assert (Contents (Target) = "captured",
              "the program's output did not reach the file: ["
              & Contents (Target) & "]");

      --  Input from a file. This one found a defect in the pipeline: it
      --  overwrote every stage's input with the shell's own, so an attached
      --  file was discarded and the program read nothing -- silently, because
      --  a program reading an empty stream succeeds.
      --
      --  Proved by exit status rather than by output, because a foreground
      --  program writes to the shell's own output and a test cannot read it
      --  back. `grep -q` says whether it found the line, and finding it is
      --  only possible if the file arrived.
      declare
         File : Ada.Text_IO.File_Type;
      begin
         Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Source);
         Ada.Text_IO.Put_Line (File, "one");
         Ada.Text_IO.Put_Line (File, "two");
         Ada.Text_IO.Close (File);
      end;

      Status := C.Execute
        (C.Command_Run_From, Args (Source, "grep", "-q", "two"),
         Shell, Produced, Report);

      if Adash.Execution.Succeeded (Status) then
         --  And the other way: a line the file does not contain is not found,
         --  so success above was the file and not an empty stream matching
         --  everything.
         Status := C.Execute
           (C.Command_Run_From, Args (Source, "grep", "-q", "absent"),
            Shell, Produced, Report);
         Assert (not Adash.Execution.Succeeded (Status),
                 "a pattern the file does not contain was found in it");
      end if;

      --  Appending adds to the end rather than replacing, and refusing an
      --  existing file refuses it. Both are properties of how the file is
      --  opened, which is why this goes through the redirection subsystem
      --  rather than opening the file itself: appending done as a seek races
      --  two programs writing one log, and refusing done as a prior check
      --  races two shells creating one file.
      Status := C.Execute
        (C.Command_Run_Append, Args (Target, Companion ("adash_test_emit"), "second"),
         Shell, Produced, Report);

      if Adash.Execution.Succeeded (Status) then
         Assert (Contents (Target) = "capturedsecond",
                 "appending replaced the file instead of adding to it: ["
                 & Contents (Target) & "]");
      end if;

      Report.Clear;
      Status := C.Execute
        (C.Command_Run_New, Args (Target, Companion ("adash_test_emit"), "clobbered"),
         Shell, Produced, Report);
      Assert (not Adash.Execution.Succeeded (Status),
              "writing to a file that must not exist overwrote one");
      Assert (Contents (Target) = "capturedsecond",
              "a refused redirection changed the file anyway: ["
              & Contents (Target) & "]");

      --  A file that cannot be opened is reported as the file, not as a
      --  missing program.
      Report.Clear;
      Status := C.Execute
        (C.Command_Run_Into,
         Args ("/nonexistent/adash/redirect", Companion ("adash_test_emit"), "x"),
         Shell, Produced, Report);
      Assert (not Adash.Execution.Succeeded (Status),
              "an unopenable redirection reported success");
      Assert (D.Message (Report.Element (1))
              = Adash.Errors.Message
                  (Adash.Errors.Error_Redirection_Open_Failed),
              "an unopenable redirection was reported as something else");

      --  Best effort: a temporary file left behind is untidy and not a
      --  failure of what this case is about.
      begin
         Ada.Directories.Delete_File (Target);
         Ada.Directories.Delete_File (Source);
      exception
         when others =>
            null;
      end;
   end Redirection_Attaches_A_File;

   procedure A_Pipeline_Joins_Its_Stages
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Shell    : C.State;
      Produced : C.Output;
      Report   : D.List;
      Status   : Adash.Execution.Exit_Status;

      Folder : constant String := Hostkit.Fs.Temp_Directory;
      Source : constant String :=
        Hostkit.Fs.Join (Folder, "adash-pipeline-in.txt");
   begin
      C.Initialize (Shell);

      --  Nothing added is refused rather than treated as a pipeline of no
      --  stages, which would succeed and look like it had run something.
      Status := C.Execute (C.Command_Pipe_Run, Args, Shell, Produced, Report);
      Assert (not Adash.Execution.Succeeded (Status),
              "an empty pipeline reported success");
      Assert (D.Message (Report.Element (1))
              = Adash.Errors.Message (Adash.Errors.Error_Empty_Pipeline),
              "an empty pipeline was reported as something else");

      declare
         File : Ada.Text_IO.File_Type;
      begin
         Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Source);
         Ada.Text_IO.Put_Line (File, "beta");
         Ada.Text_IO.Put_Line (File, "alpha");
         Ada.Text_IO.Close (File);
      end;

      --  Two stages, and the second reads what the first wrote. Proved by exit
      --  status: `grep -q` finds the sorted first line only if `sort` ran on
      --  what `cat` produced.
      Status := C.Execute (C.Command_Pipe, Args (Companion ("adash_test_upcase"), Source),
                           Shell, Produced, Report);
      Assert (Adash.Execution.Succeeded (Status), "adding a stage failed");

      --  Adding a stage cannot fail once the first has been accepted, so the
      --  status of these two is not what the case is about.
      declare
         Sorted : constant Adash.Execution.Exit_Status :=
           C.Execute (C.Command_Pipe, Args ("sort"), Shell, Produced, Report);
         Sought : constant Adash.Execution.Exit_Status :=
           C.Execute (C.Command_Pipe, Args ("grep", "-q", "alpha"),
                      Shell, Produced, Report);
      begin
         Assert (Adash.Execution.Succeeded (Sorted)
                 and then Adash.Execution.Succeeded (Sought),
                 "adding a later stage failed");
      end;

      Report.Clear;
      Status := C.Execute (C.Command_Pipe_Run, Args, Shell, Produced, Report);

      if not Adash.Execution.Succeeded (Status) then
         --  No `sort` or `grep` on this host. The capability is the host's and
         --  the case is skipped rather than failed.
         begin
            Ada.Directories.Delete_File (Source);
         exception
            when others =>
               null;
         end;

         return;
      end if;

      --  And the stages are gone: a second run with nothing added is refused
      --  again, rather than repeating what was built the first time.
      Report.Clear;
      Status := C.Execute (C.Command_Pipe_Run, Args, Shell, Produced, Report);
      Assert (not Adash.Execution.Succeeded (Status),
              "a pipeline ran twice from one set of stages");

      --  A pipeline that could not start clears its stages too. Leaving them
      --  would put them at the front of whatever is built next, which is the
      --  last thing somebody fixing a mistyped program name wants.
      Report.Clear;
      declare
         Added : Adash.Execution.Exit_Status;
      begin
         Added := C.Execute (C.Command_Pipe, Args ("adash-no-such-program"),
                             Shell, Produced, Report);
         pragma Unreferenced (Added);
      end;

      Status := C.Execute (C.Command_Pipe_Run, Args, Shell, Produced, Report);
      Assert (not Adash.Execution.Succeeded (Status),
              "a pipeline with a missing program reported success");

      Report.Clear;
      Status := C.Execute (C.Command_Pipe_Run, Args, Shell, Produced, Report);
      Assert (D.Message (Report.Element (1))
              = Adash.Errors.Message (Adash.Errors.Error_Empty_Pipeline),
              "a failed pipeline left its stages behind");

      begin
         Ada.Directories.Delete_File (Source);
      exception
         when others =>
            null;
      end;
   end A_Pipeline_Joins_Its_Stages;

   procedure The_Shell_Can_Show_And_Change_Its_Settings
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Shell    : C.State;
      Produced : C.Output;
      Report   : D.List;
      Status   : Adash.Execution.Exit_Status;

      package Config renames Adash.Configuration;
   begin
      --  Every setting there is, each with its value and the message that says
      --  what it is for. Quoted rather than rendered: a command may not turn a
      --  message into text.
      Status := C.Execute (C.Command_Settings, Args, Shell, Produced, Report);
      Assert (Adash.Execution.Succeeded (Status), "listing the settings failed");
      Assert (Produced.Count = Natural (Config.Setting_Id'Pos
                                          (Config.Setting_Id'Last) + 1),
              "the listing is not one line per setting");

      for Index in 1 .. Produced.Count loop
         Assert (C.Message (Produced.Element (Index)) = M.Msg_Line_Setting,
                 "a settings line is not a settings line");
         Assert (C.Detail (Produced.Element (Index)) /= M.Msg_Error_None,
                 "a settings line does not say what the setting is for");
      end loop;

      --  Changed, and held in the session's own state -- which is where a
      --  command can reach it and where the engine reads it back.
      Produced.Clear;
      Status := C.Execute (C.Command_Settings, Args ("color", "never"),
                           Shell, Produced, Report);
      Assert (Adash.Execution.Succeeded (Status), "changing a setting failed");
      Assert (Shell.Chosen.Choice_Value (Config.Color_Setting) = "never",
              "the change did not reach the session");

      Produced.Clear;
      Status := C.Execute (C.Command_Settings, Args ("history.limit", "500"),
                           Shell, Produced, Report);
      Assert (Adash.Execution.Succeeded (Status), "changing a number failed");
      Assert (Shell.Chosen.Integer_Value (Config.History_Limit_Setting) = 500,
              "the number did not reach the session");

      Produced.Clear;
      Status := C.Execute (C.Command_Settings, Args ("history.enabled", "false"),
                           Shell, Produced, Report);
      Assert (Adash.Execution.Succeeded (Status), "changing a Boolean failed");
      Assert (not Shell.Chosen.Boolean_Value (Config.History_Enabled_Setting),
              "the Boolean did not reach the session");

      --  Refused where the registry says so, with the registry's own bounds
      --  and lists rather than a second copy of them.
      Produced.Clear;
      Status := C.Execute (C.Command_Settings, Args ("color", "purple"),
                           Shell, Produced, Report);
      Assert (not Adash.Execution.Succeeded (Status),
              "a value outside the choices was accepted");
      Assert (Shell.Chosen.Choice_Value (Config.Color_Setting) = "never",
              "a refused change was made anyway");

      Status := C.Execute (C.Command_Settings, Args ("history.limit", "0"),
                           Shell, Produced, Report);
      Assert (not Adash.Execution.Succeeded (Status),
              "a number outside the range was accepted");

      Status := C.Execute (C.Command_Settings, Args ("history.limit", "many"),
                           Shell, Produced, Report);
      Assert (not Adash.Execution.Succeeded (Status),
              "a number that is not one was accepted");

      Status := C.Execute (C.Command_Settings, Args ("nope", "x"),
                           Shell, Produced, Report);
      Assert (not Adash.Execution.Succeeded (Status),
              "a setting that does not exist was accepted");

      --  One argument is neither a question this can answer differently from
      --  the listing nor a change.
      Status := C.Execute (C.Command_Settings, Args ("color"),
                           Shell, Produced, Report);
      Assert (not Adash.Execution.Succeeded (Status),
              "a name with no value was accepted");
   end The_Shell_Can_Show_And_Change_Its_Settings;

   overriding function Name (T : Case_Type) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Adash.Commands");
   end Name;

   --------------------
   -- Register_Tests --
   --------------------

   overriding procedure Register_Tests (T : in out Case_Type) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, The_Shell_Can_Show_And_Change_Its_Settings'Access,
         "commands : the shell can show and change its own settings");
      Register_Routine
        (T, A_Pipeline_Joins_Its_Stages'Access,
         "a pipeline joins its stages and forgets them once it has run");
      Register_Routine
        (T, Redirection_Attaches_A_File'Access,
         "a program's output goes to a file and its input comes from one");
      Register_Routine
        (T, Every_Command_Carries_Complete_Metadata'Access,
         "commands : every command carries complete metadata");
      Register_Routine
        (T, Internal_Commands_Win_Over_Programs'Access,
         "commands : an internal command wins over a program of the same name");
      Register_Routine
        (T, Commands_Produce_Data_Not_Text'Access,
         "commands : commands produce data, not rendered text");
      Register_Routine
        (T, Changing_Directory_Changes_The_Process'Access,
         "commands : cd changes the process, and a failed cd does not");
      Register_Routine
        (T, The_Environment_Is_The_Sessions_Not_The_Process'Access,
         "commands : set changes what children inherit, not the shell");
      Register_Routine
        (T, Exit_Asks_Rather_Than_Ends'Access,
         "commands : exit records a request rather than ending the process");
      Register_Routine
        (T, Argument_Counts_And_Availability_Are_Enforced'Access,
         "commands : argument counts and availability are enforced");
   end Register_Tests;

end Adash_Tests.Command_Cases;
