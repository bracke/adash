with AUnit.Test_Cases;

--  Tests for Adash.Patterns: matching a name against a pattern, and what a
--  text with brace groups stands for.
--
--  Both are pure -- no filesystem, no host, no session -- which is why they are
--  tested here rather than through a script: the corners that matter are the
--  ones a conformance case would have to build a directory to reach, and an
--  unclosed bracket needs no directory at all.
package Adash_Tests.Pattern_Cases is

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

end Adash_Tests.Pattern_Cases;
