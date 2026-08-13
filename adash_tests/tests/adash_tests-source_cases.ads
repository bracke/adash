with AUnit.Test_Cases;

--  Tests for the source model and diagnostics.
--
--  Everything Phases 4 to 7 produce will carry spans into a buffer, so the
--  properties pinned here are ones a whole subsystem will assume: that offsets
--  index the original bytes, that a CR LF file does not report twice its lines,
--  that columns count characters rather than bytes, and that malformed input is
--  refused once rather than mis-reported later as a lexical error.
package Adash_Tests.Source_Cases is

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

end Adash_Tests.Source_Cases;
