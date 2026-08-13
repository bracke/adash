with AUnit.Test_Cases;

--  Tests for the virtual machine.
--
--  Programs are built here instruction by instruction rather than lowered from
--  source: what is being tested is the machine, and a test that went through
--  the lowering would fail for two reasons and say one.
package Adash_Tests.Machine_Cases is

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

end Adash_Tests.Machine_Cases;
