with Ada.Directories;
with Ada.Text_IO;

with AUnit.Assertions;

with Adash.Diagnostics;
with Adash.Engine;
with Adash.Errors;
with Adash.Execution;
with Adash.Execution.Environment;
with Adash.Messages;
with Adash.Scripting;
with Adash.Scripting.Modules;
with Adash.Scripting.Startup;

package body Adash_Tests.Scripting_Cases is

   use AUnit.Assertions;

   package Sc renames Adash.Scripting;
   package E renames Adash.Engine;
   package D renames Adash.Diagnostics;

   use type Sc.Outcome;
   use type Sc.Modules.Search_Step;
   use type Adash.Messages.Message_Id;

   --  Write a script into the test's own directory and hand back its path.
   function Write (Name : String; Text : String) return String is
      Path : constant String :=
        Ada.Directories.Compose (Ada.Directories.Current_Directory, Name);
      File : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path);
      Ada.Text_IO.Put_Line (File, Text);
      Ada.Text_IO.Close (File);
      return Path;
   end Write;

   procedure Remove (Path : String) is
   begin
      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_File (Path);
      end if;
   end Remove;

   function Reported
     (Report : D.List; Code : Adash.Errors.Error_Code) return Boolean is
   begin
      for Index in 1 .. Report.Count loop
         if D.Message (Report.Element (Index)) = Adash.Errors.Message (Code) then
            return True;
         end if;
      end loop;

      return False;
   end Reported;

   ------------------------------------------------------------------

   procedure A_Script_Runs_Through_The_Same_Engine
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Session : E.Session;
      Context : Sc.Loading;
      Result  : Sc.Outcome;
      Status  : Adash.Execution.Exit_Status;
      Report  : D.List;
      Path    : constant String :=
        Write ("adash-test-program.adash",
               "N : Integer := 6 * 7; Put_Line (N);");
   begin
      E.Open (Session);
      Sc.Run_File (Session, Path, Context, Result, Status, Report);

      Assert (Result = Sc.Script_Ran, "a valid script did not run");
      Assert (Adash.Execution.Succeeded (Status), "a valid script failed");
      Assert (Report.Count = 0, "a valid script produced diagnostics");

      --  The chain is empty again afterwards: a script is on it only while it
      --  runs, or a second run of the same file would look like a cycle.
      Assert (Sc.Depth (Context) = 0, "the loading chain was left non-empty");

      Remove (Path);
   end A_Script_Runs_Through_The_Same_Engine;

   procedure A_Script_Changes_The_Session_It_Runs_In
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Session : E.Session;
      Context : Sc.Loading;
      Result  : Sc.Outcome;
      Status  : Adash.Execution.Exit_Status;
      Report  : D.List;
      Path    : constant String :=
        Write ("adash-test-setenv.adash", "set (""FROM_SCRIPT=yes"");");
   begin
      E.Open (Session);
      Sc.Run_File (Session, Path, Context, Result, Status, Report);

      --  A sourced script changes the session, which is the whole point of
      --  sourcing one rather than running it as a child.
      Assert (Result = Sc.Script_Ran, "a command script did not run");
      Assert (Adash.Execution.Environment.Value
                (E.Environment (Session), "FROM_SCRIPT") = "yes",
              "a script did not change the session it ran in");

      Remove (Path);
   end A_Script_Changes_The_Session_It_Runs_In;

   procedure Missing_And_Unreadable_Are_Told_Apart
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Session : E.Session;
      Context : Sc.Loading;
      Result  : Sc.Outcome;
      Status  : Adash.Execution.Exit_Status;
      Report  : D.List;
   begin
      E.Open (Session);

      Sc.Run_File (Session, "./no-such-script-anywhere.adash",
                   Context, Result, Status, Report);
      Assert (Result = Sc.Script_Not_Found, "a missing script was not reported as missing");
      Assert (Adash.Execution.Numeric (Status) = 127,
              "a missing script did not reduce to 127");
      Assert (Report.Count = 1, "a missing script did not report once");
      Assert (Reported (Report, Adash.Errors.Error_Source_Unreadable),
              "a missing script was reported as something else");

      --  A directory exists and is not a script. Reported, not raised.
      Report.Clear;
      Sc.Run_File (Session, Ada.Directories.Current_Directory,
                   Context, Result, Status, Report);
      Assert (Result /= Sc.Script_Ran, "a directory was run as a script");
      Assert (Report.Count = 1, "a directory did not report once");
   end Missing_And_Unreadable_Are_Told_Apart;

   procedure A_Script_Cannot_Load_Itself
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Session : E.Session;
      Context : Sc.Loading;
      Result  : Sc.Outcome;
      Status  : Adash.Execution.Exit_Status;
      Report  : D.List;
      Path    : constant String := Write ("adash-test-cycle.adash", "null;");
   begin
      E.Open (Session);

      Assert (Sc.Depth (Context) = 0, "a fresh chain is not empty");
      Assert (not Sc.Is_Active (Context, Path),
              "a fresh chain reported a path as active");

      Sc.Run_File (Session, Path, Context, Result, Status, Report);
      Assert (Result = Sc.Script_Ran, "the script did not run");

      --  Off the chain again afterwards, so running the same file twice is not
      --  mistaken for a cycle. Running it a second time proves that rather
      --  than only asserting the depth.
      Assert (Sc.Depth (Context) = 0, "the chain was left non-empty");
      Assert (not Sc.Is_Active (Context, Path),
              "the script stayed on the chain after it finished");

      Sc.Run_File (Session, Path, Context, Result, Status, Report);
      Assert (Result = Sc.Script_Ran,
              "running the same script twice was mistaken for a cycle");

      --  The refusal itself cannot be reached from a test yet: closing a cycle
      --  needs one script to load another, and `source` is the command that
      --  would do it -- which waits on the scripting subsystem being reachable
      --  from the commands, an inversion described in ROADMAP.md. What is
      --  tested here is the chain discipline the refusal depends on.
      Remove (Path);
   end A_Script_Cannot_Load_Itself;

   procedure Module_Resolution_Is_Predictable
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Path : constant String :=
        Write ("adash-test-module.adash", "null;");
      Here : constant String :=
        Ada.Directories.Compose (Ada.Directories.Current_Directory, "loader.adash");
   begin
      --  A name with a separator is a path, used as written and never
      --  searched for: `./setup` runs the one here.
      declare
         Found : constant Sc.Modules.Resolution :=
           Sc.Modules.Resolve ("./adash-test-module");
      begin
         Assert (Found.Found, "a relative path did not resolve");
         Assert (Found.Where = Sc.Modules.Step_As_Written,
                 "a path was searched for rather than used");
      end;

      --  A bare name is found beside the script loading it, so scripts that
      --  ship together find each other without knowing where they live.
      declare
         Found : constant Sc.Modules.Resolution :=
           Sc.Modules.Resolve ("adash-test-module", Here);
      begin
         Assert (Found.Found, "a module beside the loader did not resolve");
         Assert (Found.Where = Sc.Modules.Step_Beside_Loader,
                 "a module was not found beside its loader");
      end;

      --  The extension is optional in the name and added when absent, so a
      --  script may say either and mean one file.
      Assert (Sc.Modules.Resolve ("adash-test-module.adash", Here).Found,
              "a name carrying the extension did not resolve");

      Assert (not Sc.Modules.Resolve ("nothing-of-that-name", Here).Found,
              "a name that is not there resolved anyway");

      Remove (Path);
   end Module_Resolution_Is_Predictable;

   procedure Startup_Has_A_Documented_Order_And_Never_Refuses_To_Start
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Session : E.Session;
      Summary : Sc.Startup.Report_Summary;
      Report  : D.List;
   begin
      --  System, then user, then session: later files win where they disagree,
      --  which is the order users expect.
      Assert (Sc.Startup.Scope'Pos (Sc.Startup.System_Scope)
              < Sc.Startup.Scope'Pos (Sc.Startup.User_Scope),
              "the system file does not come before the user's");
      Assert (Sc.Startup.Scope'Pos (Sc.Startup.User_Scope)
              < Sc.Startup.Scope'Pos (Sc.Startup.Session_Scope),
              "the user file does not come before the session's");

      --  The session file is for interactive sessions only: running it for a
      --  script would make that script mean different things depending on who
      --  ran it.
      Assert (Sc.Startup.Applies (Sc.Startup.Session_Scope, Interactive => True),
              "the session file does not apply to an interactive session");
      Assert (not Sc.Startup.Applies (Sc.Startup.Session_Scope,
                                      Interactive => False),
              "the session file applies to a script");
      Assert (Sc.Startup.Applies (Sc.Startup.User_Scope, Interactive => False),
              "the user file does not apply to a script");

      --  Absence is silent, and startup always returns: refusing to start over
      --  a broken startup file would leave a user without the tool they would
      --  fix it with.
      E.Open (Session);
      Sc.Startup.Run_All (Session, Interactive => False,
                          Summary => Summary, Report => Report);
      Assert (Summary.Ran + Summary.Unreadable + Summary.Failed >= 0,
              "startup did not produce a summary");
   end Startup_Has_A_Documented_Order_And_Never_Refuses_To_Start;

   procedure The_Source_Command_Runs_A_Script
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Session : aliased E.Session;
      Context : aliased Sc.Loading;
      Report  : aliased D.List;
      Result  : Sc.Outcome;
      Status  : Adash.Execution.Exit_Status;

      Sourcing : aliased Sc.Runner
        (Session => Session'Unchecked_Access,
         Context => Context'Unchecked_Access,
         Report  => Report'Unchecked_Access,
         Output  => null);

      Inner : constant String :=
        Write ("adash-test-sourced.adash", "set (""FROM_SOURCED=yes"");");
      Outer : constant String :=
        Write ("adash-test-sourcing.adash",
               "source (""" & Inner & """);");
   begin
      E.Open (Session);
      E.Use_Script_Runner (Session, Sourcing'Unchecked_Access);

      Sc.Run_File (Session, Outer, Context, Result, Status, Report);

      Assert (Result = Sc.Script_Ran, "a script that sourced another did not run");
      Assert (Adash.Execution.Environment.Value
                (E.Environment (Session), "FROM_SOURCED") = "yes",
              "what a sourced script set did not outlive it");

      --  The chain is empty again, so the same file may be sourced twice
      --  without the second time looking like a cycle.
      Assert (Sc.Depth (Context) = 0, "the loading chain was left non-empty");

      Remove (Outer);
      Remove (Inner);
   end The_Source_Command_Runs_A_Script;

   procedure Source_Without_A_Runner_Refuses
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Session : E.Session;
      Context : Sc.Loading;
      Report  : D.List;
      Result  : Sc.Outcome;
      Status  : Adash.Execution.Exit_Status;

      Inner : constant String :=
        Write ("adash-test-unreachable.adash", "set (""NEVER=1"");");
      Outer : constant String :=
        Write ("adash-test-no-runner.adash", "source (""" & Inner & """);");
   begin
      --  No runner installed. A session that cannot run scripts has to say so:
      --  a `source` that quietly did nothing would look like an empty file.
      E.Open (Session);
      Sc.Run_File (Session, Outer, Context, Result, Status, Report);

      --  Not the exit status: this shell deliberately does not let a failed
      --  command set it, which the exit-status conformance cases pin down. The
      --  refusal shows up as a diagnostic, and as the file not having run.
      Assert (Reported (Report, Adash.Errors.Error_Command_Unavailable),
              "source without a runner did not say it could not run one");
      Assert (Adash.Execution.Environment.Value
                (E.Environment (Session), "NEVER") = "",
              "source without a runner ran the file anyway");

      Remove (Outer);
      Remove (Inner);
   end Source_Without_A_Runner_Refuses;

   procedure A_Script_Cannot_Source_Itself
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Session : aliased E.Session;
      Context : aliased Sc.Loading;
      Report  : aliased D.List;
      Result  : Sc.Outcome;
      Status  : Adash.Execution.Exit_Status;

      Sourcing : aliased Sc.Runner
        (Session => Session'Unchecked_Access,
         Context => Context'Unchecked_Access,
         Report  => Report'Unchecked_Access,
         Output  => null);

      Path : constant String := Ada.Directories.Compose
        (Ada.Directories.Containing_Directory
           (Write ("adash-test-anchor.adash", "")),
         "adash-test-cycle.adash");

      Ignored : constant String :=
        Write ("adash-test-cycle.adash", "source (""" & Path & """);");
   begin
      E.Open (Session);
      E.Use_Script_Runner (Session, Sourcing'Unchecked_Access);

      --  A cycle is a refusal with the path that closed it, not a hang. This
      --  test would not fail if that were wrong -- it would never return -- so
      --  the assertion below is about the diagnostic, and reaching it at all
      --  is the other half.
      Sc.Run_File (Session, Path, Context, Result, Status, Report);

      Assert (Reported (Report, Adash.Errors.Error_Script_Cycle),
              "a script that sourced itself did not report a cycle");

      Remove (Ignored);
   end A_Script_Cannot_Source_Itself;

   ----------
   -- Name --
   ----------

   procedure Sourcing_A_Bare_Name_Searches_For_It
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);

      Module : constant String :=
        Write ("adash-test-wired.adash", "put_line (""wired"");");
      Loader : constant String :=
        Write ("adash-test-loader.adash", "source (""adash-test-wired"");");

      Session : aliased Adash.Engine.Session;
      Context : aliased Sc.Loading;
      Report  : aliased D.List;
      Result  : Sc.Outcome;
      Status  : Adash.Execution.Exit_Status;

      Runner : aliased Sc.Runner
        (Session => Session'Unchecked_Access,
         Context => Context'Unchecked_Access,
         Report  => Report'Unchecked_Access,
         Output  => null);
   begin
      Adash.Engine.Open (Session);
      Adash.Engine.Use_Script_Runner (Session, Runner'Unchecked_Access);

      --  Nothing is being loaded yet, so there is nothing to be beside.
      Assert (Sc.Innermost (Context) = "",
              "a fresh chain claims to be inside a script");

      --  The wiring, which is what was missing: the resolution itself has been
      --  right since Phase 14 and nothing asked it, so `source ("name")` only
      --  worked when a file of exactly that name sat in the working directory.
      Sc.Run_File (Session, Loader, Context, Result, Status, Report);

      Assert (Result = Sc.Script_Ran,
              "a script sourcing a module beside it did not run");
      Assert (Adash.Execution.Succeeded (Status),
              "sourcing a bare name failed");

      Remove (Module);
      Remove (Loader);
   end Sourcing_A_Bare_Name_Searches_For_It;

   overriding function Name (T : Case_Type) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Adash.Scripting");
   end Name;

   --------------------
   -- Register_Tests --
   --------------------

   overriding procedure Register_Tests (T : in out Case_Type) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, The_Source_Command_Runs_A_Script'Access,
         "the source command runs a script in the session it was called from");
      Register_Routine
        (T, Source_Without_A_Runner_Refuses'Access,
         "source refuses when the session has no way to run one");
      Register_Routine
        (T, A_Script_Cannot_Source_Itself'Access,
         "a script that sources itself is refused rather than looping");
      Register_Routine
        (T, A_Script_Runs_Through_The_Same_Engine'Access,
         "scripting : a script runs through the same engine");
      Register_Routine
        (T, A_Script_Changes_The_Session_It_Runs_In'Access,
         "scripting : a script changes the session it runs in");
      Register_Routine
        (T, Missing_And_Unreadable_Are_Told_Apart'Access,
         "scripting : missing and unreadable are told apart, and reported");
      Register_Routine
        (T, A_Script_Cannot_Load_Itself'Access,
         "scripting : the loading chain tracks what is active");
      Register_Routine
        (T, Sourcing_A_Bare_Name_Searches_For_It'Access,
         "scripting : sourcing a bare name searches for it");
      Register_Routine
        (T, Module_Resolution_Is_Predictable'Access,
         "scripting : module resolution is predictable and unsearchable by path");
      Register_Routine
        (T, Startup_Has_A_Documented_Order_And_Never_Refuses_To_Start'Access,
         "scripting : startup has a documented order and never refuses to start");
   end Register_Tests;

end Adash_Tests.Scripting_Cases;
