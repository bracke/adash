with AUnit.Test_Cases;

--  Tests for Adash.Terminal.
--
--  The property worth protecting is that styling is decoration: with colour
--  off, or with the destination not a terminal, the bytes out must equal the
--  bytes in. Everything downstream of Adash -- a pipe, a log, a conformance
--  case comparing output -- depends on it, and a regression here is invisible
--  to a person watching a terminal, which is the only place it does not
--  happen.
package Adash_Tests.Terminal_Cases is

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

end Adash_Tests.Terminal_Cases;
