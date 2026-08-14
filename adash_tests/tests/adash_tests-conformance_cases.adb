with Ada.Strings.Unbounded;

with AUnit.Assertions;

with Adash_Tests.Conformance;

package body Adash_Tests.Conformance_Cases is

   use AUnit.Assertions;
   use Ada.Strings.Unbounded;

   package Conf renames Adash_Tests.Conformance;

   --  Where the repository is from the directory Alire puts a test run in.
   Root : constant String := "..";

   procedure Suite_Passes (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Examples_Pass (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Cases_Actually_Ran (Test : in out AUnit.Test_Cases.Test_Case'Class);

   --  The first failure, in full, so a person reading the test output does not
   --  have to run a second tool to find out what went wrong.
   function First_Problem (Results : Conf.Report) return String;

   function First_Problem (Results : Conf.Report) return String is
      use type Conf.Verdict;
   begin
      for Index in 1 .. Conf.Count (Results) loop
         declare
            Item : constant Conf.Result := Conf.Element (Results, Index);
         begin
            if Item.Outcome = Conf.Failed or else Item.Outcome = Conf.Malformed
            then
               return Conf.Verdict'Image (Item.Outcome) & " "
                 & To_String (Item.Identity) & ": " & To_String (Item.Detail);
            end if;
         end;
      end loop;

      return "";
   end First_Problem;

   ---------------------
   -- Suite_Passes --
   ---------------------

   procedure Suite_Passes (Test : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (Test);
      Results : Conf.Report;
   begin
      Conf.Run (Root, Results);

      --  How many, not only which. A run on a host nobody can reach reports
      --  one case and leaves the scale unknown: two failures of six hundred
      --  and a hundred and fifty of six hundred are different problems, and
      --  the first line of the report is where that has to be visible.
      Assert (Conf.Passed (Results),
              "the conformance suite failed:"
              & Natural'Image (Conf.Count_Of (Results, Conf.Failed))
              & " of" & Natural'Image (Conf.Count (Results))
              & " cases; first: " & First_Problem (Results));
   end Suite_Passes;

   ----------------------
   -- Examples_Pass --
   ----------------------

   procedure Examples_Pass (Test : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (Test);
      Results : Conf.Report;
   begin
      Conf.Run_Examples (Root, Results);

      --  An example that no longer produces what it claims is documentation
      --  that lies, and this is the only thing standing between that and a
      --  reader discovering it.
      Assert (Conf.Passed (Results),
              "an example no longer matches its .expected file:"
              & Natural'Image (Conf.Count_Of (Results, Conf.Failed))
              & " of" & Natural'Image (Conf.Count (Results))
              & "; first: " & First_Problem (Results));
   end Examples_Pass;

   ------------------------------
   -- Cases_Actually_Ran --
   ------------------------------

   procedure Cases_Actually_Ran
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Results : Conf.Report;
   begin
      Conf.Run (Root, Results);
      Conf.Run_Examples (Root, Results);

      --  A suite that found no cases passes vacuously, which is exactly what a
      --  broken path or a moved directory looks like. Asserting that something
      --  ran is what tells the two apart.
      Assert (Conf.Count (Results) > 0,
              "the conformance suite found no cases at all");
      Assert (Conf.Count_Of (Results, Conf.Passed) > 0,
              "the conformance suite ran cases but passed none");
   end Cases_Actually_Ran;

   ----------
   -- Name --
   ----------

   overriding function Name (T : Case_Type) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Adash_Tests.Conformance");
   end Name;

   --------------------
   -- Register_Tests --
   --------------------

   overriding procedure Register_Tests (T : in out Case_Type) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Cases_Actually_Ran'Access,
                        "the suite finds its cases and runs them");
      Register_Routine (T, Suite_Passes'Access,
                        "every conformance case passes");
      Register_Routine (T, Examples_Pass'Access,
                        "every example still produces what it claims");
   end Register_Tests;

end Adash_Tests.Conformance_Cases;
