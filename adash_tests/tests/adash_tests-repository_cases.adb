with AUnit.Assertions;

with Adash.Messages;

with Adash_Tests.Repository;

package body Adash_Tests.Repository_Cases is

   use AUnit.Assertions;

   package Repo renames Adash_Tests.Repository;

   --  Relative to the adash_tests directory; see the note in
   --  Adash_Tests.Message_Cases about why this is not absolute.
   Repository_Root : constant String := "..";

   --  A directory that is certainly not a repository. Used to prove the
   --  checks can fail, which is the only way to know a passing run means
   --  anything.
   Empty_Root : constant String := "fixtures/not-a-repository";

   --  A source tree holding exactly one sentence, so the prose check can be
   --  seen to fail. A check only ever run against a repository that passes is
   --  a check nobody has watched work.
   Prose_Root : constant String := "fixtures/prose-in-source";

   procedure The_Repository_Passes (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Checks_Actually_Ran (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure A_Broken_Root_Fails (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Findings_Carry_Renderable_Keys (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Prose_In_Source_Is_Found (T : in out AUnit.Test_Cases.Test_Case'Class);

   --------------------------------
   -- The_Repository_Passes --
   --------------------------------

   procedure The_Repository_Passes (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Report : Repo.Report;
   begin
      Repo.Check (Repository_Root, Report);

      if not Repo.Passed (Report) then
         --  Name the first finding. A bare "the repository check failed"
         --  sends the reader to run the tool by hand to find out what.
         declare
            First : constant Repo.Finding := Report.Findings.First_Element;
         begin
            Assert (False,
                    "repository check failed with"
                    & Natural'Image (Repo.Failure_Count (Report))
                    & " findings; first is " & Repo.Key (First));
         end;
      end if;
   end The_Repository_Passes;

   -----------------------------
   -- Checks_Actually_Ran --
   -----------------------------

   procedure Checks_Actually_Ran (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Report : Repo.Report;
   begin
      Repo.Check (Repository_Root, Report);

      --  Without this, a checker that silently found no files to look at
      --  would report a clean repository and this suite would agree with it.
      Assert (Report.Checks_Run > 20,
              "suspiciously few checks ran:" & Natural'Image (Report.Checks_Run));
   end Checks_Actually_Ran;

   -----------------------------
   -- A_Broken_Root_Fails --
   -----------------------------

   procedure A_Broken_Root_Fails (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Report : Repo.Report;
   begin
      Repo.Check (Empty_Root, Report);

      Assert (not Repo.Passed (Report),
              "the checks passed against a directory that is not a repository");

      --  Specifically the missing-file and missing-directory checks, so that
      --  this stays a test of those rather than of whatever happens to fail
      --  first.
      declare
         Saw_Missing_File      : Boolean := False;
         Saw_Missing_Directory : Boolean := False;
      begin
         for Finding of Report.Findings loop
            if Repo.Key (Finding) = "tooling.check.missing_file" then
               Saw_Missing_File := True;
            elsif Repo.Key (Finding) = "tooling.check.missing_directory" then
               Saw_Missing_Directory := True;
            end if;
         end loop;

         Assert (Saw_Missing_File, "no missing-file finding for an empty root");
         Assert (Saw_Missing_Directory, "no missing-directory finding for an empty root");
      end;
   end A_Broken_Root_Fails;

   ------------------------------------
   -- Prose_In_Source_Is_Found --
   ------------------------------------

   procedure Prose_In_Source_Is_Found
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Report : Repo.Report;
      Found  : Boolean := False;
   begin
      Repo.Check_No_Prose_As_Text (Prose_Root, Report);

      for Finding of Report.Findings loop
         if Repo.Key (Finding) = "tooling.check.prose_as_text" then
            Found := True;
         end if;
      end loop;

      --  The sentence is reported and Ada's own `in out` is not, which is the
      --  whole of the rule: one finding, not two.
      Assert (Found, "a sentence written in Ada source was not reported");
      Assert (Repo.Failure_Count (Report) = 1,
              "expected one finding, got"
              & Natural'Image (Repo.Failure_Count (Report)));
   end Prose_In_Source_Is_Found;

   -----------------------------------------
   -- Findings_Carry_Renderable_Keys --
   -----------------------------------------

   procedure Findings_Carry_Renderable_Keys (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Report : Repo.Report;
   begin
      Repo.Check (Empty_Root, Report);

      for Finding of Report.Findings loop
         declare
            Value : constant String := Repo.Key (Finding);
         begin
            Assert (Value'Length > 0, "a finding carries an empty key");

            --  Findings are rendered through the catalog like everything
            --  else, so a key that is not a catalog key produces a fallback
            --  line in the tool's output rather than a sentence.
            Assert (Value (Value'First .. Value'First + 7) = "tooling.",
                    "a finding key is outside the tooling namespace: " & Value);

            Assert (Repo.Arguments (Finding)'Length
                    <= Repo.Max_Finding_Arguments,
                    "a finding carries more arguments than it can hold");

            for Argument of Repo.Arguments (Finding) loop
               Assert (Adash.Messages.Name (Argument)'Length > 0,
                       "a finding argument has no name");
            end loop;
         end;
      end loop;
   end Findings_Carry_Renderable_Keys;

   ----------
   -- Name --
   ----------

   overriding function Name (T : Case_Type) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Adash_Tests.Repository");
   end Name;

   --------------------
   -- Register_Tests --
   --------------------

   overriding procedure Register_Tests (T : in out Case_Type) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, The_Repository_Passes'Access, "the repository passes its checks");
      Register_Routine (T, Checks_Actually_Ran'Access, "the checks actually ran");
      Register_Routine (T, A_Broken_Root_Fails'Access, "a root that is not a repository fails");
      Register_Routine (T, Prose_In_Source_Is_Found'Access,
                        "a sentence written in Ada source is reported");
      Register_Routine (T, Findings_Carry_Renderable_Keys'Access,
                        "findings carry renderable catalog keys");
   end Register_Tests;

end Adash_Tests.Repository_Cases;
