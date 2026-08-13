with AUnit.Test_Cases;

--  Tests that the repository obeys its own invariants, and that the checker
--  which says so is itself working.
--
--  Both halves matter. Running the checks against the real repository is what
--  keeps AI.md honest -- a rule nothing enforces is a rule that has already
--  been broken somewhere. Running them against a deliberately broken tree is
--  what keeps the checker honest: a checker that reports success on anything
--  is worse than no checker, because it is believed.
package Adash_Tests.Repository_Cases is

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

end Adash_Tests.Repository_Cases;
