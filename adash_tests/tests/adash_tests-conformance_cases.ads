with AUnit.Test_Cases;

--  Runs the conformance suite from inside the test suite.
--
--  The same code `adash_conformance` runs, so the two cannot disagree. A
--  conformance suite reachable only from its own main is one that stops being
--  run the week somebody forgets it exists, and `alr test` is what CI invokes.
--
--  This case needs the shell to have been built: it runs `../bin/adash`, not
--  the library it is linked against. That is the point -- conformance is about
--  what a user can observe from the outside, and a suite that called into the
--  library would be testing something no user can reach.
package Adash_Tests.Conformance_Cases is

   type Case_Type is new AUnit.Test_Cases.Test_Case with null record;

   --  @param T Test case instance.
   --  @return Case name.
   overriding function Name (T : Case_Type) return AUnit.Message_String;

   --  @param T Test case instance.
   overriding procedure Register_Tests (T : in out Case_Type);

end Adash_Tests.Conformance_Cases;
