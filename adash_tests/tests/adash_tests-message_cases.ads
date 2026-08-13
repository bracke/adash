with AUnit.Test_Cases;

--  Tests for Adash.Messages and the presentation boundary.
--
--  Two things are being protected here. One is the identifier-to-key mapping:
--  a duplicated key silently merges two messages, and the compiler cannot see
--  it because both sides are legal. The other is the degradation path -- what
--  a broken catalog produces -- which is exactly the code nobody exercises by
--  hand and which runs on the worst day.
package Adash_Tests.Message_Cases is

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

end Adash_Tests.Message_Cases;
