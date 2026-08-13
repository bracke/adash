with AUnit.Test_Cases;

--  Tests for the predefined registry and what it makes possible.
--
--  Two things are pinned. The registry's own contract: complete metadata for
--  every entity, and behaviour that does not depend on the order the table
--  happens to be written in. And the two loops it closes — calls are now
--  checked against real signatures, and a program can finally write something,
--  which replaces division by zero as the way to observe a run.
package Adash_Tests.Predefined_Cases is

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

end Adash_Tests.Predefined_Cases;
