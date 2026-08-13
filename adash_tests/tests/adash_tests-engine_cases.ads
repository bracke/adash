with AUnit.Test_Cases;

--  Tests for the engine.
--
--  This is the first package that can be tested the way a user experiences the
--  shell: submit source, get a result. Everything below it has been tested in
--  pieces; these tests assert the pieces are joined — that one submission
--  reaches the language, another reaches the commands, and state carries from
--  one submission to the next.
package Adash_Tests.Engine_Cases is

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

   procedure Declarations_Survive_A_Submission
     (Test : in out AUnit.Test_Cases.Test_Case'Class);

end Adash_Tests.Engine_Cases;
