with AUnit.Test_Cases;

--  Tests for semantic analysis.
--
--  Two things are being pinned. One is that legal programs are accepted —
--  easy to lose when adding a rule, and the reason each test analyses working
--  code before it analyses broken code. The other is that the language's own
--  decisions hold: no implicit conversion, no truthiness, constants that cannot
--  be assigned to, a loop parameter that is one.
package Adash_Tests.Semantics_Cases is

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

end Adash_Tests.Semantics_Cases;
