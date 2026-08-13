with AUnit.Test_Cases;

--  Tests for Adash.Version.
--
--  Small, and worth having: the version is what a bug report identifies a
--  build by, and every value here is derived from the Alire manifest rather
--  than written down, so the thing that can break is the derivation.
package Adash_Tests.Version_Cases is

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

end Adash_Tests.Version_Cases;
