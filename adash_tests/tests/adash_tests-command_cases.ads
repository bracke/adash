with AUnit.Test_Cases;

--  Tests for the internal command framework and the commands themselves.
--
--  The property worth protecting most is that commands produce *data*: a
--  message identifier and typed arguments per line, never a rendered sentence.
--  These tests assert on identities, which is only possible because of that —
--  and would be impossible against a command that printed.
package Adash_Tests.Command_Cases is

   type Case_Type is new AUnit.Test_Cases.Test_Case with null record;

   --  Name shown by the reporter.
   --
   --  @param T Test case instance.
   --  @return Case name.
   overriding function Name (T : Case_Type) return AUnit.Message_String;

   --  Register the routines of this case.
   --
   --  @param T Test case instance.
   overriding procedure Register_Tests (T : in out Case_Type);

   procedure Redirection_Attaches_A_File
     (Test : in out AUnit.Test_Cases.Test_Case'Class);

   procedure A_Pipeline_Joins_Its_Stages
     (Test : in out AUnit.Test_Cases.Test_Case'Class);

end Adash_Tests.Command_Cases;
