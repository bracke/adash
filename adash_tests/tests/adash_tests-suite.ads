with AUnit.Test_Suites;

--  The mandatory deterministic suite.
package Adash_Tests.Suite is

   --  Build the suite of every mandatory test.
   --
   --  @return Suite ready for an AUnit runner.
   function Suite return AUnit.Test_Suites.Access_Test_Suite;

end Adash_Tests.Suite;
